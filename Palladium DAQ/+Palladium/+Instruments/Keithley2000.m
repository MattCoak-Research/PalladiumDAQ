classdef Keithley2000 < Palladium.Core.Instrument
    %Keithley2000 - Instrument driver for the Keithley Model 2000 6.5-digit digital multimeter.
    %Takes one reading per measurement tick, of whichever function (DC or AC
    %voltage, DC or AC current, 2- or 4-wire resistance, frequency, period or
    %temperature) is selected on the instrument. Set the function, range,
    %integration rate and filtering on the front panel before connecting:
    %the driver reads the function back as `MeasMode` when it connects, and
    %records the range and integration rate in the data-file header.
    %
    %The Model 2000 has GPIB and RS-232 interfaces, and is a meter only - it
    %has no source output, so it cannot drive a sweep.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Keithley 2000 DMM";                         %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "K2000";                                         %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end

    %% Properties (Public, Private Set)
    properties(GetAccess = public, SetAccess = {?Palladium.Instruments.Keithley2000, ?matlab.unittest.TestCase})
        MeasMode;                                               %Measurement function selected on the instrument, read from it when connecting. Sets the data column header and units.
        MeasUnit = "Ohms";                                      %Units of the readings in MeasMode, e.g. "V" or "Ohms". Read from the instrument for Temperature (C, F or K) and AC Voltage (V, dB or dBm).
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["DC Voltage", "AC Voltage", "DC Current", "AC Current", "Resistance", "4-Wire Resistance", "Frequency", "Period", "Temperature"]); end
    end

    %% Constructor
    methods
        function this = Keithley2000()
            %Set the supported connection types and default connection settings

            %The Model 2000 has GPIB and RS-232 ports; VISA can address either
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial", "VISA"]);
            this.GPIB_Address = 16;     %Factory default
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

            %RS-232 is fixed at 8 data bits, 1 stop bit and no parity. 4800
            %baud and an LF terminator are the factory settings - they must
            %match the RS232 menu on the instrument
            this.ConnectionSettings.SerialSettings = struct('BaudRate', 4800, 'DataBits', 8, 'Parity', 'none', 'StopBits', 1, 'Terminator', 'LF');

            this.MeasMode = this.MeasType("Resistance");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function Close(this)
            %Restore continuous readings, then disconnect.
            %Puts the instrument back to free-running readings, as on the front panel

            if ~this.SimulationMode && ~isempty(this.DeviceHandle)
                this.WriteCommand(":INIT:CONT ON");
            end
            Close@Palladium.Core.Instrument(this);
        end

        function metadataStruct = CollectMetaData(this)
            %Measurement setup, recorded in the data-file header.
            %The function and units and, where the function has them, the range and
            %integration rate
            %
            %Outputs:
            %   metadataStruct - struct with fields MeasurementMode and Units,
            %   plus Range, AutoRange and NPLC for voltage, current and
            %   resistance functions

            metadataStruct.MeasurementMode = string(this.MeasMode);
            metadataStruct.Units = this.MeasUnit;

            %Range and integration rate exist for voltage, current and
            %resistance only - frequency, period and temperature use other
            %settings
            scpiFunction = this.ScpiFunction(this.MeasMode);
            if any(startsWith(scpiFunction, ["VOLT", "CURR", "RES", "FRES"]))
                metadataStruct.Range = this.QueryDouble(":SENS:" + scpiFunction + ":RANG?");
                metadataStruct.AutoRange = this.QueryDouble(":SENS:" + scpiFunction + ":RANG:AUTO?") == 1;
                metadataStruct.NPLC = this.QueryDouble(":SENS:" + scpiFunction + ":NPLC?");
            end
        end

        function Connect(this)
            %Open the connection and prepare the instrument for measuring.
            %Sets up triggering for one fresh reading per Measure call, and reads back
            %the measurement function and units
            %selected on the instrument

            Connect@Palladium.Core.Instrument(this);
            if this.SimulationMode
                return;
            end

            %Clear the error queue, and have readings sent as a bare number
            %(no units or channel) so they can be parsed as a double
            this.WriteCommand("*CLS");
            this.WriteCommand(":FORM:ELEM READ");

            %Stop free-running readings, so that each :READ? in Measure
            %triggers and returns one new reading. The function, range,
            %integration rate and filter set on the front panel are kept
            %(unlike :CONFigure, which resets them)
            this.WriteCommand(":INIT:CONT OFF");
            this.WriteCommand(":TRIG:SOUR IMM");
            this.WriteCommand(":TRIG:COUN 1");
            this.WriteCommand(":SAMP:COUN 1");

            [this.MeasMode, this.MeasUnit] = this.GetMeasurementMode();
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column header and units for the reading returned by Measure
            %
            %Outputs:
            %   Headers - one header, e.g. "K2000 - Resistance_Ohms"
            %   Units   - its units, e.g. "Ohms"

            switch(this.MeasMode)
                case(this.MeasType("DC Voltage"));          quantity = "Voltage_DC";
                case(this.MeasType("AC Voltage"));          quantity = "Voltage_AC";
                case(this.MeasType("DC Current"));          quantity = "Current_DC";
                case(this.MeasType("AC Current"));          quantity = "Current_AC";
                case(this.MeasType("Resistance"));          quantity = "Resistance";
                case(this.MeasType("4-Wire Resistance"));   quantity = "Resistance_4W";
                case(this.MeasType("Frequency"));           quantity = "Frequency";
                case(this.MeasType("Period"));              quantity = "Period";
                case(this.MeasType("Temperature"));         quantity = "Temperature";
                otherwise
                    error("Keithley2000:InvalidMeasureMode", "%s", "Unsupported measurement mode: " + string(this.MeasMode));
            end

            Headers = this.Name + " - " + quantity + "_" + this.MeasUnit;
            Units = this.MeasUnit;
        end

        function [measMode, measUnit] = GetMeasurementMode(this)
            %Read the instrument's measurement function and reading units.
            %
            %Outputs:
            %   measMode - MeasType categorical, e.g. Resistance
            %   measUnit - units of the readings, e.g. "Ohms"

            if this.SimulationMode
                measMode = this.MeasMode;
                measUnit = this.MeasUnit;
                return;
            end

            %Reply is the quoted function name, e.g. "VOLT:DC" or "RES"
            reply = upper(strtrim(erase(string(this.QueryString(":FUNC?")), ["""", "'"])));
            switch(reply)
                case("VOLT:DC");    measMode = this.MeasType("DC Voltage");         measUnit = "V";
                case("VOLT:AC");    measMode = this.MeasType("AC Voltage");         measUnit = this.QueryUnit(":UNIT:VOLT:AC?");
                case("CURR:DC");    measMode = this.MeasType("DC Current");         measUnit = "A";
                case("CURR:AC");    measMode = this.MeasType("AC Current");         measUnit = "A";
                case("RES");        measMode = this.MeasType("Resistance");         measUnit = "Ohms";
                case("FRES");       measMode = this.MeasType("4-Wire Resistance");  measUnit = "Ohms";
                case("FREQ");       measMode = this.MeasType("Frequency");          measUnit = "Hz";
                case("PER");        measMode = this.MeasType("Period");             measUnit = "s";
                case("TEMP");       measMode = this.MeasType("Temperature");        measUnit = this.QueryUnit(":UNIT:TEMP?");
                otherwise
                    %Diode and continuity tests give pass/fail results, not
                    %readings worth logging
                    error("Keithley2000:UnsupportedMeasurementFunction", "%s", "Unsupported measurement function on " + this.Name + ": " + reply + ...
                        ". Select a voltage, current, resistance, frequency, period or temperature function on the front panel.");
            end
        end

        function [dataRow] = Measure(this)
            %Trigger and return one new reading, in MeasUnit.
            %An overrange reading is returned as NaN
            %
            %Outputs:
            %   dataRow - the reading (a scalar, matching GetHeaders)

            if(this.SimulationMode)
                dataRow = this.GenerateSimulatedData(1, Baseline=17, Variance=0.1);
                return;
            end

            %:READ? triggers a reading and waits for it (see Connect)
            dataRow = this.QueryDouble(":READ?");

            %The instrument returns +9.9e37 for an overrange reading
            if abs(dataRow) >= 9.9e37
                dataRow = NaN;
            end
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function unit = QueryUnit(this, command)
            %Query a :UNIT setting and return it as a units string, e.g. "dBm".
            %
            %Inputs:
            %   command - the :UNIT query to send, e.g. ":UNIT:TEMP?"
            %
            %Outputs:
            %   unit - units string, with dB and dBm in their usual case

            unit = strtrim(string(this.QueryString(command)));
            switch(upper(unit))
                case("DB");     unit = "dB";
                case("DBM");    unit = "dBm";
                otherwise;      unit = upper(unit);
            end
        end

        function scpiFunction = ScpiFunction(this, measMode)
            %SCPI name of a measurement function, e.g. "VOLT:DC" for DC Voltage.
            %As used in :SENS commands
            %
            %Inputs:
            %   measMode - MeasType categorical
            %
            %Outputs:
            %   scpiFunction - SCPI function name string

            names = ["VOLT:DC", "VOLT:AC", "CURR:DC", "CURR:AC", "RES", "FRES", "FREQ", "PER", "TEMP"];
            scpiFunction = names(categories(this.MeasType("Resistance")) == string(measMode));
        end

    end
end
