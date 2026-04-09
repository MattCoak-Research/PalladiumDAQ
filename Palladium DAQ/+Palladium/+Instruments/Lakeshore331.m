classdef Lakeshore331 < Palladium.Core.Instrument
    %Instrument implementation for a Lakeshore 331 temperature controller.

    %% Properties (Constant, Public)
    properties(Constant, Access = public)
        FullName = "Lakeshore 331";                             %Full name, just for displaying on GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "Ls331";                                         %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;                 %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Ch_A_Reading;              %Measure Temperature (K) or Resistance, or do not measure, for each channel ABCD
        Ch_B_Reading;              %Measure Temperature (K) or Resistance, or do not measure, for each channel ABCD
        Ch_A_Name = "Channel A Temperature (K)"                 %Change these to change how the readings are displayed in headers and graph axes
        Ch_B_Name = "Channel B Temperature (K)"                 %Change these to change how the readings are displayed in headers and graph axes
        HeaterResistance = 100;                                 %When instrument is being used to supply heater power, it needs to know the resistance of that external heater (in Ohms) to calculate power.
        ControlChannel; %Channel (A,B) that the heater is regulated by, if using the HeaterControl in ClosedLoop or Zone mode - equivalent to Loop 1 and Loop 2 on a 340
    end

    %% Properties (Public)
    properties(Access = public)
        HeaterChannel = "Ch1";                                          %Channel (1 or 2) that the heater is connected to, if using the HeaterControl
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
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = 12;      %Default Address

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

        function controlMode = GetControlMode(this)
            %Returns the currently selected control mode, off, closed loop pid,
            %zone, open loop. Channel

            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetChannelIndex(this.ControlChannel);

            if(this.SimulationMode)
                modeIndex = 1;
            else
                results = this.QueryString("CMODE? " + channelStr);
                modeIndex = str2double(results);
            end

            switch(modeIndex)
                case(0)
                    controlMode = this.ControlMode("Off");
                case(1)
                    controlMode = this.ControlMode("Manual PID");
                case(2)
                    controlMode = this.ControlMode("Zone");
                case(3)
                    controlMode = this.ControlMode("Open Loop");
                case(4)
                    controlMode = this.ControlMode("AutoTune PID");
                case(5)
                    controlMode = this.ControlMode("AutoTune PI");
                case(6)
                    controlMode = this.ControlMode("AutoTune P");
                otherwise
                    error("Control mode error");
            end
        end

        function [Headers, Units] = GetHeaders(this)
            Headers = [];
            Units = [];
            %Check each channel, add some headers if it isnt disabled
            switch(this.Ch_A_Reading)
                case(this.MeasType("Temperature"))
                    Headers = [Headers string(this.Ch_A_Name)];
                    Units = [Units "K"];
                case(this.MeasType("Resistance"))
                    Headers = [Headers "Ch A Resistance (Ohms)"];
                    Units = [Units "Ohms"];
            end
            switch(this.Ch_B_Reading)
                case(this.MeasType("Temperature"))
                    Headers = [Headers string(this.Ch_B_Name)];
                    Units = [Units "K"];
                case(this.MeasType("Resistance"))
                    Headers = [Headers "Ch B Resistance (Ohms)"];
                    Units = [Units "Ohms"];
            end

            % Add columns for heater control data too, if heater control is
            % enabled
            Headers = [Headers, this.Name + " Heater Power (W)"];
            Units = [Units, "W"];
        end

        function [htrLevel, htrEnabled] = GetHeaterLevel(this)
            %Returns the heater output, in %, and if it is currently on.

            if(this.SimulationMode)
                %Dummy values
                htrLevel = 60 + rand()*3;
                htrEnabled = true;
                return;
            end

            %Query heater output level
            htrLevel = this.QueryDouble("HTR?");

            %Check if the heater is in 'Off' range or not
            htrRange = this.GetHeaterRange();

            %Convert the heater range enum value for 'Off' into an index to
            %compare to
            offRangeIdx = this.GetHeaterRangeIndex(this.HeaterRange("Off"));

            if(htrRange == offRangeIdx)
                htrEnabled = false;
            else
                htrEnabled = true;
            end
        end

        function power = GetHeaterPower(this)
            %Returns heater power, in W, taking into account the entered heater
            %resistance
            level = this.GetHeaterLevel();
            range = this.GetHeaterRange();
            power = this.HeaterResistance * this.GetHeaterPowerPerOhmFromRange(range) * level / 100;    %Level is a percent
        end

        function htrRange = GetHeaterRange(this)

            if(this.SimulationMode)
                htrRange = 2;
            else
                %0 = Off, 1 = Low (0.5 W), 2 = Medium (5 W), 3 = High (50 W)
                htrRange = this.QueryDouble("RANGE?");
            end
        end

        function setPt = GetHeaterSetpoint(this)
            %Get the current heater setpoint value on specified channel.

            if(this.SimulationMode)
                setPt = 25.4;
                return;
            end

            loop = this.GetChannelIndexString(this.ControlChannel); %Specifies which loop to query: 1 or 2.
            setPt = this.QueryDouble("SETP? " + loop);
        end

        function output = GetManualOutputPercent(this)
            %Get the manual output setting if active. Channel 1, 2
            
            loop = this.GetChannelIndexString(this.ControlChannel); %Specifies which loop to query: 1 or 2.

            if(this.SimulationMode)
                %Return dummy value
                output = 78;
                return;
            end

            output = this.QueryDouble("MOUT? " + loop);
        end

        function [P, I, D] = GetPIDValues(this)
            %Get PID settings
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            loop = this.GetChannelIndexString(this.ControlChannel); %Specifies which loop to query: 1 or 2.

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
            %Get status (enabled on/off and rate) of ramping on channel/control loop.

            if(this.SimulationMode)
                enabled = true;
                rate = 1.2;
            else
                %Query real values for all other connection types
                loop = this.GetChannelIndexString(this.ControlChannel); %Specifies which loop to query: 1 or 2.
                result = strsplit(this.QueryString("RAMP? " + loop),',');
                enabled = strcmp(result{1}, '1');
                rate = str2double(result{2});
            end
        end

        function temp = GetResistance(this, channel)
            %Get the selected channel, as a string 'A' or 'B', from the
            %enum value
            channelStr = this.GetChannelString(channel);
            temp = this.QueryDouble("SRDG? " + channelStr);
        end

        function reading = GetSensorReading(this, channel)
            %Get the currently displayed reading on selected channel (A, B, C,
            %or D). controlChannel should be an LS331_Channel enum member
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetChannelString(channel);
            reading = this.QueryDouble("SRDG? " + channelStr);
        end

        function temp = GetTemperature(this, controlChannel)
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetChannelString(controlChannel);
            temp = this.QueryDouble("KRDG? " + channelStr);
        end

        function [dataRow] = Measure(this)
            dataRow = [];
            %Query all parameters
            switch(this.Ch_A_Reading)
                case(this.MeasType("Temperature"))
                    dataRow = [dataRow this.GetTemperature(this.Channel("A"))];
                case(this.MeasType("Resistance"))
                    dataRow = [dataRow this.GetResistance(this.Channel("A"))];
            end
            switch(this.Ch_B_Reading)
                case(this.MeasType("Temperature"))
                    dataRow = [dataRow this.GetTemperature(this.Channel("B"))];
                case(this.MeasType("Resistance"))
                    dataRow = [dataRow this.GetResistance(this.Channel("B"))];
            end

            hterPower = this.GetHeaterPower();
            dataRow = [dataRow hterPower];
        end

        function SetControlMode(this, controlMode)
            %Set the control mode: Off, Closed Loop PID,          

            loop = this.GetChannelIndexString(this.ControlChannel); %Specifies which loop to query: 1 or 2.
            modeIndex = this.GetControlModeIndex(controlMode);

            %Write command
            this.WriteCommand("CMODE " + loop + "," + num2str(modeIndex));
        end

        function SetHeaterRange(this, range)
            %Set the heater range on specified channel (1 or 2, as ints).
            %The range setting has no effect if an output is in the Off mode, and does not apply to an output in Monitor Out mode.
            %range is an int. 0 = Off, 1 = Range 1, 2 = Range 2, 3 = Range 3, 4 = Range 4, 5 = Range 5

            %Convert the heater range enum value into an index
            rangeIdx = this.GetHeaterRangeIndex(range);
            this.WriteCommand("RANGE, " + num2str(rangeIdx));
        end

        function SetHeaterSetpoint(this, setPt)
            %Set a heater setpoint on specified channel
            %Get the selected channel, as a string '0' to '4', from the
            %enum value

            this.WriteCommand("SETP " + num2str(setPt));
        end

        function SetManualOutputPercent(this, percentage)
            %Set the manual output setting. 

            loop = this.GetChannelIndexString(this.ControlChannel); %Specifies which loop to query: 1 or 2.

            %Check that the value is between 0 and 100
            assert(percentage <= 100 && percentage  >=0, "Invalid output percentage");

            %Write the command
            this.WriteCommand("MOUT " + loop + "," + num2str(percentage));
        end

        function SetPIDValues(this, P, I, D)
            %Set PID Values (numerical inputs)
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            loop = this.GetChannelIndexString(this.ControlChannel); %Specifies which loop to query: 1 or 2.

            this.WriteCommand("PID " + loop + "," + num2str(P) + "," + num2str(I) + "," + num2str(D));
        end

        function SetRamp(this, enabled, rate)
            %Set status (enabled on/off and rate) of ramping on channel/control loop.
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            if(enabled)
                enabledStr = "1";
            else
                enabledStr = "0";
            end

            this.WriteCommand("RAMP " + "," + enabledStr + "," + num2str(rate));
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function ApplySettings(this, settings)
            this.SetControlMode(settings.ControlMode);
            this.SetHeaterRange(settings.HeaterRange);
            this.SetHeaterSetpoint(settings.SetPoint);
            this.SetRamp(settings.RampEnabled, settings.RampRate);

            if(settings.ControlMode == this.ControlMode("Open Loop"))
                this.SetManualOutputPercent(settings.ManualOutput);
            end

            %Update PID values
            this.SetPIDValues(settings.PID_Settings.P, settings.PID_Settings.I, settings.PID_Settings.D);
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function channelIndex = GetChannelIndex(this, channel)
            %The lakeshore wants a number for the channel, not ABCD
            switch(channel)
                case(this.Channel("None"))
                    channelIndex = 0;
                case(this.Channel("A"))
                    channelIndex = 1;
                case(this.Channel("B"))
                    channelIndex = 2;
                otherwise
                    error("Unsupported channel, should be None, A, B, was " + string(channel));
            end
        end

        function channelStr = GetChannelIndexString(this, controlChannel)
            %Turn a Categorical channel property into a string, ready to
            %send to the hardware - A or B
            channelStr = string(this.GetChannelIndex(controlChannel));
        end

        function channelStr = GetChannelString(~, controlChannel)
            %Turn a Categorical channel property into the channel index, as
            %a string, ready to send to the hardware. 0 or 1 etc, for e.g.
            %heater channels
            channelStr = string(controlChannel);
        end

        function index = GetControlModeIndex(this, controlMode)
            switch(controlMode)
                case (this.ControlMode("Manual PID"))
                    index = 0;
                case(this.ControlMode("Zone"))
                    index = 1;
                case(this.ControlMode("Open Loop"))
                    index = 2;
                case(this.ControlMode("AutoTune PID"))
                    index = 3;
                case(this.ControlMode("AutoTune PI"))
                    index = 4;
                case(this.ControlMode("AutoTune P"))
                    index = 5;
                otherwise
                    error("Unsupported channel, should be Off, Closed Loop PID, Zone, Open Loop, Monitor Out or Warmup Supply, was " + string(controlMode));
            end
        end

        function channelIndex = GetHeaterChannelIndex(this, heaterChannel)
            %The lakeshore wants a number for the channel, not Ch1, Ch2
            switch(heaterChannel)
                case(this.OutputChannel("Ch1"))
                    channelIndex = 1;
                case(this.OutputChannel("Ch2"))
                    channelIndex = 2;
                otherwise
                    error("Unsupported channel, should be Ch1 or Ch2, was " + string(heaterChannel));
            end
        end

        function powerPerOhm = GetHeaterPowerPerOhmFromRange(this, heaterRangeIdx)
            %Needs testing!
            % 0 = Off, 1 = Low (0.5 W), 2 = Medium (5 W), 3 = High (50 W) -
            % assuming 50 Ohms
            switch(heaterRangeIdx)
                case(this.GetHeaterRangeIndex(this.HeaterRange("Off")))
                    powerPerOhm = 0;
                case(this.GetHeaterRangeIndex(this.HeaterRange("Low")))
                    powerPerOhm = 0.5 / 50;
                case(this.GetHeaterRangeIndex(this.HeaterRange("Medium")))
                    powerPerOhm = 5 / 50;
                case(this.GetHeaterRangeIndex(this.HeaterRange("High")))
                    powerPerOhm = 50 / 50;
                otherwise
                    error("Unsupported heater range index in LS331: " + string(heaterRangeIdx));
            end
        end

        function index = GetHeaterRangeIndex(this, heaterRangeEnumVal)
            switch(heaterRangeEnumVal)
                case(this.HeaterRange("Off"))
                    index = 0;
                case(this.HeaterRange("Low"))
                    index = 1;
                case(this.HeaterRange("Medium"))
                    index = 2;
                case(this.HeaterRange("High"))
                    index = 3;
                otherwise
                    error("Unsupported heater, should be Off, Low, Medium or High. Was " + string(heaterRangeEnumVal));
            end
        end

    end

end

