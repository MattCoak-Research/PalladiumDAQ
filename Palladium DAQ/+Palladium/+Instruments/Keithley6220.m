classdef Keithley6220 < Palladium.Core.Instrument
    %Keithley6220 - Instrument driver for the Keithley Model 6220 precision DC current source, in Delta mode.
    %Made for Delta mode with a paired Keithley 2182A nanovoltmeter. In
    %this mode the 6220 sources a current, triggers the 2182A over the
    %RS-232 cable between them, reverses the current and triggers again,
    %and takes the voltage readings back from the 2182A. The computer
    %talks only to the 6220, which speaks for the pair - which is why a
    %current source returns voltage (or resistance) readings.
    %
    %Set up and start Delta mode on the instrument before measuring. On
    %connecting, the driver reads the reading units selected on the
    %instrument (`UNIT?`) into `Units`, which names the data column, and
    %adds the reading number to each reading (`FORM:ELEM READ,RNUM`). Each
    %measurement tick reads the latest Delta reading (`SENS:DATA?`); if no
    %new reading has been made since the last tick, it is recorded as NaN
    %rather than repeated.
    %
    %With `DeltaMode` false, the driver records the programmed source
    %current instead (`SOUR:CURR?`), for using the 6220 as a plain current
    %source.
    %
    %The 6220 has GPIB and RS-232 interfaces.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Keithley 6220 Current Source";              %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "K6220";                                         %Instrument name, used as the prefix of its data column header
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        DeltaMode (1,1) logical = true;                         %If true, record Delta mode readings from a paired 2182A nanovoltmeter. If false, record the programmed source current.
        Units;                                                  %Units of the Delta readings - Volts, Ohms, Watts or Siemens. Read from the instrument's reading units when connecting in Delta mode.
    end

    %% Properties (Private)
    properties(Access = private)
        LastReadingNumber = NaN;                                %Reading number of the last Delta reading recorded, to spot a reading read again (NaN since connecting)
    end

    %% Categoricals
    methods
        function catOut = UnitsType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Volts", "Ohms", "Watts", "Siemens"]); end
    end

    %% Constructor
    methods
        function this = Keithley6220()
            %Set the supported connection types and default connection settings

            %The 6220 has GPIB and RS-232 ports; VISA can address either
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial", "VISA"]);
            this.GPIB_Address = 12;     %Factory default
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

            %RS-232 is fixed at 8 data bits, 1 stop bit and no parity.
            %19.2k baud and an LF terminator are the factory settings - they
            %must match the RS-232 settings on the instrument
            this.ConnectionSettings.SerialSettings = struct('BaudRate', 19200, 'DataBits', 8, 'Parity', 'none', 'StopBits', 1, 'Terminator', 'LF');

            %Make sure to set values for Properties of Categorical type
            %like these
            this.Units = this.UnitsType("Ohms");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [Headers, Units] = GetHeaders(this)
            %Data column header and units for the reading returned by Measure.
            %The Delta reading, in Units - or the source current, without
            %DeltaMode
            %
            %Outputs:
            %   Headers - one header, e.g. "K6220 - Resistance (Ohms)"
            %   Units   - its units, e.g. "Ohms"

            if ~this.DeltaMode
                Headers = this.Name + " - Source Current (A)";
                Units = "A";
                return;
            end

            switch(this.Units)
                case(this.UnitsType("Volts"));      Headers = this.Name + " - Volts (V)";           Units = "V";
                case(this.UnitsType("Ohms"));       Headers = this.Name + " - Resistance (Ohms)";   Units = "Ohms";
                case(this.UnitsType("Watts"));      Headers = this.Name + " - Watts (W)";           Units = "W";
                case(this.UnitsType("Siemens"));    Headers = this.Name + " - Siemens (S)";         Units = "S";
                otherwise
                    error("Keithley6220:InvalidUnitsType", "%s", "Units must be Volts, Ohms, Watts or Siemens, received " + string(this.Units));
            end
        end

        function [dataRow] = Measure(this)
            %Read the latest Delta mode reading (NaN if it is not new), or the source current without DeltaMode.
            %
            %Outputs:
            %   dataRow - the reading (a scalar, matching GetHeaders)

            if(this.SimulationMode)
                %Dummy values if simulating instrument
                dataRow = this.GenerateSimulatedData(1, Baseline=17, Variance=0.1);
            elseif this.DeltaMode
                dataRow = this.QueryDeltaModeMeasurementValue();
            else
                dataRow = this.QueryDouble("SOUR:CURR?");
            end
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function OnConnected(this)
            %In Delta mode, read the reading units and add reading numbers to readings.
            %(6220 Reference Manual: UNIT[:VOLT][:DC]?, and FORMat:ELEMents,
            %whose RNUMber element numbers each reading)

            this.LastReadingNumber = NaN;
            if this.SimulationMode || ~this.DeltaMode
                return;
            end

            this.WriteCommand("FORM:ELEM READ,RNUM");
            this.ReadUnits();
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function ReadUnits(this)
            %Set Units from the reading units selected on the instrument - V, OHMS, W or SIEM.

            reply = upper(strtrim(string(this.QueryString("UNIT?"))));
            switch reply
                case "V";                       units = "Volts";
                case "OHMS";                    units = "Ohms";
                case "W";                       units = "Watts";
                case {"SIEM", "S", "SIEMENS"};  units = "Siemens";
                otherwise
                    error("Keithley6220:UnexpectedUnits", "%s", this.Name + " gave unexpected reading units: """ + reply + """ (expected V, OHMS, W or SIEM).");
            end

            if this.Units ~= this.UnitsType(units)
                Palladium.Logging.Logger.Log("Info", this.Name + ": the instrument's reading units are " + units + ", so Units is set to " + units + " (was " + string(this.Units) + ").");
            end
            this.Units = this.UnitsType(units);
        end

        function value = QueryDeltaModeMeasurementValue(this)
            %Read the latest Delta reading - NaN if it is the same reading as last time.
            %SENS:DATA? returns the latest reading again if there is no new
            %one yet (6220 Reference Manual, Read commands); its reading
            %number, the last element (e.g. +00001RDNG#), tells the two apart.
            %An overflow (+9.9E37) is NaN too
            %
            %Outputs:
            %   value - the reading

            fields = strsplit(string(this.QueryString("SENS:DATA?")), ",");
            value = str2double(regexp(fields(1), "[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", "match", "once"));
            readingNumber = str2double(regexp(fields(end), "\d+", "match", "once"));

            if numel(fields) > 1 && ~isnan(readingNumber)
                if readingNumber == this.LastReadingNumber
                    value = NaN;
                end
                this.LastReadingNumber = readingNumber;
            end
            if value >= 9.9e37
                value = NaN;
            end
        end
    end
end
