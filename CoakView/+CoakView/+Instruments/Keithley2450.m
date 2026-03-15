classdef Keithley2450 < CoakView.Core.Instrument
    %Instrument implementation for Keithley 2450 source meter - use this rather than the 24X0 more general (and deprecated) option.

    properties(Constant, Access = public)
        FullName = "Keithley 2450 Src Meter";       %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = "K2450_SrcMtr";                            %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;                                   %Resistance, Voltage, Current
        SourceMode;                                 %Current, Voltage       
    end

    properties(Access = private)
        DefaultGPIB_Address = 18;          %GPIB address
    end

    methods

        %% Categoricals
        function catOut = MeasType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Resistance", "Voltage", "Current"]); end
        function catOut = SourceType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Voltage", "Current"]); end

        %% Constructor
        function this = Keithley2450()
            this.GPIB_Address = this.DefaultGPIB_Address;
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];
            this.VISA_Address = 'USB0::0x05E6::0x2450::04602266::0::INSTR';
 
            %Define the Instrument Controls that can be added to the
            %Instrument
            this.DefineInstrumentControl(Name = "Sweep Control", ClassName = "SweepController_Stepped", TabName = "Sweep Control", EnabledByDefault = false);
     
            %Make sure to set values for Properties of Categorical type
            %like these
            this.MeasMode = this.MeasType("Resistance");
            this.SourceMode = this.SourceType("Current");
        end

        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    switch(this.SourceMode)
                        case(this.SourceType("Current"))
                            Headers = [this.Name + " - Resistance_Ohms", this.Name + " - Current_A"];
                            Units = ["Ohms", "A"];
                        case(this.SourceType("Voltage"))
                            Headers = [this.Name + " - Resistance_Ohms", this.Name + " - Voltage_V"];
                            Units = ["Ohms", "V"];
                        otherwise
                            error("Invalid type");
                    end
                case(this.MeasType("Current"))
                    Headers = [this.Name + " - Current_A", this.Name + " - Voltage_V"];
                    Units = ["A", "V"];
                case(this.MeasType("Voltage"))
                    Headers = [this.Name + " - Voltage_V", this.Name + " - Current_A"];
                    Units = ["V", "A"];
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + string(this.Mode));
            end
        end

        %% GetSupportedConnectionTypes
        function connectionTypes = GetSupportedConnectionTypes(this)
            connectionTypes = [...
                CoakView.Enums.ConnectionType.Debug,...
                CoakView.Enums.ConnectionType.GPIB,...
                CoakView.Enums.ConnectionType.VISA,...
                CoakView.Enums.ConnectionType.Ethernet,...
                CoakView.Enums.ConnectionType.USB...
                ];
        end

       %% GetSweepUnitsString
        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(this)
            switch(this.SourceMode)
                case(this.MeasType("Voltage"))
                    xlabelStr = "Source Voltage (V)";
                    str = "V";
                    limits = [-50, 50];    %Need to check what these physical limits actually are and improve this
                case(this.MeasType("Current"))
                    xlabelStr = "Source Current (A)";
                    str = "A";
                    limits = [-1, 1]; %Need to check what these physical limits actually are and improve this
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

            hdrs = this.GetHeaders();
            ylabelStr = hdrs(1);
        end

        %% Measure
        function [dataRow] = Measure(this)
            %Retrieve source level (will work for simulated and real data
            %both)
            sourceLevel = this.GetSourceLevel();

            if(this.SimulationMode)
                %Return dummy values if in simulation mode
                value = rand(1)*1e-7 + 2e-6;
                dataRow = [value sourceLevel];                
                return;
            end

            %Query the source meter for latest measurement and get a string
            %returned. example for a 184 kOhm resistor with 10 microA current: '+1.839736E+00,+9.999968E-06,+1.839742E+05,+6.482821E+04,+4.506000E+04'
            data = this.QueryString("READ?");   %TODO - can this be a Querydouble instead? And avoid the stplitting and converting below? Check how Srv Meas I etc work, only tried resistance so far..

            %Split the string into a cell array, split at the commas
            splitData = strsplit(data, ',');

            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    %Get measurement values from the split string
                    resistance = str2double(splitData{1});

                    %Assign data to output data row
                    dataRow = [resistance, sourceLevel];

                case(this.MeasType("Voltage"))
                    %Get measurement values 
                    voltage = str2double(data);

                    %Assign data to output data row
                    dataRow = [voltage, sourceLevel];
                    
                case(this.MeasType("Current"))
                    %Get measurement values 
                    current = str2double(data);

                    %Assign data to output data row
                    dataRow = [current, sourceLevel];
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + string(this.Mode));
            end
        end

        %% GetSourceLevel
        function srcLevel = GetSourceLevel(this)
            if (this.SimulationMode)
                srcLevel = this.RetrieveSimulatedDataValue("SourceLevel");
                return;
            end

            switch(this.SourceMode)
                case(this.SourceType("Voltage"))
                    srcLevel = this.QueryDouble("SOUR:VOLT:LEV:AMPL?");
                case(this.SourceType("Current"))
                    srcLevel = this.QueryDouble("SOUR:CURR:LEV:AMPL?");
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end
        end

        %% SetNewSweepStepValue
        function SetNewSweepStepValue(this, value)
            %This built-in function is defined in the Instrument base class
            %(does nothing) and called by any added
            %SweepController_Stepped. Define here what action to take when
            %a new step is triggered (set the new source voltage/current)
            this.SetSourceLevel(value, true);
        end

        %% SetSourceLevel
        function SetSourceLevel(this, level, enableOutput)
             if(this.SimulationMode)
                %Store in SimulatedData struct, otherwise do nothing, just print
                disp("Setting source to " + num2str(level) + ", output enabled: " + num2str(enableOutput));
                this.SimulatedData.SourceLevel = level;
                this.SimulatedData.SourceEnabled = enableOutput;
                return;
            end

            %Turn output on or off
            if(enableOutput)
                this.WriteCommand("OUTP ON");
            else
                this.WriteCommand("OUTP OFF");
            end

            switch(this.SourceMode)
                case(this.SourceType("Voltage"))
                    this.WriteCommand("SOUR:VOLT:LEV " + num2str(level));
                case(this.SourceType("Current"))
                    this.WriteCommand("SOUR:CURR:LEV " + num2str(level));
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

        end
    end
end

