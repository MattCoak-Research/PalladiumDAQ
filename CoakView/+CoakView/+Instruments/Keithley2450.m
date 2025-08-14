classdef Keithley2450 < CoakView.Core.Instrument
    %Instrument implementation for Keithley 2450 source meter - use this rather than the 24X0 more general (and deprecated) option.

    properties(Access = public, SetObservable)
        FullName = 'Keithley 2450 Src Meter';       %Full name, just for displaying on GUI
        Name = 'SrcMtr';                            %Instrument name
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

            %Make sure to set values for Properties of Categorical type
            %like these
            this.MeasMode = this.MeasType("Resistance");
            this.SourceMode = this.SourceType("Current");
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
        function [str, limits] = GetSweepUnitsString(this)
            switch(this.SourceMode)
                case(this.MeasType("Voltage"))
                    str = "V";
                    limits = [-50, 50];    %Need to check what these physical limits actually are and improve this
                case(this.MeasType("Current"))
                    str = "A";
                    limits = [-1, 1]; %Need to check what these physical limits actually are and improve this
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end
        end

        %% Measure
        function [dataRow] = Measure(this)
            %Update the sweep controller, if one is added and a sweep is currently running, and apply its
            %latest target source level
            if ~isempty(this.SweepController)
                if this.SweepController.Running
                    valueToSet = this.SweepController.Update();
                    this.SetSourceLevel(valueToSet, true);
                end
            end

            if(this.SimulationMode)
                %Dummy values
                dataRow = [500 0.1 nan];
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
                    sourceLevel = this.GetSourceLevel();

                    %Assign data to output data row
                    dataRow = [resistance, sourceLevel];
                case(this.MeasType("Voltage"))
                    %Get measurement values 
                    voltage = str2double(data);
                    current = this.GetSourceLevel();

                    %Assign data to output data row
                    dataRow = [voltage, current];
                case(this.MeasType("Current"))
                    %Get measurement values 
                    voltage = this.GetSourceLevel();
                    current = str2double(data);

                    %Assign data to output data row
                    dataRow = [current, voltage];
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + string(this.Mode));
            end
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

