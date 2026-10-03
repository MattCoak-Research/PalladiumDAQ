classdef Lakeshore331 < Palladium.Core.Instrument
    %Lakeshore331 - Instrument driver for the Lake Shore Model 331 temperature controller.
    %Reads sensor inputs A and B (as temperature or sensor resistance) each
    %measurement tick, plus the power going into the heater. Its heater -
    %control loop 1, up to 50 W - can be controlled from the Heater Control
    %tab: setpoint, ramp, PID values, control mode, heater range and manual
    %output, regulating on the sensor input chosen by `ControlChannel`.
    %
    %The Model 331 has GPIB and RS-232 interfaces. Loop 2 (the 1 W analog
    %voltage output) is not used by this driver.

    %% Properties (Constant, Private)
    properties(Constant, Access = private)
        HeaterLoop = "1";                                       %Control loop driving the heater output - loop 1 on the 331
    end

    %% Properties (Public)
    properties(Access = public)
        FullName = "Lakeshore 331";                             %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "Ls331";                                         %Instrument name, used as the prefix of its heater power column header
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Ch_A_Reading;                                           %What to read on channel A: Temperature (K), Resistance (Ohms), or Disabled to not measure it
        Ch_B_Reading;                                           %What to read on channel B: Temperature (K), Resistance (Ohms), or Disabled to not measure it
        Ch_A_Name = "Channel A Temperature (K)"                 %Data column header for channel A when reading temperature, e.g. "Sample Temp (K)"
        Ch_B_Name = "Channel B Temperature (K)"                 %Data column header for channel B when reading temperature
        HeaterResistance = 100;                                 %Resistance of the heater connected to the heater output, in Ohms - used to calculate heater power
        ControlChannel;                                         %Sensor input (A or B) the heater regulates on - sent to the instrument when heater settings are applied. None leaves the instrument's choice unchanged.
    end

    %% Properties (Private)
    properties(Access = private)
        HeaterOutputIsPower = true;                             %Whether the heater output percentage (HTR?) is of full-scale power (true) or current (false), as set on the instrument and read when connecting
    end

    %% Categoricals
    methods
        function catOut = Channel(this, inputStr);          catOut = this.ConvertToCategorical(inputStr, ["A", "B", "None"]); end
        function catOut = ControlMode(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Manual PID", "Zone", "Open Loop", "AutoTune PID", "AutoTune PI", "AutoTune P"]); end
        function catOut = HeaterRange(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Off", "Low", "Medium", "High"]); end % 0 = Off, 1 = Low (0.5 W), 2 = Medium (5 W), 3 = High (50 W)
        function catOut = MeasType(this, inputStr);         catOut = this.ConvertToCategorical(inputStr, ["Temperature", "Resistance", "Disabled"]); end
    end

    %% Constructor
    methods
        function this = Lakeshore331()
            %Set the connection options, default readings and Heater Control tab.

            %The Model 331 has GPIB and RS-232 ports; VISA can address either
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial", "VISA"]);
            this.GPIB_Address = 12;

            %RS-232 is fixed at 7 data bits, odd parity and 1 stop bit, with
            %CR LF terminators. 9600 baud is the factory setting - it must
            %match the Interface menu on the instrument
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
            %Read the heater's settings and output, for the Heater Control tab.
            %
            %Outputs:
            %   settings       - struct of the heater settings, with fields ControlMode,
            %                    HeaterRange, SetPoint, RampEnabled, RampRate, ManualOutput
            %                    and PID_Settings (with fields P, I and D). The same
            %                    struct, edited, is passed back to ApplySettings
            %   heaterLevelPct - heater output, in percent (see GetHeaterLevel)
            %   heaterEnabled  - false if the heater range is Off
            %   heaterPower    - heater power, in W (see GetHeaterPower)

            settings.ControlMode = this.GetControlMode();
            settings.HeaterRange = this.GetHeaterRange();
            settings.SetPoint = this.GetHeaterSetpoint();
            [settings.RampEnabled, settings.RampRate] = this.GetRamp();
            settings.ManualOutput = this.GetManualOutputPercent();
            [P, I, D] = this.GetPIDValues();
            settings.PID_Settings.P = P;
            settings.PID_Settings.I = I;
            settings.PID_Settings.D = D;

            [heaterLevelPct, heaterEnabled] = this.GetHeaterLevel();
            heaterPower = this.GetHeaterPower();
        end

        function Connect(this)
            %Open the connection and read the heater output display mode.
            %Whether the heater output is a percentage of power or of current is
            %needed by GetHeaterPower

            Connect@Palladium.Core.Instrument(this);
            if this.SimulationMode
                return;
            end

            %Reply is "<input>,<units>,<powerup enable>,<current/power>",
            %where current/power is 1 = current, 2 = power
            cset = strsplit(strtrim(this.QueryString("CSET? " + this.HeaterLoop)), ",");
            this.HeaterOutputIsPower = str2double(cset{4}) == 2;
        end

        function controlMode = GetControlMode(this)
            %Read the heater's control mode
            %
            %Outputs:
            %   controlMode - ControlMode categorical, e.g. Manual PID

            if(this.SimulationMode)
                modeIndex = 1;
            else
                modeIndex = this.QueryDouble("CMODE? " + this.HeaterLoop);
            end

            switch(modeIndex)
                case(1);    controlMode = this.ControlMode("Manual PID");
                case(2);    controlMode = this.ControlMode("Zone");
                case(3);    controlMode = this.ControlMode("Open Loop");
                case(4);    controlMode = this.ControlMode("AutoTune PID");
                case(5);    controlMode = this.ControlMode("AutoTune PI");
                case(6);    controlMode = this.ControlMode("AutoTune P");
                otherwise
                    error("Lakeshore331:InvalidControlMode", "%s", "Unknown control mode index returned by " + this.Name + ": " + string(modeIndex));
            end
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %One per enabled channel, then the heater power
            %
            %Outputs:
            %   Headers - e.g. ["Channel A Temperature (K)", "Ls331 Heater Power (W)"].
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
            htrEnabled = this.GetHeaterRange() ~= this.HeaterRange("Off");
        end

        function power = GetHeaterPower(this)
            %Calculate the power going into the heater, in W.
            %From the heater output, heater range and HeaterResistance
            %
            %Outputs:
            %   power - heater power, in W
            %
            %Each range's full-scale current is fixed (it gives the range's
            %maximum power into 50 Ohms), so power = HeaterResistance x I^2.
            %The heater output is a percentage of full-scale power or current,
            %depending on the instrument's setting - squared for current.
            %Tested 2026-04-13 on a 370 Ohm resistor test box, in Open Loop
            %mode at 1% and 4% manual output (power display): the calculated
            %power agreed with V^2/R measured across the resistor with a DMM.

            level = this.GetHeaterLevel() / 100;
            if ~this.HeaterOutputIsPower
                level = level^2;
            end
            fullScaleCurrentSquared = this.GetMaxPowerInto50Ohms(this.GetHeaterRange()) / 50;
            power = this.HeaterResistance * fullScaleCurrentSquared * level;
        end

        function htrRange = GetHeaterRange(this)
            %Read the heater range
            %
            %Outputs:
            %   htrRange - HeaterRange categorical: Off, Low (0.5 W), Medium
            %              (5 W) or High (50 W)

            if(this.SimulationMode)
                rangeIndex = 2;
            else
                rangeIndex = this.QueryDouble("RANGE?");
            end

            switch(rangeIndex)
                case(0);    htrRange = this.HeaterRange("Off");
                case(1);    htrRange = this.HeaterRange("Low");
                case(2);    htrRange = this.HeaterRange("Medium");
                case(3);    htrRange = this.HeaterRange("High");
                otherwise
                    error("Lakeshore331:InvalidHeaterRange", "%s", "Unknown heater range index returned by " + this.Name + ": " + string(rangeIndex));
            end
        end

        function setPt = GetHeaterSetpoint(this)
            %Read the heater's control setpoint
            %
            %Outputs:
            %   setPt - setpoint, in the setpoint units set on the instrument
            %           (usually K)

            if(this.SimulationMode)
                setPt = 25.4;
                return;
            end

            setPt = this.QueryDouble("SETP? " + this.HeaterLoop);
        end

        function output = GetManualOutputPercent(this)
            %Read the heater's manual output setting, in percent.
            %Used in Open Loop mode, and added to the PID output in the other modes
            %
            %Outputs:
            %   output - manual output, in percent

            if(this.SimulationMode)
                output = 78;
                return;
            end

            output = this.QueryDouble("MOUT? " + this.HeaterLoop);
        end

        function [P, I, D] = GetPIDValues(this)
            %Read the heater's PID control values
            %
            %Outputs:
            %   P - proportional gain (0.1 to 1000)
            %   I - integral, or reset (0.1 to 1000)
            %   D - derivative, or rate (0 to 200)

            if(this.SimulationMode)
                P = 50;
                I = 10;
                D = 5;
            else
                readings = strsplit(this.QueryString("PID? " + this.HeaterLoop), ',');
                P = str2double(readings{1});
                I = str2double(readings{2});
                D = str2double(readings{3});
            end
        end

        function [enabled, rate] = GetRamp(this)
            %Read whether the setpoint ramps to a new value, and how fast
            %
            %Outputs:
            %   enabled - true if setpoint ramping is on
            %   rate    - ramp rate, in K/min

            if(this.SimulationMode)
                enabled = true;
                rate = 1.2;
            else
                result = strsplit(this.QueryString("RAMP? " + this.HeaterLoop), ',');
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

        function SetControlInput(this, channel)
            %Set which sensor input the heater regulates on.
            %The other control loop parameters (setpoint units, power-up enable and
            %current/power display) are kept as they are
            %
            %Inputs:
            %   channel - Channel categorical: A or B. None leaves the
            %             instrument's setting unchanged

            if channel == this.Channel("None")
                return;
            end
            if this.SimulationMode
                return;
            end

            %Reply is "<input>,<units>,<powerup enable>,<current/power>" -
            %write it back with only the input changed
            cset = strtrim(strsplit(strtrim(this.QueryString("CSET? " + this.HeaterLoop)), ","));
            this.WriteCommand("CSET " + this.HeaterLoop + "," + this.GetChannelString(channel) + "," + strjoin(cset(2:4), ","));
        end

        function SetControlMode(this, controlMode)
            %Set the heater's control mode
            %
            %Inputs:
            %   controlMode - ControlMode categorical, e.g. Manual PID

            switch(controlMode)
                case(this.ControlMode("Manual PID"));       modeIndex = 1;
                case(this.ControlMode("Zone"));             modeIndex = 2;
                case(this.ControlMode("Open Loop"));        modeIndex = 3;
                case(this.ControlMode("AutoTune PID"));     modeIndex = 4;
                case(this.ControlMode("AutoTune PI"));      modeIndex = 5;
                case(this.ControlMode("AutoTune P"));       modeIndex = 6;
                otherwise
                    error("Lakeshore331:UnsupportedControlMode", "%s", "Unsupported control mode, should be Manual PID, Zone, Open Loop, AutoTune PID, AutoTune PI or AutoTune P, was " + string(controlMode));
            end

            this.WriteCommand("CMODE " + this.HeaterLoop + "," + num2str(modeIndex));
        end

        function SetHeaterRange(this, range)
            %Set the heater range, which sets the maximum heater power
            %
            %Inputs:
            %   range - HeaterRange categorical: Off, Low (0.5 W), Medium (5 W) or
            %           High (50 W). Off turns the heater off

            this.WriteCommand("RANGE " + num2str(this.GetHeaterRangeIndex(range)));
        end

        function SetHeaterSetpoint(this, setPt)
            %Set the heater's control setpoint.
            %With ramping on, the setpoint ramps to the new value at the ramp rate
            %
            %Inputs:
            %   setPt - setpoint, in the setpoint units set on the instrument
            %           (usually K)

            this.WriteCommand("SETP " + this.HeaterLoop + "," + num2str(setPt));
        end

        function SetManualOutputPercent(this, percentage)
            %Set the heater's manual output, in percent.
            %Used in Open Loop mode, and added to the PID output in the other modes
            %
            %Inputs:
            %   percentage - manual output, 0 to 100 %

            assert(percentage <= 100 && percentage >= 0, "Lakeshore331:InvalidOutputPercentage", "Invalid output percentage");
            this.WriteCommand("MOUT " + this.HeaterLoop + "," + num2str(percentage));
        end

        function SetPIDValues(this, P, I, D)
            %Set the heater's PID control values
            %
            %Inputs:
            %   P - proportional gain (0.1 to 1000)
            %   I - integral, or reset (0.1 to 1000)
            %   D - derivative, or rate (0 to 200)

            this.WriteCommand("PID " + this.HeaterLoop + "," + num2str(P) + "," + num2str(I) + "," + num2str(D));
        end

        function SetRamp(this, enabled, rate)
            %Turn setpoint ramping on or off, and set its rate
            %
            %Inputs:
            %   enabled - true to ramp the setpoint to new values, false to
            %             step it
            %   rate    - ramp rate, in K/min (0.1 to 100)

            this.WriteCommand("RAMP " + this.HeaterLoop + "," + num2str(double(logical(enabled))) + "," + num2str(rate));
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function ApplySettings(this, settings)
            %Send the Heater Control tab's settings to the instrument.
            %Also sets the sensor input to regulate on, from ControlChannel
            %
            %Inputs:
            %   settings - struct with the fields returned by
            %              CollectHeaterControlSettings

            this.SetControlInput(this.ControlChannel);
            this.SetControlMode(settings.ControlMode);
            this.SetHeaterRange(settings.HeaterRange);
            this.SetRamp(settings.RampEnabled, settings.RampRate);
            pause(0.05);
            this.SetHeaterSetpoint(settings.SetPoint);

            if(settings.ControlMode == this.ControlMode("Open Loop"))
                this.SetManualOutputPercent(settings.ManualOutput);
            end

            this.SetPIDValues(settings.PID_Settings.P, settings.PID_Settings.I, settings.PID_Settings.D);
        end

    end

    %% Methods (Private)
    methods (Access = private)

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

        function maxPower = GetMaxPowerInto50Ohms(this, heaterRange)
            %Maximum heater power of a heater range, into a 50 Ohm heater
            %
            %Inputs:
            %   heaterRange - HeaterRange categorical
            %
            %Outputs:
            %   maxPower - in W

            switch(heaterRange)
                case(this.HeaterRange("Off"));      maxPower = 0;
                case(this.HeaterRange("Low"));      maxPower = 0.5;
                case(this.HeaterRange("Medium"));   maxPower = 5;
                case(this.HeaterRange("High"));     maxPower = 50;
                otherwise
                    error("Lakeshore331:UnsupportedHeaterRange", "%s", "Unsupported heater range in " + this.Name + ": " + string(heaterRange));
            end
        end

        function index = GetHeaterRangeIndex(this, heaterRange)
            %Heater range number used by the RANGE command
            %
            %Inputs:
            %   heaterRange - HeaterRange categorical
            %
            %Outputs:
            %   index - 0 = Off, 1 = Low, 2 = Medium, 3 = High

            switch(heaterRange)
                case(this.HeaterRange("Off"));      index = 0;
                case(this.HeaterRange("Low"));      index = 1;
                case(this.HeaterRange("Medium"));   index = 2;
                case(this.HeaterRange("High"));     index = 3;
                otherwise
                    error("Lakeshore331:UnsupportedHeaterRange", "%s", "Unsupported heater range, should be Off, Low, Medium or High. Was " + string(heaterRange));
            end
        end

    end

end
