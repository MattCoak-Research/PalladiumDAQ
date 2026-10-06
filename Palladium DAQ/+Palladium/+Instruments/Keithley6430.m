classdef Keithley6430 < Palladium.Core.Instrument
    %Keithley6430 - Instrument driver for the Keithley Model 6430 sub-femtoamp SourceMeter.
    %Sources a voltage or current and takes one reading per measurement tick
    %with `:READ?`, which keeps the settings made on the front panel. Depending
    %on `MeasMode`, it records the resistance, current and voltage, or just the
    %current and voltage. Each of these is the measured value where that
    %function is measured, or else the programmed source level.
    %
    %Set the source function, measurement functions, compliance and ranges on
    %the front panel, and turn the output on before measuring (`:READ?` needs
    %it on unless auto output-off is enabled). When connecting, the driver sets
    %the reading's data elements to voltage, current and resistance. A value
    %that is neither measured nor sourced, or is overrange, is recorded as NaN.
    %
    %The 6430 is a 2400-series SourceMeter with a Remote PreAmp, and has GPIB
    %and RS-232 interfaces.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Keithley 6430 Src Meter";                   %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "SrcMtr";                                        %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;                                               %Which columns to record: Resistance (R, I, V), Voltage (I, V) or Current (V, I)
        SourceMode;                                             %Source function, Voltage or Current - must match the source function set on the instrument
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr);     catOut = this.ConvertToCategorical(inputStr, ["Resistance", "Voltage", "Current"]); end
        function catOut = SourceType(this, inputStr);   catOut = this.ConvertToCategorical(inputStr, ["Voltage", "Current"]); end
    end

    %% Constructor
    methods
        function this = Keithley6430()
            %Set the supported connection types and default settings.

            %The 6430 has GPIB and RS-232 ports; VISA can address either
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial", "VISA"]);
            this.GPIB_Address = 24;     %Factory default
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

            %RS-232 uses 8 data bits, 1 stop bit and no parity. 9600 baud is the
            %factory setting, and the instrument acts on a command when it
            %receives a CR - the baud rate and terminator must match the
            %COMMUNICATION menu on the instrument
            this.ConnectionSettings.SerialSettings = struct('BaudRate', 9600, 'DataBits', 8, 'Parity', 'none', 'StopBits', 1, 'Terminator', 'CR');

            %Make sure to set values for Properties of Categorical type
            %like these
            this.MeasMode = this.MeasType("Resistance");
            this.SourceMode = this.SourceType("Current");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function Connect(this)
            %Open the connection and set the data elements returned by readings.
            %Readings are then voltage, current and resistance, in that order

            Connect@Palladium.Core.Instrument(this);
            if this.SimulationMode
                return;
            end

            this.WriteCommand(":FORM:ELEM VOLT,CURR,RES");
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %
            %Outputs:
            %   Headers - Resistance, Current and Voltage columns in Resistance
            %             MeasMode; Current then Voltage in Voltage MeasMode; and
            %             Voltage then Current in Current MeasMode
            %   Units   - matching units, e.g. ["V", "A"]

            switch(this.MeasMode)
                case(this.MeasType("Resistance"));  Headers = [this.Name + " - Resistance_Ohms", this.Name + " - Current_A", this.Name + " - Voltage_V"];     Units = ["Ohms", "A", "V"];
                case(this.MeasType("Voltage"));     Headers = [this.Name + " - Current_A", this.Name + " - Voltage_V"];                                     Units = ["A", "V"];
                case(this.MeasType("Current"));     Headers = [this.Name + " - Voltage_V", this.Name + " - Current_A"];                                     Units = ["V", "A"];
                otherwise
                    error("Keithley6430:InvalidMeasureMode", "%s", "Mode must be Resistance, Voltage, or Current, this was " + string(this.MeasMode));
            end
        end

        function srcLevel = GetSourceLevel(this)
            %Read the programmed source level.
            %
            %Outputs:
            %   srcLevel - source level, in V or A (see SourceMode)

            if (this.SimulationMode)
                %Just return dummy value
                srcLevel = 2;
                return;
            end

            switch(this.SourceMode)
                case(this.SourceType("Voltage"));   srcLevel = this.QueryDouble("SOUR:VOLT:LEV:AMPL?");
                case(this.SourceType("Current"));   srcLevel = this.QueryDouble("SOUR:CURR:LEV:AMPL?");
                otherwise
                    error("Keithley6430:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end
        end

        function [dataRow] = Measure(this)
            %Take one reading of voltage, current and resistance.
            %Each of voltage and current is the measured value if that function is
            %measured, or else the programmed source level. Values that are
            %neither measured nor sourced, or are overrange, are NaN
            %
            %Outputs:
            %   dataRow - the values, in the order of GetHeaders

            if(this.SimulationMode)
                %Dummy values, one per header
                switch(this.MeasMode)
                    case(this.MeasType("Resistance"));  dataRow = [500 0.1 50];
                    otherwise;                          dataRow = [1 0.1];
                end
                return;
            end

            %Reply is voltage, current and resistance (the data elements set in
            %Connect), e.g. for a 184 kOhm resistor with 10 uA current:
            %'+1.839736E+00,+9.999968E-06,+1.839742E+05'
            values = str2double(strsplit(this.QueryString("READ?"), ','));

            %+9.91e37 marks a value that is neither measured nor sourced, and
            %+9.9e37 an overrange reading
            values(abs(values) >= 9.9e37) = NaN;
            voltage = values(1);
            current = values(2);
            resistance = values(3);

            switch(this.MeasMode)
                case(this.MeasType("Resistance"));  dataRow = [resistance, current, voltage];
                case(this.MeasType("Voltage"));     dataRow = [current, voltage];
                case(this.MeasType("Current"));     dataRow = [voltage, current];
                otherwise
                    error("Keithley6430:InvalidMeasureMode", "%s", "Mode must be Resistance, Voltage, or Current, this was " + string(this.MeasMode));
            end
        end

        function SetSourceLevel(this, level, enableOutput)
            %Set the source level, and turn the output on or off.
            %
            %Inputs:
            %   level        - source level, in V or A (see SourceMode)
            %   enableOutput - true to turn the output on, false to turn it off

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
                case(this.SourceType("Voltage"));   this.WriteCommand("SOUR:VOLT:LEV " + num2str(level));
                case(this.SourceType("Current"));   this.WriteCommand("SOUR:CURR:LEV " + num2str(level));
                otherwise
                    error("Keithley6430:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end
        end

    end
end
