classdef PicoVNA_NetworkAnalyser < Palladium.Core.Instrument
    %PicoVNA_NetworkAnalyser - Instrument driver for the Pico Technology PicoVNA 106 and 108 USB vector network analysers, through the PicoVNA 5 software.
    %Records whole frequency sweeps through the VNA Control tab, rather
    %than a value each measurement tick: each scan is saved to its own data
    %file as two columns, frequency (Hz) and the S-parameter selected by
    %`MeasMode`, in the units of `MeasUnit` (dB, or linear magnitude for
    %Absolute). `Measure` returns no values, so the analyser adds no
    %columns to the main data file. The sweep settings are recorded in the
    %data-file header.
    %
    %The analyser is controlled with SCPI commands over TCP, through the
    %PicoVNA 5 software, which must be running with its SCPI interface
    %enabled (it is by default, on port 5025 - see User Preferences,
    %Network, in the software). Connect with the Ethernet connection type
    %and `IP_Address` 127.0.0.1 if the software runs on the same PC, or run
    %it without its window (`bin\vnaserver --instrument <serial>` in its
    %install folder). (Commands from the PicoVNA 5 User Guide, SCPI
    %chapter.)
    %
    %Running a scan applies the tab's settings (`RunScan`): start and stop
    %frequency and number of points. It then starts a sweep (`INITiate`) and asks for the
    %S-parameter in `MeasMode` (`CALCulate:DATa`) - the software holds the
    %reply back until the sweep is done, so the driver checks each tick,
    %without waiting, whether it has arrived (`CheckScanComplete`) and
    %Palladium stays responsive however long the sweep takes. Abort ends the
    %scan on screen; the software's sweep is stopped (`ABORt`) when the next
    %scan starts, or on Disconnect. The tab starts from the software's own
    %settings (`GetScanSettings`).
    %
    %The calibration, bandwidth and power are those of the software, as
    %with the other analysers: set them there (the data file's header
    %records what they were) and make or load a calibration there before
    %measuring - or set `CalibrationFile` to have one applied each time the
    %analyser connects. S12 and S22 need a two-port calibration. The
    %software must not be sweeping continuously (its Start button) while a
    %scan runs, and its trigger must be Free run. The sweep is always
    %linear in frequency, and its time is set by the points and bandwidth,
    %so the tab's sweep type must be Linear and its sweep time is ignored.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Pico Technology PicoVNA Network Analyser";  %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'PicoVNA';                                       %Instrument name, used as the prefix of its scan data column headers
        Connection_Type = Palladium.Enums.ConnectionType.Ethernet;  %Type of connection to use to communicate with the instrument: Ethernet is the PicoVNA 5 software's SCPI port. Debug allows testing without a physical instrument.
        MeasMode;                                               %S-parameter measured: S11, S21, S12 or S22 - S12 and S22 need a two-port calibration
        MeasUnit;                                               %dB (log magnitude) or Absolute (linear magnitude)
        CalibrationFile {mustBeTextScalar} = "";                %Full path of a calibration file (made in the PicoVNA 5 software) to apply each time the analyser connects - empty to keep the software's own calibration
    end

    %% Properties (Private)
    properties(Access = private)
        ScanComplete = true;                                    %False from RunScan asking for the sweep's data until it has arrived (or been abandoned)
        ScanValues = [];                                        %The sweep's values, once they have arrived
        MeasureError = [];                                      %MException if the sweep failed - raised when its data is collected (GetCompletedScanData). Empty if it didn't
        SweepSettings = [];                                     %Struct of the plan (as GetScanSettings) and Power_dBm, Bandwidth_Hz and CalType read back before the last sweep started - answered from here while it is under way, when the software can't be asked. Empty until the first sweep
        SimulatedSettings = struct("StartFrequency_Hz", 300e3, "StopFrequency_Hz", 8.5e9, "NumPoints", 201);     %In SimulationMode, the frequency plan last set
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr);        catOut = this.ConvertToCategorical(inputStr, ["S11", "S21", "S12", "S22"]); end
        function catOut = MeasUnitType(this, inputStr);    catOut = this.ConvertToCategorical(inputStr, ["dB", "Absolute"]); end
    end

    %% Constructor
    methods
        function this = PicoVNA_NetworkAnalyser()
            %Set the supported connection types, default settings and Scan Control tab.

            %The PicoVNA 5 software's SCPI port, on this PC by default. Not
            %USB: the software owns the analyser
            this.DefineSupportedConnectionTypes(["Debug", "Ethernet"]);
            this.IP_Address = '127.0.0.1';
            this.ConnectionSettings.Port = 5025;

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
            %The sweep has finished once the software's reply to the data
            %request is waiting; it is then read. If the sweep failed (e.g.
            %no calibration covers it) this is also true, and
            %GetCompletedScanData raises the error
            %
            %Outputs:
            %   complete - true once the sweep has finished

            if ~this.ScanComplete && this.IsReplyWaiting()
                reply = strip(string(this.ReadString()));
                values = str2double(split(reply, ","))';
                if isscalar(values) && isnan(values) && lower(reply) ~= "nan"
                    %Not numbers: the software's error message
                    this.MeasureError = MException("PicoVNA_NetworkAnalyser:MeasureFailed", "%s", ...
                        this.Name + ": measuring " + string(this.MeasMode) + " failed - the software replied """ + reply + """.");
                else
                    this.ScanValues = values;
                end
                this.ScanComplete = true;
            end
            complete = this.ScanComplete;
        end

        function metadataStruct = CollectMetaData(this)
            %Sweep settings, recorded in the data-file header.
            %While a sweep is under way, those read back before it started
            %
            %Outputs:
            %   metadataStruct - struct with fields Freq_Start_Hz, Freq_Stop_Hz,
            %   NumPoints, Power_dBm, Bandwidth_Hz and CalType

            settings = this.ReadSweepSettings();
            metadataStruct.Freq_Start_Hz = settings.StartFrequency_Hz;
            metadataStruct.Freq_Stop_Hz = settings.StopFrequency_Hz;
            metadataStruct.NumPoints = settings.NumPoints;
            metadataStruct.Power_dBm = settings.Power_dBm;
            metadataStruct.Bandwidth_Hz = settings.Bandwidth_Hz;
            metadataStruct.CalType = settings.CalType;
        end

        function data = GetCompletedScanData(this)
            %Frequencies and S-parameter values of the sweep just taken, for the Scan Control tab to save and plot.
            %The software gives only the values; the frequencies are the
            %sweep's points, evenly spaced from start to stop. Errors if
            %the sweep failed - see CheckScanComplete - or gave no values
            %
            %Outputs:
            %   data - one row per point: [frequency (Hz), value in MeasUnit]

            if ~isempty(this.MeasureError)
                err = this.MeasureError;
                this.MeasureError = [];
                throw(err);
            end

            if this.SimulationMode
                plan = this.SimulatedSettings;
                frequency = linspace(plan.StartFrequency_Hz, plan.StopFrequency_Hz, plan.NumPoints)';
                values = this.GenerateSimulatedData(plan.NumPoints, 1, Baseline=-3, Variance=0.1);
                if this.MeasUnit == this.MeasUnitType("Absolute")
                    values = 10 .^ (values / 20);
                end
                data = [frequency, values(:)];
                return;
            end

            plan = this.SweepSettings;
            values = this.ScanValues(:);
            assert(numel(values) == plan.NumPoints, "PicoVNA_NetworkAnalyser:DataSizeMismatch", "%s", ...
                this.Name + ": the sweep has " + plan.NumPoints + " points but the software sent " + numel(values) + " values.");
            assert(~all(isnan(values)), "PicoVNA_NetworkAnalyser:NoData", "%s", ...
                this.Name + ": the software sent no data for " + string(this.MeasMode) + " - it needs a calibration covering it (S12 and S22 need a two-port one).");
            data = [linspace(plan.StartFrequency_Hz, plan.StopFrequency_Hz, plan.NumPoints)', values];
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
            %   Headers - frequency and S-parameter headers, e.g. "PicoVNA - S11 (dB)"
            %   Units   - their units: "Hz", and "dB" or "" for the S-parameter

            Headers = [this.Name + " - Frequency_Hz", this.Name + " - " + string(this.MeasMode) + " (" + string(this.MeasUnit) + ")"];
            if this.MeasUnit == this.MeasUnitType("dB")
                Units = ["Hz", "dB"];
            else
                Units = ["Hz", ""];
            end
        end

        function settings = GetScanSettings(this)
            %The software's current frequency plan, for the VNA Control tab to start from - the fields RunScan takes.
            %While a sweep is under way, the plan read back before it
            %started. The sweep time is 0 (automatic) - it follows from the
            %points and bandwidth - and the sweep is always linear.
            %MeasMode and MeasUnit are this instrument's own
            %
            %Outputs:
            %   settings - struct: StartFrequency_Hz, StopFrequency_Hz, NumPoints,
            %              SweepTime_s (0), SweepType ("Linear"), MeasMode and
            %              MeasUnit (text)

            settings = this.ReadPlan();
            settings.SweepTime_s = 0;
            settings.SweepType = "Linear";
            settings.MeasMode = string(this.MeasMode);
            settings.MeasUnit = string(this.MeasUnit);
        end

        function LoadCalibration(this, fileName)
            %Load a calibration made in the PicoVNA 5 software and apply it.
            %
            %Inputs:
            %   fileName - full path of the calibration file

            arguments
                this;
                fileName {mustBeTextScalar};
            end

            if this.SimulationMode
                return;
            end

            %Quoted, as the software wants for a path with backslashes
            this.SendCommand("MMEMory:APPLY:CALibration '" + string(fileName) + "'", "applying the calibration file " + string(fileName));
        end

        function [dataRow] = Measure(~)
            %Return no values - scans are recorded through the Scan Control tab instead.
            %Sweeps are slow and standalone, so this instrument does not
            %return row-by-row data
            %
            %Outputs:
            %   dataRow - empty, matching GetHeaders

            dataRow = [];
        end

        function RunScan(this, scanDetails)
            %Start a scan, when Run is pressed on the VNA Control tab: apply its settings, then start one sweep - without waiting for it (see CheckScanComplete).
            %Sets the frequency plan from the fields scanDetails has (see
            %GetScanSettings; any it lacks stay as the software has them -
            %others, e.g. the file settings, are ignored), then starts a
            %sweep and asks for MeasMode's S-parameter in MeasUnit. The settings are read back before the
            %sweep starts, for the data file's metadata (the software can't
            %be asked anything while a request is waiting for the sweep). If
            %an abandoned scan's sweep is still going, it is stopped first
            %
            %Inputs:
            %   scanDetails - (optional) struct of settings. Default: none, keeping the software's

            arguments
                this;
                scanDetails (1,1) struct = struct();
            end

            this.MeasureError = [];
            has = @(name) isfield(scanDetails, name) && ~isempty(scanDetails.(name));
            if has("SweepType") && string(scanDetails.SweepType) ~= "Linear"
                error("PicoVNA_NetworkAnalyser:UnsupportedSweepType", "%s", "The PicoVNA only sweeps linearly in frequency - sweep type must be Linear, received " + string(scanDetails.SweepType));
            end
            if has("SweepTime_s") && scanDetails.SweepTime_s > 0
                Palladium.Logging.Logger.Log("Warning", this.Name + ": the PicoVNA's sweep time can't be set (it follows from the points and bandwidth) - ignoring " + scanDetails.SweepTime_s + " s.");
            end
            if has("MeasMode");     this.MeasMode = this.MeasType(string(scanDetails.MeasMode));       end
            if has("MeasUnit");     this.MeasUnit = this.MeasUnitType(string(scanDetails.MeasUnit));   end

            this.AbortOutstandingSweep();

            %Whatever the tab doesn't give stays as the software has it
            plan = this.ReadPlan();
            for name = ["StartFrequency_Hz", "StopFrequency_Hz", "NumPoints"]
                if has(name);   plan.(name) = scanDetails.(name);   end
            end
            this.SetFrequencyPlan(plan.StartFrequency_Hz, plan.StopFrequency_Hz, plan.NumPoints);
            if this.SimulationMode
                return;     %Simulated sweeps are instant
            end

            this.SendCommand("FORMat ASCii", "setting the data format");

            %Read back what was set, then start the sweep and ask for its
            %data - the reply comes when the sweep is done
            this.SweepSettings = this.ReadSweepSettings();
            this.SendCommand("INITiate", "starting the sweep");
            this.WriteCommand("CALCulate:DATa " + string(this.MeasMode) + "," + this.DataType());
            this.ScanValues = [];
            this.ScanComplete = false;
        end

        function SetFrequencyPlan(this, start_Hz, stop_Hz, numPoints)
            %Set the frequency sweep: start and stop frequency, and number of points, in evenly spaced (linear) steps.
            %The software refuses frequencies outside the instrument's range
            %and more than 10001 points, and its message is given in the error
            %
            %Inputs:
            %   start_Hz  - start frequency, in Hz
            %   stop_Hz   - stop frequency, in Hz
            %   numPoints - number of points

            arguments
                this;
                start_Hz (1,1) double;
                stop_Hz (1,1) double;
                numPoints (1,1) double {mustBeInteger, mustBePositive};
            end

            assert(stop_Hz > start_Hz, "PicoVNA_NetworkAnalyser:FrequencyOutOfRange", "%s", ...
                "The stop frequency (" + stop_Hz / 1e6 + " MHz) must be above the start frequency (" + start_Hz / 1e6 + " MHz).");

            if this.SimulationMode
                this.SimulatedSettings = struct("StartFrequency_Hz", start_Hz, "StopFrequency_Hz", stop_Hz, "NumPoints", numPoints);
                return;
            end

            %The software won't put the start above the current stop, so
            %when moving the whole sweep up, the stop goes first
            number = @(value) Palladium.Core.Instrument.NumberToCommandString(value);
            setStart = @() this.SendCommand("SENSe:FREQuency:STARt " + number(start_Hz), "setting the start frequency");
            setStop = @() this.SendCommand("SENSe:FREQuency:STOP " + number(stop_Hz), "setting the stop frequency");
            if start_Hz >= this.ParseValue(this.QueryString("SENSe:FREQuency:STOP?"))
                setStop();
                setStart();
            else
                setStart();
                setStop();
            end
            this.SendCommand("SENSe:SWEep:POINts " + number(numPoints), "setting the number of points");
        end

    end

    %% Methods (Protected)
    methods(Access = protected)

        function CloseConnection(this)
            %Stop a sweep still going, then close the connection.

            if ~this.SimulationMode && ~isempty(this.DeviceHandle)
                try
                    this.AbortOutstandingSweep();
                catch
                    %Close it anyway
                end
            end
            CloseConnection@Palladium.Core.Instrument(this);
        end

        function OnConnected(this)
            %Check it is a PicoVNA, allow time for the software to answer, and apply CalibrationFile if set, after connecting.

            this.ScanComplete = true;
            if this.SimulationMode
                return;
            end

            this.DeviceHandle.Timeout = 30;
            identity = this.QueryString("*IDN?");
            if ~contains(identity, "Pico", IgnoreCase = true)
                Palladium.Logging.Logger.Log("Warning", this.Name + ": connected, but the instrument says it is """ + identity + """ - is this the PicoVNA 5 software's SCPI port?");
            end
            if strlength(string(this.CalibrationFile)) > 0
                this.LoadCalibration(this.CalibrationFile);
            end
        end

        function OpenConnection(this)
            %Connect to the PicoVNA 5 software's SCPI port, with a hint if it can't be reached.

            try
                OpenConnection@Palladium.Core.Instrument(this);
            catch err
                if this.Connection_Type == Palladium.Enums.ConnectionType.Debug
                    rethrow(err);
                end
                error("PicoVNA_NetworkAnalyser:ConnectionFailed", "%s", err.message + newline + newline + ...
                    "Is the PicoVNA 5 software running, with its SCPI interface enabled on port " + this.ConnectionSettings.Port + " (User Preferences, Network)?");
            end
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function AbortOutstandingSweep(this)
            %Stop an abandoned scan's sweep, if one is still going, and throw away the reply to its data request.
            %ABORt on the same connection makes the software answer the data
            %request with what the sweep had got, then OK. Does nothing if no
            %data request is outstanding

            if this.SimulationMode || this.ScanComplete
                return;
            end

            this.WriteCommand("ABORt");
            reply = "";
            while reply ~= "OK"
                reply = strip(string(this.ReadString()));
            end
            this.ScanComplete = true;
        end

        function type = DataType(this)
            %The CALCulate:DATa type for MeasUnit: LOGMAG (dB) or MAG (linear magnitude).

            switch(this.MeasUnit)
                case(this.MeasUnitType("dB"));          type = "LOGMAG";
                case(this.MeasUnitType("Absolute"));    type = "MAG";
            end
        end

        function value = ParseValue(~, reply)
            %A number from the software's reply, which has a unit after it, e.g. "1000000.000000 Hz" or "0.300000 MHz" - frequencies are returned in Hz.

            parts = split(strip(string(reply)));
            value = str2double(parts(1));
            if numel(parts) > 1
                scales = dictionary(["Hz", "kHz", "MHz", "GHz"], [1, 1e3, 1e6, 1e9]);
                if isKey(scales, parts(2))
                    value = value * scales(parts(2));
                end
            end
        end

        function plan = ReadPlan(this)
            %The frequency plan: from the last read-back while a sweep is under way, else asked for (or the simulated one).

            if this.SimulationMode
                plan = this.SimulatedSettings;
            elseif ~this.ScanComplete
                plan = struct("StartFrequency_Hz", this.SweepSettings.StartFrequency_Hz, "StopFrequency_Hz", this.SweepSettings.StopFrequency_Hz, ...
                    "NumPoints", this.SweepSettings.NumPoints);
            else
                plan = struct("StartFrequency_Hz", this.ParseValue(this.QueryString("SENSe:FREQuency:STARt?")), ...
                    "StopFrequency_Hz", this.ParseValue(this.QueryString("SENSe:FREQuency:STOP?")), ...
                    "NumPoints", this.ParseValue(this.QueryString("SENSe:SWEep:POINts?")));
            end
        end

        function settings = ReadSweepSettings(this)
            %The plan, power, bandwidth and calibration type: asked for, or from before the sweep if one is under way (or simulated).

            if this.SimulationMode
                settings = this.SimulatedSettings;
                settings.Power_dBm = 3;
                settings.Bandwidth_Hz = 1000;
                settings.CalType = "Simulated";
            elseif ~this.ScanComplete
                settings = this.SweepSettings;
            else
                settings = this.ReadPlan();
                settings.Power_dBm = this.ParseValue(this.QueryString("SENSe:LEVel?"));
                settings.Bandwidth_Hz = this.ParseValue(this.QueryString("SENSe:BANDwidth?"));
                settings.CalType = string(this.QueryString("MMEMory:CALibration:INFO:TYPe?"));
            end
        end

        function SendCommand(this, command, action)
            %Send a command and error, naming the action, unless the software replies OK - it replies to every command.

            reply = strip(string(this.QueryString(command)));
            assert(reply == "OK", "PicoVNA_NetworkAnalyser:CommandFailed", "%s", ...
                this.Name + ": " + action + " failed - the software replied """ + reply + """.");
        end

    end
end
