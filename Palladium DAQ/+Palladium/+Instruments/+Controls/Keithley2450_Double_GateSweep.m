classdef Keithley2450_Double_GateSweep < Palladium.Core.InstrumentControlBase
    %KEITHLEY2450_DOUBLE_GATESWEEP - Logic controller add-on object to be
    %added on to a Keithley2450 Instrument, where it drives a
    %digital-I/O-triggered "double gate sweep":
    %   Main instrument (this Control's parent, this.Instrument) - sources a
    %       fixed Bias_V and measures current each time the trigger line
    %       pulses. Its digital I/O line is an input.
    %   Second instrument (the Gate, this.SecondInstrument, chosen in the
    %       GUI) - sources a zig-zag pulse train (toreduce hysteresis in the DUT)
    %       about Baseline_V, measuring
    %       current, and drives the shared digital I/O line to trigger the
    %       Main instrument's reading at each point.
    %Both instruments run their own on-board TSP script so the
    %pulse-and-measure timing loop does not need a MATLAB round trip per
    %point. Both must be set to the TSP command set. 


    %% Properties (Constant, Public)
    properties (Constant)
        %The digital trigger is one-way - the Gate never waits for the
        %Main instrument to finish its reading. With PulseWidth_s = 0 the
        %idle gap between pulses can be shorter than a reading, the Main
        %instrument misses pulses and its loop never finishes. Found on
        %hardware (two 2450s, NPLC 0.01): 0 fails, 1 ms and above works
        MinPulseWidth_s = 1e-3;

        %How often Run() checks, while waiting for the timing loops, whether
        %they have finished or Abort has been pressed
        PollInterval_s = 0.05;
    end

    %% Properties (Public) - Sweep Parameters
    properties (Access = public)
        Baseline_V       (1,1) double = 0;              %V, applied by the Gate instrument between pulses
        PulseVoltage_V   (1,1) double = 0.0001;         %V, step size added on the Gate instrument each half-cycle
        Compliance2450_A (1,1) double = 0.0001;         %A, Main (bias/measure) instrument current limit
        Compliance2450_Gate_A (1,1) double = 0.0001;    %A, Gate (pulse) instrument current limit

        Bias_V       (1,1) double = 0;                  %V, small bias voltage sourced by the Main (parent) instrument for measurement
        NPLC = 0.01;

        PulseWidth_s     (1,1) double {mustBeNonnegative} = 0;                  %s, dwell time at each source level before triggering/measuring
        OffTime_s        (1,1) double {mustBeNonnegative} = 0;                  %s, gap between points

        NumPulses        (1,1) double {mustBeInteger, mustBePositive} = 800;    %Number of baseline + pulse pairs - the sweep reaches Baseline_V +/- (NumPulses/2) * PulseVoltage_V

        DigioLine        (1,1) double {mustBeInteger, mustBePositive} = 6;      %Digital I/O line, same on both instruments (must be wired straight across)
        ActiveLow        (1,1) logical = true;                                  %true: idle HIGH, pulse LOW to trigger a measurement
        KeepGateAtBaselineWhenComplete (1,1) logical = true;                    %true: when the sweep completes, leave the Gate instrument's output on at Baseline_V. false: turn its output off
        KeepMainAtBiasWhenComplete (1,1) logical = true;                        %true: when the sweep completes, leave the Main instrument's output on at Bias_V. false: turn its output off
        MainFourWire (1,1) logical = true;                                      %true: Main instrument measures in 4-wire (remote sense) mode - needs the sense leads connected. false: 2-wire
        AutoZero (1,1) logical = false;                                         %false: both instruments autozero once at the start of the sweep, not before every reading - about 35% faster per point (6.0 -> 3.9 ms on hardware, no change in noise). true: autozero every reading (instrument default), guards against drift in very long sweeps
        SourceReadback (1,1) logical = true;                                    %true: record each point's MEASURED source value (shows the real value when in compliance). false: record the programmed level - saves ~0.9 ms per point
        FileSettings = struct("SaveSweepFile", true, "FileName", "SweepFileName");
    end

    %% Properties (Public, Protected Set) - Results of the last Run()
    properties (GetAccess = public, SetAccess = protected)
        Running = false;
        TimeElapsed_s = 0;
        LastRunAborted = false;     %true if the last Run() was stopped by Abort() - it then returns empty data
    end

    %% Properties (Protected)
    properties (Access = protected)
        SecondInstrument;           %Palladium.Core.Instrument reference for the second (Gate, pulse) SMU
        ParentController;           %Palladium.Core.Controller reference, stored so Run() can log via the standard Controller.Log path. Empty when running headless
        GUIView;                    %Empty when running headless
        timerVal;
    end

    %% Properties (Private)
    properties (Access = private)
        Plotter;                    %Empty when running headless
        DataWriter;                 %Empty when no data file is being written
        AbortRequested = false;     %Set by Abort(), checked by Run() while it waits for the timing loops
        PendingRun = false;         %true when a GUI Run request is queued, to be started in the next measurement tick (see RequestRun)
        PendingRunDetails = [];     %The GUI sweepDetails for the queued run
        PendingRunTimer = [];       %One-shot timer about to start a run when the measurement loop is not running (see RequestRun)
        MainOVPSetting = "";        %Each instrument's own overvoltage protection, read before the sweep resets it, and restored after (see ValidateSweepSettings)
        GateOVPSetting = "";
    end

    %% Constructor
    methods
        function this = Keithley2450_Double_GateSweep(Settings)
            %Called with no arguments by the framework, which then attaches
            %the instruments, controller, GUI and plotter in
            %CreateInstrumentControlGUI. To run headless (e.g. from a
            %script), pass the instruments here instead and call Run():
            %   gs = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep(Instrument = main, SecondInstrument = gate);
            %   [sweepData, data] = gs.Run();
            arguments
                Settings.Instrument = [];           %Main (bias/measure) Keithley2450
                Settings.SecondInstrument = [];     %Gate (pulse) Keithley2450
                Settings.Controller = [];           %Optional Palladium.Core.Controller, for logging
            end

            if ~isempty(Settings.Instrument); this.SetMainInstrument(Settings.Instrument); end
            if ~isempty(Settings.SecondInstrument); this.SetSecondInstrument(Settings.SecondInstrument); end
            this.ParentController = Settings.Controller;
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function Abort(this)
            %Stop both instruments' timing loops and turn their outputs
            %off. While Run() waits for the timing loops it keeps
            %processing GUI events, so an Abort press during a sweep lands
            %here straight away: the instruments are stopped immediately,
            %and Run() then sees AbortRequested, and returns without
            %reading back any data
            this.AbortRequested = true;     %Reset at the start of each Run()
            this.Running = false;
            this.TimeElapsed_s = 0;

            %Cancel any queued run that has not started yet - in the next
            %tick, or from a timer about to fire (e.g. between Continuous
            %sweeps). Stopping the timer before it fires means its callback
            %never runs; its StopFcn deletes it
            this.PendingRun = false;
            this.PendingRunDetails = [];
            if ~isempty(this.PendingRunTimer) && isvalid(this.PendingRunTimer)
                stop(this.PendingRunTimer);
            end
            this.PendingRunTimer = [];

            this.AbortInstruments();
        end

        function CreateInstrumentControlGUI(this, controller, tab, instrRef)
            
            this.Instrument = instrRef;
            this.ParentController = controller;

            %Create grid and GUI component and position them in the
            %tab.
            grid = uigridlayout(tab, "ColumnWidth", {10, 540, 10, '1x'}, "RowHeight", {'1x', 10}, 'RowSpacing', 2);
            scrollableGrid = uigridlayout(grid, [1,1], "ColumnWidth", {'1x'}, "RowHeight", {'fit', '1x'}, 'RowSpacing', 0, Scrollable='on');
            scrollableGrid.Layout.Row = 1;
            scrollableGrid.Layout.Column = 2;

            comp = Palladium.Instruments.Controls.Keithley2450_DoubleGateSweep(scrollableGrid);

            %Store the reference to this View as a property
            this.GUIView = comp;

            %Update the instrument selection dropdown in the View, get from
            %Controller
            instrsList = controller.InstrumentController.GetInstruments();
            this.SetInstrumentList(instrsList);

            %Subscribe to events
            this.AddGuardedListener(comp, 'Run', @(src,evnt)this.RequestRun(evnt.SweepDetails));
            this.AddGuardedListener(comp, 'Abort', @(src,evnt)this.Abort());
            this.AddGuardedListener(comp, 'InsertSmartTag', @(src,evnt)this.InsertSmartTagRequest(src, evnt, controller));

            %Add a plotter as well, to the right
            this.Plotter = controller.AddNewPlotter(grid, Size="Medium", RegisterPlotter=false);    %Don't register the plotter centrally, as we will push data to it only when the sweep is running, and clear it on sweep start. This does mean, for now at least, that the Plotter is not hooked up
            this.Plotter.Layout.Row = 1;
            this.Plotter.Layout.Column = 4;

            %Default axes: Gate voltage vs Main current (as the original
            %Python script plotted). The Plotter draws nothing until an x
            %axis is selected, and UpdateVariables applies these defaults
            %(it must come after them)
            this.Plotter.SetDefaultXAxis("Gate_Voltage_V");
            this.Plotter.SetDefaultYAxis(1, "Current_A");
            this.Plotter.UpdateVariables(this.GetHeaderNames());
            ltr = this.AddGuardedListener(this.Plotter, 'AxesSelectionChange', @(src,evnt)this.PlotterAxesSelectionChange(src));
            this.RegisterEventListener(ltr);
        end

        function OnDoubleGateSweepComplete(this, sweepData)
            %Plot, save and update the GUI with the finished sweep - each
            %step is skipped if that part is not available (headless)
            this.Running = false;

            %Keep the data, so the base class's PlotterAxesSelectionChange
            %can replot it when the user picks different axes
            this.DataArray = sweepData;

            %Plot the data
            if ~isempty(this.Plotter)
                this.Plotter.PlotData(sweepData);
            end

            %Write the data (will check if Save to File is selected)
            this.WriteData(sweepData)

            %Update the View, and loop the next one if in Continuous mode
            if ~isempty(this.GUIView)
                this.GUIView.SweepComplete();
                if this.GUIView.IsContinuousSelected()
                    this.GUIView.RunSweep();
                end
            end
        end


        function RemoveControl(this, ~)
            if ~isempty(this.GUIView)
                delete(this.GUIView);
                this.GUIView = [];
            end
        end

        function RequestRun(this, sweepDetails)
            %Entry point for the GUI's Run button. GUI events are handled
            %whenever MATLAB is idle - between measurement ticks - so if the
            %measurement loop is running, starting the sweep here would let
            %the next ticks call Measure on both instruments in the middle
            %of their TSP scripts, mixing their replies into the sweep's.
            %Instead queue it, and Update() (called within the parent
            %instrument's tick, just before its Measure) starts it, so
            %nothing else talks to the instruments until it finishes.
            %
            %Otherwise nothing is polling the instruments, so start it
            %straight away - but from a one-shot timer, not from within
            %this call. This is the GUI's Run event listener, and in
            %Continuous mode the finished sweep fires the Run event again:
            %if the sweep were still running inside this listener, that
            %nested event would be silently dropped (MATLAB listeners are
            %not recursive), and each continuous sweep would also nest one
            %level deeper
            arguments
                this;
                sweepDetails = [];
            end

            if this.IsMeasurementLoopRunning()
                this.PendingRun = true;
                this.PendingRunDetails = sweepDetails;
                this.Log("Double gate sweep queued - starting at the next measurement tick...");
            else
                %The start delay matters: with 0, MATLAB runs the callback
                %straight away inside start(), i.e. still inside this
                %listener. The timer deletes itself once its callback has
                %finished
                runTimer = timer("StartDelay", 0.1, "ExecutionMode", "singleShot", "ObjectVisibility", "off", ...
                    "TimerFcn", @(~, ~) this.RunFromTimer(sweepDetails), ...
                    "StopFcn", @(tmr, ~) delete(tmr));
                this.PendingRunTimer = runTimer;
                start(runTimer);
            end
        end

        function [sweepData, data] = Run(this, sweepDetails)
            arguments
                this;
                sweepDetails = [];%Optional parameter, to allow running headless without GUI event calling this
            end
            %RUN - Configure both SMUs, run the triggered pulse train, and
            %pull the resulting buffers back. Blocking - waits for both
            %instruments to report "DONE". Returns sweepData, a matrix with
            %one column per header (see GetHeaderNames), and data, a struct
            %of the same columns by name. Plotting, the GUI and the data
            %file are each skipped if not available, so this also runs
            %headless.

            if ~isempty(sweepDetails)
                this.RetrieveSettingsFromGUIStruct(sweepDetails);
            end

            assert(~isempty(this.Instrument), "Keithley2450_Double_GateSweep:NoMainInstrument", "Keithley2450_Double_GateSweep has no Main instrument set - add it as a Control on a Keithley2450, or pass Instrument= to the constructor, or call SetMainInstrument(instr).");
            assert(~isempty(this.SecondInstrument), "Keithley2450_Double_GateSweep:NoGateInstrument", "Keithley2450_Double_GateSweep has no Gate instrument set - select it in the GUI, or pass SecondInstrument= to the constructor, or call SetSecondInstrument(instr).");

            %Start both instruments from a well-defined state: stop any
            %script still running (e.g. left from a failed sweep), discard
            %stale replies and queued commands, and turn the outputs off.
            %A device clear alone would not stop a running script. Both are
            %reset in Configure* below anyway, so nothing is lost
            this.AbortRequested = false;
            this.LastRunAborted = false;
            this.Log("Stopping and clearing both instruments...");
            this.AbortInstruments();

            %The timing loops are TSP scripts, so both instruments must be
            %running the TSP command set - check the hardware, not just the
            %Language setting
            this.CheckCommandSetIsTSP(this.Instrument, "Main (bias/measure)");
            this.CheckCommandSetIsTSP(this.SecondInstrument, "Gate (pulse)");

            %Too short a pulse width makes the Main instrument miss pulses
            %and hang - see MinPulseWidth_s
            if this.PulseWidth_s < this.MinPulseWidth_s
                msg = "Double Gate Sweep: pulse width " + num2str(this.PulseWidth_s * 1e3) + " ms is below the " + num2str(this.MinPulseWidth_s * 1e3) + ...
                    " ms minimum needed for the Main instrument to catch every trigger pulse - using " + num2str(this.MinPulseWidth_s * 1e3) + " ms.";
                this.LogWarning(msg);
                this.PulseWidth_s = this.MinPulseWidth_s;
            end

            %Check every level and limit the sweep will use against what
            %the instruments can and are allowed to do, before anything is
            %sourced - rather than failing, or being silently clamped,
            %part-way through
            this.ValidateSweepSettings();

            %Create data writer if a data file is being written. The file
            %location comes from the app's file settings, which the
            %Controller copies onto each Instrument when measurements
            %start - without them (e.g. running from a script) no file is
            %written and the data is just returned
            this.DataWriter = [];
            if ~isempty(this.Instrument.FileWriteDetails)
                this.CreateDataFile(this.FileSettings.SaveSweepFile);
            elseif this.FileSettings.SaveSweepFile
                this.Log("No data file settings available (not running within Palladium, or measurements not started) - sweep data will be returned but not saved to file.");
            end
            this.UpdatePlotterSavedPlotTitle();

            this.Running = true;
            this.timerVal = tic();

            numMeasurements = this.NumPulses + 1;   %zig-zag: baseline, +pulse, -pulse, +pulse, ... the +1 is for that initial baseline 'zero' measurement point

            if this.ActiveLow
                idleState = "STATE_HIGH";
                pulseState = "STATE_LOW";
            else
                idleState = "STATE_LOW";
                pulseState = "STATE_HIGH";
            end

            this.Log("Configuring Main (bias/measure) and Gate (pulse) SMUs...");
            this.ConfigureMainInstrument(numMeasurements);
            this.ConfigureSecondInstrument(numMeasurements, idleState);

            loopMain = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.CollapseScriptToOneLine(this.BuildLoop2450_Meas_Script(numMeasurements, idleState, pulseState));
            loopGate = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.CollapseScriptToOneLine(this.BuildLoop2450_Gate_Script(idleState, pulseState));

            %Last chance to stop before anything is sourced beyond the
            %bias (logging to the GUI can process an Abort press)
            if this.AbortRequested
                this.AbortInstruments();
                [sweepData, data] = this.FinishAbortedRun();
                return;
            end

            %Arm the Main instrument's triggered measure loop first, THEN
            %start the Gate pulse train, so no pulse is missed
            this.Log("Arming Main (bias/measure) trigger loop...");
            this.Instrument.WriteCommand(loopMain);
            this.Log("Starting Gate pulse train...");
            this.SecondInstrument.WriteCommand(loopGate);

            %Both scripts print DONE when finished - allow for the expected
            %run time, which can be far longer than the GPIB timeout. Abort
            %can be pressed at any point while waiting
            maxWait_s = this.EstimateMaxRunTime(numMeasurements);
            this.Log("Waiting for Gate to finish (allowing up to " + num2str(round(maxWait_s)) + " s)...");
            respGate = this.WaitForDone(this.SecondInstrument, maxWait_s);
            if this.AbortRequested
                [sweepData, data] = this.FinishAbortedRun();
                return;
            end
            this.Log("Gate says: " + respGate);

            this.Log("Waiting for Main to finish...");
            respMain = this.WaitForDone(this.Instrument, maxWait_s - toc(this.timerVal));
            if this.AbortRequested
                [sweepData, data] = this.FinishAbortedRun();
                return;
            end
            this.Log("Main says: " + respMain);

            data = this.PullBufferData(numMeasurements);

            this.Running = false;
            this.TimeElapsed_s = toc(this.timerVal);
            this.Log("Double gate sweep complete in " + num2str(this.TimeElapsed_s) + " s.");

            %Unpack the data into columns, in the same order as the headers
            %(buffer data comes back as row vectors)
            sweepData = [data.Gate_Voltage_V(:), data.Current_A(:), ...
                data.Gate_Leakage_Current_A(:), data.Bias_Voltage_V(:), ...
                data.Time_2450(:), data.Time_2450_Gate(:)];
            data = structfun(@(col) col(:), data, "UniformOutput", false);

            this.OnDoubleGateSweepComplete(sweepData);
        end

        function SetMainInstrument(this, instr)
            %Manually attach the Main (bias/measure) SMU Instrument
            %reference - for driving the Control directly, outside of the
            %normal Controller-managed GUI flow (which sets it in
            %CreateInstrumentControlGUI)
            arguments
                this;
                instr (1,1) Palladium.Core.Instrument;
            end

            this.Instrument = instr;
        end

        function SetSecondInstrument(this, instr)
            %Manually attach the second (Gate, pulse) SMU Instrument
            %reference - for driving the Control directly, outside of the
            %normal Controller-managed GUI flow (where it is chosen in the
            %GUI's instrument dropdown)
            arguments
                this;
                instr (1,1) Palladium.Core.Instrument;
            end

            this.SecondInstrument = instr;
        end

        function Update(this)
            %Called every measurement tick, from the parent instrument's
            %UpdateAndMeasure, just before its Measure - start a queued
            %run (see RequestRun). The timer skips ticks while this runs
            if this.PendingRun
                sweepDetails = this.PendingRunDetails;
                this.PendingRun = false;
                this.PendingRunDetails = [];
                this.RunFromGUI(sweepDetails);
            end
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function AbortInstruments(this)
            %Stop any running timing loop on both instruments, clear their
            %interfaces and turn their outputs off. Done in stages across
            %both instruments (the same steps as Keithley2450.AbortScript),
            %so they share the pauses rather than each waiting in turn.
            %Each step is tried separately per instrument, so a failure on
            %one still stops the other
            instrs = {this.Instrument, this.SecondInstrument};
            instrs = instrs(~cellfun(@isempty, instrs));
            if isempty(instrs); return; end
            pause_s = Palladium.Instruments.Keithley2450.ABORT_PAUSE_S;

            this.TryOnEachInstrument(instrs, @(instr) instr.SendAbortCommand(), "send abort to");
            pause(pause_s);
            this.TryOnEachInstrument(instrs, @(instr) instr.ClearInterface(), "clear the interface of");
            pause(pause_s);
            this.TryOnEachInstrument(instrs, @(instr) instr.TurnOutputOff(), "turn off the output of");
        end

        function ApplySpeedSettings(this, instr)
            %Autozero and source readback - the two instrument settings that
            %set most of the time per point (see the AutoZero and
            %SourceReadback properties). Both are stored per function, so
            %call after the source and measure functions (and the NPLC,
            %which autozero.once() refreshes the reference for) are set
            if this.AutoZero
                instr.WriteCommand("smu.measure.autozero.enable = smu.ON");
            else
                instr.WriteCommand("smu.measure.autozero.enable = smu.OFF");
                instr.WriteCommand("smu.measure.autozero.once()");
            end

            if this.SourceReadback
                instr.WriteCommand("smu.source.readback = smu.ON");
            else
                instr.WriteCommand("smu.source.readback = smu.OFF");
            end
        end

        function script = BuildLoop2450_Meas_Script(this, numMeasurements, idleState, pulseState)
            %TIMING LOOP for the Main instrument - has to go as a single TSP
            %script, since it's the part that has to run without any
            %MATLAB/GPIB round-trip per point for speed. Everything it
            %references (measBuffer, digio mode, smu settings) was already
            %configured via individual commands in ConfigureMainInstrument.
            nStr = num2str(numMeasurements);
            lineStr = num2str(this.DigioLine);
            nl = newline;

            %After the last reading, either leave the output on (the level
            %is still Bias_V, as it never changes during the sweep), or
            %turn it off
            if this.KeepMainAtBiasWhenComplete
                finalStateStr = "";
            else
                finalStateStr = "smu.source.output = smu.OFF";
            end

            script = "for i = 1, " + nStr + " do" + nl + ...
                "    while digio.line[" + lineStr + "].state == digio." + idleState + " do end" + nl + ...
                "    smu.measure.read(measBuffer)" + nl + ...
                "    while digio.line[" + lineStr + "].state == digio." + pulseState + " do end" + nl + ...
                "end" + nl + ...
                finalStateStr + nl + ...
                "print(""DONE"")" + nl;
        end

        function script = BuildLoop2450_Gate_Script(this, idleState, pulseState)
            %TIMING LOOP for the Gate instrument - see note on
            %BuildLoop2450_Meas_Script. zig-zag baseline/pulse stepping from
            %the original: each pulse steps further from Baseline_V by
            %PulseVoltage_V, alternating sign every other pulse. Reads into
            %gateBuffer, made in ConfigureSecondInstrument.
            lineStr = num2str(this.DigioLine);
            baselineStr = num2str(this.Baseline_V);
            pulseVStr = num2str(this.PulseVoltage_V);
            nl = newline;

            %After the last point (a pulse, not the baseline), either return
            %to the baseline with the output left on, or turn the output off
            if this.KeepGateAtBaselineWhenComplete
                finalStateStr = "smu.source.level = " + baselineStr;
            else
                finalStateStr = "smu.source.output = smu.OFF";
            end

            %  -- only measure/trigger on the very first baseline visit (i == 0);
            %  -- every later baseline visit still sources the voltage, just doesn't
            %  -- measure or trigger the other 2450
            script = "local function do_point(v, take_measurement)" + nl + ...
                "    smu.source.level = v" + nl + ...
                "    delay(" + num2str(this.PulseWidth_s) + ")" + nl + ...
                "    if take_measurement then" + nl +...
                "       digio.line[" + lineStr + "].state = digio." + pulseState + nl + ...
                "       smu.measure.read(gateBuffer)" + nl + ...
                "       delay(" + num2str(this.OffTime_s) + ")" + nl + ...
                "       digio.line[" + lineStr + "].state = digio." + idleState + nl + ...
                "    else" + nl +...
                "       delay(" + num2str(this.OffTime_s) + ")" + nl + ...
                "    end" + nl +...
                "end" + nl + ...
                nl + ...
                "for i = 0, " + num2str(this.NumPulses) + " - 1 do" + nl + ...
                "    do_point(" + baselineStr + ", i == 0)" + nl + ...
                nl + ...
                "    local half = math.floor(i / 2) + 1" + nl + ...
                "    local v" + nl + ...
                "    if math.mod(i, 2) == 0 then" + nl + ...
                "        v = " + baselineStr + " + half * " + pulseVStr + nl + ...
                "    else" + nl + ...
                "        v = " + baselineStr + " - half * " + pulseVStr + nl + ...
                "    end" + nl + ...
                "    do_point(v,true)" + nl + ...
                "end" + nl + ...
                nl + ...
                finalStateStr + nl + ...
                "print(""DONE"")" + nl;
        end

        function CheckCommandSetIsTSP(~, instr, roleName)
            %Error with a clear message if an instrument is not a
            %Keithley2450 running the TSP command set
            if ~isa(instr, "Palladium.Instruments.Keithley2450")
                error("Keithley2450_Double_GateSweep:InvalidInstrumentType", "%s", "Double Gate Sweep: the " + roleName + " instrument (" + instr.Name + ") must be a Keithley2450.");
            end
            if instr.GetLanguage() ~= instr.LanguageType("TSP")
                error("Keithley2450_Double_GateSweep:WrongCommandSet", "%s", "Double Gate Sweep: the " + roleName + " instrument (" + instr.Name + ") is using the " + string(instr.GetLanguage()) + ...
                    " command set, but the sweep needs TSP. Change the command set on the instrument (MENU > System > Settings > Command Set, or send *LANG TSP) and reboot it.");
            end
        end

        function [problems, ovpSetting] = CheckInstrumentLimits(~, instr, roleName, levelName, levels, compliance_A)
            %Check the voltage levels and current limit one instrument will
            %use against the 2450's source range, power envelope and
            %compliance range, and against the instrument's own OVP and
            %interlock. Returns a list of problems (empty if all is well)
            %and the instrument's OVP setting
            problems = strings(0);
            maxAbs_V = max(abs(levels));
            levelDesc = levelName + " (up to " + num2str(maxAbs_V, 4) + " V)";
            [ovp_V, ovpSetting] = instr.GetVoltageSourceOVP();

            %Hardware source span: +/-210 V (200 V range plus 5% overrange)
            if maxAbs_V > 210
                problems(end+1) = roleName + ": " + levelDesc + " exceeds the 2450's +/-210 V source maximum.";
            end

            %The instrument's own overvoltage protection, as set on it
            if maxAbs_V >= ovp_V
                problems(end+1) = roleName + ": " + levelDesc + " reaches or exceeds " + instr.Name + "'s overvoltage protection limit of " + ...
                    num2str(ovp_V) + " V (" + ovpSetting + "), set on the instrument.";
            end

            %Above 42 V needs the safety interlock - without it the output
            %is silently limited to below 42 V
            if maxAbs_V > 42 && ~instr.IsInterlockEngaged()
                problems(end+1) = roleName + ": " + levelDesc + " is above 42 V, which needs " + instr.Name + "'s safety interlock engaged - it is not, so the output would be limited to below 42 V.";
            end

            %Current limit range, and the power envelope (at most 105 mA
            %above 21 V)
            if compliance_A < 1e-9 || compliance_A > 1.05
                problems(end+1) = roleName + ": current limit " + num2str(compliance_A) + " A is outside the 2450's 1 nA to 1.05 A range.";
            elseif maxAbs_V > 21 && compliance_A > 0.105
                problems(end+1) = roleName + ": current limit " + num2str(compliance_A) + " A is above 105 mA, which the 2450 cannot source above 21 V - " + levelDesc + ".";
            end
        end

        function ConfigureMainInstrument(this, numMeasurements)
            %The Main (parent) instrument: sources a fixed voltage bias and
            %measures current each time the Gate instrument pulses the
            %digital I/O line, which is an input on this instrument
            instr = this.Instrument;

            instr.Reset();

            %Fixed source range (no range changes mid-sweep) - the smallest
            %that fits the bias. Set the range before the level, as a level
            %beyond a fixed range is rejected. Restore the instrument's own
            %overvoltage protection, which the reset cleared, before any
            %level is set
            instr.WriteCommand("smu.source.func = smu.FUNC_DC_VOLTAGE");
            instr.SetVoltageSourceOVP(this.MainOVPSetting);
            instr.WriteCommand("smu.source.autorange = smu.OFF");
            instr.WriteCommand("smu.source.range = " + num2str(Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.SourceRangeFor(this.Bias_V)));
            instr.WriteCommand("smu.source.level = " + num2str(this.Bias_V));
            instr.WriteCommand("smu.source.ilimit.level = " + num2str(this.Compliance2450_A));

            instr.WriteCommand("smu.measure.func = smu.FUNC_DC_CURRENT");
            instr.WriteCommand("smu.measure.autorange = smu.OFF");
            instr.WriteCommand("smu.measure.range = " + num2str(this.Compliance2450_A));
            instr.WriteCommand("smu.measure.nplc = " + num2str(this.NPLC));
            this.ApplySpeedSettings(instr);

            %Sense mode is stored per measure function, so set it after
            %the function, and before the output goes on (changing it with
            %the output on turns the output off)
            if this.MainFourWire
                instr.WriteCommand("smu.measure.sense = smu.SENSE_4WIRE");
            else
                instr.WriteCommand("smu.measure.sense = smu.SENSE_2WIRE");
            end

            instr.WriteCommand("digio.line[" + num2str(this.DigioLine) + "].mode = digio.MODE_DIGITAL_IN");

            instr.WriteCommand("smu.source.output = smu.ON");
            instr.WriteCommand("measBuffer = buffer.make(" + num2str(numMeasurements) + ")");
        end

        function ConfigureSecondInstrument(this, numMeasurements, idleState)
            %The Gate (second) instrument: steps through the zig-zag pulse
            %train, measuring current, and drives the digital I/O line
            %(an output on this instrument) to trigger the Main
            %instrument's reading at each point
            instr = this.SecondInstrument;

            instr.Reset();

            %Fixed source range (no range changes mid-sweep) - the smallest
            %that fits every level in the pulse train. Restore the
            %instrument's own overvoltage protection, which the reset
            %cleared, before any level is set
            instr.WriteCommand("smu.source.func = smu.FUNC_DC_VOLTAGE");
            instr.SetVoltageSourceOVP(this.GateOVPSetting);
            instr.WriteCommand("smu.source.autorange = smu.OFF");
            instr.WriteCommand("smu.source.range = " + num2str(Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.SourceRangeFor(this.GetGateVoltageExtremes())));
            instr.WriteCommand("smu.source.ilimit.level = " + num2str(this.Compliance2450_Gate_A));
            instr.WriteCommand("smu.source.autodelay = smu.OFF");

            instr.WriteCommand("smu.measure.func = smu.FUNC_DC_CURRENT");
            instr.WriteCommand("smu.measure.autorange = smu.OFF");
            instr.WriteCommand("smu.measure.range = " + num2str(this.Compliance2450_Gate_A));
            instr.WriteCommand("smu.measure.nplc = " + num2str(this.NPLC));
            this.ApplySpeedSettings(instr);

            instr.WriteCommand("digio.line[" + num2str(this.DigioLine) + "].mode = digio.MODE_DIGITAL_OUT");
            instr.WriteCommand("digio.line[" + num2str(this.DigioLine) + "].state = digio." + idleState);

            instr.WriteCommand("smu.source.output = smu.ON");
            instr.WriteCommand("gateBuffer = buffer.make(" + num2str(numMeasurements) + ")");
        end

        function maxWait_s = EstimateMaxRunTime(this, numMeasurements)
            %Generous upper bound on how long the Gate pulse train takes:
            %per point, the pulse width and off time delays, plus the
            %reading (allowing 3 power line cycles' worth per NPLC, at 50 Hz,
            %for autozero) and a few ms of script overhead. Doubled, plus a
            %margin, so a slow sweep is not mistaken for a hang
            perPoint_s = this.PulseWidth_s + this.OffTime_s + 3 * this.NPLC / 50 + 0.005;
            maxWait_s = 2 * numMeasurements * perPoint_s + 60;
        end

        function [sweepData, data] = FinishAbortedRun(this)
            %Tidy up after Abort was pressed mid-sweep. Abort() has already
            %stopped both instruments and turned their outputs off. No data
            %is read back or plotted, and continuous mode does not start
            %another sweep
            this.Running = false;
            this.LastRunAborted = true;
            this.TimeElapsed_s = toc(this.timerVal);
            this.Log("Double gate sweep aborted after " + num2str(this.TimeElapsed_s, 3) + " s - both instruments stopped, outputs off. No data saved.");

            if this.FileSettings.SaveSweepFile && ~isempty(this.DataWriter)
                this.DataWriter.InsertMetadataLines("Sweep aborted by user after " + num2str(this.TimeElapsed_s, 3) + " s - no data.");
            end

            sweepData = [];
            data = struct([]);
        end

        function extremes = GetGateVoltageExtremes(this)
            %Lowest and highest levels the Gate instrument will source: the
            %zig-zag reaches Baseline_V +/- halfMax * PulseVoltage_V, where
            %halfMax = floor(i/2) + 1 for the last pulse, i = NumPulses - 1
            halfMax = floor((this.NumPulses - 1) / 2) + 1;
            extremes = this.Baseline_V + [-1, 1] * halfMax * this.PulseVoltage_V;
        end

        function Log(this, message)
            %Route status messages through the standard Controller.Log
            %path when available (ie when driven via the normal
            %Controller-managed GUI flow), otherwise just print to the
            %command window so this Control also works headless.
            if ~isempty(this.ParentController)
                this.ParentController.Log("Info", message, "Green", "Double Gate Sweep");
            else
                disp(message);
            end
        end

        function LogWarning(this, message)
            %Warnings go through the central Logger when running within
            %Palladium (the Logger needs the app's setup), otherwise as a
            %MATLAB warning so this Control also works headless
            if ~isempty(this.ParentController)
                Palladium.Logging.Logger.Log("Warning", message);
            else
                warning("Keithley2450_Double_GateSweep:Warning", "%s", message);
            end
        end

        function OnMeasurementsInitialised(this, headers)
            if ~isempty(this.GUIView)
                this.GUIView.UpdateAvailableDataColumnHeaders(headers);
                this.GUIView.SetReady();
                this.GUIView.EnableRunButton();
            end
        end

        function OnMeasurementsStarted(this)
        end 

        function OnMeasurementsStopped(this)
            if ~isempty(this.GUIView)
                this.GUIView.SetReady();
                this.GUIView.DisableRunButton();
            end
        end

        function data = PullBufferData(this, numMeasurements)
            %Pull data back - one bulk transfer per instrument. printbuffer
            %with several columns interleaves them point by point
            %(src1, reading1, time1, src2, reading2, time2, ...)
            this.Log("Pulling buffer data back from both SMUs...");
            nStr = num2str(numMeasurements);

            

            %Main (bias/measure) instrument - measBuffer
            if this.Instrument.SimulationMode
                mainCols = this.Instrument.GenerateSimulatedData(3, numMeasurements, Transpose=true);
            else
                mainStr = this.Instrument.QueryString("printbuffer(1, " + nStr + ", measBuffer.sourcevalues, measBuffer.readings, measBuffer.relativetimestamps)");
                mainCols = this.SplitInterleavedColumns(mainStr, 3, numMeasurements);
            end

            data.Bias_Voltage_V = mainCols(1, :);
            data.Current_A = mainCols(2, :);
            data.Time_2450 = mainCols(3, :);

            %Gate (pulse) instrument - gateBuffer
            if this.SecondInstrument.SimulationMode
                gateCols = this.SecondInstrument.GenerateSimulatedData(3, numMeasurements, Transpose=true);
            else
                gateStr = this.SecondInstrument.QueryString("printbuffer(1, " + nStr + ", gateBuffer.readings, gateBuffer.sourcevalues, gateBuffer.relativetimestamps)");
                gateCols = this.SplitInterleavedColumns(gateStr, 3, numMeasurements);
            end

            data.Gate_Leakage_Current_A = gateCols(1, :);
            data.Gate_Voltage_V = gateCols(2, :);
            data.Time_2450_Gate = gateCols(3, :);
        end

        function RunFromGUI(this, sweepDetails)
            %Run a sweep requested from the GUI. If it fails, put the GUI
            %back in its ready state (so the Run button is usable again)
            %before passing the error on
            try
                this.Run(sweepDetails);
            catch err
                this.Running = false;
                if ~isempty(this.GUIView)
                    this.GUIView.SweepComplete();
                end
                rethrow(err);
            end
        end

        function RunFromTimer(this, sweepDetails)
            %One-shot timer callback that starts a GUI-requested sweep when
            %the measurement loop is not running (see RequestRun). Errors
            %are reported through the Controller's error handling, as a
            %timer callback has no caller to pass them to
            this.PendingRunTimer = [];
            try
                this.RunFromGUI(sweepDetails);
            catch err
                if ~isempty(this.ParentController)
                    this.ParentController.HandleCallbackError("Double gate sweep failed", err);
                else
                    this.LogWarning("Double gate sweep failed: " + err.message);
                end
            end
        end

        function cols = SplitInterleavedColumns(~, str, numCols, numPoints)
            %Split an interleaved printbuffer response into rows, one per
            %column requested (numCols x numPoints)
            values = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.ParseBufferString(str);
            if numel(values) ~= numCols * numPoints
                error("Keithley2450_Double_GateSweep:UnexpectedValueCount", "%s", "Double Gate Sweep: expected " + (numCols * numPoints) + " values from printbuffer, got " + numel(values) + ".");
            end
            cols = reshape(values, numCols, numPoints);
        end

        function TryOnEachInstrument(this, instrs, fn, actionDescription)
            %Apply fn to each instrument, warning (not erroring) on failure
            for i = 1:numel(instrs)
                try
                    fn(instrs{i});
                catch err
                    this.LogWarning("Double Gate Sweep: failed to " + actionDescription + " " + instrs{i}.Name + " - check its output is off. Error: " + err.message);
                end
            end
        end

        function ValidateSweepSettings(this)
            %Error, listing every problem found, if the sweep would ask
            %either instrument for something it cannot or must not do.
            %Reads each instrument's own overvoltage protection (OVP) and
            %interlock state, and stores the OVP to restore after the
            %reset in Configure*. Call before anything is configured
            problems = strings(0);

            [p, this.MainOVPSetting] = this.CheckInstrumentLimits(this.Instrument, "Main (bias/measure)", "Bias", this.Bias_V, this.Compliance2450_A);
            problems = [problems, p];
            [p, this.GateOVPSetting] = this.CheckInstrumentLimits(this.SecondInstrument, "Gate (pulse)", "Gate pulse train", this.GetGateVoltageExtremes(), this.Compliance2450_Gate_A);
            problems = [problems, p];

            if this.NPLC < 0.01 || this.NPLC > 10
                problems(end+1) = "NPLC " + num2str(this.NPLC) + " is outside the 2450's 0.01 to 10 range.";
            end

            if ~isempty(problems)
                error("Keithley2450_Double_GateSweep:NothingSourced", "%s", "Double Gate Sweep cannot run - nothing has been sourced:" + newline + "  - " + strjoin(problems, newline + "  - "));
            end
        end

        function resp = WaitForDone(this, instr, maxWait_s)
            %Wait for an instrument's timing loop to print DONE, without
            %blocking: poll whether a reply is waiting (a serial poll, fine
            %while the script runs), and in between process GUI events so
            %an Abort press is handled straight away. Returns "" if Abort
            %was pressed (AbortRequested is then true).
            %
            %Processing GUI events here is safe from the measurement loop
            %polling the instruments mid-sweep: from the GUI, Run() is
            %started inside a measurement tick (see RequestRun), and the
            %timer skips ticks while one is still running.
            %
            %If DONE never arrives, stop both instruments' loops and turn
            %their outputs off before erroring, rather than leaving a
            %script running with the output on
            resp = "";
            waitTimer = tic();
            while ~instr.IsReplyWaiting()
                drawnow();
                if this.AbortRequested
                    return;
                end
                if toc(waitTimer) > maxWait_s
                    this.Running = false;
                    this.AbortInstruments();
                    error("Keithley2450_Double_GateSweep:DoneTimeout", "%s", "Double Gate Sweep: no DONE from " + instr.Name + " after " + num2str(round(toc(waitTimer))) + ...
                        " s - both instruments have been aborted and their outputs turned off.");
                end
                pause(this.PollInterval_s);
            end

            resp = string(strtrim(instr.ReadString()));
        end
        
    end

    %% Methods (Private)
    methods (Access = private)

        function CreateDataFile(this, writeToFile)
            %Create or reset the data writer class
            fileNameSuffix = this.FileSettings.FileName;
            this.DataWriter = this.InitialiseDataWriter(fileNameSuffix, WriteToFile=writeToFile);

            %Built in functions in base class will write the data row of all instruments/diagnostics at the start
            %of the sweep, for things like temperature, time
            %Write the metadata string for this instrument - frequencies,
            %voltages, settings etc

            %Assemble some sweep metadata
            sweepMetadataDescLine = "Sweep Parameters:";
            sweepMetadataLine = this.CreateSweepMetaDataLine();

            %Get headers for the sweep data - not the same as overall
            %programme DataRow headers.
            headers = this.GetHeaders();

            %Create new file and write metadata and headers
            extraMetadataLines = [sweepMetadataDescLine, sweepMetadataLine];
            this.StartNewDataFile(this.DataWriter, headers, extraMetadataLines, writeToFile);
        end

        function stringLine = CreateSweepMetaDataLine(this)
            SweepParams.Baseline_V = this.Baseline_V;
            SweepParams.PulseVoltage_V = this.PulseVoltage_V;
            SweepParams.Compliance_Main_A = this.Compliance2450_A;
            SweepParams.Compliance_Gate_A = this.Compliance2450_Gate_A;
            SweepParams.Bias_V = this.Bias_V;
            SweepParams.NPLC = this.NPLC;
            SweepParams.PulseWidth_s = this.PulseWidth_s;
            SweepParams.OffTime_s = this.OffTime_s;
            SweepParams.NumPulses = this.NumPulses;
            SweepParams.KeepGateAtBaselineWhenComplete = this.KeepGateAtBaselineWhenComplete;
            SweepParams.KeepMainAtBiasWhenComplete = this.KeepMainAtBiasWhenComplete;
            SweepParams.MainFourWire = this.MainFourWire;
            SweepParams.AutoZero = this.AutoZero;
            SweepParams.SourceReadback = this.SourceReadback;

            stringLine = "Keithley 2450 Double Gate Sweep";

            sweepParamsStr = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", SweepParams);

            stringLine = stringLine + " || Parameters: " + sweepParamsStr;
        end

        function headersString = GetHeaders(this)
            %Data file headers, as a single tab-separated string (the
            %DataWriter writes the headers argument as one line)
            headersString = strjoin(this.GetHeaderNames(), sprintf('\t'));
        end

        function hdrs = GetHeaderNames(~)
            %Column names, in the order the columns are written in
            %OnDoubleGateSweepComplete
            hdrs = ["Gate_Voltage_V", "Current_A", ...
                "Gate_Leakage_Current_A", "Bias_Voltage_V", ...
                "Time_s", "Time_Gate_Instr_s"];
        end

        function tf = IsMeasurementLoopRunning(this)
            %true if Palladium's measurement loop is running, i.e. ticks
            %are calling Measure on the instruments
            tf = false;
            if isempty(this.ParentController); return; end
            try
                tf = this.ParentController.TimingLoopController.State == "Running";
            catch
                tf = false;
            end
        end

        function RetrieveSettingsFromGUIStruct(this, sweepData)

            %Measurement 2450 Settings. The GUI gives compliance in mA
            this.Bias_V = sweepData.BiasV;
            this.Compliance2450_A = sweepData.Meas_Compliance_mA * 1e-3;

            %Gate 2450 Settings
            this.SecondInstrument = sweepData.GateInstr;
            this.Compliance2450_Gate_A = sweepData.Gate_Compliance_mA * 1e-3;
            this.Baseline_V = sweepData.Baseline_V;
            this.PulseVoltage_V = sweepData.StepSize_V;
            this.NumPulses = sweepData.NumSteps;
            this.PulseWidth_s = sweepData.PulseWidth_s;
            this.OffTime_s = sweepData.OffTime_s;

            %The GUI's "No of steps" is how many PulseVoltage_V steps the
            %sweep goes out either side of the baseline - each step takes
            %two pulses (one each side), so NumPulses = 2 * steps. Only
            %present if the GUI's GatherSettings sends it
            if isfield(sweepData, "NumSteps")
                this.NumPulses = 2 * sweepData.NumSteps;
            end

            %Shared settings
            this.NPLC = sweepData.NPLC;
            
            %Only present if the GUI's GatherSettings sends it - otherwise
            %the property keeps its current value (default true)
            if isfield(sweepData, "KeepGateAtBaselineWhenComplete")
                this.KeepGateAtBaselineWhenComplete = sweepData.KeepGateAtBaselineWhenComplete;
            end
            if isfield(sweepData, "KeepMainAtBiasWhenComplete")
                this.KeepMainAtBiasWhenComplete = sweepData.KeepMainAtBiasWhenComplete;
            end
            if isfield(sweepData, "MainFourWire")
                this.MainFourWire = sweepData.MainFourWire;
            end
            if isfield(sweepData, "AutoZero")
                this.AutoZero = sweepData.AutoZero;
            end
            if isfield(sweepData, "SourceReadback")
                this.SourceReadback = sweepData.SourceReadback;
            end

            %Save file Settings
            this.FileSettings.SaveSweepFile = sweepData.SaveSweepFile;
            this.FileSettings.FileName = sweepData.FileName;
        end


        function SetInstrumentList(this, listOfAllInstrs)

            %Only add Keithley 2450 instances that are not the parent -
            %filter out the rest

            if isempty(listOfAllInstrs)
                warndlg("No additional instruments added. Double Gate Sweep requires two Keithleys to be live, or it cannot run");
                return;
            end

            kInstrs = [];
            for i = 1 : length(listOfAllInstrs)
                instr = listOfAllInstrs{i};

                if isa(instr, "Palladium.Instruments.Keithley2450")
                    if~strcmp(instr.Name, this.Instrument.Name)

                        if isempty(kInstrs)
                            kInstrs = instr;
                        else
                            kInstrs(end+1) = instr; %#ok<AGROW>
                        end
                    end
                end
            end

            %Pass on to update the drop-down in the GUI
            this.GUIView.SetInstrumentList(kInstrs);
        end

        function UpdatePlotterSavedPlotTitle(this)
            if isempty(this.Plotter) || isempty(this.DataWriter); return; end
            this.Plotter.TitleForCopiedPlots = this.DataWriter.FileWriteDetails.FileName;
        end

        function WriteData(this, sweepData)
            %Write final details to file if option selected (and a data
            %file was set up - see Run)
            if this.FileSettings.SaveSweepFile && ~isempty(this.DataWriter)
                this.DataWriter.WriteData(sweepData);

                %Add in an end-of sweep metadata line
                this.InsertEndMetadataIntoFile(this.DataWriter);
            end
        end
    end

    %% Methods (Static, Protected)
    methods (Static, Access = protected)

        function oneLine = CollapseScriptToOneLine(script)
            %Collapse a multi-line TSP snippet into a single physical
            %line, joined with plain spaces. This avoids embedded newline
            %characters, which appear to get treated as message boundaries
            %somewhere in the GPIB path and split scripts into broken
            %fragments. Using spaces (not semicolons) avoids
            %leading-empty-statement issues right after do/then/else (the
            %2450 runs Lua 5.0) - Lua doesn't require any separator between
            %statements at all.
            lines = splitlines(string(script));
            keptLines = strings(0,1);

            for i = 1 : length(lines)
                line = extractBefore(lines(i) + "--", "--");  %drop any inline comments (guard the case of no "--" present)
                line = strtrim(line);
                if strlength(line) > 0
                    keptLines(end+1,1) = line; %#ok<AGROW>
                end
            end

            oneLine = strjoin(keptLines, " ");
        end

        function values = ParseBufferString(str)
            %Convert a comma-separated printbuffer(...) response string
            %into a numeric row vector.
            values = str2double(strsplit(strtrim(string(str)), ","));
        end

        function range = SourceRangeFor(levels)
            %Value to send as a fixed smu.source.range so every level fits:
            %the instrument picks the smallest range at least this big.
            %20 mV is the smallest voltage range
            range = max([abs(levels(:)); 0.02]);
        end

    end
end
