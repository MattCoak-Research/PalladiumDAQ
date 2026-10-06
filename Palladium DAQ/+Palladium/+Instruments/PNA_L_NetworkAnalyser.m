classdef PNA_L_NetworkAnalyser < Palladium.Core.Instrument
    %PNA_L_NetworkAnalyser - Instrument driver for the Keysight (Agilent) PNA-L N5232A vector network analyser.
    %Records whole frequency sweeps through the Scan Control tab, rather
    %than a value each measurement tick. Running a scan triggers one sweep
    %on channel 1; when the channel returns to HOLD the sweep is read back
    %and saved to its own data file as two columns, frequency (Hz) and the
    %formatted trace data of the selected measurement. `Measure` returns no
    %values, so the analyser adds no columns to the main data file. The
    %sweep settings are recorded in the data-file header.
    %
    %Set up the measurement (S-parameter, format, frequency range, points)
    %on the instrument, with the trigger source set to Internal. `MeasMode`
    %and `MeasUnit` label the data column; `MeasMode` is also the parameter
    %used by `DefineMeasurement`.
    %
    %The PNA-L is controlled with SCPI commands over GPIB or LAN. Other PNA
    %series analysers share the command set and should work too, but have
    %not been tested.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Keysight PNA-L N5232A Network Analyser";    %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'PNA';                                           %Instrument name, used as the prefix of its scan data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;                                               %S-parameter measured: S11, S21, S12 or S22. Labels the data column, and is the parameter DefineMeasurement creates.
        MeasUnit;                                               %Units label (dB or Absolute) for the data column header. Only labels the column - set the trace format on the instrument.
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr);        catOut = this.ConvertToCategorical(inputStr, ["S11", "S21", "S12", "S22"]); end
        function catOut = MeasUnitType(this, inputStr);    catOut = this.ConvertToCategorical(inputStr, ["dB", "Absolute"]); end
    end

    %% Constructor
    methods
        function this = PNA_L_NetworkAnalyser()
            %Set the supported connection types, default settings and Scan Control tab.

            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "USB", "VISA"]);
            this.GPIB_Address = 16;     %Factory default
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];
            this.ConnectionSettings.GPIB_Timeout = 3;

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
            %   complete - true when the sweep is complete (see CheckSystemReady)

            complete = this.CheckSystemReady();
        end

        function ready = CheckSystemReady(this)
            %Check whether channel 1 has finished its sweep and is back on HOLD.
            %In SimulationMode, returns true at random one call in ten
            %
            %Outputs:
            %   ready - true when the channel's sweep mode is HOLD

            if this.SimulationMode
                dieRoll = randi(100);
                ready = dieRoll > 90; %10% chance to be true
                return;
            end

            %We are assuming here that the instrument is on HOLD, then will
            %execute a single measurement via TriggerSingle. Then it will
            %be in status SING throughout that, then go back to HOLD when
            %the measurement is complete. HOLD therefore means Ready
            val = this.QueryTriggerStatus();
            ready = strcmp(val, "HOLD");
        end

        function Clear(this)
            %Send a device clear to the instrument, clearing its input and output buffers.

            if this.SimulationMode
                return;
            end

            clrdevice(this.DeviceHandle);
        end

        % function ConfigurePNA(this, fileFormat)
        %     arguments
        %         this;
        %         % MA - Linear Magnitude / degrees
        %         % DB - Log Magnitude / degrees
        %         % RI - Real / Imaginary
        %         % AUTO - data is output in currently selected trace form
        %         fileFormat {mustBeTextScalar} = "AUTO";
        %     end
        %
        %     if this.SimulationMode
        %         disp("Configured simulated PNA Instrument");
        %         return;
        %     end
        %
        %     % Preset system
        %     this.WriteCommand("SYST:PRES");
        %     this.WaitForSystemReady();
        %
        %     % Set S2P File Format.
        %     this.WriteCommand("MMEM:STOR:TRAC:FORM:SNP " + string(fileFormat));
        %
        %     % Set byte order to swapped (little-endian) format
        %     % FORMat:BORDer <char>
        %     this.WriteCommand("FORM:BORD SWAP");
        %     % NORMal - Use when your controller is anything other than an IBM compatible computers
        %     % SWAPped - for IBM compatible computers
        %
        %     % Set data type to real 64 bit binary block
        %     % FORMat[:DATA] <char>, 64 for more significant digits and precision
        %     this.WriteCommand("FORM REAL,64");
        %     % REAL,32 - (default value for REAL) Best for transferring large amounts of measurement data.
        %     % REAL,64 - Slower but has more significant digits than REAL,32. Use REAL,64 if you have a computer that doesn't support REAL,32.
        %     % ASCii,0 - The easiest to implement, but very slow. Use if small amounts of data to transfer.
        % end

        function metadataStruct = CollectMetaData(this)
            %Sweep settings, recorded in the data-file header.
            %
            %Outputs:
            %   metadataStruct - struct with fields Freq_Start_Hz, Freq_Stop_Hz,
            %   NumPoints, SweepTime_s and SweepType

            metadataStruct.Freq_Start_Hz = this.GetFrequencyStart();
            metadataStruct.Freq_Stop_Hz = this.GetFrequencyStop();
            metadataStruct.NumPoints = this.GetNumPoints();
            metadataStruct.SweepTime_s = this.GetSweepTime();
            metadataStruct.SweepType = this.GetSweepType();
        end

        function DefineMeasurement(this, name)
            %Create a measurement on channel 1 of the S-parameter in MeasMode.
            %
            %Inputs:
            %   name - name of the new measurement, e.g. "CH1_S11_1"

            arguments
                this;
                name {mustBeTextScalar} = "CH1_S11_1";
            end

            %scpi.Parse("CALC:PAR:DEF ""sdd21"",S11")
            this.WriteCommand("CALC:PAR:DEF " + """" + name + """," + string(this.MeasMode));
        end

        % function data = InitialiseMeasurementAndFetchData(this)
        %     % Set up the trace corresponding to PARAMETER on the PNA and return DATA,
        %     % a matrix of 2-port S-Parameters in S2P format with specified PRECISION.
        %     % COUNT is the number of values read and MESSAGE tells us if the read
        %     % operation was unsuccessful for some reason.
        %     if this.SimulationMode
        %         data = randn([this.GetNumPoints, 2]);
        %         return;
        %     end
        %
        %     sParameter = string(this.MeasMode);
        %     this.WriteCommand("CALC:PAR:MOD " + sParameter);
        %
        %     this.WaitForSystemReady();
        %
        %     this.WriteCommand("CALC:DATA:SNP? 2");
        %
        %     this.WaitForSystemReady();
        %
        %     % Read the data back using binblock format
        %     [rawData] = binblockread(this.DeviceHandle, 'double');
        %     data = reshape(rawData, [(length(rawData)/9),9]);
        %     data = data';
        % end


        %The *OPC? query stops the controller until all pending commands are completed.
        % In the following example, the Read statement following the *OPC? query will not complete until the analyzer
        % responds, which will not happen until all pending commands have finished. Therefore, the analyzer and other
        % devices receive no subsequent commands. A "1" is placed in the analyzer output queue when the analyzer
        % completes processing an overlapped command. The "1" in the output queue satisfies the Read command and the
        % 2511
        % program continues.
        % Example of the *OPC? query
        % This program determines which frequency contains the maximum amplitude.
        % GPIB.Write "ABORT; :INITIATE:IMMEDIATE"! Restart the measurement
        % GPIB.Write "*OPC?" 'Wait until complete
        % Meas_done = GPIB.Read 'Read output queue, throw away result
        % GPIB.Write "CALCULATE:MARKER:MAX" 'Search for max amplitude
        % GPIB.Write "CALCULATE:MARKER:X?" 'Which frequency?
        % Marker_x = GPIB.Read
        % PRINT "MARKER at " & Marker_x & " Hz"

        function data = FetchData(this)
            %Read the formatted trace data of the selected measurement on channel 1.
            %Call only once the sweep is complete. Sets ASCII data format
            %
            %Outputs:
            %   data - row vector of one value per point, in the displayed format (two
            %          values per point for Polar and Smith chart formats)

            if this.SimulationMode
                %One value per point, as from the instrument
                data = this.GenerateSimulatedData(this.GetNumPoints, 1, Baseline=1, Variance=0.04);
                return;
            end

            % Read the data back using binblock format
            %[rawData] = binblockread(this.DeviceHandle, 'double');
            %data = reshape(rawData, [(length(rawData)/9),9]);
            % data = data';

            %Have these options:
            %'GPIB.Write "CALCulate:DATA? FDATA" 'Formatted Meas
            %'GPIB.Write "CALCulate:DATA? FMEM" 'Formatted Memory
            %GPIB.Write "CALCulate:DATA? SDATA" 'Corrected, Complex Meas
            %'GPIB.Write "CALCulate:DATA? SMEM" 'Corrected, Complex Memory
            %'GPIB.Write "CALCulate:DATA? SCORR1" 'Error-Term Directivity

            this.WriteCommand("FORMat ASCII");
            this.WriteCommand("CALCulate1:DATA? FDATA");
            result = this.ReadString();
            data = str2num(result); %#ok<ST2NM> - this is not a scalar, it's a 1xNumPoints cellarray
        end

        function data = GetCompletedScanData(this)
            %Frequencies and trace data from a completed scan, for the Scan Control tab to save and plot.
            %
            %Outputs:
            %   data - two columns: frequency (Hz) and the trace data from FetchData

            %Read the trace first: FetchData sets the ASCII data format that
            %GetFrequencyValues also needs
            traceData = this.FetchData();
            data(:,1) = this.GetFrequencyValues();
            data(:,2) = traceData;
        end

        function freq_Hz = GetFrequencyStart(this)
            %Read the channel 1 start frequency, in Hz.

            if this.SimulationMode
                freq_Hz = 300e3;
                return;
            end

            freq_Hz = this.QueryDouble("SENSe1:FREQuency:STARt?");
        end

        function freq_Hz = GetFrequencyStop(this)
            %Read the channel 1 stop frequency, in Hz.

            if this.SimulationMode
                freq_Hz = 300e3 + this.GetNumPoints - 1;
                return;
            end

            freq_Hz = this.QueryDouble("SENSe1:FREQuency:STOP?");
        end

        function freqVals_Hz = GetFrequencyValues(this)
            %Read the stimulus (frequency) value of every point in the sweep.
            %Reply is in the current data format (FORMat), which must be ASCII
            %
            %Outputs:
            %   freqVals_Hz - row vector of frequencies, in Hz

            if this.SimulationMode
                freqVals_Hz = 300e3 : 300e3 + this.GetNumPoints - 1;
                return;
            end

            result = this.QueryString("SENS:X?");
            freqVals_Hz = str2num(result); %#ok<ST2NM> - this is not a scalar, it's a 1xNumPoints cellarray
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
            %   Headers - frequency and S-parameter headers, e.g. "PNA - S11 (dB)"
            %   Units   - their units: "Hz", and "" for the S-parameter

            Headers = [this.Name + " - Frequency_Hz", this.Name + " - " + string(this.MeasMode) + " (" + string(this.MeasUnit) + ")"];
            Units = ["Hz", ""];
        end

        function time = GetSweepTime(this)
            %Read the channel 1 sweep time, in seconds.

            if this.SimulationMode
                time = 1.4;
                return;
            end

            time = this.QueryDouble("SENS1:SWE:TIME?");
        end

        function type = GetSweepType(this)
            %Read the sweep type, e.g. "LIN" or "LOG" (also POW, CW or SEGM).

            result = this.QueryString("SENS:SWE:TYPE?");
            type = strip(string(result));
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

            numOfPoints = this.QueryDouble("SENS:SWE:POIN?");
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

        function statusStr = QueryTriggerStatus(this)
            %Read the channel 1 sweep (trigger) mode: HOLD, CONT, GRO or SING.

            result = this.QueryString("SENS1:SWEep:MODE?");
            statusStr = strip(string(result));
        end

        function RunScan(this)
            %Start a scan, when Run is pressed on the Scan Control tab, by triggering one sweep.

            this.TriggerSingle();
        end

        function SetFrequencyStartAndStop(this, start_Hz, stop_Hz)
            %Set the channel 1 start and stop frequencies.
            %
            %Inputs:
            %   start_Hz - start frequency, in Hz
            %   stop_Hz  - stop frequency, in Hz

            arguments
                this;
                start_Hz (1,1) double;
                stop_Hz (1,1) double;
            end

            this.WriteCommand("SENSe1:FREQuency:STARt " + num2str(start_Hz, '%d'));
            this.WriteCommand("SENSe1:FREQuency:STOP " + num2str(stop_Hz, '%d'));
        end

        function SetNumPoints(this, numPts)
            %Set the number of points per sweep (1 to 20001).

            arguments
                this;
                numPts (1,1) {mustBeInteger}
            end

            if this.SimulationMode
                disp("Set simulated VNA num pts to " + num2str(numPts));
                return;
            end

            this.WriteCommand("SENS:SWE:POIN " + num2str(numPts));
        end

        function SetSweepTime(this, time_s)
            %Set the channel 1 sweep time, in seconds.

            arguments
                this;
                time_s (1,1) double {mustBePositive};
            end

            if this.SimulationMode
                disp("Set simulated VNA scan time to " + num2str(time_s) + " s");
                return;
            end

            this.WriteCommand("SENS1:SWE:TIME " + num2str(time_s));
        end

        function SetSweepType(this, type)
            %Set the sweep type to linear or logarithmic frequency.
            %
            %Inputs:
            %   type - "Linear" or "Log"

            arguments
                this;
                type {mustBeTextScalar}; %The instrument also has POWer, CW and SEGMent (SEGMent needs a segment turned ON) - not supported here
            end

            if this.SimulationMode
                disp("Set simulated VNA sweep type to " + type);
            end

            switch(type)
                case("Linear");     this.WriteCommand("SENS:SWE:TYPE LIN");
                case("Log");        this.WriteCommand("SENS:SWE:TYPE LOG");
                otherwise
                    error("PNA_L_NetworkAnalyser:UnsupportedSweepType", "%s", "Sweep type " + string(type) + " not supported");
            end
        end

        function SelectMeasurement(this, name)
            %Select a measurement on channel 1, for the CALCulate commands (e.g. FetchData) to act on.
            %
            %Inputs:
            %   name - name of the measurement, e.g. "CH1_S11_1"

            arguments
                this;
                name {mustBeTextScalar} = "CH1_S11_1";
            end

            this.WriteCommand("CALC:PAR:SEL " + """" + name + """");
        end

        function result = Test(this)
            %Read the status byte (`*STB?`), as a quick communication check.
            %
            %Outputs:
            %   result - the status byte reply, as text

            this.WriteCommand("*STB?");
            result = this.ReadString();
        end

        function TriggerSingle(this, waitForCompletion)
            %Trigger one sweep on channel 1, after which it goes to HOLD.
            %
            %Inputs:
            %   waitForCompletion - if true, wait (with `*OPC?`) until the sweep is
            %                       complete. Default false

            arguments
                this;
                waitForCompletion (1,1) logical = false;
            end

            if waitForCompletion
                %*OPC? replies "1" when the sweep is complete - read it, so it
                %does not sit in the output queue as the reply to the next query
                this.QueryDouble("SENS1:SWE:MODE SINGle;*OPC?");
            else
                this.WriteCommand("SENS1:SWE:MODE SINGle");
            end
        end

    end

    %% Methods (Protected)
    methods(Access = protected)

        function OnInitialised(this)
            %Enlarge the input buffer for trace data transfers, after connecting.

            if this.SimulationMode
                return;
            end

            % Set a sufficiently large input buffer size to store the S-Parameter data
            this.DeviceHandle.InputBufferSize = 20000;
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function WaitForSystemReady(this)
            %Poll CheckSystemReady every 50 ms until the sweep is complete.

            opcStatus = 0;
            while(~opcStatus)
                opcStatus = this.CheckSystemReady();
                pause(0.05);
            end
        end

    end
end
