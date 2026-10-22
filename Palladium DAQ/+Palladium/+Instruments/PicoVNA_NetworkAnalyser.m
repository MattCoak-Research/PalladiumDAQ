classdef PicoVNA_NetworkAnalyser < Palladium.Core.Instrument
    %PicoVNA_NetworkAnalyser - Instrument driver for the Pico Technology PicoVNA 106 and 108 USB vector network analysers, through the PicoVNA 5 or PicoVNA 3 software.
    %Records whole frequency sweeps through the VNA Control tab, rather
    %than a value each measurement tick: each scan is saved to its own data
    %file as two columns, frequency (Hz) and the S-parameter selected by
    %`MeasMode`, in the units of `MeasUnit` (dB, or linear magnitude for
    %Absolute). `Measure` returns no values, so the analyser adds no
    %columns to the main data file. The sweep settings are recorded in the
    %data-file header.
    %
    %Older analysers can't use the newer PicoVNA 5 software without an
    %upgrade, so the driver works with either, and finds which is there
    %when it connects (`Software`, Auto by default): first the PicoVNA 5
    %software, running on this PC - or at `IP_Address` - with its SCPI
    %interface enabled (it is by default, on port 5025: User Preferences,
    %Network); failing that, the PicoVNA 3 software's library on this PC.
    %If neither is found, the error says what is expected and where to get
    %them: https://www.picotech.com/downloads#t9. The two differ in what
    %the user has to do:
    %
    %* PicoVNA 5 is controlled through the running application. Make or
    %  load the calibration, and set the bandwidth and power, there (set
    %  `CalibrationFile` to have a calibration applied on connecting). It
    %  must not be sweeping continuously (its Start button) during a scan,
    %  and its trigger must be Free run.
    %* PicoVNA 3 has no remote control of its application: the driver uses
    %  the library the software installs, which takes the analyser over -
    %  so the PicoVNA 3 application must be CLOSED. The bandwidth and
    %  power are the settings `Bandwidth_Hz` and `Power_dBm` here (ignored
    %  with PicoVNA 5). The calibration must be made with the library -
    %  `Calibrate` opens its dialogue and `SaveCalibration` keeps it -
    %  as files saved by the PicoVNA application can't be used; load one
    %  with `CalibrationFile` or `LoadCalibration`.
    %
    %Either way, running a scan applies the tab's settings (`RunScan`):
    %start and stop frequency and number of points. It starts a sweep and
    %returns at once, so Palladium stays responsive however long the sweep
    %takes, and the driver checks each tick, without waiting, whether it
    %has finished (`CheckScanComplete`). Abort ends the scan on screen;
    %PicoVNA 5's sweep is then stopped when the next scan starts or on
    %Disconnect (PicoVNA 3's library can't stop one: the next scan waits
    %for it, and Disconnect cuts it off). The calibration decides what can be
    %measured: a one-port (S11) calibration is enough for S11 sweeps, S21
    %needs an S21 or S11+S21 one, and S12 and S22 need a two-port one -
    %PicoVNA 3's library would otherwise hand back placeholder values for
    %them, so the driver refuses. The sweep is always linear in frequency, and its time is
    %set by the points and bandwidth, so the tab's sweep type must be
    %Linear and its sweep time is ignored. The tab starts from the
    %software's own settings (`GetScanSettings`).
    %
    %How each software is driven is in the classes of the
    %Palladium.Instruments.PicoVNA package: Software5 (SCPI over TCP) and
    %Software3 (Pico's COM library, run through
    %Palladium.Utilities.ComServerProcess).

    %% Properties (Public)
    properties(Access = public)
        FullName = "Pico Technology PicoVNA Network Analyser";  %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'PicoVNA';                                       %Instrument name, used as the prefix of its scan data column headers
        Connection_Type = Palladium.Enums.ConnectionType.Ethernet;  %Type of connection: Ethernet reaches the PicoVNA software (IP_Address and the port are for PicoVNA 5's SCPI interface; PicoVNA 3 is found on this PC). Debug allows testing without a physical instrument.
        Software;                                               %Which software to use: Auto (the PicoVNA 5 software if it is there, else PicoVNA 3), or PicoVNA 5 or PicoVNA 3 to use only that
        MeasMode;                                               %S-parameter measured: S11, S21, S12 or S22 - S12 and S22 need a two-port calibration
        MeasUnit;                                               %dB (log magnitude) or Absolute (linear magnitude)
        Power_dBm (1,1) double {mustBeBetween(Power_dBm, -20, 10)} = 0;     %PicoVNA 3 only (PicoVNA 5: set in its software): test signal power, -20 to +6 dBm (106) or +10 dBm (108), sent with the frequency plan before each sweep
        Bandwidth_Hz (1,1) double {mustBeMember(Bandwidth_Hz, [10 50 100 500 1000 5000 10000 15000 35000 70000 140000])} = 1000;  %PicoVNA 3 only (PicoVNA 5: set in its software): measurement (IF) bandwidth, sent with the frequency plan before each sweep - narrower is less noisy but slower
        CalibrationFile {mustBeTextScalar} = "";                %Full path of a calibration file to apply each time the analyser connects - empty to keep the software's own calibration. PicoVNA 5: made in its software. PicoVNA 3: saved with SaveCalibration
    end

    %% Properties (Protected)
    properties(Access = protected)
        Backend = [];                                           %The Palladium.Instruments.PicoVNA.Backend talking to the software, found by OpenConnection - empty when not connected, or in SimulationMode
    end

    %% Properties (Private)
    properties(Access = private)
        ScanComplete = true;                                    %False from RunScan starting a sweep until it has finished (or been abandoned)
        ScanData = [];                                          %The sweep's data (frequency and value of each point), once it has finished
        MeasureError = [];                                      %MException if the sweep failed - raised when its data is collected (GetCompletedScanData). Empty if it didn't
        SweepSettings = [];                                     %Struct of the plan (as GetScanSettings) and Power_dBm, Bandwidth_Hz and CalType read back before the last sweep started - answered from here while it is under way, when the software can't be asked. Empty until the first sweep
        SimulatedSettings = struct("StartFrequency_Hz", 300e3, "StopFrequency_Hz", 8.5e9, "NumPoints", 201);     %In SimulationMode, the frequency plan last set
    end

    %% Categoricals
    methods
        function catOut = SoftwareType(this, inputStr);    catOut = this.ConvertToCategorical(inputStr, ["Auto", "PicoVNA 5", "PicoVNA 3"]); end
        function catOut = MeasType(this, inputStr);        catOut = this.ConvertToCategorical(inputStr, ["S11", "S21", "S12", "S22"]); end
        function catOut = MeasUnitType(this, inputStr);    catOut = this.ConvertToCategorical(inputStr, ["dB", "Absolute"]); end
    end

    %% Constructor
    methods
        function this = PicoVNA_NetworkAnalyser()
            %Set the supported connection types, default settings and Scan Control tab.

            %The PicoVNA 5 software's SCPI port, on this PC by default; the
            %PicoVNA 3 library is found on this PC (see OpenConnection)
            this.DefineSupportedConnectionTypes(["Debug", "Ethernet"]);
            this.IP_Address = '127.0.0.1';
            this.ConnectionSettings.Port = 5025;

            %Default settings
            this.Software = this.SoftwareType("Auto");
            this.MeasMode = this.MeasType("S11");
            this.MeasUnit = this.MeasUnitType("dB");

            %Define the Instrument Controls that can be added
            this.DefineInstrumentControl(Name = "VNA Control", ClassName = "VNAController", TabName = "VNA Control", EnabledByDefault = true);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function Calibrate(this)
            %Open the PicoVNA 3 library's calibration dialogue, to set the frequency plan and calibrate - not while a scan is running.
            %PicoVNA 3 only: with PicoVNA 5, calibrate in its software.
            %Keep the calibration with SaveCalibration

            if this.SimulationMode
                return;
            end

            this.Backend.Calibrate();
        end

        function complete = CheckScanComplete(this)
            %Check, without waiting, whether the sweep started by RunScan has finished - for the Scan Control tab.
            %If the sweep failed (e.g. no calibration covers it) this is
            %also true, and GetCompletedScanData raises the error
            %
            %Outputs:
            %   complete - true once the sweep has finished

            if ~this.ScanComplete && this.Backend.IsSweepDone()
                try
                    this.ScanData = this.Backend.CollectSweep();
                catch err
                    identifier = err.identifier;
                    if strlength(identifier) == 0
                        identifier = "PicoVNA_NetworkAnalyser:MeasureFailed";
                    end
                    this.MeasureError = MException(identifier, "%s", this.Name + ": " + err.message);
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

        function description = GetActiveSoftware(this)
            %What the driver is connected to, e.g. "PicoVNA 5 software at 127.0.0.1:5025 (...)" - "Simulated" in SimulationMode, empty if not connected.
            %
            %Outputs:
            %   description - text

            if this.SimulationMode
                description = "Simulated";
            elseif isempty(this.Backend)
                description = "";
            else
                description = this.Backend.Description;
            end
        end

        function data = GetCompletedScanData(this)
            %Frequencies and S-parameter values of the sweep just taken, for the Scan Control tab to save and plot.
            %Errors if the sweep failed - see CheckScanComplete - or gave no values
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
            data = this.ScanData;
            assert(size(data, 1) == plan.NumPoints, "PicoVNA_NetworkAnalyser:DataSizeMismatch", "%s", ...
                this.Name + ": the sweep has " + plan.NumPoints + " points but the software sent " + size(data, 1) + " values.");
            assert(~all(isnan(data(:, 2))), "PicoVNA_NetworkAnalyser:NoData", "%s", ...
                this.Name + ": the software sent no data for " + string(this.MeasMode) + " - it needs a calibration covering it (S12 and S22 need a two-port one).");
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
            %Load and apply a calibration file - for PicoVNA 5 one made in its software, for PicoVNA 3 one saved with SaveCalibration.
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

            this.Backend.LoadCalibration(fileName);
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
            %sweep of MeasMode's S-parameter in MeasUnit. The settings are
            %read back before the sweep starts, for the data file's
            %metadata (the software can't be asked anything once it is
            %sweeping). If an abandoned scan's sweep is still going, PicoVNA
            %5 stops it first and PicoVNA 3 waits for it
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

            if ~this.SimulationMode
                this.Backend.AbortSweep();
                this.ScanComplete = true;
            end

            %Whatever the tab doesn't give stays as the software has it
            plan = this.ReadPlan();
            for name = ["StartFrequency_Hz", "StopFrequency_Hz", "NumPoints"]
                if has(name);   plan.(name) = scanDetails.(name);   end
            end
            if ~this.SimulationMode
                this.Backend.SetSweepOptions(this.Power_dBm, this.Bandwidth_Hz);
            end
            this.SetFrequencyPlan(plan.StartFrequency_Hz, plan.StopFrequency_Hz, plan.NumPoints);
            if this.SimulationMode
                return;     %Simulated sweeps are instant
            end

            %Read back what was set, then start the sweep
            this.SweepSettings = this.ReadSweepSettings();
            this.Backend.StartSweep(string(this.MeasMode), string(this.MeasUnit), this.SweepSettings);
            this.ScanData = [];
            this.ScanComplete = false;
        end

        function SaveCalibration(this, fileName)
            %Save the PicoVNA 3 library's calibration and frequency plan, to load again with LoadCalibration or CalibrationFile.
            %PicoVNA 3 only: with PicoVNA 5, save calibrations in its software
            %
            %Inputs:
            %   fileName - full path of the file to write

            arguments
                this;
                fileName {mustBeTextScalar};
            end

            if this.SimulationMode
                return;
            end

            this.Backend.SaveCalibration(fileName);
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
            assert(numPoints >= 2, "PicoVNA_NetworkAnalyser:NumPointsOutOfRange", "%s", "A sweep needs at least 2 points, received " + numPoints + ".");

            if this.SimulationMode
                this.SimulatedSettings = struct("StartFrequency_Hz", start_Hz, "StopFrequency_Hz", stop_Hz, "NumPoints", numPoints);
                return;
            end

            this.Backend.SetFrequencyPlan(start_Hz, stop_Hz, numPoints);
        end

    end

    %% Methods (Protected)
    methods(Access = protected)

        function CloseConnection(this)
            %Stop a sweep still going where the software allows, release the software and close the connection.

            if this.SimulationMode
                disp("Disconnected from simulated " + this.Name + " instrument.");
                return;
            end

            if ~isempty(this.Backend)
                this.Backend.Close();
                this.Backend = [];
            end
        end

        function backend = CreateBackend(this, software)
            %Make the backend for one of the softwares, not yet connected.
            %
            %Inputs:
            %   software - "PicoVNA 5" or "PicoVNA 3"
            %
            %Outputs:
            %   backend - a Palladium.Instruments.PicoVNA.Backend

            switch(software)
                case "PicoVNA 5";   backend = Palladium.Instruments.PicoVNA.Software5(Address = string(this.IP_Address), Port = this.ConnectionSettings.Port);
                case "PicoVNA 3";   backend = Palladium.Instruments.PicoVNA.Software3();
            end
        end

        function OnConnected(this)
            %Say what was connected to, and apply CalibrationFile if set, after connecting.

            this.ScanComplete = true;
            if this.SimulationMode
                return;
            end

            disp("Connected to " + this.Name + " instrument: " + this.Backend.Description + ".");
            if strlength(string(this.CalibrationFile)) > 0
                this.LoadCalibration(this.CalibrationFile);
            end
        end

        function OpenConnection(this)
            %Find the PicoVNA software to use and connect to it. In Debug mode, no connection - SimulationMode.
            %Auto tries the PicoVNA 5 software first, then (for a PC that is
            %this one) the PicoVNA 3 library. Errors, saying what is
            %expected and where to get it, if none is found

            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    disp("Connected to simulated " + this.Name + " instrument.");
                    this.SimulationMode = true;

                case(Palladium.Enums.ConnectionType.Ethernet)
                    this.SimulationMode = false;
                    this.Backend = this.FindSoftware();

                otherwise
                    error("PicoVNA_NetworkAnalyser:UnsupportedConnectionType", "%s", "Unsupported connection type on the PicoVNA: " + string(this.Connection_Type) + ". Use Ethernet (or Debug).");
            end
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function backend = FindSoftware(this)
            %Connect to the first of the softwares to try that is there - errors with what is expected if none is.
            %PicoVNA 3's library only exists on this PC, so it isn't tried
            %when IP_Address is another computer

            requested = string(this.Software);
            localPC = ismember(lower(string(this.IP_Address)), ["127.0.0.1", "localhost", "::1"]);
            switch requested
                case "Auto";        tryList = ["PicoVNA 5", "PicoVNA 3"];
                otherwise;          tryList = requested;
            end
            if ~localPC
                tryList = tryList(tryList ~= "PicoVNA 3");
            end

            failures = strings(1, 0);
            for software = tryList
                candidate = this.CreateBackend(software);
                try
                    candidate.Open();
                    backend = candidate;
                    return;
                catch err
                    failures(end + 1) = "* " + software + ": " + err.message; %#ok<AGROW>
                end
            end

            expected = strings(1, 0);
            if any(requested == ["Auto", "PicoVNA 5"])
                expected(end + 1) = "* the PicoVNA 5 software, running on the computer at " + string(this.IP_Address) + ", with its SCPI interface enabled on port " + this.ConnectionSettings.Port + " (User Preferences, Network)";
            end
            if any(requested == ["Auto", "PicoVNA 3"]) && localPC && ispc     %PicoVNA 3's library is Windows only
                expected(end + 1) = "* the PicoVNA 3 software installed on this computer (the application itself closed - its library takes the analyser over)";
            end
            error("PicoVNA_NetworkAnalyser:SoftwareNotFound", "%s", "No PicoVNA software was found to talk to the analyser. This needs:" + newline + strjoin(expected, newline) + newline + newline + ...
                "Download and install them from https://www.picotech.com/downloads#t9" + newline + newline + "What happened:" + newline + strjoin(failures, newline));
        end

        function plan = ReadPlan(this)
            %The frequency plan: from the last read-back while a sweep is under way, else asked for (or the simulated one).

            if this.SimulationMode
                plan = this.SimulatedSettings;
            elseif ~this.ScanComplete
                plan = struct("StartFrequency_Hz", this.SweepSettings.StartFrequency_Hz, "StopFrequency_Hz", this.SweepSettings.StopFrequency_Hz, ...
                    "NumPoints", this.SweepSettings.NumPoints);
            else
                plan = this.Backend.ReadPlan();
            end
        end

        function settings = ReadSweepSettings(this)
            %The plan, power, bandwidth and calibration type: asked for, or from before the sweep if one is under way (or simulated).

            if this.SimulationMode
                settings = this.SimulatedSettings;
                settings.Power_dBm = this.Power_dBm;
                settings.Bandwidth_Hz = this.Bandwidth_Hz;
                settings.CalType = "Simulated";
            elseif ~this.ScanComplete
                settings = this.SweepSettings;
            else
                settings = this.Backend.ReadSweepSettings();
            end
        end

    end
end
