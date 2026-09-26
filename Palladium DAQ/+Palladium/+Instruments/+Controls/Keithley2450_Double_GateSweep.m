classdef Keithley2450_Double_GateSweep < Palladium.Core.InstrumentControlBase
    %KEITHLEY2450_DOUBLE_GATESWEEP - Logic controller add-on object to be
    %added on to a Keithley2450 Instrument, where it drives a
    %digital-I/O-triggered "double gate sweep": the 2450 or 2470 (this Control's
    %parent Instrument) sources a zig-zag pulse train while a second SMU
    %(a Keithley2450 or 2470, referenced by name via SecondInstrumentName) sources
    %a fixed bias and measures current in lock-step, triggered off a
    %shared digital I/O line. Both instruments run their own on-board TSP
    %script so the pulse-and-measure timing loop does not need a
    %Python/MATLAB round trip per point.
    

    %% Properties (Public) - Sweep Parameters
    properties (Access = public)
        Baseline_V       (1,1) double = 0;         %V, applied by the 2450 between pulses
        PulseVoltage_V   (1,1) double = 0.0001;     %V, step size added on the 2450 each half-cycle
        Compliance2450_A (1,1) double = 0.0001;     %A, 2450 current limit
        Compliance2450_Gate_A (1,1) double = 0.0001;     %A, 2450_Gate_ current limit

        Bias_V       (1,1) double = 0;          %V, small bias voltage sourced by the parent instr for measurement
        NPLC = 0.01;

        PulseWidth_s     (1,1) double {mustBeNonnegative} = 0;   %s, dwell time at each source level before triggering/measuring
        OffTime_s        (1,1) double {mustBeNonnegative} = 0;   %s, gap between points

        NumPulses        (1,1) double {mustBeInteger, mustBePositive} = 800;

        DigioLine        (1,1) double {mustBeInteger, mustBePositive} = 6;   %2450 digital I/O line -> 2470 digital I/O line (must be wired straight across)
        ActiveLow        (1,1) logical = true;      %true: idle HIGH, pulse LOW to trigger a measurement
        FileSettings = struct("SaveSweepFile", true, "FileName", "SweepFileName");
    end

    %% Properties (Public, Protected Set) - Results of the last Run()
    properties (GetAccess = public, SetAccess = protected)
        Running = false;
        TimeElapsed_s = 0;
    end

    %% Properties (Protected)
    properties (Access = protected)
        SecondInstrument;           %Palladium.Core.Instrument reference for the second (bias/measure) SMU
        ParentController;           %Palladium.Core.Controller reference, stored so Run() can log via the standard Controller.Log path
        GUIView;        
        timerVal;
    end

    %% Properties (Private)
    properties (Access = private)
        Plotter;
        DataWriter;
    end

    %% Constructor
    methods
        function this = Keithley2450_Double_GateSweep()
        end
    end

    %% Methods (Public)
    methods (Access = public)

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
            addlistener(comp, 'Run', @(src,evnt)this.Run(evnt.SweepDetails));
            addlistener(comp, 'Abort', @(src,evnt)this.Abort());
            addlistener(comp, 'InsertSmartTag', @(src,evnt)this.InsertSmartTagRequest(src, evnt, controller));

            %Add a plotter as well, to the right
            this.Plotter = controller.AddNewPlotter(grid, Size="Medium", RegisterPlotter=false);    %Don't register the plotter centrally, as we will push data to it only when the sweep is running, and clear it on sweep start. This does mean, for now at least, that the Plotter is not hooked up
            this.Plotter.Layout.Row = 1;
            this.Plotter.Layout.Column = 4;
            ltr = addlistener(this.Plotter, 'AxesSelectionChange', @(src,evnt)this.PlotterAxesSelectionChange(src));
            this.RegisterEventListener(ltr);
        end

        function RemoveControl(this, ~)
            if ~isempty(this.GUIView)
                delete(this.GUIView);
                this.GUIView = [];
            end
        end

        function SetSecondInstrument(this, instr)
            %Manually attach the second (bias/measure) SMU Instrument
            %reference - use this instead of SecondInstrumentName when
            %driving the Control directly, outside of the normal
            %Controller-managed GUI flow.
            arguments
                this;
                instr (1,1) Palladium.Core.Instrument;
            end

            this.SecondInstrument = instr;
        end

        function Abort(this)
            %Best-effort abort - Run() blocks waiting for each instrument's
            %TSP loop to finish and print "DONE", so this can only turn the
            %outputs off after that wait returns (eg after a timeout); it
            %cannot interrupt an in-flight GPIB read.
            this.Running = false;
            this.TimeElapsed_s = 0;

            if ~isempty(this.Instrument)
                this.Instrument.WriteCommand("smu.source.output = smu.OFF");
            end
            if ~isempty(this.SecondInstrument)
                this.SecondInstrument.WriteCommand("smu.source.output = smu.OFF");
            end
        end

        function Run(this, sweepDetails)
            arguments
                this;
                sweepDetails = [];%Optional parameter, to allow running headless without GUI event calling this
            end
            %RUN - Configure both SMUs, run the triggered pulse train, and
            %pull the resulting buffers back. Blocking - waits for both
            %instruments to report "DONE".

            if ~isempty(sweepDetails)
                this.RetrieveSettingsFromGUIStruct(sweepDetails);
            end

            assert(~isempty(this.Instrument), "Keithley2450_Double_GateSweep has no parent Instrument set (this.Instrument) - it must be added as a Control on a Keithley2450, or have Instrument set manually first.");
            assert(~isempty(this.SecondInstrument), "Keithley2450_Double_GateSweep has no SecondInstrument set - either set SecondInstrumentName before CreateInstrumentControlGUI runs, or call SetSecondInstrument(instr) directly.");

            %Create data writer if a data file is being written
            this.CreateDataFile(this.FileSettings.SaveSweepFile);
            this.UpdatePlotterSavedPlotTitle();

            this.Running = true;
            this.timerVal = tic();

            numMeasurements = this.NumPulses * 2;   %zig-zag: baseline, pulse, baseline, pulse, ...

            if this.ActiveLow
                idleState = "STATE_HIGH";
                pulseState = "STATE_LOW";
            else
                idleState = "STATE_LOW";
                pulseState = "STATE_HIGH";
            end

            this.Log("Configuring (bias/measure) and (source/pulse) SMUs...");
            this.ConfigureMainInstrument(numMeasurements);
            this.ConfigureSecondInstrument(numMeasurements, idleState);

            loop2450 = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.CollapseScriptToOneLine(this.BuildLoop2450_Meas_Script(numMeasurements, idleState, pulseState));
            loop2450_Gate = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.CollapseScriptToOneLine(this.BuildLoop2450_Gate_Script(idleState, pulseState));

            %Arm the 2450_Gate_ first, THEN start the 2450, so no pulse is missed
            this.Log("Arming 2450_Gate_ trigger loop...");
            this.SecondInstrument.WriteCommand(loop2450_Gate);
            this.Log("Starting 2450 pulse train...");
            this.Instrument.WriteCommand(loop2450);

            this.Log("Waiting for 2450_Gate to finish...");
            resp2450_Gate = strtrim(this.SecondInstrument.ReadString());
            this.Log("2450_Gate_ says: " + string(resp2450_Gate));

            this.Log("Waiting for 2450 to finish...");
            resp2450 = strtrim(this.Instrument.ReadString());
            this.Log("2450 says: " + string(resp2450));

            data = this.PullBufferData(numMeasurements);

            this.Running = false;
            this.TimeElapsed_s = toc(this.timerVal);
            this.Log("Double gate sweep complete in " + num2str(this.TimeElapsed_s) + " s.");

            this.OnDoubleGateSweepComplete(data);
        end

        function OnDoubleGateSweepComplete(this, data)
            this.Running = false;

            %Unpack the data to plot
            sweepData = [data.Voltage_2450_Gate, data.Current_2450];

            %Plot the data
            this.Plotter.PlotData(sweepData);

            %Write the data (will check if Save to File is selected)
            this.WriteData(sweepData)

            %Update the View
            this.GUIView.SweepComplete();

            %Loop the next one if in Continuous mode
            if this.GUIView.IsContinuousSelected()
                this.GUIView.RunSweep();
            end
        end

        function OnMeasurementsStarted(this)
            this.GUIView.EnableRunButton();
        end
    end

    %% Methods (Protected)
    methods (Access = protected)

        function ConfigureMainInstrument(this, numMeasurements)
            instr = this.SecondInstrument;

            instr.WriteCommand("reset()");
            instr.WriteCommand("smu.source.func = smu.FUNC_DC_VOLTAGE");
            instr.WriteCommand("smu.source.autorange = smu.OFF");
            instr.WriteCommand("smu.source.range = 0.2");
            instr.WriteCommand("smu.source.level = " + num2str(this.Bias_V));
            instr.WriteCommand("smu.source.ilimit.level = " + num2str(this.Compliance2450_A));

            instr.WriteCommand("smu.measure.func = smu.FUNC_DC_CURRENT");
            instr.WriteCommand("smu.measure.autorange = smu.OFF");
            instr.WriteCommand("smu.measure.range = " + num2str(this.Compliance2450_A));
            instr.WriteCommand("smu.measure.nplc = " + num2str(this.NPLC));

            instr.WriteCommand("digio.line[" + num2str(this.DigioLine) + "].mode = digio.MODE_DIGITAL_IN");

            instr.WriteCommand("smu.source.output = smu.ON");
            instr.WriteCommand("buffer2 = buffer.make(" + num2str(numMeasurements) + ")");
        end

        function ConfigureSecondInstrument(this, numMeasurements, idleState)
            %The 2450 that will sweep the gate voltage, while the Main one measures current, with a fixed voltage bias
            instr = this.Instrument;

            instr.WriteCommand("reset()");
            instr.WriteCommand("smu.source.func = smu.FUNC_DC_VOLTAGE");
            instr.WriteCommand("smu.source.autorange = smu.OFF");
            instr.WriteCommand("smu.source.range = 0.2");
            instr.WriteCommand("smu.source.ilimit.level = " + num2str(this.Compliance2450_Gate_A));
            instr.WriteCommand("smu.source.autodelay = smu.OFF");

            instr.WriteCommand("smu.measure.func = smu.FUNC_DC_CURRENT");
            instr.WriteCommand("smu.measure.autorange = smu.OFF");
            instr.WriteCommand("smu.measure.range = " + num2str(this.Compliance2450_Gate_A));
            instr.WriteCommand("smu.measure.nplc = " + num2str(this.NPLC));

            instr.WriteCommand("digio.line[" + num2str(this.DigioLine) + "].mode = digio.MODE_DIGITAL_OUT");
            instr.WriteCommand("digio.line[" + num2str(this.DigioLine) + "].state = digio." + idleState);

            instr.WriteCommand("smu.source.output = smu.ON");
            instr.WriteCommand("buffer1 = buffer.make(" + num2str(numMeasurements) + ")");
        end

        function script = BuildLoop2450_Meas_Script(this, numMeasurements, idleState, pulseState)
            %TIMING LOOP - has to go as a single TSP script, since it's the
            %part that has to run without any MATLAB/GPIB round-trip per
            %point for speed. Everything it references (buffer2, digio
            %mode, smu settings) was already configured via individual
            %commands in ConfigureMainInstrument.
            nStr = num2str(numMeasurements);
            lineStr = num2str(this.DigioLine);
            nl = newline;

            script = "for i = 1, " + nStr + " do" + nl + ...
                "    while digio.line[" + lineStr + "].state == digio." + idleState + " do end" + nl + ...
                "    smu.measure.read(buffer2)" + nl + ...
                "    while digio.line[" + lineStr + "].state == digio." + pulseState + " do end" + nl + ...
                "end" + nl + ...
                "smu.source.output = smu.OFF" + nl + ...
                "print(""DONE"")" + nl;
        end

        function script = BuildLoop2450_Gate_Script(this, idleState, pulseState)
            %TIMING LOOP - see note on BuildLoop2450_Gate_Script. zig-zag baseline/pulse stepping from the original: each pulse steps further from Baseline_V by
            %PulseVoltage_V, alternating sign every other pulse.
            lineStr = num2str(this.DigioLine);
            baselineStr = num2str(this.Baseline_V);
            pulseVStr = num2str(this.PulseVoltage_V);
            nl = newline;

            script = "local function do_point(v)" + nl + ...
                "    smu.source.level = v" + nl + ...
                "    delay(" + num2str(this.PulseWidth_s) + ")" + nl + ...
                "    digio.line[" + lineStr + "].state = digio." + pulseState + nl + ...
                "    smu.measure.read(buffer1)" + nl + ...
                "    delay(" + num2str(this.OffTime_s) + ")" + nl + ...
                "    digio.line[" + lineStr + "].state = digio." + idleState + nl + ...
                "end" + nl + ...
                nl + ...
                "for i = 0, " + num2str(this.NumPulses) + " - 1 do" + nl + ...
                "    do_point(" + baselineStr + ")" + nl + ...
                nl + ...
                "    local half = math.floor(i / 2) + 1" + nl + ...
                "    local v" + nl + ...
                "    if math.mod(i, 2) == 0 then" + nl + ...
                "        v = " + baselineStr + " + half * " + pulseVStr + nl + ...
                "    else" + nl + ...
                "        v = " + baselineStr + " - half * " + pulseVStr + nl + ...
                "    end" + nl + ...
                "    do_point(v)" + nl + ...
                "end" + nl + ...
                nl + ...
                "smu.source.output = smu.OFF" + nl + ...
                "print(""DONE"")" + nl;
        end

        function data = PullBufferData(this, numMeasurements)
            %Pull data back - one bulk transfer per instrument, not per
            %point.
            this.Log("Pulling buffer data back from both SMUs...");

            V2450Str = this.Instrument.QueryString("printbuffer(1, " + num2str(numMeasurements) + ", buffer1.sourcevalues)");
            data.SourceVoltage_2450 = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.ParseBufferString(V2450Str);

            I2450Str = this.Instrument.QueryString("printbuffer(1, " + num2str(numMeasurements) + ", buffer1.readings)");
            data.Current_2450 = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.ParseBufferString(I2450Str);

            T2450Str = this.Instrument.QueryString("printbuffer(1, " + num2str(numMeasurements) + ", buffer1.relativetimestamps)");
            data.Time_2450 = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.ParseBufferString(T2450Str);

            I2450_Gate_Str = this.SecondInstrument.QueryString("printbuffer(1, " + num2str(numMeasurements) + ", buffer2.readings)");
            data.Current_2450_Gate_ = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.ParseBufferString(I2450_Gate_Str);

            V2450_Gate_Str = this.SecondInstrument.QueryString("printbuffer(1, " + num2str(numMeasurements) + ", buffer2.sourcevalues)");
            data.Voltage_2450_Gate = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.ParseBufferString(V2450_Gate_Str);

            T2450_Gate_Str = this.SecondInstrument.QueryString("printbuffer(1, " + num2str(numMeasurements) + ", buffer2.relativetimestamps)");
            data.Time_2450_Gate = Palladium.Instruments.Controls.Keithley2450_Double_GateSweep.ParseBufferString(T2450_Gate_Str);
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

    end

    %% Methods (Private)
    methods (Access = private)

        function CreateDataFile(this, writeToFile)
            %Create or reset the data writer class
            fileNameSuffix = this.FileSettings.FileName;
            this.DataWriter = this.InitialiseDataWriter(fileNameSuffix);

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

            stringLine = "Keithley 2450 Double Gate Sweep";

            sweepParamsStr = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", SweepParams);

            stringLine = stringLine + " || Parameters: " + sweepParamsStr;
        end

        function hdrs = GetHeaders(this)

            hdrs = ["Voltage_2450_Gate", "Current_2450", ...
                "Current_2450_Gate_", "SourceVoltage_2450", ...
                "Time_2450", "Time_2450_Gate"];
        end

        function RetrieveSettingsFromGUIStruct(this, sweepData)

            %Measurement 2450 Settings
            this.Bias_V = sweepData.BiasV;
            this.Compliance2450_A = sweepData.Meas_Compliance_mA;

            %Gate 2450 Settings
            this.SecondInstrument = sweepData.GateInstr;
            this.Compliance2450_Gate_A = sweepData.Gate_Compliance_mA;
            this.Baseline_V = sweepData.Baseline_V;
            this.PulseVoltage_V = sweepData.StepSize_V;
            this.PulseWidth_s = sweepData.PulseWidth_s;
            this.OffTime_s = sweepData.OffTime_s;

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
            this.Plotter.TitleForCopiedPlots = this.DataWriter.FileWriteDetails.FileName;
        end

        function WriteData(this, sweepData)
            %Write final details to file if option selected
            if this.FileSettings.SaveSweepFile
                this.DataWriter.WriteData(sweepData);

                %Add in an end-of sweep metadata line
                this.InsertEndMetadataIntoFile(this.DataWriter);
            end
        end
    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function values = ParseBufferString(str)
            %Convert a comma-separated printbuffer(...) response string
            %into a numeric row vector.
            values = str2double(strsplit(strtrim(string(str)), ","));
        end

        function oneLine = CollapseScriptToOneLine(script)
            %Collapse a multi-line TSP snippet into a single physical
            %line, joined with plain spaces. This avoids embedded newline
            %characters, which appear to get treated as message boundaries
            %somewhere in the GPIB path and split scripts into broken
            %fragments. Using spaces (not semicolons) avoids
            %leading-empty-statement issues right after do/then/else on
            %Lua 5.1 - Lua doesn't require any separator between
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

    end
end
