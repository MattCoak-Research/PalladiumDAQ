classdef Keithley2000 < CoakView.Core.Instrument
    %Instrument implementation for Keithley 2000 digital multimeters.
    %Assumes device has already been manually configured and is measuring
    %resistance.
    
    properties(Constant, Access = public)
        FullName = "Keithley 2000 DMM";     %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = "K2000";             %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;                                   %Resistance, Voltage, Current
        SourceMode;                                 %Current, Voltage  
    end
    
    properties(Access = private)
        DefaultGPIB_Address = 22;          %GPIB address
    end
    
    methods

        %% Categoricals
        function catOut = MeasType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Resistance", "Voltage", "Current"]); end
        function catOut = SourceType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Voltage", "Current"]); end

        %% Constructor
        function this = Keithley2000()
            this.GPIB_Address = this.DefaultGPIB_Address;
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

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
                case(this.MeasType("Voltage"))
                    Headers = [this.Name + " - Current_A", this.Name + " - Voltage_V"];
                    Units = ["A", "V"];
                case(this.MeasType("Current"))
                    Headers = [this.Name + " - Voltage_V", this.Name + " - Current_A"];
                    Units = ["V", "A"];
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + string(this.Mode));
            end
        end
              
        %% GetAvailableControlOptions
        function [controlDetailsStructs] = GetAvailableControlOptions(this)
            %Tell the GUI what options for Control GUIs to create
            controlDetailsStructs = struct(...
                "Name", "Sweep Control",...
                "ControlClassFileName", "SweepController_Stepped",...
                "TabName", "Sweep Control",...
                "EnabledByDefault", false);
        end

        %% GetSourceLevel
        function srcLevel = GetSourceLevel(this)
            %Returns in amps or volts.
            if (this.SimulationMode)
                %Just return dummy value
                srcLevel = 2;
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

        %% GetSupportedConnectionTypes
        function connectionTypes = GetSupportedConnectionTypes(this)
            connectionTypes = [...
                CoakView.Enums.ConnectionType.Debug,...
                CoakView.Enums.ConnectionType.GPIB,...
                CoakView.Enums.ConnectionType.VISA,...
                CoakView.Enums.ConnectionType.Ethernet,...
                CoakView.Enums.ConnectionType.Serial,...
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
            %Update the sweep controller, if one is added and a sweep is currently running, and apply its
            %latest target source level
            if ~isempty(this.SweepController)
                if this.SweepController.Running
                    valueToSet = this.SweepController.Update();
                    this.SetSourceLevel(valueToSet, true);

                    %And now wait for the set Settle Time for that change
                    %to take place before measuring
                    this.SweepController.WaitSettleTime();
                end
            end

            %Get measurement values
            if(this.SimulationMode)
                %Dummy values if simulating instrument
                data = 17 + rand()*0.1;
                sourceLevel = 0.55;
            else
                %Query the source meter for latest measurement 
                data = this.QueryDouble("MEAS?");
                sourceLevel = this.GetSourceLevel();
            end
            
            %Assign data to output data row 
            dataRow = [data, sourceLevel];
        end

        %% SetSourceLevel
        function SetSourceLevel(this, level, enableOutput)
            if(this.SimulationMode)
                %Do nothing, just print
                disp("Setting source to " + num2str(level) + ", output enabled: " + num2str(enableOutput));
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

