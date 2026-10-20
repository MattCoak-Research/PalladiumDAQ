classdef HP_8722ES_NetworkAnalyser < Palladium.Core.Instrument
    %HP_8722ES_NetworkAnalyser - Instrument driver for the HP 8722ES vector network analyser.
    %Records whole frequency sweeps through the VNA Control tab, rather
    %than a value each measurement tick: each scan is saved to its own data
    %file as two columns, frequency (Hz) and the S-parameter selected by
    %`MeasMode`. `Measure` returns no values, so the analyser adds no
    %columns to the main data file.
    %
    %Before each sweep the driver applies the tab's settings (`RunScan`):
    %frequency range, number of points (one of the analyser's: 3, 11, 21,
    %26, 51, 101, 201, 401, 801 or 1601 - the nearest is used), sweep time
    %(0 for automatic) and linear or log sweep, then `MeasMode`'s
    %S-parameter and the display format for `MeasUnit` (log magnitude for
    %dB, linear magnitude for Absolute). It then takes one sweep
    %(`OPC?;SING;`), checking for its completion each tick without
    %waiting. The trace is read as ASCII (`FORM4;`, `OUTPFORM;`) and the
    %frequency of each point from the limit-test array (`OUTPLIML;`), which
    %gives them for linear, log and list sweeps alike. Set the power and
    %calibration on the analyser. The tab starts from the analyser's own
    %settings (`GetScanSettings`). (Commands from the 8719ES/8720ES/8722ES
    %Programmer's Guide.)
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
        MeasMode;                                               %S-parameter to measure: S11, S21, S12 or S22 - selected on the analyser before each sweep
        MeasUnit;                                               %dB (log magnitude) or Absolute (linear magnitude) - the display format is set to match before each sweep
    end

    %% Properties (Private)
    properties(Access = private)
        ScanComplete = true;                                    %False while a sweep started by RunScan is under way
        SweepSettings = struct("StartFrequency_Hz", 50e6, "StopFrequency_Hz", 40e9, "NumPoints", 201, ...
            "SweepTime_s", 0, "SweepType", "Linear");          %The sweep settings read back before the last sweep - answered from here while a sweep is under way, when queries can't be (the reply to OPC? is pending). In SimulationMode, the settings last set
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr);        catOut = this.ConvertToCategorical(inputStr, ["S11", "S21", "S12", "S22"]); end
        function catOut = MeasUnitType(this, inputStr);    catOut = this.ConvertToCategorical(inputStr, ["dB", "Absolute"]); end
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
            %   metadataStruct - struct with fields Freq_Start_Hz, Freq_Stop_Hz and NumPoints

            metadataStruct.Freq_Start_Hz = this.GetStartFrequency();
            metadataStruct.Freq_Stop_Hz = this.GetStopFrequency();
            metadataStruct.NumPoints = this.GetNumPoints();
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
            %   data - one row per point: [frequency in Hz, S-parameter in MeasUnit]

            if this.SimulationMode
                numPoints = this.GetNumPoints();
                frequency = linspace(this.GetStartFrequency(), this.GetStopFrequency(), numPoints)';
                values = this.GenerateSimulatedData(numPoints, 1, Baseline=-3, Variance=0.1);
                data = [frequency, values(:)];
                return;
            end

            %Two numbers per point for the trace, four for the limit test
            numPoints = this.GetNumPoints();
            this.WriteCommand("FORM4;");
            trace = this.QueryNumbers("OUTPFORM;", 2 * numPoints);
            limits = this.QueryNumbers("OUTPLIML;", 4 * numPoints);

            values = trace(1:2:end);
            frequency = limits(1:4:end);
            assert(numel(values) == numel(frequency), "HP_8722ES_NetworkAnalyser:DataSizeMismatch", "%s", ...
                this.Name + ": the trace has " + numel(values) + " points but the frequency list " + numel(frequency) + ".");
            data = [frequency(:), values(:)];
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

        function [Headers, Units] = GetScanHeaders(this)
            %Column headers and units of the scan data files written by the Scan Control tab.
            %
            %Outputs:
            %   Headers - frequency and S-parameter headers, e.g. "HP_8722ES_NetworkAnalyser - S11 (dB)"
            %   Units   - their units: "Hz", and "dB" or "" for the S-parameter

            Headers = [this.Name + " - Frequency_Hz", this.Name + " - " + string(this.MeasMode) + " (" + string(this.MeasUnit) + ")"];
            if this.MeasUnit == this.MeasUnitType("dB")
                Units = ["Hz", "dB"];
            else
                Units = ["Hz", ""];
            end
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

        function settings = GetScanSettings(this)
            %The analyser's current sweep settings, for the VNA Control tab to start from - the fields RunScan takes.
            %While a sweep is under way, those read back before it started.
            %The sweep time is the analyser's actual one - automatic can't be
            %read back
            %
            %Outputs:
            %   settings - struct: StartFrequency_Hz, StopFrequency_Hz, NumPoints,
            %              SweepTime_s, SweepType ("Linear" or "Log"), MeasMode
            %              and MeasUnit (text)

            measMode = string(this.MeasMode);
            measUnit = string(this.MeasUnit);
            if this.SimulationMode || ~this.ScanComplete
                settings = this.SweepSettings;
            else
                settings = this.ReadSweepSettings();

                %The S-parameter and display format selected, if one of ours
                for sParameter = string(categories(this.MeasMode))'
                    if this.QueryDouble(sParameter + "?;") == 1
                        measMode = sParameter;
                    end
                end
                if this.QueryDouble("LOGM?;") == 1
                    measUnit = "dB";
                elseif this.QueryDouble("LINM?;") == 1
                    measUnit = "Absolute";
                end
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

        function [dataRow] = Measure(~)
            %Return no values - scans are recorded through the Scan Control tab instead.
            %
            %Outputs:
            %   dataRow - empty, matching GetHeaders

            dataRow = [];
        end
        
        function RunScan(this, scanDetails)
            %Start one sweep, for the VNA Control tab, with its settings - without waiting for it (see CheckScanComplete).
            %Applies each setting scanDetails has (see GetScanSettings for
            %the fields; others, e.g. the file settings, are ignored), then
            %selects MeasMode's S-parameter and MeasUnit's display format. A
            %device clear first discards any reply left from an aborted
            %sweep. The settings are read back before the sweep starts, for
            %the data file's metadata
            %
            %Inputs:
            %   scanDetails - (optional) struct of settings. Default: none, keeping the analyser's

            arguments
                this;
                scanDetails (1,1) struct = struct();
            end

            has = @(name) isfield(scanDetails, name) && ~isempty(scanDetails.(name));
            if has("MeasMode");     this.MeasMode = this.MeasType(string(scanDetails.MeasMode));       end
            if has("MeasUnit");     this.MeasUnit = this.MeasUnitType(string(scanDetails.MeasUnit));   end

            if this.SimulationMode
                this.ApplySimulatedSettings(scanDetails, has);
                this.ScanComplete = false;
                return;
            end

            this.Clear();

            %Numbers without exponents (whole Hz), as the Programmer's Guide
            %doesn't say the analyser accepts them
            if has("StartFrequency_Hz") && has("StopFrequency_Hz")
                this.WriteCommand(sprintf("STAR%.0fHZ;", scanDetails.StartFrequency_Hz));
                this.WriteCommand(sprintf("STOP%.0fHZ;", scanDetails.StopFrequency_Hz));
            end
            if has("NumPoints")
                this.WriteCommand(sprintf("POIN%d;", this.AllowedNumPoints(scanDetails.NumPoints)));
            end
            if has("SweepTime_s")
                this.WriteCommand(sprintf("SWET%.6fS;", scanDetails.SweepTime_s));     %SWET0 is automatic, as SWEA
            end
            if has("SweepType")
                switch string(scanDetails.SweepType)
                    case "Linear";  this.WriteCommand("LINFREQ;");
                    case "Log";     this.WriteCommand("LOGFREQ;");
                    otherwise
                        error("HP_8722ES_NetworkAnalyser:UnsupportedSweepType", "%s", "Sweep type must be Linear or Log, received " + string(scanDetails.SweepType));
                end
            end
            this.WriteCommand(string(this.MeasMode) + ";");
            this.WriteCommand(this.DisplayFormatCommand() + ";");

            %Read back what was set - no queries can be answered once the
            %sweep has started
            this.SweepSettings = this.ReadSweepSettings();
            this.ScanComplete = false;

            %OPC? makes the analyser reply 1 once the single sweep is done
            %(Programmer's Guide, Example 3B)
            this.WriteCommand("OPC?;SING;");
        end

    end

    %% Methods (Protected)
    methods(Access = protected)

        function OnConnected(this)
            %Allow a long timeout, for slow sweeps and large data transfers, after connecting.

            this.ScanComplete = true;
            if this.SimulationMode
                return;
            end

            this.DeviceHandle.Timeout = 30;
        end

    end

    %% Methods (Private)
    methods(Access = private)

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

        function command = DisplayFormatCommand(this)
            %The display format command for MeasUnit: LOGM (log magnitude, dB) or LINM (linear magnitude).

            switch(this.MeasUnit)
                case(this.MeasUnitType("dB"));          command = "LOGM";
                case(this.MeasUnitType("Absolute"));    command = "LINM";
                otherwise
                    error("HP_8722ES_NetworkAnalyser:InvalidMeasUnit", "%s", "MeasUnit must be dB or Absolute, received " + string(this.MeasUnit));
            end
        end

        function numPoints = AllowedNumPoints(~, requested)
            %The analyser's number of points nearest a requested number - it takes only 3, 11, 21, 26, 51, 101, 201, 401, 801 or 1601 (POIN).

            allowed = [3, 11, 21, 26, 51, 101, 201, 401, 801, 1601];
            [~, idx] = min(abs(allowed - requested));
            numPoints = allowed(idx);
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

        function numbers = ParseNumbers(~, text)
            %The comma-separated numbers in a line of text, as a row vector.

            numbers = str2double(strsplit(strtrim(string(text)), ","));
            numbers = numbers(:)';
        end

    end
end
