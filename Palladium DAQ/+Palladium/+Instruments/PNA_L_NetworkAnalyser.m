classdef PNA_L_NetworkAnalyser < Palladium.Core.Instrument
    %Instrument implementation for a Keithley PNA-L_Network Analyser N5232A
    %- other PNA instruments in the series should work too, but could not
    %yet be tested

    %% Properties (Constant, Public)
    properties(Constant, Access = public)
        FullName = "Keithley PNA-L_Network Analyser N5232A";       %Full name, just for displaying on GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'PNA';                            %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;
        MeasUnit;
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["S11", "S21", "S12", "S22"]); end
        function catOut = MeasUnitType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["dB", "Absolute"]); end
    end

    %% Constructor
    methods
        function this = PNA_L_NetworkAnalyser()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = 16;      %Default Address
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
            %Used by ScanController update logic
            complete = this.CheckSystemReady();
        end

        function ready = CheckSystemReady(this)

            if this.SimulationMode
                dieRoll = randi(100);
                ready = dieRoll > 90; %10% chance to be true
                return;
            end

            %We are assuming here that the instrument is on HOLD, then will
            %execute a single measurement via TriggerSingle. Then it will
            %be in status GRO throughout that, then go back to HOLD when
            %the measurement is complete. HOLD therefore means Ready
            val = this.QueryTriggerStatus();
            ready = strcmp(val, "HOLD");
        end

        function Clear(this)
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
            %Does nothing by default - implementations of individual
            %instruments can override this to give functionality.
            %Delete this function if no metadata is desired for this
            %instrument.
            %If a struct is returned it will be parsed
            %into a string and that added as a line in the data file
            %header.
            %Use this to record instrument settings and metadata like
            %frequency, voltage, measurement mode, that will not change
            %during the measurement and therefore don't merit logging each
            %step
            metadataStruct.Freq_Start_Hz = this.GetFrequencyStart();
            metadataStruct.Freq_Stop_Hz = this.GetFrequencyStop();
            metadataStruct.NumPoints = this.GetNumPoints();
            metadataStruct.SweepTime_s = this.GetSweepTime();
            metadataStruct.SweepType = this.GetSweepType();
        end

        function DefineMeasurement(this, name)
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
            % Only call this after verifying data ar ready to be read
            if this.SimulationMode
                data = randn([this.GetNumPoints, 2]);
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
            data(:,1) = this.GetFrequencyValues();
            data(:,2) = this.FetchData();
        end

        function freq_Hz = GetFrequencyStart(this)
            if this.SimulationMode
                freq_Hz = 300e3;
                return;
            end

            freq_Hz = this.QueryDouble("SENSe1:FREQuency:STARt?");
        end

        function freq_Hz = GetFrequencyStop(this)
            if this.SimulationMode
                freq_Hz = 300e3 + this.GetNumPoints - 1;
                return;
            end

            freq_Hz = this.QueryDouble("SENSe1:FREQuency:STOP?");
        end

        function freqVals_Hz = GetFrequencyValues(this)

            if this.SimulationMode
                freqVals_Hz = 300e3 : 300e3 + this.GetNumPoints - 1;
                return;
            end

            result = this.QueryString("SENS:X?");
            freqVals_Hz = str2num(result); %#ok<ST2NM> - this is not a scalar, it's a 1xNumPoints cellarray
        end

        function [Headers, Units] = GetHeaders(this)
            %Gets the column headers for data columns returned by this
            %instrument. There must be the same number as Measure returns.
            Headers = [];
            Units = [];
        end

        function [Headers, Units] = GetScanHeaders(this)
            Headers = [this.Name + " - Frequency_Hz", this.Name + " - " + string(this.MeasMode) + " (" + string(this.MeasUnit) + ")"];
            Units = ["Hz", ""];
        end

        function time = GetSweepTime(this)
            if this.SimulationMode
                time = 1.4;
                return;
            end

            time = this.QueryDouble("SENS1:SWE:TIME?");
        end

        function type = GetSweepType(this)
            result = this.QueryString("SENS:SWE:TYPE?");
            type = strip(string(result));
        end

        function numOfPoints = GetNumPoints(this)
            if this.SimulationMode
                numOfPoints = 20;
                return;
            end

            % numOfPoints = query(visaObj, 'SENS:SWE:POIN?','%s\n','%d');
            numOfPoints = this.QueryDouble("SENS:SWE:POIN?");
        end

        function [dataRow] = Measure(this)
            %As sweeps are slow and standalone, this instrument does not
            %return any row-by-row data, only individual Scans via a
            %ScanController
            dataRow = [];
        end

        function statusStr = QueryTriggerStatus(this)
            result = this.QueryString("SENS1:SWEep:MODE?");
            statusStr = strip(string(result));
        end

        function RunScan(this)
            %Called by ScanController when the scan gets Run called
            this.TriggerSingle();
        end

        function SetFrequencyStartAndStop(this, start_Hz, stop_Hz)
            arguments
                this;
                start_Hz (1,1) double;
                stop_Hz (1,1) double;
            end
            %GPIBWrite("SENSe1:FREQuency:STARt 1000000000");
            %GPIBWrite("SENSe1:FREQuency:STOP 2000000000");
            this.WriteCommand("SENSe1:FREQuency:STARt " + num2str(start_Hz, '%d'));
            this.WriteCommand("SENSe1:FREQuency:STOP " + num2str(stop_Hz, '%d'));
        end

        function SetNumPoints(this, numPts)
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
            arguments
                this;
                type {mustBeTextScalar}; %LINear | LOGarithmic | POWer | CW | SEGMent
                %Note: SWEep TYPE cannot be set to SEGMent if there are no segments turned
                %ON. A segment is automatically turned ON when the analyzer is started
            end

            if this.SimulationMode
                disp("Set simulated VNA sweep type to " + type);
            end

            switch(type)
                case("Linear")
                    this.WriteCommand("SENS:SWE:TYPE LIN");
                case("Log")
                    this.WriteCommand("SENS:SWE:TYPE LOG");
                otherwise
                    error("Sweep type " + string(type) + " not supported");
            end
        end

        function SelectMeasurement(this, name)
            arguments
                this;
                name {mustBeTextScalar} = "CH1_S11_1";
            end

            %fprintf(visaObj, 'CALC:PAR:SEL "CH1_S11_1"');
            this.WriteCommand("CALC:PAR:SEL " + """" + name + """");
        end

        function result = Test(this)
            % Set data return format and trigger a single measurement
            %  this.WriteCommand("FORM5; OPC?; SING");
            % data=fscanf(this.DeviceHandle);

            this.WriteCommand("*STB?");
            result = this.ReadString();
        end

        function TriggerSingle(this, waitForCompletion)
            arguments
                this;
                waitForCompletion (1,1) logical = false;
            end

            %'The following command makes the channel immediately sweep
            %'*OPC? allows the measurement to complete before the controller sends another
            %command
            %scpi.Execute ("SENS1:SWE:MODE SINGle;*OPC?")
            if waitForCompletion
                this.WriteCommand("SENS1:SWE:MODE SINGle;*OPC?");
            else
                this.WriteCommand("SENS1:SWE:MODE SINGle");
            end
        end

        %scpi.Execute ("SENS1:SWE:MODE HOLD") to put into hold trigger
        %status (before?)

    end

    %% Methods (Protected)
    methods(Access = protected)

        function OnInitialised(this)
            %This gets called right after Connect()
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
            opcStatus = 0;
            while(~opcStatus)
                opcStatus = this.CheckSystemReady();
                pause(0.05);
            end
        end

    end
end

