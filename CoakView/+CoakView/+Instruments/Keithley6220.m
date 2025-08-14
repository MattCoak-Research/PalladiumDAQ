classdef Keithley6220 < CoakView.Core.Instrument
    %Instrument implementation for Keithley 6220 precision current source.
    %Assumes device has already been manually configured and is measuring.
    %Just grabs latest reading
    %When written, assumes this will be being used in Delta Mode with a
    %paired Keithley 2182A Nanovoltmeter. In this mode, the 6220 sets a
    %current, sends a command via RS232 cable to the nanovoltmeter, flips
    %its current direction and sends another command, then gets the reading
    %of voltage back from the nanovoltmeter. Computer communication has to
    %be with this instrument, the 6220, in this setup. This is why we are
    %querying a current source for voltage measurement data - it is
    %speaking for a pair of instruments.
    
    properties(Access = public, SetObservable)
        FullName = "Keithley 6220 Current Source";     %Full name, just for displaying on GUI
        Name = "K6220";             %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        DeltaMode = true; %If true, measurements are being carried out with a parried nanovoltmeter in Delta Mode (this is the intended usage)
        Units;                                 %Volts, Ohms, Watts, Seimens  
    end
    
    properties(Access = private)
        DefaultGPIB_Address = 10;          %GPIB address
    end
    
    methods

        %% Categoricals
        function catOut = UnitsType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Volts", "Ohms", "Watts", "Seimens"]); end

        %% Constructor
        function this = Keithley6220()
            this.GPIB_Address = this.DefaultGPIB_Address;
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

            %Make sure to set values for Properties of Categorical type
            %like these
            this.Units = this.UnitsType("Ohms");
        end        

        %% GetSupportedConnectionTypes
        function connectionTypes = GetSupportedConnectionTypes(this)
            connectionTypes = [...
                CoakView.Enums.ConnectionType.Debug,...
                CoakView.Enums.ConnectionType.GPIB,...
                CoakView.Enums.ConnectionType.VISA,...
                CoakView.Enums.ConnectionType.Serial
                ];
        end

        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
            %Select headers and units based on the selected measurement
            %units
            switch(this.Units)
                case(this.UnitsType("Volts"))
                    Headers = [this.Name + " - Volts (V)"];
                    Units = ["V",];
                case(this.UnitsType("Ohms"))
                    Headers = [this.Name + " - Resistance (Ohms)"];
                    Units = ["Ohms"];
                case(this.UnitsType("Watts"))
                    Headers = [this.Name + " - Watts (W)"];
                    Units = ["W"];
                case(this.UnitsType("Seimens"))
                    Headers = [this.Name + " - Seimens (S)"];
                    Units = ["S"];
                otherwise
                    error("Invalid type");
            end
               
        end

        %% Measure
        function [dataRow] = Measure(this)
           
            %Get measurement values
            if(this.SimulationMode)
                %Dummy values if simulating instrument
                data = 17 + rand()*0.1;
            else
                %Query for latest measurement 
                if this.DeltaMode
                    data = this.QueryDeltaModeMeasurementValue();
                else
                    data = this.QueryMeasurementValue();
                end
            end
            
            %Assign data to output data row 
            dataRow = [data];
        end        

        function SendCommand(this, comd)
            this.QueryString(comd)
        end

    end

    methods (Access = private)

        %% QueryDeltaModeMeasurementValue
        function value = QueryDeltaModeMeasurementValue(this)
            result = this.QueryString("SENS:DATA?");
            ss = strsplit(result, ',');
            value = str2double(ss{1});
        end

        %% QueryMeasurementValue
        function value = QueryMeasurementValue(this)
            error("Not implemented");
        end
    end
end

