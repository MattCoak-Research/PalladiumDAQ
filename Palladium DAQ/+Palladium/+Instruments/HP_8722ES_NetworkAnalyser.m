classdef HP_8722ES_NetworkAnalyser < Palladium.Core.Instrument
    %HP_8722ES_NetworkAnalyser - Instrument driver for the HP 8722ES vector network analyser (prototype).
    %Records whole frequency sweeps through the Scan Control tab, rather
    %than a value each measurement tick: each scan is saved to its own data
    %file as two columns, frequency (Hz) and the S-parameter selected by
    %`MeasMode`. `Measure` returns no values, so the analyser adds no
    %columns to the main data file.
    %
    %The 8722ES (50 MHz to 40 GHz) is remote-controlled over HP-IB (GPIB)
    %only - its RS-232 and parallel ports are for printers and plotters.
    %Other analysers in the HP 8719/8720/8722 ES and ET family share its
    %HP-IB command set and should work too.
    %
    %This driver is an untested prototype. The 87xx analysers use HP-IB
    %mnemonics such as `POIN?` and `STAR?`, not SCPI, but the data-transfer
    %methods (`InitialiseMeasurementAndFetchData`, `FetchData`) still use
    %SCPI commands copied from the PNA-L driver, and there is no `RunScan`
    %method yet to start a sweep from the Scan Control tab.

    %% Properties (Public)
    properties(Access = public)
        FullName = "HP 8722ES Network Analyser";                %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'HP_8722ES_NetworkAnalyser';                     %Instrument name, used as the prefix of its scan data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;                                               %S-parameter to measure: S11, S21, S12 or S22
        MeasUnit;                                               %Units label (dB or Absolute) for the S-parameter column header. Only labels the column - it does not change the format on the instrument.
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
            this.DefineInstrumentControl(Name = "Scan Control", ClassName = "ScanController", TabName = "Scan Control", EnabledByDefault = true);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function complete = CheckScanComplete(this)
            %Check whether the current scan has finished, for the Scan Control tab.
            %
            %Outputs:
            %   complete - true when the instrument is ready (see CheckSystemReady)

            complete = this.CheckSystemReady();
        end

        function ready = CheckSystemReady(this)
            %Check whether the instrument has finished all pending operations.
            %Queries `*OPC?`. In SimulationMode, returns true at random one call in ten
            %
            %Outputs:
            %   ready - true when the instrument is ready

            if this.SimulationMode
                dieRoll = randi(100);
                ready = dieRoll > 90; %10% chance to be true
                return;
            end

            ready = logical(this.QueryDouble("*OPC?"));
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

        function data = InitialiseMeasurementAndFetchData(this)
            %Select the S-parameter in MeasMode, then read back the sweep data.
            %Untested: the commands are SCPI from the PNA, which the 8722ES does not use
            %
            %Outputs:
            %   data - 9-row matrix of 2-port S-parameters in S2P layout (frequency, then
            %          the four S-parameters as pairs of values), one column per point

            if this.SimulationMode
                data = this.GenerateSimulatedData(this.GetNumPoints, 2, Baseline=[1000, 1e-3], Variance=[100, 1e-4]);
                return;
            end

            sParameter = string(this.MeasMode);
            this.WriteCommand("CALC:PAR:MOD " + sParameter);

            this.WaitForSystemReady();

            this.WriteCommand("CALC:DATA:SNP? 2");

            this.WaitForSystemReady();

            % Read the data back using binblock format
            [rawData] = binblockread(this.DeviceHandle, 'double');
            data = reshape(rawData, [(length(rawData)/9),9]);
            data = data';
        end

        function data = FetchData(this)
            %Read a block of sweep data already requested from the instrument.
            %Call only once the data are ready to be read. Untested on the 8722ES
            %
            %Outputs:
            %   data - 9-row matrix in S2P layout, as InitialiseMeasurementAndFetchData

            if this.SimulationMode
                data = this.GenerateSimulatedData(this.GetNumPoints, 2, Baseline=[1000, 1e-3], Variance=[100, 1e-4]);
                return;
            end

            % Read the data back using binblock format
            [rawData] = binblockread(this.DeviceHandle, 'double');
            data = reshape(rawData, [(length(rawData)/9),9]);
            data = data';
        end

        function data = GetCompletedScanData(this)
            %Data from a completed scan, for the Scan Control tab to save and plot.
            %
            %Outputs:
            %   data - scan data, as returned by FetchData

            data = this.FetchData();
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
            %   Units   - their units: "Hz", and "" for the S-parameter

            Headers = [this.Name + " - Frequency_Hz", this.Name + " - " + string(this.MeasMode) + " (" + string(this.MeasUnit) + ")"];
            Units = ["Hz", ""];
        end

        function numOfPoints = GetNumPoints(this)
            %Read the number of points per sweep.
            %
            %Outputs:
            %   numOfPoints - number of points (20 in SimulationMode)

            if this.SimulationMode
                numOfPoints = 20;
                return;
            end

            numOfPoints = this.QueryDouble("POIN?");
        end

        function startFreq_Hz = GetStartFrequency(this)
            %Read the sweep start frequency, in Hz.

            startFreq_Hz = this.QueryDouble("STAR?");
        end

        function stopFreq_Hz = GetStopFrequency(this)
            %Read the sweep stop frequency, in Hz.

            stopFreq_Hz = this.QueryDouble("STOP?");
        end

        function [dataRow] = Measure(~)
            %Return no values - scans are recorded through the Scan Control tab instead.
            %
            %Outputs:
            %   dataRow - empty, matching GetHeaders

            dataRow = [];
        end

    end

    %% Methods (Protected)
    methods(Access = protected)

        function OnInitialised(this)
            %Enlarge the input buffer and timeout for S-parameter data transfers, after connecting.

            if this.SimulationMode
                return;
            end

            % Set a sufficiently large input buffer size to store the S-Parameter data
            this.DeviceHandle.InputBufferSize = 20000;
            % Set large timeout in the event of long s-parameter measurement
            this.DeviceHandle.Timeout = 30;
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function WaitForSystemReady(this)
            %Poll CheckSystemReady every 50 ms until the instrument is ready.

            opcStatus = 0;
            while(~opcStatus)
                opcStatus = this.CheckSystemReady();
                pause(0.05);
            end
        end

    end
end
