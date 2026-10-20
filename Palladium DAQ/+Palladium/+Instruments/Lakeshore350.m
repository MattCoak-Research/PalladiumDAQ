classdef Lakeshore350 < Palladium.Core.Instrument
    %Lakeshore350 - Instrument driver for the Lake Shore Model 350 temperature controller.
    %Reads its four sensor inputs, A to D, each measurement tick - each in
    %kelvin, in sensor units, both or neither, as set by `Ch_A_Reading` to
    %`Ch_D_Reading` - plus the power going into the heater. The sensor units
    %follow each input's sensor type, read when connecting (Ω for platinum
    %and NTC RTDs; V, mV or nF for the diode, thermocouple and capacitance
    %options). One of its two heater outputs, chosen by
    %`HeaterChannel` (output 1, up to 75 W, or output 2, up to 1 W), can be
    %controlled from the Heater Control tab: setpoint, ramp, PID values,
    %control mode, heater range and manual output, regulating on the sensor
    %input chosen by `ControlChannel`.
    %
    %The Model 350 has GPIB, Ethernet (TCP port 7777) and USB interfaces.
    %The USB interface is a virtual serial port, so use the Serial connection
    %type with its COM port; Serial settings are set to match it.
    %
    %Applying the Heater Control tab's settings keeps the output's power-up
    %enable as it is set on the instrument. Analog outputs 3 and 4 (and
    %their Monitor Out and Warmup Supply modes) are not used by this driver.
    %(Commands from the Model 350 User's Manual, chapter 6.)

    %% Properties (Public)
    properties(Access = public)
        FullName = "Lakeshore 350";                             %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "Ls350";                                         %Instrument name, used as the prefix of its heater power column header
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Ch_A_Reading;                                           %What to log for input A: Both (temperature and sensor units), Temperature, Sensor Units, or Disabled
        Ch_B_Reading;                                           %What to log for input B: Both, Temperature, Sensor Units, or Disabled
        Ch_C_Reading;                                           %What to log for input C: Both, Temperature, Sensor Units, or Disabled
        Ch_D_Reading;                                           %What to log for input D: Both, Temperature, Sensor Units, or Disabled
        Ch_A_Name = "Channel A Temperature (K)"                 %Data column header for the input A temperature, e.g. "Sample Temp (K)"
        Ch_B_Name = "Channel B Temperature (K)"                 %Data column header for the input B temperature
        Ch_C_Name = "Channel C Temperature (K)"                 %Data column header for the input C temperature
        Ch_D_Name = "Channel D Temperature (K)"                 %Data column header for the input D temperature
        HeaterResistance = 100;                                 %Resistance of the heater connected to HeaterChannel, in Ohms - used to calculate heater power
        HeaterChannel;                                          %Heater output used by the Heater Control tab and the heater power column: Ch1 (output 1) or Ch2 (output 2)
        ControlChannel;                                         %Sensor input (A to D) the heater regulates on - sent to the instrument when heater settings are applied. None sets no control input.
    end

    %% Properties (Private)
    properties(Access = private)
        SensorUnits = ["Ω", "Ω", "Ω", "Ω"];                     %Units of each input's sensor-units reading, from its sensor type (INTYPE?) - read when connecting
        HeaterSetups = struct("MaxCurrent", {1, 0.1}, "OutputIsPower", {true, true});  %Each heater output's set-up (HTRSET?): range 5's full-scale current (A), and whether its output is in % of power or of current - read when connecting and after applying settings
    end

    %% Categoricals
    methods
        function catOut = Channel(this, inputStr);          catOut = this.ConvertToCategorical(inputStr, ["A", "B", "C", "D", "None"]); end
        function catOut = ControlMode(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Off", "Closed Loop PID", "Zone", "Open Loop"]); end
        function catOut = HeaterRange(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Off", "Range 1", "Range 2", "Range 3", "Range 4", "Range 5"]); end
        function catOut = MeasType(this, inputStr);         catOut = this.ConvertToCategorical(inputStr, ["Both", "Temperature", "Sensor Units", "Disabled"]); end
        function catOut = OutputChannel(this, inputStr);    catOut = this.ConvertToCategorical(inputStr, ["Ch1", "Ch2"]); end
    end

    %% Constructor
    methods
        function this = Lakeshore350()
            %Set the connection options, default readings and Heater Control tab.

            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = 12;

            %The Model 350 takes TCP socket connections on port 7777
            this.ConnectionSettings.Port = 7777;

            %The USB interface is a virtual serial port, fixed at 57600
            %baud, 7 data bits, odd parity and 1 stop bit. Replies end in CR LF
            this.ConnectionSettings.SerialSettings = struct('BaudRate', 57600, 'DataBits', 7, 'Parity', 'odd', 'StopBits', 1, 'Terminator', 'CR/LF');

            %Define the Instrument Controls that can be added
            this.DefineInstrumentControl(Name = "🕹️ Heater Control", ClassName = "LakeshoreHeaterControl", TabName = "Heater Control", EnabledByDefault = true);

            %Make sure to set values for Properties of Categorical type
            %like these
            this.Ch_A_Reading = this.MeasType("Both");
            this.Ch_B_Reading = this.MeasType("Both");
            this.Ch_C_Reading = this.MeasType("Both");
            this.Ch_D_Reading = this.MeasType("Both");
            this.ControlChannel = this.Channel("A");
            this.HeaterChannel = this.OutputChannel("Ch1");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [settings, heaterLevelPct, heaterEnabled, heaterPower] = CollectHeaterControlSettings(this)
            %Read the heater output's settings and level, for the Heater Control tab.
            %The output is set by HeaterChannel
            %
            %Outputs:
            %   settings       - struct of the heater settings, with fields ControlMode,
            %                    HeaterRange, SetPoint, RampEnabled, RampRate, ManualOutput
            %                    and PID_Settings (with fields P, I and D). The same
            %                    struct, edited, is passed back to ApplySettings
            %   heaterLevelPct - heater output, in percent (see GetHeaterLevel)
            %   heaterEnabled  - false if the heater range is Off
            %   heaterPower    - heater power, in W (see GetHeaterPower)

            settings.ControlMode = this.GetControlMode(this.HeaterChannel);
            settings.HeaterRange = this.GetHeaterRangeFromIndex(this.GetHeaterRange(this.HeaterChannel));
            settings.SetPoint = this.GetHeaterSetpoint(this.HeaterChannel);
            [settings.RampEnabled, settings.RampRate] = this.GetRamp(this.HeaterChannel);
            settings.ManualOutput = this.GetManualOutputPercent(this.HeaterChannel);
            [P, I, D] = this.GetPIDValues(this.HeaterChannel);
            settings.PID_Settings.P = P;
            settings.PID_Settings.I = I;
            settings.PID_Settings.D = D;

            %The heater set-up may have been changed on the front panel
            this.ReadHeaterSetup(this.HeaterChannel);
            [heaterPower, heaterLevelPct, rangeIdx] = this.ReadHeaterOutput(this.HeaterChannel);
            heaterEnabled = rangeIdx ~= 0;
        end

        function controlMode = GetControlMode(this, outputChannel)
            %Read a heater output's control mode
            %
            %Inputs:
            %   outputChannel - OutputChannel categorical, Ch1 or Ch2
            %
            %Outputs:
            %   controlMode - ControlMode categorical, e.g. Closed Loop PID

            channelStr = this.GetHeaterChannelIndex(outputChannel);

            if(this.SimulationMode)
                modeIndex = 1;
            else
                %Reply is "<mode>,<input>,<powerup enable>"
                results = strsplit(this.QueryString("OUTMODE? " + channelStr), ',');
                modeIndex = str2double(results{1});
            end

            switch(modeIndex)
                case(0);    controlMode = this.ControlMode("Off");
                case(1);    controlMode = this.ControlMode("Closed Loop PID");
                case(2);    controlMode = this.ControlMode("Zone");
                case(3);    controlMode = this.ControlMode("Open Loop");
                otherwise
                    error("Lakeshore350:InvalidControlMode", "%s", "Unknown control mode index returned by " + this.Name + ": " + string(modeIndex));
            end
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %For each input, A to D, as its Ch_X_Reading says: its temperature
            %(headed Ch_X_Name), its sensor units, both, or neither - then the
            %heater power
            %
            %Outputs:
            %   Headers - e.g. ["Channel A Temperature (K)", "Ls350 - Ch A Sensor (Ω)",
            %             ..., "Ls350 Heater Power (W)"]
            %   Units   - matching units, e.g. ["K", "Ω", ..., "W"]

            Headers = strings(1, 0);
            Units = strings(1, 0);
            letters = ["A", "B", "C", "D"];
            for i = 1:4
                [withTemperature, withSensor] = this.InputColumns(letters(i));
                if withTemperature
                    Headers(end+1) = string(this.("Ch_" + letters(i) + "_Name")); %#ok<AGROW>
                    Units(end+1) = "K"; %#ok<AGROW>
                end
                if withSensor
                    Headers(end+1) = this.Name + " - Ch " + letters(i) + " Sensor (" + this.SensorUnits(i) + ")"; %#ok<AGROW>
                    Units(end+1) = this.SensorUnits(i); %#ok<AGROW>
                end
            end

            %The heater power is always recorded
            Headers = [Headers, this.Name + " Heater Power (W)"];
            Units = [Units, "W"];
        end

        function [htrLevel, htrEnabled] = GetHeaterLevel(this, heaterChannel)
            %Read a heater output's percentage, and whether the heater is on.
            %The output is a percentage of full scale for the heater range
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %
            %Outputs:
            %   htrLevel   - heater output, in percent of full-scale power or
            %                current, as set on the instrument
            %   htrEnabled - false if the heater range is Off

            [~, htrLevel, rangeIdx] = this.ReadHeaterOutput(heaterChannel);
            htrEnabled = rangeIdx ~= 0;
        end

        function power = GetHeaterPower(this, heaterChannel)
            %Calculate the power going into a heater, in W.
            %From the heater output, heater range, the output's maximum current
            %and HeaterResistance - see ReadHeaterOutput
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %
            %Outputs:
            %   power - heater power, in W

            power = this.ReadHeaterOutput(heaterChannel);
        end

        function htrRange = GetHeaterRange(this, outputChannel)
            %Read a heater output's range number
            %
            %Inputs:
            %   outputChannel - OutputChannel categorical, Ch1 or Ch2
            %
            %Outputs:
            %   htrRange - 0 = Off, 1 to 5 = Range 1 to Range 5

            channelStr = this.GetHeaterChannelIndex(outputChannel);

            if(this.SimulationMode)
                htrRange = 2;
            else
                htrRange = this.QueryDouble("RANGE? " + channelStr);
            end
        end

        function setPt = GetHeaterSetpoint(this, heaterChannel)
            %Read a heater output's control setpoint
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %
            %Outputs:
            %   setPt - setpoint, in the preferred units of the control input
            %           (usually K)

            channelStr = this.GetHeaterChannelIndex(heaterChannel);

            if(this.SimulationMode)
                setPt = 25.4;
                return;
            end

            setPt = this.QueryDouble("SETP? " + channelStr);
        end

        function output = GetManualOutputPercent(this, heaterChannel)
            %Read a heater output's manual output setting, in percent.
            %Used in Open Loop mode, and added to the PID output in the other modes
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %
            %Outputs:
            %   output - manual output, in percent

            channelStr = Palladium.Core.Instrument.NumberToCommandString(this.GetHeaterChannelIndex(heaterChannel));

            if(this.SimulationMode)
                output = 78;
                return;
            end

            output = this.QueryDouble("MOUT? " + channelStr);
        end

        function [P, I, D] = GetPIDValues(this, heaterChannel)
            %Read a heater output's PID control values
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %
            %Outputs:
            %   P - proportional gain (0.1 to 1000)
            %   I - integral, or reset (0.1 to 1000)
            %   D - derivative, or rate (0 to 200)

            channelStr = this.GetHeaterChannelIndex(heaterChannel);

            if(this.SimulationMode)
                P = 50;
                I = 10;
                D = 5;
            else
                readings = strsplit(this.QueryString("PID? " + channelStr), ',');
                P = str2double(readings{1});
                I = str2double(readings{2});
                D = str2double(readings{3});
            end
        end

        function [enabled, rate] = GetRamp(this, heaterChannel)
            %Read whether a heater output's setpoint ramps to a new value, and how fast
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %
            %Outputs:
            %   enabled - true if setpoint ramping is on
            %   rate    - ramp rate, in K/min

            channelStr = this.GetHeaterChannelIndex(heaterChannel);

            if(this.SimulationMode)
                enabled = true;
                rate = 1.2;
            else
                result = strsplit(this.QueryString("RAMP? " + channelStr), ',');
                enabled = strcmp(strtrim(result{1}), '1');
                rate = str2double(result{2});
            end
        end

        function [R_ChA, R_ChB, R_ChC, R_ChD] = GetSensorReadingAllChannels(this)
            %Read all four sensor inputs in sensor units, with one query where possible
            %
            %Outputs:
            %   R_ChA, R_ChB, R_ChC, R_ChD - the readings of inputs A to D, in
            %   sensor units

            values = this.ReadAllInputs("SRDG?", @this.GetSensorReading);
            R_ChA = values(1);
            R_ChB = values(2);
            R_ChC = values(3);
            R_ChD = values(4);
        end

        function reading = GetSensorReading(this, controlChannel)
            %Read a sensor input in sensor units (Ω for resistive sensors - see the class help)
            %
            %Inputs:
            %   controlChannel - Channel categorical or input letter: A, B, C or D
            %
            %Outputs:
            %   reading - the reading, in sensor units

            letter = this.InputLetter(controlChannel);
            if this.SimulationMode
                reading = this.GenerateSimulatedData(1, Baseline=164, Variance=0.01);
                return;
            end

            reading = this.QueryDouble("SRDG? " + letter);
        end

        function temp = GetTemperature(this, controlChannel)
            %Read a sensor input in kelvin
            %
            %Inputs:
            %   controlChannel - Channel categorical or input letter: A, B, C or D
            %
            %Outputs:
            %   temp - the reading, in K

            letter = this.InputLetter(controlChannel);
            if this.SimulationMode
                temp = this.GenerateSimulatedData(1, Baseline=273, Variance=0.03);
                return;
            end

            temp = this.QueryDouble("KRDG? " + letter);
        end

        function [T_ChA, T_ChB, T_ChC, T_ChD] = GetTemperatureAllChannels(this)
            %Read all four sensor inputs in kelvin, with one query where possible
            %
            %Outputs:
            %   T_ChA, T_ChB, T_ChC, T_ChD - the readings of inputs A to D, in K

            values = this.ReadAllInputs("KRDG?", @this.GetTemperature);
            T_ChA = values(1);
            T_ChB = values(2);
            T_ChC = values(3);
            T_ChD = values(4);
        end

        function [dataRow] = Measure(this)
            %Read each input as its Ch_X_Reading says, then the heater power.
            %In the same order as GetHeaders. All four inputs are read with one
            %query each for kelvin and sensor units, only if any are logged
            %
            %Outputs:
            %   dataRow - the readings, then the heater power in W

            letters = ["A", "B", "C", "D"];
            withTemperature = false(1, 4);
            withSensor = false(1, 4);
            for i = 1:4
                [withTemperature(i), withSensor(i)] = this.InputColumns(letters(i));
            end

            temperatures = nan(1, 4);
            sensors = nan(1, 4);
            if any(withTemperature)
                [temperatures(1), temperatures(2), temperatures(3), temperatures(4)] = this.GetTemperatureAllChannels();
            end
            if any(withSensor)
                [sensors(1), sensors(2), sensors(3), sensors(4)] = this.GetSensorReadingAllChannels();
            end

            dataRow = [];
            for i = 1:4
                if withTemperature(i);  dataRow(end+1) = temperatures(i);  end %#ok<AGROW>
                if withSensor(i);       dataRow(end+1) = sensors(i);       end %#ok<AGROW>
            end

            dataRow = [dataRow this.GetHeaterPower(this.HeaterChannel)];
        end

        function SetControlMode(this, outputChannel, controlChannel, controlMode)
            %Set a heater output's control mode, and the sensor input it regulates on.
            %The output's power-up enable (whether it comes back on after a
            %power cycle) is kept as it is set on the instrument. For example:
            %`ls.SetControlMode(ls.OutputChannel("Ch1"), ls.Channel("A"), ls.ControlMode("Open Loop"))`
            %
            %Inputs:
            %   outputChannel  - OutputChannel categorical, Ch1 or Ch2
            %   controlChannel - Channel categorical: A to D, or None
            %   controlMode    - ControlMode categorical, e.g. Closed Loop PID

            htrChannelStr = Palladium.Core.Instrument.NumberToCommandString(this.GetHeaterChannelIndex(outputChannel));
            channelStr = this.GetChannelString(controlChannel);
            modeIndex = this.GetControlModeIndex(controlMode);

            %Keep the power-up enable set on the instrument - OUTMODE needs
            %one, and this used to always send 1 (on)
            powerupEnable = "0";
            if ~this.SimulationMode
                current = split(this.QueryString("OUTMODE? " + htrChannelStr), ",");
                powerupEnable = strip(current(3));
            end

            this.WriteCommand("OUTMODE " + htrChannelStr + "," + Palladium.Core.Instrument.NumberToCommandString(modeIndex) + "," + channelStr + "," + powerupEnable);
        end

        function SetHeaterRange(this, heaterChannel, range)
            %Set a heater output's range, which sets its maximum power.
            %Each range is a decade lower in power than the next. The range has
            %no effect while the output is in the Off control mode
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %   range         - HeaterRange categorical: Off or Range 1 to Range 5.
            %                   Off turns the heater off

            channelStr = this.GetHeaterChannelIndex(heaterChannel);
            rangeIdx = this.GetHeaterRangeIndex(range);

            this.WriteCommand("RANGE " + channelStr + "," + Palladium.Core.Instrument.NumberToCommandString(rangeIdx));
        end

        function SetHeaterSetpoint(this, heaterChannel, setPt)
            %Set a heater output's control setpoint.
            %With ramping on, the setpoint ramps to the new value at the ramp rate
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %   setPt         - setpoint, in the preferred units of the control
            %                   input (usually K)

            channelStr = this.GetHeaterChannelIndex(heaterChannel);

            this.WriteCommand("SETP " + channelStr + "," + Palladium.Core.Instrument.NumberToCommandString(setPt, SignificantFigures=6));
        end

        function SetManualOutputPercent(this, heaterChannel, percentage)
            %Set a heater output's manual output, in percent.
            %Used in Open Loop mode, and added to the PID output in the other modes
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %   percentage    - manual output, 0 to 100 %

            channelStr = Palladium.Core.Instrument.NumberToCommandString(this.GetHeaterChannelIndex(heaterChannel));
            assert(percentage <= 100 && percentage >= 0, "Lakeshore350:InvalidOutputPercentage", "Invalid output percentage");

            this.WriteCommand("MOUT " + channelStr + "," + Palladium.Core.Instrument.NumberToCommandString(percentage, SignificantFigures=5));
        end

        function SetPIDValues(this, heaterChannel, P, I, D)
            %Set a heater output's PID control values
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %   P             - proportional gain (0.1 to 1000)
            %   I             - integral, or reset (0.1 to 1000)
            %   D             - derivative, or rate (0 to 200)

            channelStr = this.GetHeaterChannelIndex(heaterChannel);

            this.WriteCommand("PID " + channelStr + "," + Palladium.Core.Instrument.NumberToCommandString(P, SignificantFigures=5) + "," + Palladium.Core.Instrument.NumberToCommandString(I, SignificantFigures=5) + "," + Palladium.Core.Instrument.NumberToCommandString(D, SignificantFigures=4));
        end

        function SetRamp(this, outputChannel, enabled, rate)
            %Turn setpoint ramping on or off for a heater output, and set its rate
            %
            %Inputs:
            %   outputChannel - OutputChannel categorical, Ch1 or Ch2
            %   enabled       - true to ramp the setpoint to new values, false
            %                   to step it
            %   rate          - ramp rate, in K/min (0.001 to 100)

            channelStr = this.GetHeaterChannelIndex(outputChannel);

            this.WriteCommand("RAMP " + channelStr + "," + Palladium.Core.Instrument.NumberToCommandString(double(logical(enabled))) + "," + Palladium.Core.Instrument.NumberToCommandString(rate, SignificantFigures=4));
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function ApplySettings(this, settings)
            %Send the Heater Control tab's settings to the instrument.
            %They go to the output set by HeaterChannel, regulating on
            %ControlChannel. In one pass: the control mode, then the PID
            %values, ramp (before the setpoint, so a new setpoint ramps),
            %setpoint and (in Open Loop) manual output, and the heater range
            %last - so the heater is only switched on once everything it acts
            %on is set
            %
            %Inputs:
            %   settings - struct with the fields returned by
            %              CollectHeaterControlSettings

            this.SetControlMode(this.HeaterChannel, this.ControlChannel, settings.ControlMode);
            this.SetPIDValues(this.HeaterChannel, settings.PID_Settings.P, settings.PID_Settings.I, settings.PID_Settings.D);
            this.SetRamp(this.HeaterChannel, settings.RampEnabled, settings.RampRate);
            this.SetHeaterSetpoint(this.HeaterChannel, settings.SetPoint);
            if(settings.ControlMode == this.ControlMode("Open Loop"))
                this.SetManualOutputPercent(this.HeaterChannel, settings.ManualOutput);
            end
            this.SetHeaterRange(this.HeaterChannel, settings.HeaterRange);
        end

        function OnConnected(this)
            %Read each input's sensor type, for the units of its sensor reading, and both heater outputs' set-up.

            if this.SimulationMode
                return;
            end

            letters = ["A", "B", "C", "D"];
            for i = 1:4
                %<sensor type>,<autorange>,<range>,<compensation>,<units>,<excitation>
                sensorType = str2double(extractBefore(this.QueryString("INTYPE? " + letters(i)) + ",", ","));
                switch sensorType
                    case 0;         this.SensorUnits(i) = "";        %Disabled
                    case 1;         this.SensorUnits(i) = "V";       %Diode (3062 option)
                    case {2, 3};    this.SensorUnits(i) = "Ω";       %Platinum or NTC RTD
                    case 4;         this.SensorUnits(i) = "mV";      %Thermocouple (3060 option)
                    case 5;         this.SensorUnits(i) = "nF";      %Capacitance (3061 option)
                end
            end
            this.ReadHeaterSetup(this.OutputChannel("Ch1"));
            this.ReadHeaterSetup(this.OutputChannel("Ch2"));
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function channelIndex = GetChannelIndex(this, channel)
            %Input number for a channel, as used by OUTMODE
            %
            %Inputs:
            %   channel - Channel categorical
            %
            %Outputs:
            %   channelIndex - 0 = None, 1 = A, 2 = B, 3 = C, 4 = D

            switch(channel)
                case(this.Channel("None"));     channelIndex = 0;
                case(this.Channel("A"));        channelIndex = 1;
                case(this.Channel("B"));        channelIndex = 2;
                case(this.Channel("C"));        channelIndex = 3;
                case(this.Channel("D"));        channelIndex = 4;
                otherwise
                    error("Lakeshore350:UnsupportedChannel", "%s", "Unsupported channel, should be None, A, B, C or D, was " + string(channel));
            end
        end

        function channelStr = GetChannelString(this, controlChannel)
            %Input number for a channel, as a string ready to send to the instrument
            %
            %Inputs:
            %   controlChannel - Channel categorical
            %
            %Outputs:
            %   channelStr - "0" (None) to "4" (D)

            channelStr = string(this.GetChannelIndex(controlChannel));
        end

        function index = GetControlModeIndex(this, controlMode)
            %Control mode number used by the OUTMODE command
            %
            %Inputs:
            %   controlMode - ControlMode categorical
            %
            %Outputs:
            %   index - 0 = Off, 1 = Closed Loop PID, 2 = Zone, 3 = Open Loop

            switch(controlMode)
                case(this.ControlMode("Off"));              index = 0;
                case(this.ControlMode("Closed Loop PID"));  index = 1;
                case(this.ControlMode("Zone"));             index = 2;
                case(this.ControlMode("Open Loop"));        index = 3;
                otherwise
                    error("Lakeshore350:UnsupportedControlMode", "%s", "Unsupported control mode, should be Off, Closed Loop PID, Zone or Open Loop (Monitor Out and Warmup Supply are only for analog outputs 3 and 4), was " + string(controlMode));
            end
        end

        function channelIndex = GetHeaterChannelIndex(this, heaterChannel)
            %Heater output number for an output channel
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %
            %Outputs:
            %   channelIndex - 1 or 2

            switch(heaterChannel)
                case(this.OutputChannel("Ch1"));    channelIndex = 1;
                case(this.OutputChannel("Ch2"));    channelIndex = 2;
                otherwise
                    error("Lakeshore350:UnsupportedHeaterChannel", "%s", "Unsupported heater output, should be Ch1 or Ch2, was " + string(heaterChannel));
            end
        end

        function heaterRange = GetHeaterRangeFromIndex(this, index)
            %HeaterRange categorical for a heater range number from RANGE?
            %
            %Inputs:
            %   index - 0 = Off, 1 to 5 = Range 1 to Range 5
            %
            %Outputs:
            %   heaterRange - HeaterRange categorical

            switch(index)
                case(0);    heaterRange = this.HeaterRange("Off");
                case(1);    heaterRange = this.HeaterRange("Range 1");
                case(2);    heaterRange = this.HeaterRange("Range 2");
                case(3);    heaterRange = this.HeaterRange("Range 3");
                case(4);    heaterRange = this.HeaterRange("Range 4");
                case(5);    heaterRange = this.HeaterRange("Range 5");
                otherwise
                    error("Lakeshore350:InvalidHeaterRange", "%s", "Unknown heater range index returned by " + this.Name + ": " + string(index));
            end
        end

        function index = GetHeaterRangeIndex(this, heaterRange)
            %Heater range number used by the RANGE command
            %
            %Inputs:
            %   heaterRange - HeaterRange categorical
            %
            %Outputs:
            %   index - 0 = Off, 1 to 5 = Range 1 to Range 5

            switch(heaterRange)
                case(this.HeaterRange("Off"));          index = 0;
                case(this.HeaterRange("Range 1"));      index = 1;
                case(this.HeaterRange("Range 2"));      index = 2;
                case(this.HeaterRange("Range 3"));      index = 3;
                case(this.HeaterRange("Range 4"));      index = 4;
                case(this.HeaterRange("Range 5"));      index = 5;
                otherwise
                    error("Lakeshore350:UnsupportedHeaterRange", "%s", "Unsupported heater range, should be Off or Range 1 to Range 5, was " + string(heaterRange));
            end
        end

        function ReadHeaterSetup(this, heaterChannel)
            %Read a heater output's set-up (HTRSET?) into HeaterSetups: range 5's full-scale current, and whether its output is in % of power.
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2

            if this.SimulationMode
                return;
            end

            outputIdx = this.GetHeaterChannelIndex(heaterChannel);

            %Reply is "<htr resistance>,<max current>,<max user current>,<current/power>"
            htrset = str2double(split(strip(string(this.QueryString("HTRSET? " + outputIdx))), ","))';
            outputIsPower = htrset(4) == 2;

            if outputIdx == 2
                %Output 2 is limited to 100 mA
                maxCurrent = 0.1;
            else
                %Output 1: max current 0 = user specified, 1 = 0.707 A, 2 = 1 A,
                %3 = 1.414 A (the manual says 1.141 - a typo: each step doubles
                %the power), 4 = 2 A
                switch(htrset(2))
                    case(0);    maxCurrent = htrset(3);
                    case(1);    maxCurrent = 0.707;
                    case(2);    maxCurrent = 1;
                    case(3);    maxCurrent = 1.414;
                    case(4);    maxCurrent = 2;
                    otherwise
                        error("Lakeshore350:InvalidMaxCurrent", "%s", "Unknown heater max current setting returned by " + this.Name + ": " + string(htrset(2)));
                end

                %The output is limited to 1.73 A at the 25 Ohm heater resistance
                %setting (1), and 1 A at the 50 Ohm setting (2)
                if htrset(1) == 2
                    maxCurrent = min(maxCurrent, 1);
                else
                    maxCurrent = min(maxCurrent, 1.732);
                end
            end

            this.HeaterSetups(outputIdx).MaxCurrent = maxCurrent;
            this.HeaterSetups(outputIdx).OutputIsPower = outputIsPower;
        end

        function [power, level, rangeIdx] = ReadHeaterOutput(this, heaterChannel)
            %Read a heater output (HTR?) and its range, and work out the power going into the heater, in W.
            %Range 5's full-scale current is the output's maximum current
            %(see ReadHeaterSetup) and each lower range is a decade lower in
            %power, so power = HeaterResistance x I^2. The heater output is a
            %percentage of full-scale power or current, depending on the
            %instrument's setting - squared for current
            %
            %Inputs:
            %   heaterChannel - OutputChannel categorical, Ch1 or Ch2
            %
            %Outputs:
            %   power    - heater power, in W
            %   level    - heater output, in percent of full-scale power or current
            %   rangeIdx - heater range number, 0 (Off) to 5

            outputIdx = this.GetHeaterChannelIndex(heaterChannel);
            if this.SimulationMode
                level = this.GenerateSimulatedData(1, Baseline=60, Variance=3);
            else
                level = this.QueryDouble("HTR? " + outputIdx);
            end
            rangeIdx = this.GetHeaterRange(heaterChannel);

            setup = this.HeaterSetups(outputIdx);
            fraction = level / 100;
            if ~setup.OutputIsPower
                fraction = fraction^2;
            end
            if rangeIdx == 0
                power = 0;
            else
                power = this.HeaterResistance * setup.MaxCurrent^2 * 10^(rangeIdx - 5) * fraction;
            end
        end

        function [withTemperature, withSensor] = InputColumns(this, letter)
            %Whether an input's temperature and sensor units are logged, from its Ch_X_Reading.

            reading = this.("Ch_" + letter + "_Reading");
            both = reading == this.MeasType("Both");
            withTemperature = both || reading == this.MeasType("Temperature");
            withSensor = both || reading == this.MeasType("Sensor Units");
        end

        function letter = InputLetter(~, controlChannel)
            %The input letter, A to D, of a Channel categorical or text.

            letter = upper(strip(string(controlChannel)));
            assert(isscalar(letter) && any(letter == ["A", "B", "C", "D"]), "Lakeshore350:InvalidInput", "%s", ...
                "The input must be A, B, C or D, was " + string(controlChannel));
        end

        function values = ReadAllInputs(this, query, readOne)
            %Read all four inputs with one query (e.g. KRDG? 0) - or one at a time if the reply hasn't four values (some 350s).
            %
            %Inputs:
            %   query   - "KRDG?" or "SRDG?"
            %   readOne - function reading one input by letter, for the fallback

            letters = ["A", "B", "C", "D"];
            if this.SimulationMode
                values = arrayfun(readOne, letters);
                return;
            end

            values = str2double(split(string(this.QueryString(query + " 0")), ","))';
            if numel(values) ~= 4
                values = arrayfun(readOne, letters);
            end
        end

    end

end
