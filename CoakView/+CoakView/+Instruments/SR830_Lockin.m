classdef SR830_Lockin < CoakView.Core.Instrument
    %Instrument implementation for Stanford Research 830 Model lockin
    %amplifiers

    properties(Constant, Access = public)
        FullName = "SR830 lockin";     %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = "SR830";             %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        AutoSensitivity = true;    %Toggle if the instrument should change voltage range automatically
        ConnectedCurrentSource;                                     %Do we have a current source connected that will turn voltage out into a current?
        AmplifierGain = 1;  %Gain of any externally-added amplifiers or transformers to take into account.
    end

    properties(Access = private)
        DefaultGPIB_Address = 8;          %GPIB address
    end

    methods

        %% Categoricals
        function catOut = CurrentSource(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["None", "200 uA/V"]); end
      
        %% Constructor
        function this = SR830_Lockin()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial"]);
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];
            this.GPIB_Address = this.DefaultGPIB_Address;
            this.ConnectedCurrentSource = this.CurrentSource("200 uA/V");
        end

        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
            Headers = [this.Name + " - Vx (V)", this.Name + " - Vy (V)"];
            Units = ["V", "V"];

            %Find out what units the device is supplying (current or
            %voltage)
            switch(this.ConnectedCurrentSource)
                case(this.CurrentSource("None"))
                    supplyOutUnits = "V";
                    supplyOutName = "Voltage (V)";
                    calculateResistance = false;
                otherwise
                    supplyOutUnits = "A";
                    supplyOutName = "Current (A)";
                    calculateResistance = true;
            end

            %Add on output supply column
            Headers = [Headers, this.Name + " - Output " + supplyOutName];
            Units = [Units, supplyOutUnits];

            %Add on a resistance calculation too, if we have a current
            %source etc - just for convenience
            if calculateResistance
                Headers = [Headers, this.Name + " - Resistance (Ohms)"];
                Units = [Units "Ohm"];
            end
        end

        %% CollectMetadata
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
            metadataStruct.Frequency_Hz = this.GetFrequency();
        end

        %% Measure
        function [dataRow] = Measure(this)
            if(this.SimulationMode)
                data = "0.0705876,0.00256349";
            else
                %Query the lockin for simultaneous x and y values measurement and get a comma seperated string
                %returned. example for x, y of 70mV and 2.5mV: '0.0705876,0.00256349'
                %OUTP? i gets a single value. 1 = X voltage, 2 = Y, see manual 5-15
                %for more details
                data = this.QueryString("SNAP? 1,2");
            end

            %Split the string into a cell array, split at the commas
            splitData = strsplit(data, ',');

            %Get measurement values from the split string
            x = str2double(splitData{1});
            y = str2double(splitData{2});
            
            %Get the VOsc ouput level
            output = this.GetSuppliedVoltageOrCurrentAndUnits();

            %Assign data to output data row
            dataRow = [x, y, output];
            
            %Calculate resistance if current source attached   
            switch(this.ConnectedCurrentSource)
                case(this.CurrentSource("None"))
                    %Do nothing
                otherwise
                    resistance_Ohms = x / (output * this.AmplifierGain);
                    dataRow = [dataRow resistance_Ohms];
            end

            %If sensitivity autotune is enabled, auto adjust the
            %sensitivity level
            if(this.AutoSensitivity && ~this.SimulationMode)
                this.AutoTuneSensitivity(x, y);
            end
        end

        %% GetFrequency
        function freq_Hz = GetFrequency(this)
            if(this.SimulationMode)
                freq_Hz = 78.67;
                return;
            end

            freq_Hz = this.QueryDouble("FREQ?");
        end

        %% GetOutputLevel
        function level = GetOutputLevel(this)
            if(this.SimulationMode)
                level = 2;
                return;
            end

            level = this.QueryDouble("SLVL?");
        end


        %% GetSuppliedVoltageOrCurrentAndUnits
        function [magnitude, unit, name] = GetSuppliedVoltageOrCurrentAndUnits(this)

            %Get the size of voltage being output at the signal out port
            vOut = this.GetOutputLevel();  

            switch(this.ConnectedCurrentSource)
                case(this.CurrentSource("None"))
                    magnitude = vOut;
                    unit = "V";
                    name = "Voltage";
                case(this.CurrentSource("200 uA/V"))
                    magnitude = 200e-6 * vOut;
                    unit = "A";
                    name = "Current";
                otherwise
                    error("Connected current source option " + this.ConnectedCurrentSource + " not implemented in SR830 code file");
            end
        end
    end

    methods (Access = private)

        %% AutoTuneSensitivity
        function AutoTuneSensitivity(this, vx, vy)
            %Automatically increase or decrease sensitivity range by 1 if
            %voltage outside useful range

            %Largest of the two voltages X and Y, and absolute value of
            %that too to avoid negative values making trouble
            v = max(abs(vx), abs(vy));

            %Get the currrent sensitivity voltage range
            sensIndex = this.QuerySensitivityLevel();
            range = this.SensLevelToRange(sensIndex);
            rangeBelow = this.SensLevelToRange(max(sensIndex-1, 0));    %note , will return 2 nV if we are in lowest 2nV range (0->0)

            %Percentage of range at which to switch to next one up
            cutoffUpperFactor = 0.95;

            %Percentage of range below we need to be dipped into nto switch
            %down - want to avoid instability on range boundaries by
            %introducing a bit of hysteresis in up and down
            cutoffLowerFactor = 0.85;

            if(v >= cutoffUpperFactor * range)  %If voltage is equal to or above 98% of the current range, we need to switch up a range
                sensIndex = sensIndex +1;           %Increase range index by 1 - higher voltage range
                sensIndex = min(sensIndex, 26);     %26 is highest value, top range

                %Set the new range
                this.SetSensitivityLevel(sensIndex);
            elseif(v < rangeBelow * cutoffLowerFactor)          %if voltage is less than the lower factor x the max value of the range below this one, switch down
                sensIndex = sensIndex -1;           %Decrease range index by 1 - lower voltage range
                sensIndex = max(sensIndex, 0);     %0 is minimum value, lowest range

                %Set the new range
                this.SetSensitivityLevel(sensIndex);
            end
        end

        %% QuerySensitivityLevel
        function sensitivityIndex = QuerySensitivityLevel(this)
            %Returns an integer corresponding to the current
            %sensitivity / voltage range of the instrument. Runs from 0 (2nV)
            %to 26 (1V)

            % Do not do anything if instrument is simulated
            if(this.SimulationMode); return; end

            %Query instrument
            sensitivityIndex = this.QueryDouble("SENS?");
        end

        %% SetSensitivityLevel
        function SetSensitivityLevel(this, levelIndex)
            %Set a sensitivity level by passing an integer index from 0 to 26)
            arguments 
                this;
                levelIndex (1,1) {mustBeInteger, mustBeInRange(levelIndex, 0, 26)};
            end

            % Do not do anything if instrument is simulated
            if(this.SimulationMode); return; end

            %Send command
            this.WriteCommand("SENS " + string(levelIndex));
        end
    end

    methods(Static)

        %% SensLevelToRange
        function range = SensLevelToRange(level)
            %Converts the sensitivity index to the corresponding voltage range
            %value, returned as a number
            arguments
                level (1,1) {mustBeInteger};
            end

            switch(level)
                case 0
                    range = 2e-9;
                case 1
                    range = 5e-9;
                case 2
                    range = 10e-9;
                case 3
                    range = 20e-9;
                case 4
                    range = 50e-9;
                case 5
                    range = 100e-9;
                case 6
                    range = 200e-9;
                case 7
                    range = 500e-9;
                case 8
                    range = 1e-6;
                case 9
                    range = 2e-6;
                case 10
                    range = 5e-6;
                case 11
                    range = 10e-6;
                case 12
                    range = 20e-6;
                case 13
                    range = 50e-6;
                case 14
                    range = 100e-6;
                case 15
                    range = 200e-6;
                case 16
                    range = 500e-6;
                case 17
                    range = 1e-3;
                case 18
                    range = 2e-3;
                case 19
                    range = 5e-3;
                case 20
                    range = 10e-3;
                case 21
                    range = 20e-3;
                case 22
                    range = 50e-3;
                case 23
                    range = 100e-3;
                case 24
                    range = 200e-3;
                case 25
                    range = 500e-3;
                case 26
                    range = 1;
                otherwise
                    error("SR830 range index Not supported. Value: " + string(level));
            end
        end
    end
end

