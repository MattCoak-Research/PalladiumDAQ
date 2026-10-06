classdef Keithley6220 < Palladium.Core.Instrument
    %Keithley6220 - Instrument driver for the Keithley Model 6220 precision DC current source, in Delta mode.
    %Made for Delta mode with a paired Keithley 2182A nanovoltmeter. In
    %this mode the 6220 sources a current, triggers the 2182A over the
    %RS-232 cable between them, reverses the current and triggers again,
    %and takes the voltage readings back from the 2182A. The computer
    %talks only to the 6220, which speaks for the pair - which is why a
    %current source returns voltage (or resistance) readings.
    %
    %Set up and start Delta mode on the instrument before measuring: each
    %measurement tick just reads the latest Delta reading (`SENS:DATA?`),
    %which is the previous reading again if no new one has been made since.
    %Set `Units` to match the reading units selected on the instrument
    %(UNITS key) - it sets the data column header, and is not sent to or
    %read from the instrument.
    %
    %The 6220 has GPIB and RS-232 interfaces. Reading without Delta mode
    %(`DeltaMode` false) is not implemented.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Keithley 6220 Current Source";              %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "K6220";                                         %Instrument name, used as the prefix of its data column header
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        DeltaMode (1,1) logical = true;                         %If true, readings come from a paired 2182A nanovoltmeter in Delta mode (the intended use). False is not implemented.
        Units;                                                  %Units of the readings - Volts, Ohms, Watts or Siemens. Must match the reading units set on the instrument.
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
            %Data column header and units for the reading returned by Measure, set by `Units`.
            %
            %Outputs:
            %   Headers - one header, e.g. "K6220 - Resistance (Ohms)"
            %   Units   - its units, e.g. "Ohms"

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
            %Read the latest Delta mode reading, in Units.
            %
            %Outputs:
            %   dataRow - the reading (a scalar, matching GetHeaders)

            if(this.SimulationMode)
                %Dummy values if simulating instrument
                data = this.GenerateSimulatedData(1, Baseline=17, Variance=0.1);
            else
                %Query for latest measurement
                if this.DeltaMode
                    data = this.QueryDeltaModeMeasurementValue();
                else
                    data = this.QueryMeasurementValue();
                end
            end

            %Assign data to output data row
            dataRow = data;
        end

        function SendCommand(this, comd)
            %Send a query to the instrument and display its reply in the Command Window.
            %
            %Inputs:
            %   comd - the query to send, e.g. "UNIT?"

            this.QueryString(comd)
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function value = QueryDeltaModeMeasurementValue(this)
            %Read the latest Delta mode reading.
            %
            %Outputs:
            %   value - the reading, the first field of the reply

            %Returns the latest reading again if there is no new one yet.
            %The reply may also contain other elements, e.g. the timestamp,
            %depending on FORMat:ELEMents
            result = this.QueryString("SENS:DATA?");
            ss = strsplit(result, ',');
            value = str2double(ss{1});
        end

        function value = QueryMeasurementValue(this) %#ok<MANU>
            %Read a measurement without Delta mode - not implemented, so this always errors.

            value = 43; %#ok<NASGU>
            error("Keithley6220:NotImplemented", "Not implemented");
        end
    end
end
