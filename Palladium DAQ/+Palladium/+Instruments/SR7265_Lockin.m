classdef SR7265_Lockin < Palladium.Core.Instrument
    %SR7265_Lockin - Instrument driver for the Signal Recovery 7265 (and 7260) DSP lock-in amplifier.
    %Reads the X and Y outputs each measurement tick, in floating-point
    %mode (`XY.`). They are in volts in voltage input mode - in a current
    %input mode they are in amps, though the column headers still say V.
    %
    %With `AutoSensitivity` on, the driver checks the signal magnitude after
    %each reading and steps the sensitivity up a range when it is above
    %200% of full scale, or down a range when it is below 40%. Set the
    %reference, time constant and input configuration on the front panel.
    %
    %The 7265 has GPIB and RS-232 interfaces. Over RS-232, the factory
    %settings are 9600 baud, 7 data bits and even parity, as set in
    %`ConnectionSettings.SerialSettings`; turn character echo and the prompt
    %off in the instrument's RS232 Settings menu, as they would be read as
    %part of the replies.

    %% Properties (Public)
    properties(Access = public)
        FullName = "SR7265 Lockin";                                 %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "SR7265";                                            %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.Debug;     %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        AutoSensitivity (1,1) logical = true;                       %Step the sensitivity range up or down automatically after each reading, to keep the signal on range
    end

    %% Constructor
    methods
        function this = SR7265_Lockin()
            %Set the supported connection types and default connection settings.

            %The 7265 has GPIB and RS-232 ports; VISA can address either.
            %Its GPIB terminator is set on the instrument - the default
            %CR/LF matches its factory setting
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial", "VISA"]);
            this.GPIB_Address = 12;     %Factory default

            %RS-232 always has 1 stop bit. 9600 baud, 7 data bits and even
            %parity are the factory settings - they must match the RS232
            %Settings menu on the instrument. Replies end with CR LF
            this.ConnectionSettings.SerialSettings = struct('BaudRate', 9600, 'DataBits', 7, 'Parity', 'even', 'StopBits', 1, 'Terminator', 'CR/LF');
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for X and Y, as returned by Measure
            %
            %Outputs:
            %   Headers - ["SR7265 - Vx (V)", "SR7265 - Vy (V)"]
            %   Units   - ["V", "V"]

            Headers = [this.Name + " - Vx (V)", this.Name + " - Vy (V)"];
            Units = ["V", "V"];
        end

        function [dataRow] = Measure(this)
            %Read X and Y, then step the sensitivity if AutoSensitivity is on.
            %
            %Outputs:
            %   dataRow - X and Y, in V (or A in current input mode)

            if(this.SimulationMode)
                data = "0.0705876,0.00256349";
            else
                %The '.' after XY selects floating-point mode, so the reply
                %is in volts (or amps) rather than a percentage of full
                %scale. The two values are separated by the delimiter
                %character, a comma by default (manual section 6.3.11)
                data = this.QueryString("XY.");
            end

            splitData = strsplit(data, ',');
            x = str2double(splitData{1});
            y = str2double(splitData{2});

            dataRow = [x, y];

            if(this.AutoSensitivity)
                this.AutoTuneSensitivity();
            end
        end
    end

    %% Methods (Private)
    methods (Access = private)

        function AutoTuneSensitivity(this)
            %Step the sensitivity range up or down by one if the signal is near its limits.
            %Uses the magnitude as a percentage of full scale, so works the same on
            %every range

            mag = this.QueryMagnitudeLevel();

            %Sensitivity range index, 1 to 27 - see manual page 6-10
            sen = this.QuerySensitivityLevel();

            %Magnitude (full scale = 10000) at which to move up a range -
            %200% of full scale
            upperCutoff = 20000;

            %Magnitude at which to move down a range - 40% of full scale.
            %Ranges go in 1-2-5 steps, so this is at most 100% of the range
            %below
            lowerCutoff = 4000;

            if(mag >= upperCutoff)
                sensIndex = min(sen + 1, 27);       %27 is the top range, 1 V
                this.SetSensitivityLevel(sensIndex);
            elseif(mag < lowerCutoff)
                sensIndex = max(sen - 1, 1);        %1 is the bottom range, 2 nV
                this.SetSensitivityLevel(sensIndex);
            end
        end

        function magnitude = QueryMagnitudeLevel(this)
            %Read the signal magnitude as a fraction of full scale, where 10000 is full scale.
            %MAG without the '.' replies in fixed-point mode, 0 to 30000,
            %whatever the sensitivity range
            %
            %Outputs:
            %   magnitude - signal magnitude, 0 to 30000

            if(this.SimulationMode)
                magnitude = 15000;
            else
                magnitude = this.QueryDouble("MAG");
            end
        end

        function sensitivityIndex = QuerySensitivityLevel(this)
            %Read the sensitivity range, as an index from 1 (2 nV) to 27 (1 V).
            %
            %Outputs:
            %   sensitivityIndex - sensitivity index (manual page 6-10)

            if(this.SimulationMode)
                sensitivityIndex = 3;
            else
                sensitivityIndex = this.QueryDouble("SEN");
            end
        end

        function SetSensitivityLevel(this, levelIndexInt)
            %Set the sensitivity range, as an index from 1 (2 nV) to 27 (1 V).
            %
            %Inputs:
            %   levelIndexInt - sensitivity index (manual page 6-10)

            if(this.SimulationMode); return; end

            this.WriteCommand("SEN " + string(levelIndexInt));
        end
    end
end
