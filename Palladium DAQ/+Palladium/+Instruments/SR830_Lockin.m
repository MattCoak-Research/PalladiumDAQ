classdef SR830_Lockin < Palladium.Core.Instrument
    %SR830_Lockin - Instrument driver for the Stanford Research Systems SR830 DSP lock-in amplifier.
    %Reads the X and Y outputs each measurement tick (as one coherent
    %`SNAP?` snapshot), plus the amplitude of the sine output. If the sine
    %output drives a sample through a voltage-to-current converter (set in
    %`ConnectedCurrentSource`), the output column is the current instead, and
    %a resistance column X / (current x `AmplifierGain`) is added.
    %
    %With `AutoSensitivity` on, the driver steps the sensitivity up or down
    %one range after each reading when the larger of X and Y is near the top
    %of the range or would fit in the range below. Its ranges are in volts,
    %so it is meant for the voltage inputs (A or A-B). Set the reference,
    %time constant and input configuration on the front panel.
    %
    %The SR830 has GPIB and RS-232 interfaces; the driver tells it which
    %one to reply on when connecting. Over RS-232, set its baud rate and
    %parity (Setup menu) to match `ConnectionSettings.SerialSettings` - 9600
    %baud and no parity are its defaults.

    %% Properties (Public)
    properties(Access = public)
        FullName = "SR830 lockin";                                  %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "SR830";                                             %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;      %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        AutoSensitivity (1,1) logical = true;                       %Step the sensitivity range up or down automatically after each reading, to keep X and Y on range
        ConnectedCurrentSource categorical;                         %Voltage-to-current converter driven by the sine output, if any: None, or 200 uA/V. Sets the output column's units and adds a resistance column.
        AmplifierGain (1,1) double = 1;                             %Gain of any external preamplifier or transformer before the input, used in the resistance calculation
    end

    %% Categoricals
    methods
        function catOut = CurrentSource(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["None", "200 uA/V"]); end
    end

    %% Constructor
    methods
        function this = SR830_Lockin()
            %Set the supported connection types and default connection settings.

            %The SR830 has GPIB and RS-232 ports
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial"]);
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];
            this.GPIB_Address = 8;      %Factory default

            %Over RS-232 the SR830 ends its replies with CR, and accepts CR
            %as a command terminator. Its word length is fixed at 8 bits
            this.ConnectionSettings.SerialSettings.Terminator = 'CR';

            this.ConnectedCurrentSource = this.CurrentSource("200 uA/V");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function metadataStruct = CollectMetaData(this)
            %Reference frequency, recorded in the data-file header.
            %
            %Outputs:
            %   metadataStruct - struct with field Frequency_Hz

            metadataStruct.Frequency_Hz = this.GetFrequency();
        end

        function Connect(this)
            %Open the connection, and tell the SR830 which interface to reply on.
            %Replies go to only one interface, set by OUTX, which must be sent
            %before any query (manual section 5, Setup commands)

            Connect@Palladium.Core.Instrument(this);
            if this.SimulationMode
                return;
            end

            if this.Connection_Type == Palladium.Enums.ConnectionType.Serial
                this.WriteCommand("OUTX 0");
            else
                this.WriteCommand("OUTX 1");
            end
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %X, Y and the output level, plus a resistance column when a current
            %source is connected
            %
            %Outputs:
            %   Headers - e.g. ["SR830 - Vx (V)", "SR830 - Vy (V)", "SR830 - Output Current (A)",
            %             "SR830 - Resistance (Ohms)"]
            %   Units   - matching units, e.g. ["V", "V", "A", "Ohm"]

            Headers = [this.Name + " - Vx (V)", this.Name + " - Vy (V)"];
            Units = ["V", "V"];

            %Units of the output column: the sine output voltage, or the
            %current a connected current source turns it into
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

            Headers = [Headers, this.Name + " - Output " + supplyOutName];
            Units = [Units, supplyOutUnits];

            %With a current source, add a calculated resistance too - just
            %for convenience
            if calculateResistance
                Headers = [Headers, this.Name + " - Resistance (Ohms)"];
                Units = [Units "Ohm"];
            end
        end

        function freq_Hz = GetFrequency(this)
            %Read the reference frequency, in Hz.
            %
            %Outputs:
            %   freq_Hz - reference frequency, in Hz

            if(this.SimulationMode)
                freq_Hz = 78.67;
                return;
            end

            freq_Hz = this.QueryDouble("FREQ?");
        end

        function level = GetOutputLevel(this)
            %Read the amplitude of the sine output, in V rms.
            %
            %Outputs:
            %   level - sine output amplitude, 0.004 to 5 V rms

            if(this.SimulationMode)
                level = 2;
                return;
            end

            level = this.QueryDouble("SLVL?");
        end

        function [magnitude, unit, name] = GetSuppliedVoltageOrCurrentAndUnits(this)
            %Read the voltage or current being supplied to the sample.
            %The sine output voltage, or the current it is converted to by the
            %ConnectedCurrentSource
            %
            %Outputs:
            %   magnitude - the output level, in V rms or A rms
            %   unit      - "V" or "A"
            %   name      - "Voltage" or "Current"

            vOut = this.GetOutputLevel();

            switch(this.ConnectedCurrentSource)
                case(this.CurrentSource("None"));       magnitude = vOut;           unit = "V";     name = "Voltage";
                case(this.CurrentSource("200 uA/V"));   magnitude = 200e-6 * vOut;  unit = "A";     name = "Current";
                otherwise
                    error("SR830_Lockin:UnsupportedCurrentSource", "%s", "Connected current source option " + string(this.ConnectedCurrentSource) + " not implemented in SR830 code file");
            end
        end

        function [dataRow] = Measure(this)
            %Read X and Y, the output level and, with a current source, the resistance.
            %In the same order as GetHeaders. With AutoSensitivity on, the
            %sensitivity is then stepped up or down a range if needed
            %
            %Outputs:
            %   dataRow - X and Y in V, the output level in V or A, then the
            %             resistance in Ohms if a current source is connected

            if(this.SimulationMode)
                data = "0.0705876,0.00256349";
            else
                %SNAP? reads X (1) and Y (2) at the same instant, as a comma
                %separated string, e.g. "0.0705876,0.00256349" for 70 mV and
                %2.5 mV (manual page 5-15)
                data = this.QueryString("SNAP? 1,2");
            end

            splitData = strsplit(data, ',');
            x = str2double(splitData{1});
            y = str2double(splitData{2});

            %Get the output level - voltage, or current if a current source
            %is connected
            output = this.GetSuppliedVoltageOrCurrentAndUnits();

            dataRow = [x, y, output];

            %Calculate resistance if a current source is attached
            switch(this.ConnectedCurrentSource)
                case(this.CurrentSource("None"))
                    %No resistance column
                otherwise
                    resistance_Ohms = x / (output * this.AmplifierGain);
                    dataRow = [dataRow resistance_Ohms];
            end

            if(this.AutoSensitivity && ~this.SimulationMode)
                this.AutoTuneSensitivity(x, y);
            end
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function AutoTuneSensitivity(this, vx, vy)
            %Step the sensitivity range up or down by one if the signal is near its limits.
            %Up when the larger of |X| and |Y| reaches 95% of the range; down when
            %it is below 85% of the range below, so there is some hysteresis
            %
            %Inputs:
            %   vx - X reading, in V
            %   vy - Y reading, in V

            v = max(abs(vx), abs(vy));

            sensIndex = this.QuerySensitivityLevel();
            range = this.SensLevelToRange(sensIndex);
            rangeBelow = this.SensLevelToRange(max(sensIndex-1, 0));

            %Fraction of the range at which to switch up to the next one
            cutoffUpperFactor = 0.95;

            %Fraction of the range below that the signal must drop under to
            %switch down - a bit of hysteresis to avoid flipping back and
            %forth on range boundaries
            cutoffLowerFactor = 0.85;

            if(v >= cutoffUpperFactor * range && sensIndex < 26)        %26 is the top range, 1 V
                this.SetSensitivityLevel(sensIndex + 1);
            elseif(v < rangeBelow * cutoffLowerFactor && sensIndex > 0) %0 is the bottom range, 2 nV
                this.SetSensitivityLevel(sensIndex - 1);
            end
        end

        function sensitivityIndex = QuerySensitivityLevel(this)
            %Read the sensitivity range, as an index from 0 (2 nV) to 26 (1 V).
            %
            %Outputs:
            %   sensitivityIndex - sensitivity index (see SensLevelToRange)

            if(this.SimulationMode)
                sensitivityIndex = 26;
                return;
            end

            sensitivityIndex = this.QueryDouble("SENS?");
        end

        function SetSensitivityLevel(this, levelIndex)
            %Set the sensitivity range, as an index from 0 (2 nV) to 26 (1 V).
            %
            %Inputs:
            %   levelIndex - sensitivity index (see SensLevelToRange)

            arguments
                this;
                levelIndex (1,1) {mustBeInteger, mustBeBetween(levelIndex, 0, 26)};
            end

            if(this.SimulationMode); return; end

            this.WriteCommand("SENS " + string(levelIndex));
        end
    end

    %% Methods (Static, Public)
    methods(Static, Access = public)

        function range = SensLevelToRange(level)
            %Convert a sensitivity index to its full-scale voltage, in V.
            %The SENS index table is on manual page 5-6
            %
            %Inputs:
            %   level - sensitivity index, 0 (2 nV) to 26 (1 V)
            %
            %Outputs:
            %   range - full-scale sensitivity, in V

            arguments
                level (1,1) {mustBeInteger};
            end

            switch(level)
                case 0;     range = 2e-9;
                case 1;     range = 5e-9;
                case 2;     range = 10e-9;
                case 3;     range = 20e-9;
                case 4;     range = 50e-9;
                case 5;     range = 100e-9;
                case 6;     range = 200e-9;
                case 7;     range = 500e-9;
                case 8;     range = 1e-6;
                case 9;     range = 2e-6;
                case 10;    range = 5e-6;
                case 11;    range = 10e-6;
                case 12;    range = 20e-6;
                case 13;    range = 50e-6;
                case 14;    range = 100e-6;
                case 15;    range = 200e-6;
                case 16;    range = 500e-6;
                case 17;    range = 1e-3;
                case 18;    range = 2e-3;
                case 19;    range = 5e-3;
                case 20;    range = 10e-3;
                case 21;    range = 20e-3;
                case 22;    range = 50e-3;
                case 23;    range = 100e-3;
                case 24;    range = 200e-3;
                case 25;    range = 500e-3;
                case 26;    range = 1;
                otherwise
                    error("SR830_Lockin:UnsupportedRangeIndex", "%s", "SR830 range index Not supported. Value: " + string(level));
            end
        end
    end
end
