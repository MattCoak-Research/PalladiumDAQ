classdef Keithley6430 < Palladium.Core.Instrument
    %Instrument implementation for Keithley 6430 source meters.

    %% Properties (Constant, Public)
    properties(Constant, Access = public)
        FullName = 'Keithley 6430 Src Meter';       %Full name, just for displaying on GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'SrcMtr';                            %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;                                   %Resistance, Voltage, Current
        SourceMode;                                 %Current, Voltage
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Resistance", "Voltage", "Current"]); end
        function catOut = SourceType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Voltage", "Current"]); end
    end

    %% Constructor
    methods
        function this = Keithley6430()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = 18;      %Default Address

            %Make sure to set values for Properties of Categorical type
            %like these
            this.MeasMode = this.MeasType("Resistance");
            this.SourceMode = this.SourceType("Current");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [Headers, Units] = GetHeaders(this)
            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    Headers = [this.Name + " - Resistance_Ohms", this.Name + " - Current_A", this.Name + " - Voltage_V"];
                    Units = ["Ohms", "A", "V"];
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
        
        function [dataRow] = Measure(this)
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
                    switch(this.SourceMode)
                        case(this.SourceType("Voltage"))
                            voltage = this.GetSourceLevel();
                            current = nan;
                        case(this.SourceType("Current"))
                            current = this.GetSourceLevel();
                            voltage = nan;
                        otherwise
                            error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
                    end

                    %Assign data to output data row
                    dataRow = [resistance, current, voltage];
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
                    dataRow = [voltage, current];
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + string(this.Mode));
            end

        end

        function SetSourceLevel(this, level, enableOutput)
            if(this.SimulationMode)
                %Do nothing
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

