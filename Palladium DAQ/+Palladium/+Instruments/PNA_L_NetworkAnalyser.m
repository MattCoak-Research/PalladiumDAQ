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

            %opcStatus = query(this.DeviceHandle, '*OPC?','%s\n','%d');
            ready = logical(this.QueryDouble("*OPC?"));
        end

        function Clear(this)
            clrdevice(this.DeviceHandle);
        end

        function ConfigurePNA(fileFormat)
            arguments
                % MA - Linear Magnitude / degrees
                % DB - Log Magnitude / degrees
                % RI - Real / Imaginary
                % AUTO - data is output in currently selected trace form
                fileFormat {mustBeTextScalar} = "AUTO";
            end

            if this.SimulationMode
                disp("Configured simulated PNA Instrument");
                return;
            end

            % Preset system
            this.WriteCommand("SYST:PRES");
            this.WaitForSystemReady();

            % Set S2P File Format.
            this.WriteCommand("MMEM:STOR:TRAC:FORM:SNP " + string(fileFormat));

            % Set byte order to swapped (little-endian) format
            % FORMat:BORDer <char>
            this.WriteCommand("FORM:BORD SWAP");
            % NORMal - Use when your controller is anything other than an IBM compatible computers
            % SWAPped - for IBM compatible computers

            % Set data type to real 64 bit binary block
            % FORMat[:DATA] <char>, 64 for more significant digits and precision
            this.WriteCommand("FORM REAL,64");
            % REAL,32 - (default value for REAL) Best for transferring large amounts of measurement data.
            % REAL,64 - Slower but has more significant digits than REAL,32. Use REAL,64 if you have a computer that doesn't support REAL,32.
            % ASCii,0 - The easiest to implement, but very slow. Use if small amounts of data to transfer.
        end

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
            metadataStruct.ExampleProperty1 = "TODO - write PNA metadata";
        end

        function data = InitialiseMeasurementAndFetchData(this)
            % Set up the trace corresponding to PARAMETER on the PNA and return DATA,
            % a matrix of 2-port S-Parameters in S2P format with specified PRECISION.
            % COUNT is the number of values read and MESSAGE tells us if the read
            % operation was unsuccessful for some reason.
            if this.SimulationMode
                data = randn([this.GetNumPoints, 2]);
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
            % Only call this after verifying data ar ready to be read
            if this.SimulationMode
                data = randn([this.GetNumPoints, 2]);
                return;
            end

            % Read the data back using binblock format
            [rawData] = binblockread(this.DeviceHandle, 'double');
            data = reshape(rawData, [(length(rawData)/9),9]);
            data = data';
        end

        function data = GetCompletedScanData(this)
            data = this.FetchData();
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

        function numOfPoints = GetNumPoints(this)
            if this.SimulationMode
                numOfPoints = 20;
                return;
            end

            % numOfPoints = query(visaObj, 'SENS:SWE:POIN?','%s\n','%d');
            numOfPoints = this.QueryDouble("SENS:SWE:POIN?");
        end

        function [dataRow] = Measure(this)
            dataRow = [];
        end

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
            % Set large timeout in the event of long s-parameter measurement
            this.DeviceHandle.Timeout = 30;
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

