classdef Lakeshore340 < Palladium.Core.Instrument
    %Lakeshore340 - Instrument driver for the Lake Shore Model 340 temperature controller.
    %Reads sensor inputs A and B (as temperature or sensor resistance) each
    %measurement tick, plus the power going into the heater. A control loop
    %can be run from the Heater Control tab: setpoint, ramp, PID values,
    %control mode, heater range and manual output. `ControlChannel` picks the
    %loop: A uses control loop 1, which drives the heater output (up to
    %100 W); B uses control loop 2, which drives Analog Output 2 rather than
    %the heater. The heater range, heater output and heater power always
    %refer to the heater (loop 1).
    %
    %The Model 340 has GPIB (IEEE-488) and RS-232 interfaces. Its command set
    %is close to the Model 331's (see `Lakeshore331`).
    %
    %The input each loop regulates on is set on the instrument (CONTROL
    %SETUP screen, or the CSET command), not by this driver.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Lakeshore 340";                             %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "Ls340";                                         %Instrument name, used as the prefix of its heater power column header
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Ch_A_Reading;                                           %What to read on channel A: Temperature (K), Resistance (Ohms), or Disabled to not measure it
        Ch_B_Reading;                                           %What to read on channel B: Temperature (K), Resistance (Ohms), or Disabled to not measure it
        Ch_A_Name = "Channel A Temperature (K)"                 %Data column header for channel A when reading temperature, e.g. "Sample Temp (K)"
        Ch_B_Name = "Channel B Temperature (K)"                 %Data column header for channel B when reading temperature
        HeaterResistance = 100;                                 %Resistance of the heater connected to the heater output, in Ohms - used to calculate heater power
        ControlChannel;                                         %Control loop the Heater Control tab acts on: A for loop 1 (the heater output), B for loop 2 (Analog Output 2)
    end

    %% Properties (Private)
    properties(Access = private)
        HeaterOutputIsPower = true;                             %Whether the heater output percentage (HTR?) is of full-scale power (true) or current (false), as set on the instrument and read when connecting
        MaxHeaterCurrent = 1;                                   %Maximum heater current setting, in A - the full-scale current of range 5 - read when connecting. NaN if set to User, which cannot be read back
    end

    %% Categoricals
    methods
        function catOut = Channel(this, inputStr);          catOut = this.ConvertToCategorical(inputStr, ["A", "B", "None"]); end
        function catOut = ControlMode(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Manual PID", "Zone", "Open Loop", "AutoTune PID", "AutoTune PI", "AutoTune P"]); end
        function catOut = HeaterRange(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Off", "Range 1", "Range 2", "Range 3", "Range 4", "Range 5"]); end
        function catOut = MeasType(this, inputStr);         catOut = this.ConvertToCategorical(inputStr, ["Temperature", "Resistance", "Disabled"]); end
    end

    %% Constructor
    methods
        function this = Lakeshore340()
            %Set the connection options, default readings and Heater Control tab.

            %The Model 340 has GPIB and RS-232 ports; VISA can address either
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial", "VISA"]);
            this.GPIB_Address = 12;

            %RS-232 is set to 7 data bits, odd parity and 1 stop bit, with
            %CR LF terminators. The baud rate (up to 19200) must match the
            %COMPUTER INTERFACE screen on the instrument
            this.ConnectionSettings.SerialSettings = struct('BaudRate', 9600, 'DataBits', 7, 'Parity', 'odd', 'StopBits', 1, 'Terminator', 'CR/LF');

            %Define the Instrument Controls that can be added
            this.DefineInstrumentControl(Name = "🕹️ Heater Control", ClassName = "LakeshoreHeaterControl", TabName = "Heater Control", EnabledByDefault = true);

            %Make sure to set values for Properties of Categorical type
            %like these
            this.Ch_A_Reading = this.MeasType("Temperature");
            this.Ch_B_Reading = this.MeasType("Temperature");
            this.ControlChannel = this.Channel("A");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [settings, heaterLevelPct, heaterEnabled, heaterPower] = CollectHeaterControlSettings(this)
            %Read the control loop's settings and the heater output, for the Heater Control tab.
            %The loop is set by ControlChannel
            %
            %Outputs:
            %   settings       - struct of the heater settings, with fields ControlMode,
            %                    HeaterRange, SetPoint, RampEnabled, RampRate, ManualOutput
            %                    and PID_Settings (with fields P, I and D). The same
            %                    struct, edited, is passed back to ApplySettings
            %   heaterLevelPct - heater output, in percent (see GetHeaterLevel)
            %   heaterEnabled  - false if the heater range is Off
            %   heaterPower    - heater power, in W (see GetHeaterPower)

            settings.ControlMode = this.GetControlMode(this.ControlChannel);
            settings.HeaterRange = this.GetHeaterRangeFromIndex(this.GetHeaterRange());
            settings.SetPoint = this.GetHeaterSetpoint();
            [settings.RampEnabled, settings.RampRate] = this.GetRamp();
            settings.ManualOutput = this.GetManualOutputPercent(this.ControlChannel);
            [P, I, D] = this.GetPIDValues(this.ControlChannel);
            settings.PID_Settings.P = P;
            settings.PID_Settings.I = I;
            settings.PID_Settings.D = D;

            [heaterLevelPct, heaterEnabled] = this.GetHeaterLevel();
            heaterPower = this.GetHeaterPower();
        end

        function Connect(this)
            %Open the connection and read the heater's maximum current and display mode.
            %Both are needed by GetHeaterPower
            %
            %Reads loop 1's maximum current (CLIMIT?) and whether its output
            %is shown as a percentage of current or power (CDISP?). Change
            %these on the instrument, then reconnect.

            Connect@Palladium.Core.Instrument(this);
            if this.SimulationMode
                return;
            end

            %Reply is "<SP limit>,<positive slope>,<negative slope>,<max current>,<max range>",
            %where max current is 1 = 0.25 A, 2 = 0.5 A, 3 = 1 A, 4 = 2 A, 5 = User
            climit = strsplit(strtrim(this.QueryString("CLIMIT? 1")), ",");
            switch(str2double(climit{4}))
                case(1);    this.MaxHeaterCurrent = 0.25;
                case(2);    this.MaxHeaterCurrent = 0.5;
                case(3);    this.MaxHeaterCurrent = 1;
                case(4);    this.MaxHeaterCurrent = 2;
                otherwise
                    this.MaxHeaterCurrent = NaN;
                    warning("Lakeshore340:UnknownMaxCurrent", "%s", this.Name + ": the heater's maximum current is set to User (or could not be read), so the heater power cannot be calculated and is recorded as NaN. Choose 0.25, 0.5, 1 or 2 A on the instrument to record it.");
            end

            %Reply is "<number of loops>,<resistance>,<current/power>,<large output enable>",
            %where current/power is 1 = current, 2 = power
            cdisp = strsplit(strtrim(this.QueryString("CDISP? 1")), ",");
            this.HeaterOutputIsPower = str2double(cdisp{3}) == 2;
        end

        function controlMode = GetControlMode(this, controlChannel)
            %Read a control loop's control mode
            %
            %Inputs:
            %   controlChannel - Channel categorical: A for loop 1, B for loop 2
            %
            %Outputs:
            %   controlMode - ControlMode categorical, e.g. Manual PID

            loop = this.GetLoopString(controlChannel);

            if(this.SimulationMode)
                modeIndex = 1;
            else
                modeIndex = this.QueryDouble("CMODE? " + loop);
            end

            switch(modeIndex)
                case(1);    controlMode = this.ControlMode("Manual PID");
                case(2);    controlMode = this.ControlMode("Zone");
                case(3);    controlMode = this.ControlMode("Open Loop");
                case(4);    controlMode = this.ControlMode("AutoTune PID");
                case(5);    controlMode = this.ControlMode("AutoTune PI");
                case(6);    controlMode = this.ControlMode("AutoTune P");
                otherwise
                    error("Lakeshore340:InvalidControlMode", "%s", "Unknown control mode index returned by " + this.Name + ": " + string(modeIndex));
            end
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %One per enabled channel, then the heater power
            %
            %Outputs:
            %   Headers - e.g. ["Channel A Temperature (K)", "Ls340 Heater Power (W)"].
            %             Temperature columns use Ch_A_Name / Ch_B_Name
            %   Units   - matching units, e.g. ["K", "W"]

            Headers = [];
            Units = [];

            %Add a column for each channel that isn't Disabled
            switch(this.Ch_A_Reading)
                case(this.MeasType("Temperature"));     Headers = [Headers string(this.Ch_A_Name)];          Units = [Units "K"];
                case(this.MeasType("Resistance"));      Headers = [Headers "Ch A Resistance (Ohms)"];       Units = [Units "Ohms"];
            end
            switch(this.Ch_B_Reading)
                case(this.MeasType("Temperature"));     Headers = [Headers string(this.Ch_B_Name)];          Units = [Units "K"];
                case(this.MeasType("Resistance"));      Headers = [Headers "Ch B Resistance (Ohms)"];       Units = [Units "Ohms"];
            end

            %The heater power is always recorded
            Headers = [Headers, this.Name + " Heater Power (W)"];
            Units = [Units, "W"];
        end

        function [htrLevel, htrEnabled] = GetHeaterLevel(this)
            %Read the heater output percentage, and whether the heater is on.
            %The output is a percentage of full scale for the heater range
            %
            %Outputs:
            %   htrLevel   - heater output, in percent of full-scale power or
            %                current (see HeaterOutputIsPower)
            %   htrEnabled - false if the heater range is Off

            if(this.SimulationMode)
                htrLevel = this.GenerateSimulatedData(1, Baseline=60, Variance=3);
                htrEnabled = true;
                return;
            end

            htrLevel = this.QueryDouble("HTR?");
            htrEnabled = this.GetHeaterRange() ~= this.GetHeaterRangeIndex(this.HeaterRange("Off"));
        end

        function power = GetHeaterPower(this)
            %Calculate the power going into the heater, in W.
            %From the heater output, heater range, maximum current and HeaterResistance
            %
            %Outputs:
            %   power - heater power, in W. NaN if the maximum current is set
            %           to User on the instrument
            %
            %Range 5's full-scale current is the maximum current setting, and
            %each lower range is a decade lower in power, so power =
            %HeaterResistance x I^2. Full-scale current is also limited by the
            %50 V compliance voltage. The heater output is a percentage of
            %full-scale power or current, depending on the instrument's
            %setting - squared for current. Not yet tested on hardware.

            level = this.GetHeaterLevel() / 100;
            if ~this.HeaterOutputIsPower
                level = level^2;
            end

            rangeIdx = this.GetHeaterRange();
            if rangeIdx == 0
                power = 0;
                return;
            end
            fullScaleCurrent = min(this.MaxHeaterCurrent * sqrt(10^(rangeIdx - 5)), 50 / this.HeaterResistance);
            power = this.HeaterResistance * fullScaleCurrent^2 * level;
        end

        function htrRange = GetHeaterRange(this)
            %Read the heater range number
            %
            %Outputs:
            %   htrRange - 0 = Off, 1 to 5 = Range 1 to Range 5

            if(this.SimulationMode)
                htrRange = 2;
            else
                htrRange = this.QueryDouble("RANGE?");
            end
        end

        function setPt = GetHeaterSetpoint(this)
            %Read the control setpoint of the loop set by ControlChannel
            %
            %Outputs:
            %   setPt - setpoint, in the setpoint units set on the instrument
            %           (usually K)

            if(this.SimulationMode)
                setPt = 25.4;
                return;
            end

            setPt = this.QueryDouble("SETP? " + this.GetLoopString(this.ControlChannel));
        end

        function output = GetManualOutputPercent(this, controlChannel)
            %Read a control loop's manual output setting, in percent.
            %Used in Open Loop mode, and added to the PID output in the other modes
            %
            %Inputs:
            %   controlChannel - Channel categorical: A for loop 1, B for loop 2
            %
            %Outputs:
            %   output - manual output, in percent

            loop = this.GetLoopString(controlChannel);

            if(this.SimulationMode)
                output = 78;
                return;
            end

            output = this.QueryDouble("MOUT? " + loop);
        end

        function [P, I, D] = GetPIDValues(this, controlChannel)
            %Read a control loop's PID control values
            %
            %Inputs:
            %   controlChannel - Channel categorical: A for loop 1, B for loop 2
            %
            %Outputs:
            %   P - proportional gain
            %   I - integral, or reset
            %   D - derivative, or rate

            loop = this.GetLoopString(controlChannel);

            if(this.SimulationMode)
                P = 50;
                I = 10;
                D = 5;
            else
                readings = strsplit(this.QueryString("PID? " + loop), ',');
                P = str2double(readings{1});
                I = str2double(readings{2});
                D = str2double(readings{3});
            end
        end

        function [enabled, rate] = GetRamp(this)
            %Read whether the setpoint of the ControlChannel loop ramps, and how fast
            %
            %Outputs:
            %   enabled - true if setpoint ramping is on
            %   rate    - ramp rate, in K/min

            if(this.SimulationMode)
                enabled = true;
                rate = 1.2;
            else
                result = strsplit(this.QueryString("RAMP? " + this.GetLoopString(this.ControlChannel)), ',');
                enabled = strcmp(strtrim(result{1}), '1');
                rate = str2double(result{2});
            end
        end

        function resistance = GetResistance(this, channel)
            %Read a sensor input in sensor units (Ohms for resistive sensors)
            %
            %Inputs:
            %   channel - Channel categorical, A or B
            %
            %Outputs:
            %   resistance - the reading, in sensor units

            resistance = this.QueryDouble("SRDG? " + this.GetChannelString(channel));
        end

        function reading = GetSensorReading(this, channel)
            %Read a sensor input in sensor units - the same as GetResistance
            %
            %Inputs:
            %   channel - Channel categorical, A or B
            %
            %Outputs:
            %   reading - the reading, in sensor units

            reading = this.QueryDouble("SRDG? " + this.GetChannelString(channel));
        end

        function temp = GetTemperature(this, channel)
            %Read a sensor input in kelvin
            %
            %Inputs:
            %   channel - Channel categorical, A or B
            %
            %Outputs:
            %   temp - the reading, in K

            temp = this.QueryDouble("KRDG? " + this.GetChannelString(channel));
        end

        function [dataRow] = Measure(this)
            %Read each enabled channel, then the heater power.
            %In the same order as GetHeaders
            %
            %Outputs:
            %   dataRow - the readings, in K or Ohms, then the heater power in W

            dataRow = [];
            switch(this.Ch_A_Reading)
                case(this.MeasType("Temperature"));     dataRow = [dataRow this.GetTemperature(this.Channel("A"))];
                case(this.MeasType("Resistance"));      dataRow = [dataRow this.GetResistance(this.Channel("A"))];
            end
            switch(this.Ch_B_Reading)
                case(this.MeasType("Temperature"));     dataRow = [dataRow this.GetTemperature(this.Channel("B"))];
                case(this.MeasType("Resistance"));      dataRow = [dataRow this.GetResistance(this.Channel("B"))];
            end

            dataRow = [dataRow this.GetHeaterPower()];
        end

        function SetControlMode(this, controlChannel, controlMode)
            %Set a control loop's control mode
            %
            %Inputs:
            %   controlChannel - Channel categorical: A for loop 1, B for loop 2
            %   controlMode    - ControlMode categorical, e.g. Manual PID

            loop = this.GetLoopString(controlChannel);
            modeIndex = this.GetControlModeIndex(controlMode);

            this.WriteCommand("CMODE " + loop + "," + num2str(modeIndex));
        end

        function SetHeaterRange(this, range)
            %Set the heater range, which sets the maximum heater power
            %
            %Inputs:
            %   range - HeaterRange categorical: Off or Range 1 to Range 5. Off
            %           turns the heater off

            rangeIdx = this.GetHeaterRangeIndex(range);
            this.WriteCommand("RANGE " + num2str(rangeIdx));
        end

        function SetHeaterSetpoint(this, setPt)
            %Set the control setpoint of the loop set by ControlChannel.
            %With ramping on, the setpoint ramps to the new value at the ramp rate
            %
            %Inputs:
            %   setPt - setpoint, in the setpoint units set on the instrument
            %           (usually K)

            this.WriteCommand("SETP " + this.GetLoopString(this.ControlChannel) + "," + num2str(setPt));
        end

        function SetManualOutputPercent(this, controlChannel, percentage)
            %Set a control loop's manual output, in percent.
            %Used in Open Loop mode, and added to the PID output in the other modes
            %
            %Inputs:
            %   controlChannel - Channel categorical: A for loop 1, B for loop 2
            %   percentage     - manual output, 0 to 100 %

            loop = this.GetLoopString(controlChannel);
            assert(percentage <= 100 && percentage >= 0, "Lakeshore340:InvalidOutputPercentage", "Invalid output percentage");
            this.WriteCommand("MOUT " + loop + "," + num2str(percentage));
        end

        function SetPIDValues(this, controlChannel, P, I, D)
            %Set a control loop's PID control values
            %
            %Inputs:
            %   controlChannel - Channel categorical: A for loop 1, B for loop 2
            %   P              - proportional gain
            %   I              - integral, or reset
            %   D              - derivative, or rate

            loop = this.GetLoopString(controlChannel);
            this.WriteCommand("PID " + loop + "," + num2str(P) + "," + num2str(I) + "," + num2str(D));
        end

        function SetRamp(this, enabled, rate)
            %Turn setpoint ramping on or off for the ControlChannel loop, and set its rate
            %
            %Inputs:
            %   enabled - true to ramp the setpoint to new values, false to
            %             step it
            %   rate    - ramp rate, in K/min (0.1 to 100)

            this.WriteCommand("RAMP " + this.GetLoopString(this.ControlChannel) + "," + num2str(double(logical(enabled))) + "," + num2str(rate));
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function ApplySettings(this, settings)
            %Send the Heater Control tab's settings to the instrument.
            %They go to the control loop set by ControlChannel. The ramp is set
            %before the setpoint, so a new setpoint ramps
            %
            %Inputs:
            %   settings - struct with the fields returned by
            %              CollectHeaterControlSettings

            this.SetControlMode(this.ControlChannel, settings.ControlMode);
            this.SetHeaterRange(settings.HeaterRange);
            this.SetRamp(settings.RampEnabled, settings.RampRate);
            pause(0.05);
            this.SetHeaterSetpoint(settings.SetPoint);

            if(settings.ControlMode == this.ControlMode("Open Loop"))
                this.SetManualOutputPercent(this.ControlChannel, settings.ManualOutput);
            end

            this.SetPIDValues(this.ControlChannel, settings.PID_Settings.P, settings.PID_Settings.I, settings.PID_Settings.D);
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function channelIndex = GetChannelIndex(this, channel)
            %Number for a channel: 0 = None, 1 = A, 2 = B
            %
            %Inputs:
            %   channel - Channel categorical
            %
            %Outputs:
            %   channelIndex - 0, 1 or 2

            switch(channel)
                case(this.Channel("None"));     channelIndex = 0;
                case(this.Channel("A"));        channelIndex = 1;
                case(this.Channel("B"));        channelIndex = 2;
                otherwise
                    error("Lakeshore340:UnsupportedChannel", "%s", "Unsupported channel, should be None, A or B, was " + string(channel));
            end
        end

        function channelStr = GetChannelString(~, channel)
            %Channel letter to send to the instrument
            %
            %Inputs:
            %   channel - Channel categorical, A or B
            %
            %Outputs:
            %   channelStr - "A" or "B"

            channelStr = string(channel);
        end

        function index = GetControlModeIndex(this, controlMode)
            %Control mode number used by the CMODE command
            %
            %Inputs:
            %   controlMode - ControlMode categorical
            %
            %Outputs:
            %   index - 1 = Manual PID, 2 = Zone, 3 = Open Loop, 4 = AutoTune PID,
            %           5 = AutoTune PI, 6 = AutoTune P

            switch(controlMode)
                case(this.ControlMode("Manual PID"));       index = 1;
                case(this.ControlMode("Zone"));             index = 2;
                case(this.ControlMode("Open Loop"));        index = 3;
                case(this.ControlMode("AutoTune PID"));     index = 4;
                case(this.ControlMode("AutoTune PI"));      index = 5;
                case(this.ControlMode("AutoTune P"));       index = 6;
                otherwise
                    error("Lakeshore340:UnsupportedControlMode", "%s", "Unsupported control mode, should be Manual PID, Zone, Open Loop, AutoTune PID, AutoTune PI or AutoTune P, was " + string(controlMode));
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
                    error("Lakeshore340:InvalidHeaterRange", "%s", "Unknown heater range index returned by " + this.Name + ": " + string(index));
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
                    error("Lakeshore340:UnsupportedHeaterRange", "%s", "Unsupported heater range, should be Off or Range 1 to Range 5, was " + string(heaterRange));
            end
        end

        function loop = GetLoopString(this, controlChannel)
            %Control loop number to send to the instrument for a channel
            %
            %Inputs:
            %   controlChannel - Channel categorical: A for loop 1, B for loop 2
            %
            %Outputs:
            %   loop - "1" or "2"

            assert(controlChannel ~= this.Channel("None"), "Lakeshore340:NoControlLoop", "%s", "ControlChannel of " + this.Name + " is None - set it to A (loop 1) or B (loop 2) to use the heater control");
            loop = string(this.GetChannelIndex(controlChannel));
        end

    end

end
