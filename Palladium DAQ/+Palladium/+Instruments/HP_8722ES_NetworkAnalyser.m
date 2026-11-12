classdef HP_8722ES_NetworkAnalyser < Palladium.Core.Instrument
    %HP_8722ES_NetworkAnalyser - Instrument driver for the HP 8722ES vector network analyser.
    %Records whole frequency sweeps through the VNA Control tab, rather
    %than a value each measurement tick: each scan is saved to its own data
    %file as two columns, frequency (Hz) and the S-parameter measured.
    %`Measure` returns no values, so the analyser adds no columns to the
    %main data file.
    %
    %From a script, with no GUI: create and connect the instrument, then
    %`RunMeasurement` takes the whole measurement as named arguments, e.g.
    %`data = vna.RunMeasurement(Channel = 3, MeasMode = "S21", NumPoints = 401, Wait = true)`.
    %Any argument left out keeps what the analyser has. Without `Wait` it
    %only starts the sweep: poll `CheckScanComplete`, then read it with
    %`GetCompletedScanData`. The VNA Control tab does the same through
    %`RunScan(scanDetails)`, which is `RunMeasurement` with the settings in
    %a struct. The S-parameter and units are therefore not settings of the
    %instrument: `MeasMode` and `MeasUnit` only record the last measurement
    %started (or recalled), to label its data.
    %
    %Before each sweep the driver applies the settings given:
    %frequency range, number of points (one of the analyser's: 3, 11, 21,
    %26, 51, 101, 201, 401, 801 or 1601 - the nearest is used), sweep time
    %(0 for automatic) and linear or log sweep, then the S-parameter and the
    %display format for the units (log magnitude for dB, linear magnitude
    %for Absolute). It then takes one sweep
    %(`OPC?;NUMG1;`), checking for its completion each tick without
    %waiting. The trace is read as ASCII (`FORM4;`, `OUTPFORM;`) and the
    %frequency of each point from the limit-test array (`OUTPLIML;`), which
    %gives them for linear, log and list sweeps alike. Set the power and
    %calibration on the analyser. The tab starts from the analyser's own
    %settings (`GetScanSettings`). (Commands from the 8719ES/8720ES/8722ES
    %Programmer's Guide.)
    %
    %Channels: the analyser has four - 1 and 2, and the auxiliary channels
    %3 and 4 (of 1 and 2), which exist only once switched on (Display, AUX
    %CHAN ON). Every setting and the trace data belong to the *active*
    %channel, so each scan names its channel (the VNA Control's Channel
    %drop-down, scanDetails.Channel): `RunScan` selects it (`SelectChannel`,
    %checked by asking the analyser which is active), `GetCompletedScanData`
    %checks it is still the active one before reading, and the tab shows
    %that channel's own settings. With no Channel given, the active
    %channel is used. The channels' stimulus (frequencies, points) is
    %shared while Sweep Setup, COUPLED CH is on (the preset), so setting it
    %on one changes the other too - the tab shows what the analyser ends
    %up with after each scan.
    %
    %A sweep is taken with `NUMG1;` (one group: whatever the analyser needs
    %to update the measurement once, e.g. both directions for a 2-port
    %calibration) rather than a single sweep. After a change of the number
    %of points the manual says to wait two sweeps, so that sweep is
    %`NUMG2;`.
    %
    %`LoadSavedData` (or Run with `scanDetails.LoadRegister`) recalls an
    %analyser save/recall register (1 to 31) and reads its trace without
    %sweeping. The register holds the trace only if it was saved with the
    %data array (Save/Recall, DEFINE DISK-SAVE DATA: DATA ARRAY ON or
    %FORMATTED ARRAY ON) - otherwise it only restores the instrument state.
    %
    %The 8722ES (50 MHz to 40 GHz) is remote-controlled over HP-IB (GPIB)
    %only - its RS-232 and parallel ports are for printers and plotters.
    %Other analysers in the HP 8719/8720/8722 ES and ET family share its
    %HP-IB command set and should work too.

    %% Properties (Public)
    properties(Access = public)
        FullName = "HP 8722ES Network Analyser";                %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'HP_8722ES_NetworkAnalyser';                     %Instrument name, used as the prefix of its scan data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end

    %% Properties (Public, Read Only)
    properties(SetAccess = private)
        MeasMode;                                               %S-parameter (S11, S21, S12 or S22) of the last measurement started by RunMeasurement or RecallRegister - labels its data. Chosen per measurement (RunMeasurement, or the VNA Control), not an instrument setting
        MeasUnit;                                               %Units of the last measurement: dB (log magnitude), Absolute (linear magnitude) or Real/Imaginary (the complex value, for a Smith chart)
    end

    %% Properties (Constant)
    properties(Constant, Access = public)
        NumPointsChoices = [3, 11, 21, 26, 51, 101, 201, 401, 801, 1601];   %The numbers of points the analyser takes (POIN) - anything else is rounded to the nearest. The VNA Control snaps its Number of points to these
    end

    %% Properties (Private)
    properties(Access = private)
        ScanChannel = 0;                                        %The channel (1-4) of the last scan started by RunScan, 0 if not known - checked to be the active one before its data is read
        SimulatedChannel = 1;                                   %In SimulationMode, the active channel
        ScanComplete = true;                                    %False while a sweep started by RunScan is under way
        SweepSettings = struct("StartFrequency_Hz", 50e6, "StopFrequency_Hz", 40e9, "NumPoints", 201, ...
            "SweepTime_s", 0, "SweepType", "Linear");          %The sweep settings read back before the last sweep - answered from here while a sweep is under way, when queries can't be (the reply to OPC? is pending). In SimulationMode, the settings last set
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr);        catOut = this.ConvertToCategorical(inputStr, ["S11", "S21", "S12", "S22"]); end
        function catOut = MeasUnitType(this, inputStr);    catOut = this.ConvertToCategorical(inputStr, ["dB", "Absolute", "Real/Imaginary"]); end
    end

    %% Constructor
    methods
        function this = HP_8722ES_NetworkAnalyser()
            %Set the supported connection types, default settings and Scan Control tab.

            %HP-IB is the only remote-control interface; VISA can address
            %it through a GPIB adapter
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "VISA"]);
            this.GPIB_Address = 16;     %Factory default
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

            %Default settings
            this.MeasMode = this.MeasType("S11");
            this.MeasUnit = this.MeasUnitType("dB");

            %Define the Instrument Controls that can be added
            this.DefineInstrumentControl(Name = "VNA Control", ClassName = "VNAController", TabName = "VNA Control", EnabledByDefault = true);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function complete = CheckScanComplete(this)
            %Check, without waiting, whether the sweep started by RunScan has finished - for the Scan Control tab.
            %The sweep has finished once the reply to OPC?;SING; is waiting
            %(a serial poll); it is then read. In SimulationMode, finishes at
            %random, one call in ten
            %
            %Outputs:
            %   complete - true once the sweep has finished

            if ~this.ScanComplete
                if this.SimulationMode
                    this.ScanComplete = randi(100) > 90;
                elseif this.IsReplyWaiting()
                    this.ReadString();      %The "1" from OPC?
                    this.ScanComplete = true;
                end
            end
            complete = this.ScanComplete;
        end

        function Clear(this)
            %Send a device clear to the instrument, clearing its input and output buffers.

            if this.SimulationMode
                return;
            end

            clrdevice(this.DeviceHandle);
        end

        function metadataStruct = CollectMetaData(this)
            %Sweep settings, recorded in the data-file header.
            %
            %Outputs:
            %   metadataStruct - struct with fields Channel (if known), Freq_Start_Hz, Freq_Stop_Hz and NumPoints

            if this.ScanChannel > 0
                metadataStruct.Channel = this.ScanChannel;
            end
            metadataStruct.Freq_Start_Hz = this.GetStartFrequency();
            metadataStruct.Freq_Stop_Hz = this.GetStopFrequency();
            metadataStruct.NumPoints = this.GetNumPoints();
        end

        function channel = GetActiveChannel(this)
            %The analyser's active channel (OUTPCHAN).
            %
            %Outputs:
            %   channel - 1, 2, 3 or 4 (the selected channel in SimulationMode)

            if this.SimulationMode
                channel = this.SimulatedChannel;
                return;
            end

            channel = this.QueryDouble("OUTPCHAN;");
            assert(ismember(channel, 1:4), "HP_8722ES_NetworkAnalyser:NoActiveChannel", "%s", ...
                this.Name + ": could not read the active channel - OUTPCHAN gave """ + string(channel) + """.");
        end

        function data = GetCompletedScanData(this)
            %The completed sweep, for the Scan Control tab to save and plot.
            %The formatted trace (OUTPFORM sends two values per point; in log
            %and linear magnitude formats the first is the value) and the
            %frequency of each point (the first of OUTPLIML's four values
            %per point), both in ASCII (FORM4) - Programmer's Guide,
            %Examples 3B and 3D. The analyser sends them a line at a time
            %(see QueryNumbers), so every point is read, not just the first
            %
            %Outputs:
            %   data - one row per point: [frequency in Hz, S-parameter in MeasUnit], or
            %          [frequency in Hz, real, imaginary] for Real/Imaginary (polar format,
            %          where OUTPFORM gives the real and imaginary parts)

            complexValues = this.MeasUnit == this.MeasUnitType("Real/Imaginary");
            if this.SimulationMode
                numPoints = this.GetNumPoints();
                frequency = linspace(this.GetStartFrequency(), this.GetStopFrequency(), numPoints)';
                if complexValues
                    gamma = Palladium.Utilities.MathsUtils.SimulatedReflection(numPoints);
                    data = [frequency, real(gamma), imag(gamma)];
                    return;
                end
                values = this.GenerateSimulatedData(numPoints, 1, Baseline=-3, Variance=0.1);
                data = [frequency, values(:)];
                return;
            end

            %The trace and its points belong to the active channel - make
            %sure it is the scan's (it can be changed at the front panel)
            if this.ScanChannel > 0
                this.EnsureChannel(this.ScanChannel);
            end

            %Two numbers per point for the trace, four for the limit test
            numPoints = this.GetNumPoints();
            this.WriteCommand("FORM4;");
            trace = this.QueryNumbers("OUTPFORM;", 2 * numPoints);
            limits = this.QueryNumbers("OUTPLIML;", 4 * numPoints);
            this.DiscardUnexpectedReplies();

            values = trace(1:2:end);
            frequency = limits(1:4:end);
            assert(numel(trace) == 2 * numPoints && numel(limits) == 4 * numPoints && numel(values) == numel(frequency), ...
                "HP_8722ES_NetworkAnalyser:DataSizeMismatch", "%s", ...
                this.Name + ": expected " + numPoints + " points (POIN) but the trace has " + numel(trace) / 2 + " and the frequency list " + numel(limits) / 4 + ".");
            if complexValues
                data = [frequency(:), values(:), reshape(trace(2:2:end), [], 1)];
            else
                data = [frequency(:), values(:)];
            end
        end

        function controls = GetExtraScanControls(~)
            %Extra settings for the VNA Control tab to offer, beside the sweep settings - a Channel drop-down.
            %The tab adds a control for each, passes its value in
            %scanDetails under the Name (and to GetScanSettings as the
            %selection), and refreshes its settings from the analyser when
            %it changes. Types: "dropdown" (Items), "number" (Limits) and
            %"checkbox"
            %
            %Outputs:
            %   controls - struct array: Name, Label, Tooltip, Type, Items, Value

            controls = struct("Name", "Channel", "Label", "Channel", ...
                "Tooltip", "The analyser's channel to measure - the settings below are that channel's. 3 and 4 are the auxiliary channels of 1 and 2 (Display, AUX CHAN ON on the analyser)", ...
                "Type", "dropdown", "Items", {["1", "2", "3", "4"]}, "Value", "1");
        end

        function [Headers, Units] = GetHeaders(~)
            %No per-tick data columns - scans are recorded through the Scan Control tab.
            %
            %Outputs:
            %   Headers - empty
            %   Units   - empty

            Headers = [];
            Units = [];
        end

        function numOfPoints = GetNumPoints(this)
            %Read the number of points per sweep.
            %
            %Outputs:
            %   numOfPoints - number of points (201 in SimulationMode, until set)

            if this.SimulationMode || ~this.ScanComplete
                numOfPoints = this.SweepSettings.NumPoints;
                return;
            end

            numOfPoints = this.QueryDouble("POIN?;");
        end

        function [Headers, Units] = GetScanHeaders(this)
            %Column headers and units of the scan data files written by the Scan Control tab.
            %
            %Outputs:
            %   Headers - frequency and S-parameter headers, e.g. "HP_8722ES_NetworkAnalyser - S11 (dB)",
            %             or "... - S11 Real" and "... - S11 Imaginary" for Real/Imaginary
            %   Units   - their units: "Hz", and "dB" or "" for the S-parameter

            if this.MeasUnit == this.MeasUnitType("Real/Imaginary")
                Headers = [this.Name + " - Frequency_Hz", this.Name + " - " + string(this.MeasMode) + " Real", this.Name + " - " + string(this.MeasMode) + " Imaginary"];
                Units = ["Hz", "", ""];
                return;
            end
            Headers = [this.Name + " - Frequency_Hz", this.Name + " - " + string(this.MeasMode) + " (" + string(this.MeasUnit) + ")"];
            if this.MeasUnit == this.MeasUnitType("dB")
                Units = ["Hz", "dB"];
            else
                Units = ["Hz", ""];
            end
        end

        function settings = GetScanSettings(this, selection)
            %The analyser's current sweep settings, for the VNA Control tab to start from - the fields RunScan takes.
            %While a sweep is under way, those read back before it started.
            %The sweep time is the analyser's actual one - automatic can't be
            %read back. Settings belong to a channel: with selection.Channel
            %the analyser is switched to that channel first (so the tab can
            %show another channel's settings); an unavailable channel
            %(e.g. 3 with the auxiliary channels off) is an error
            %
            %Inputs:
            %   selection - (optional) struct, with the field Channel (1-4) to read. Default: the active channel
            %
            %Outputs:
            %   settings - struct: Channel (1-4), StartFrequency_Hz, StopFrequency_Hz, NumPoints,
            %              SweepTime_s, SweepType ("Linear" or "Log"), MeasMode
            %              and MeasUnit (text)

            arguments
                this;
                selection (1,1) struct = struct();
            end

            measMode = string(this.MeasMode);
            measUnit = string(this.MeasUnit);
            if this.SimulationMode || ~this.ScanComplete
                settings = this.SweepSettings;
                settings.Channel = max(this.ScanChannel, 1);
                if this.SimulationMode
                    if isfield(selection, "Channel") && ~isempty(selection.Channel)
                        this.SelectChannel(this.ChannelNumber(selection.Channel));
                    end
                    settings.Channel = this.SimulatedChannel;
                end
            else
                if isfield(selection, "Channel") && ~isempty(selection.Channel)
                    this.SelectChannel(this.ChannelNumber(selection.Channel));
                end
                settings = this.ReadSweepSettings();
                settings.Channel = this.GetActiveChannel();
                [measMode, measUnit] = this.ReadMeasurementFormat();
            end
            settings.MeasMode = measMode;
            settings.MeasUnit = measUnit;
        end

        function startFreq_Hz = GetStartFrequency(this)
            %Read the sweep start frequency, in Hz.

            if this.SimulationMode || ~this.ScanComplete
                startFreq_Hz = this.SweepSettings.StartFrequency_Hz;
                return;
            end

            startFreq_Hz = this.QueryDouble("STAR?;");
        end

        function stopFreq_Hz = GetStopFrequency(this)
            %Read the sweep stop frequency, in Hz.

            if this.SimulationMode || ~this.ScanComplete
                stopFreq_Hz = this.SweepSettings.StopFrequency_Hz;
                return;
            end

            stopFreq_Hz = this.QueryDouble("STOP?;");
        end

        function data = LoadSavedData(this, register)
            %Recall an analyser save/recall register and read its trace, without sweeping - for scripts (the VNA Control's Load does it as a scan).
            %See RecallRegister for what the register must hold
            %
            %Inputs:
            %   register - whole number, 1 to 31
            %
            %Outputs:
            %   data - as GetCompletedScanData

            this.RecallRegister(register);
            data = this.GetCompletedScanData();
        end

        function [dataRow] = Measure(~)
            %Return no values - scans are recorded through the Scan Control tab instead.
            %
            %Outputs:
            %   dataRow - empty, matching GetHeaders

            dataRow = [];
        end

        function RecallRegister(this, register)
            %Recall one of the analyser's save/recall registers (1-31), taking on its channel, measurement and display format - for loading saved data.
            %The analyser is put in hold so that the register's trace stays
            %on screen rather than being swept over (the trace is there
            %only if the register was saved with the data array: Save/Recall,
            %DEFINE DISK-SAVE DATA, DATA ARRAY ON or FORMATTED ARRAY ON). Read
            %it with GetCompletedScanData, or use LoadSavedData. An empty
            %register is an error (the analyser reports error 55). The
            %scan's channel becomes the register's active channel, and
            %MeasMode and MeasUnit are set to what it measured, so the data's
            %headers are right. Do not call during a sweep
            %
            %Inputs:
            %   register - whole number, 1 to 31

            arguments
                this;
                register (1,1) {mustBeInteger, mustBeInRange(register, 1, 31)};
            end

            if this.SimulationMode
                return;
            end

            this.Clear();
            this.ReadErrorQueue();      %Old errors are not this recall's

            %RECAREG01-31 are OPC-compatible: reply 1 when done
            this.QueryDouble(sprintf("OPC?;RECAREG%02d;", register));
            this.WriteCommand("HOLD;");
            errors = this.ReadErrorQueue();
            assert(~any(errors == 55), "HP_8722ES_NetworkAnalyser:EmptyRegister", "%s", ...
                this.Name + ": register " + register + " has no saved instrument state (analyser error 55).");

            this.ScanChannel = this.GetActiveChannel();
            [measMode, measUnit] = this.ReadMeasurementFormat();
            this.MeasMode = this.MeasType(measMode);
            this.MeasUnit = this.MeasUnitType(measUnit);
            this.SweepSettings = this.ReadSweepSettings();
            this.ScanComplete = true;
        end

        function data = RunMeasurement(this, options)
            %Start one measurement - a sweep on a channel with the settings given - from a script or the VNA Control tab.
            %Selects the channel (the active one if not given), applies each
            %setting given - leaving the others as the analyser has them -
            %then selects the S-parameter and the display format for the
            %units, and starts one sweep without waiting (see
            %CheckScanComplete, GetCompletedScanData), or with Wait reads
            %the data as well. A device clear first discards any reply left
            %from an aborted sweep. The settings are read back before the
            %sweep starts, for the data file's metadata. MeasMode and
            %MeasUnit then record what was measured.
            %S-parameter and units not given are the channel's own (read
            %from the analyser; if it is showing something else, e.g. phase,
            %the last measurement's are set instead)
            %Example: data = vna.RunMeasurement(Channel = 3, MeasMode = "S21", MeasUnit = "dB", NumPoints = 401, Wait = true);
            %
            %Inputs (all optional name-value arguments):
            %   Channel           - 1 to 4 (3 and 4 are the auxiliary channels, Display, AUX CHAN ON)
            %   MeasMode          - "S11", "S21", "S12" or "S22"
            %   MeasUnit          - "dB", "Absolute" or "Real/Imaginary"
            %   StartFrequency_Hz - sweep start, in Hz
            %   StopFrequency_Hz  - sweep stop, in Hz
            %   NumPoints         - number of points; the nearest of the analyser's (NumPointsChoices) is used
            %   SweepTime_s       - sweep time, in seconds; 0 for automatic
            %   SweepType         - "Linear" or "Log"
            %   Wait              - true to wait for the sweep and return its data. Default: false
            %   Timeout_s         - longest to wait, in seconds, with Wait. Default: 120
            %
            %Outputs:
            %   data - with Wait, as GetCompletedScanData; otherwise empty

            arguments
                this;
                options.Channel = [];
                options.MeasMode = [];
                options.MeasUnit = [];
                options.StartFrequency_Hz {mustBeNumeric, mustBeScalarOrEmpty, mustBePositive} = [];
                options.StopFrequency_Hz {mustBeNumeric, mustBeScalarOrEmpty, mustBePositive} = [];
                options.NumPoints {mustBeNumeric, mustBeScalarOrEmpty, mustBePositive} = [];
                options.SweepTime_s {mustBeNumeric, mustBeScalarOrEmpty, mustBeNonnegative} = [];
                options.SweepType = [];
                options.Wait (1,1) logical = false;
                options.Timeout_s (1,1) double {mustBePositive} = 120;
            end

            data = [];
            has = @(name) ~isempty(options.(name));

            %Check what was asked before touching the analyser
            measMode = [];
            measUnit = [];
            if has("MeasMode");     measMode = this.MeasType(string(options.MeasMode));        end
            if has("MeasUnit");     measUnit = this.MeasUnitType(string(options.MeasUnit));    end
            if has("Channel");      options.Channel = this.ChannelNumber(options.Channel);     end
            if has("SweepType")
                assert(any(string(options.SweepType) == ["Linear", "Log"]), "HP_8722ES_NetworkAnalyser:UnsupportedSweepType", "%s", ...
                    "Sweep type must be Linear or Log, received " + string(options.SweepType));
            end

            if this.SimulationMode
                if has("Channel");  this.SelectChannel(this.ChannelNumber(options.Channel));   end
                this.ScanChannel = this.SimulatedChannel;
                if ~isempty(measMode);  this.MeasMode = measMode;   end
                if ~isempty(measUnit);  this.MeasUnit = measUnit;   end
                this.ApplySimulatedSettings(options, has);
                this.ScanComplete = false;
            else
                this.StartSweep(options, has, measMode, measUnit);
            end

            if options.Wait
                timer = tic;
                while ~this.CheckScanComplete()
                    assert(toc(timer) < options.Timeout_s, "HP_8722ES_NetworkAnalyser:Timeout", "%s", ...
                        this.Name + ": the sweep was not complete after " + options.Timeout_s + " s.");
                    pause(0.05);
                end
                data = this.GetCompletedScanData();
            end
        end

        function RunScan(this, scanDetails)
            %Start one sweep, for the VNA Control tab, with its settings - without waiting (see CheckScanComplete).
            %A wrapper for RunMeasurement: the settings are fields of
            %scanDetails, named as RunMeasurement's arguments (Channel,
            %MeasMode, MeasUnit, StartFrequency_Hz, StopFrequency_Hz,
            %NumPoints, SweepTime_s and SweepType); others, e.g. the file
            %settings, are ignored. One left out or empty keeps the
            %analyser's
            %With scanDetails.LoadRegister (1-31) nothing is swept or set:
            %that analyser register is recalled instead (RecallRegister),
            %and its trace is the scan's data
            %
            %Inputs:
            %   scanDetails - (optional) struct of settings. Default: none, keeping the analyser's

            arguments
                this;
                scanDetails (1,1) struct = struct();
            end

            has = @(name) isfield(scanDetails, name) && ~isempty(scanDetails.(name));
            if has("LoadRegister")
                this.RecallRegister(scanDetails.LoadRegister);
                this.ScanComplete = ~this.SimulationMode;       %Nothing to wait for - except in SimulationMode, which finishes at random
                return;
            end

            options = struct();
            for name = ["Channel", "MeasMode", "MeasUnit", "StartFrequency_Hz", "StopFrequency_Hz", "NumPoints", "SweepTime_s", "SweepType"]
                if has(name)
                    options.(name) = scanDetails.(name);
                end
            end
            args = namedargs2cell(options);
            this.RunMeasurement(args{:});
        end

        function SelectChannel(this, channel)
            %Make a channel the analyser's active channel - settings and trace data are the active channel's.
            %Waits for the analyser to switch (OPC?, whose reply is read -
            %the Programmer's Guide says to use it to avoid timing errors),
            %then checks, with OUTPCHAN, that it did: a channel that isn't
            %on (3 and 4 need Display, AUX CHAN ON) leaves the active
            %channel as it was, which is an error rather than data from the
            %wrong channel. Do not call during a sweep
            %
            %Inputs:
            %   channel - 1, 2, 3 or 4

            channel = this.ChannelNumber(channel);
            if this.SimulationMode
                this.SimulatedChannel = channel;
                return;
            end

            this.QueryDouble("OPC?;CHAN" + channel + ";");
            active = this.GetActiveChannel();
            assert(active == channel, "HP_8722ES_NetworkAnalyser:ChannelUnavailable", "%s", ...
                this.Name + ": channel " + channel + " could not be selected - the active channel is " + active + ". " + ...
                "Channels 3 and 4 are the auxiliary channels of 1 and 2: switch them on at the analyser (Display, AUX CHAN ON).");
        end

    end

    %% Methods (Protected)
    methods(Access = protected)

        function OnConnected(this)
            %Allow a long timeout, for slow sweeps and large data transfers, after connecting.

            this.ScanComplete = true;
            this.ScanChannel = 0;
            this.SimulatedChannel = 1;
            if this.SimulationMode
                return;
            end

            this.DeviceHandle.Timeout = 30;
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function numPoints = AllowedNumPoints(this, requested)
            %The analyser's number of points nearest a requested number - it takes only 3, 11, 21, 26, 51, 101, 201, 401, 801 or 1601 (POIN).

            [~, idx] = min(abs(this.NumPointsChoices - requested));
            numPoints = this.NumPointsChoices(idx);
        end

        function ApplyMeasurementFormat(this, measMode, measUnit)
            %Select the S-parameter and display format of the measurement, and record them as MeasMode and MeasUnit.
            %One not given (empty) is the channel's own, read from the
            %analyser - unless that isn't one of ours (e.g. a phase display),
            %when the last measurement's is set so the data matches its label

            given = [~isempty(measMode), ~isempty(measUnit)];
            recognised = [false, false];
            if ~all(given)
                [readMode, readUnit, recognised] = this.ReadMeasurementFormat();
                if ~given(1) && recognised(1);  measMode = this.MeasType(readMode);    end
                if ~given(2) && recognised(2);  measUnit = this.MeasUnitType(readUnit);  end
            end
            if ~isempty(measMode);  this.MeasMode = measMode;   end
            if ~isempty(measUnit);  this.MeasUnit = measUnit;   end

            if given(1) || ~recognised(1);  this.WriteCommand(string(this.MeasMode) + ";");                end
            if given(2) || ~recognised(2);  this.WriteCommand(this.DisplayFormatCommand() + ";");          end
        end

        function ApplySimulatedSettings(this, scanDetails, has)
            %In SimulationMode, remember the sweep settings scanDetails has, as the analyser would set them.

            for name = ["StartFrequency_Hz", "StopFrequency_Hz", "SweepTime_s", "SweepType"]
                if has(name)
                    this.SweepSettings.(name) = scanDetails.(name);
                end
            end
            if has("NumPoints")
                this.SweepSettings.NumPoints = this.AllowedNumPoints(scanDetails.NumPoints);
            end
        end

        function channel = ChannelNumber(this, channel)
            %A channel as a number 1-4 from a number or text ("3") - errors for anything else.

            if ~isnumeric(channel)
                channel = str2double(string(channel));
            end
            assert(isscalar(channel) && ismember(channel, 1:4), "HP_8722ES_NetworkAnalyser:InvalidChannel", "%s", ...
                this.Name + ": the channel must be 1, 2, 3 or 4.");
        end

        function DiscardUnexpectedReplies(this)
            %Read and drop anything the analyser still has to send after a data transfer, with a warning - it would otherwise be taken as the reply to the next command.

            discarded = 0;
            while discarded < 20000 && this.IsReplyWaiting()
                this.ReadString();
                discarded = discarded + 1;
            end
            if discarded > 0
                Palladium.Logging.Logger.Log("Warning", this.Name + ": the analyser sent " + discarded + " more lines than expected after the trace (more points than POIN reported?) - they were discarded.");
            end
        end

        function command = DisplayFormatCommand(this)
            %The display format command for MeasUnit: LOGM (log magnitude, dB), LINM (linear magnitude) or POLA (polar, whose OUTPFORM data is real and imaginary parts).

            switch(this.MeasUnit)
                case(this.MeasUnitType("dB"));          command = "LOGM";
                case(this.MeasUnitType("Absolute"));    command = "LINM";
                case(this.MeasUnitType("Real/Imaginary")); command = "POLA";
                otherwise
                    error("HP_8722ES_NetworkAnalyser:InvalidMeasUnit", "%s", "MeasUnit must be dB, Absolute or Real/Imaginary, received " + string(this.MeasUnit));
            end
        end

        function EnsureChannel(this, channel)
            %Select a channel unless it is already the active one - the analyser's front panel can change it between a scan's start and its data being read.

            if this.GetActiveChannel() ~= channel
                this.SelectChannel(channel);
            end
        end

        function numbers = ParseNumbers(~, text)
            %The comma-separated numbers in a line of text, as a row vector.

            numbers = str2double(strsplit(strtrim(string(text)), ","));
            numbers = numbers(:)';
        end

        function numbers = QueryNumbers(this, command, expectedCount)
            %Send an output command and read its reply as a list of numbers (FORM4 ASCII), however many lines it comes in.
            %The analyser ends each pair of numbers in a trace with a line
            %feed, and ends the transmission only with the GPIB EOI line
            %(Programmer's Guide, "Output Syntax") - so a single read
            %gets just the first point. Lines are read, adding their
            %comma-separated numbers, until expectedCount have arrived (or a
            %read comes back empty, so the caller finds the shortfall).
            %Reading everything also leaves nothing behind in the buffer
            %for the next command to find
            %
            %Inputs:
            %   command       - the output command, e.g. "OUTPFORM;"
            %   expectedCount - how many numbers the reply holds
            %
            %Outputs:
            %   numbers - row vector of the numbers

            numbers = this.ParseNumbers(this.QueryString(command));
            while numel(numbers) < expectedCount
                line = strtrim(string(this.ReadString()));
                if strlength(line) == 0
                    break;
                end
                numbers = [numbers, this.ParseNumbers(line)]; %#ok<AGROW>
            end
        end

        function errors = ReadErrorQueue(this)
            %Read, and so clear, the analyser's error queue (OUTPERRO gives the oldest as "number,message") - the error numbers, oldest first.
            %Stops at error 0 (none), or after ten, so a reply that is
            %always the same can't loop forever

            errors = [];
            for k = 1:10
                number = str2double(strtok(this.QueryString("OUTPERRO;"), ","));
                if isnan(number) || number == 0
                    break;
                end
                errors(end + 1) = number; %#ok<AGROW>
            end
        end

        function [measMode, measUnit, recognised] = ReadMeasurementFormat(this)
            %The S-parameter and display format of the active channel, as text - if one of ours, else MeasMode and MeasUnit as they are.
            %
            %Outputs:
            %   measMode   - "S11", "S21", "S12" or "S22"
            %   measUnit   - "dB", "Absolute" or "Real/Imaginary"
            %   recognised - [mode, unit]: true for each that the analyser is showing one of ours (not, say, a phase display)

            measMode = string(this.MeasMode);
            measUnit = string(this.MeasUnit);
            recognised = [false, false];
            for sParameter = string(categories(this.MeasMode))'
                if this.QueryDouble(sParameter + "?;") == 1
                    measMode = sParameter;
                    recognised(1) = true;
                end
            end
            if this.QueryDouble("LOGM?;") == 1
                measUnit = "dB";
                recognised(2) = true;
            elseif this.QueryDouble("LINM?;") == 1
                measUnit = "Absolute";
                recognised(2) = true;
            elseif this.QueryDouble("POLA?;") == 1
                measUnit = "Real/Imaginary";
                recognised(2) = true;
            end
        end

        function settings = ReadSweepSettings(this)
            %Read the sweep settings from the analyser: frequency range, points, sweep time and sweep type.

            settings.StartFrequency_Hz = this.QueryDouble("STAR?;");
            settings.StopFrequency_Hz = this.QueryDouble("STOP?;");
            settings.NumPoints = this.QueryDouble("POIN?;");
            settings.SweepTime_s = this.QueryDouble("SWET?;");
            if this.QueryDouble("LOGFREQ?;") == 1
                settings.SweepType = "Log";
            else
                settings.SweepType = "Linear";
            end
        end

        function StartSweep(this, options, has, measMode, measUnit)
            %Send RunMeasurement's settings to the analyser, then start the sweep without waiting.
            %measMode and measUnit are the categoricals asked for, or empty

            this.Clear();

            %The channel the settings and the data belong to
            if has("Channel")
                this.ScanChannel = this.ChannelNumber(options.Channel);
                this.SelectChannel(this.ScanChannel);
            else
                this.ScanChannel = this.GetActiveChannel();
            end

            %Numbers without exponents (whole Hz), as the Programmer's Guide
            %doesn't say the analyser accepts them
            if has("StartFrequency_Hz")
                this.WriteCommand(sprintf("STAR%.0fHZ;", options.StartFrequency_Hz));
            end
            if has("StopFrequency_Hz")
                this.WriteCommand(sprintf("STOP%.0fHZ;", options.StopFrequency_Hz));
            end
            pointsChanged = false;
            if has("NumPoints")
                numPoints = this.AllowedNumPoints(options.NumPoints);
                pointsChanged = this.QueryDouble("POIN?;") ~= numPoints;
                this.WriteCommand(sprintf("POIN%d;", numPoints));
            end
            if has("SweepTime_s")
                this.WriteCommand(sprintf("SWET%.6fS;", options.SweepTime_s));     %SWET0 is automatic, as SWEA
            end
            if has("SweepType")
                if string(options.SweepType) == "Log"
                    this.WriteCommand("LOGFREQ;");
                else
                    this.WriteCommand("LINFREQ;");
                end
            end
            this.ApplyMeasurementFormat(measMode, measUnit);

            %Read back what was set - no queries can be answered once the
            %sweep has started
            this.SweepSettings = this.ReadSweepSettings();
            if has("NumPoints") && this.SweepSettings.NumPoints ~= numPoints
                Palladium.Logging.Logger.Log("Warning", this.Name + ": asked the analyser for " + numPoints + " points (channel " + this.ScanChannel + ") but it reports " + ...
                    this.SweepSettings.NumPoints + ". Data will have the number it reports.");
            end
            this.ScanComplete = false;

            %OPC? makes the analyser reply 1 once the sweep is done. One
            %group (NUMG1) is whatever the analyser needs to update the
            %measurement once, which a single sweep (SING) isn't if it takes
            %several sweeps (e.g. a 2-port calibration). The manual says to
            %wait two sweeps after a change of POIN, so then two groups
            this.WriteCommand("OPC?;NUMG" + (1 + pointsChanged) + ";");
        end

    end
end
