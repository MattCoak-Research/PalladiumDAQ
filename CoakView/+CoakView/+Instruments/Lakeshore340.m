classdef Lakeshore340 < CoakView.Core.Instrument
    %Instrument implementation for a Lakeshore 340 temperature controller.
    %Same as a 350, but with only 2 inputs, A and B

    properties(Constant, Access = public)
        FullName = "Lakeshore 340";                             %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = "Ls340";                                         %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Ch_A_Reading;                                           %Measure Temperature (K) or Resistance, or do not measure, for each channel ABCD
        Ch_B_Reading;                                           %Measure Temperature (K) or Resistance, or do not measure, for each channel ABCD
        Ch_A_Name = "Channel A Temperature (K)"                 %Change these to change how the readings are displayed in headers and graph axes
        Ch_B_Name = "Channel B Temperature (K)"                 %Change these to change how the readings are displayed in headers and graph axes
        HeaterResistance = 100;                                 %When instrument is being used to supply heater power, it needs to know the resistance of that external heater (in Ohms) to calculate power.
        ControlChannel;                                         %Channel (A,B) that the heater is regulated by, if using the HeaterControl in ClosedLoop or Zone mode - equivalent to Loop 1 and Loop 2 on a 340
    end

    properties(Access = private)
        DefaultGPIB_Address = 12;           %GPIB address     
    end

    methods

        %% Categoricals
        function catOut = Channel(this, inputStr);          catOut = this.ConvertToCategorical(inputStr, ["A", "B", "None"]); end
        function catOut = ControlMode(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Manual PID", "Zone", "Open Loop", "AutoTune PID", "AutoTune PI", "AutoTune P"]); end
        function catOut = HeaterRange(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Off", "Range 1", "Range 2", "Range 3", "Range 4", "Range 5"]); end
        function catOut = MeasType(this, inputStr);         catOut = this.ConvertToCategorical(inputStr, ["Temperature", "Resistance", "Disabled"]); end

        %% Constructor
        function this = Lakeshore340()
            this.GPIB_Address = this.DefaultGPIB_Address;

            %Make sure to set values for Properties of Categorical type
            %like these
            this.Ch_A_Reading = this.MeasType("Temperature");
            this.Ch_B_Reading = this.MeasType("Temperature");
            this.ControlChannel = this.Channel("A");
        end

        %% CollectHeaterControlSettings
        function [settings, heaterLevelPct, heaterEnabled, heaterPower] = CollectHeaterControlSettings(this)
            settings.ControlMode = this.GetControlMode(this.ControlChannel);
            settings.HeaterRange = this.GetHeaterRange(this.ControlChannel);
            settings.SetPoint = this.GetHeaterSetpoint(this.ControlChannel);
            [settings.RampEnabled, settings.RampRate] = this.GetRamp(this.ControlChannel);
            settings.ManualOutput = this.GetManualOutputPercent(this.ControlChannel);
            [P, I, D] = this.GetPIDValues(this.ControlChannel);
            settings.PID_Settings.P = P;
            settings.PID_Settings.I = I;
            settings.PID_Settings.D = D;

            [heaterLevelPct, heaterEnabled] = this.GetHeaterLevel(this.ControlChannel);
            heaterPower = this.GetHeaterPower();
        end

        %% GetAvailableControlOptions
        function [controlDetailsStructs] = GetAvailableControlOptions(this)
            %Tell the GUI what options for Control GUIs to create
            controlDetailsStructs = struct(...
                "Name", "🕹️ Heater Control",...
                "ControlClassFileName", "LakeshoreHeaterControl",...
                "TabName", this.Name + " Heater Control",...
                "EnabledByDefault", false);
        end
        
        %% GetHeaders
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

        %% GetSupportedConnectionTypes
        function connectionTypes = GetSupportedConnectionTypes(this)
            connectionTypes = [...
                CoakView.Enums.ConnectionType.Debug,...
                CoakView.Enums.ConnectionType.GPIB,...
                CoakView.Enums.ConnectionType.VISA,...
                CoakView.Enums.ConnectionType.Ethernet,...
                CoakView.Enums.ConnectionType.Serial,...
                CoakView.Enums.ConnectionType.USB...
                ];
        end

        %% Measure
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


            %Append heater status columns to the data row
            hterPower = 0;% this.GetHeaterPower();
            dataRow = [dataRow hterPower];
        end

        %% GetTemperature
        function temp = GetTemperature(this, controlChannel)
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetChannelString(controlChannel);
            temp = this.QueryDouble("KRDG? " + channelStr);
        end

        %% GetResistance
        function temp = GetResistance(this, controlChannel)
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetChannelString(controlChannel);
            temp = this.QueryDouble("SRDG? " + channelStr);
        end

        %% GetHeaterPower
        function power = GetHeaterPower(this)
            %Returns heater power, in W, taking into account the entered heater
            %resistance
            level = this.GetHeaterLevel();
            range = this.GetHeaterRange();
            power = this.HeaterResistance * this.GetHeaterPowerPerOhmFromRange(range) * level / 100;    %Level is a percent
        end

        %% GetHeaterLevel
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

        %% GetHeaterRange
        function htrRange = GetHeaterRange(this)

            if(this.SimulationMode)
                htrRange = 2;
            else
                htrRange = this.QueryDouble("RANGE?");
            end
        end

        %% SetHeaterRange
        function SetHeaterRange(this, range)
            %Set the heater range on specified channel (1 or 2, as ints).
            %The range setting has no effect if an output is in the Off mode, and does not apply to an output in Monitor Out mode.
            %range is an int. 0 = Off, 1 = Range 1, 2 = Range 2, 3 = Range 3, 4 = Range 4, 5 = Range 5

            %Convert the heater range enum value into an index
            rangeIdx = this.GetHeaterRangeIndex(range);
            this.WriteCommand("RANGE, " + num2str(rangeIdx));
        end

        %% SetHeaterSetpoint
        function SetHeaterSetpoint(this, setPt)
            %Set a heater setpoint on specified channel
            %Get the selected channel, as a string '0' to '4', from the
            %enum value

            this.WriteCommand("SETP " + num2str(setPt));
        end

        %% GetHeaterSetpoint
        function setPt = GetHeaterSetpoint(this)
            %Get the current heater setpoint value on specified channel.

            if(this.SimulationMode)
                setPt = 25.4;
                return;
            end

            setPt = this.QueryDouble("SETP?");
        end

        %% GetRamp
        function [enabled, rate] = GetRamp(this)
            %Get status (enabled on/off and rate) of ramping on channel/control loop.

            if(this.SimulationMode)
                enabled = true;
                rate = 1.2;
            else
                %Query real values for all other connection types
                result = strsplit(this.QueryString("RAMP?"),',');
                enabled = strcmp(result{1}, '1');
                rate = str2double(result{2});
            end
        end

        %% SetRamp
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

        %% GetSensorReading
        function reading = GetSensorReading(this, controlChannel)
            %Get the currently displayed reading on selected channel (A, B, C,
            %or D). controlChannel should be an LS350_Channel enum member
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetChannelString(controlChannel);
            reading = this.QueryDouble("SRDG? " + channelStr);
        end

        %% SetControlMode
        function SetControlMode(this, controlChannel, controlMode)
            %Set the control mode: Off, Closed Loop PID,
            %Zone, or Open Loop. Channel A B C D to use for control,
            %outputChannel 1 or 2

            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetChannelString(controlChannel);

            modeIndex = this.GetControlModeIndex(controlMode);

            %Write command
            this.WriteCommand("CMODE" + "," + channelStr + "," + num2str(modeIndex));
        end

        %% GetControlMode
        function controlMode = GetControlMode(this, controlChannel)
            %Returns the currently selected control mode, off, closed loop pid,
            %zone, open loop. Channel  A B
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetChannelString(controlChannel);

            if(this.SimulationMode)
                modeIndex = 1;
            else
                modeIndex = this.QueryDouble("CMODE? " + channelStr);
            end

            switch(modeIndex)
                case(0)
                    controlMode = this.ControlMode("Off");  %Is this actually an option on a 340?
                case(1)
                    controlMode = this.ControlMode("Manual PID");
                case(2)
                    controlMode = this.ControlMode("Zone");
                case(3)
                    controlMode = this.ControlMode("Open Loop");
                case(4)
                    controlMode = this.ControlMode("AutoTune PID");
                case(5)
                    controlMode = this.ControlMode("Autotune PI");
                case(6)
                    controlMode = this.ControlMode("Autotune P");
                otherwise
                    error("Control mode error");
            end
        end

        %% SetPIDValues
        function SetPIDValues(this, controlChannel, P, I, D)
            %Set PID Values (numerical inputs)
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetChannelString(controlChannel);

            this.WriteCommand("PID " + channelStr + "," + num2str(P) + "," + num2str(I) + "," + num2str(D));
        end

        %% GetPIDValues
        function [P, I, D] = GetPIDValues(this, controlChannel)
            %Get PID settings
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetChannelString(controlChannel);

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

        %% GetManualOutputPercent
        function output = GetManualOutputPercent(this, controlChannel)
            %Get the manual output setting if active. Channel 1, 2

            channelStr = string(this.GetChannelIndex(controlChannel));

            if(this.SimulationMode)
                %Return dummy value
                output = 78;
                return;
            end

            output = this.QueryDouble("MOUT? " + channelStr);
        end

        %% SetManualOutputPercent
        function SetManualOutputPercent(this, controlChannel, percentage)
            %Set the manual output setting. Channel 1, 2
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = string(this.GetChannelIndex(controlChannel));

            %Check that the value is between 0 and 100
            assert(percentage <= 100 && percentage  >=0, "Invalid output percentage");

            %Write the command
            this.WriteCommand("MOUT " + channelStr + "," + num2str(percentage));
        end
    end

    methods (Access = protected)

        %% ApplySettings
        function ApplySettings(this, settings)
            this.SetControlMode(this.ControlChannel, settings.ControlMode);
            this.SetHeaterRange(this.ControlChannel, settings.HeaterRange);
            this.SetHeaterSetpoint(this.ControlChannel, settings.SetPoint);
            this.SetRamp(this.ControlChannel, settings.RampEnabled, settings.RampRate);

            if(settings.ControlMode == this.ControlMode("Open Loop"))
                this.SetManualOutputPercent(this.ControlChannel, settings.ManualOutput);
            end

            this.SetPIDValues(this.ControlChannel, settings.PID_Settings.P, settings.PID_Settings.I, settings.PID_Settings.D);
        end

    end

    methods (Access = private)

        %% GetChannelIndex
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

        %% GetChannelIndexString
        function channelStr = GetChannelIndexString(this, controlChannel)
            %Turn a Categorical channel property into a string, ready to
            %send to the hardware - A or B
            channelStr = string(this.GetChannelIndex(controlChannel));
        end

        %% GetChannelString
        function channelStr = GetChannelString(~, controlChannel)
            %Turn a Categorical channel property into the channel index, as
            %a string, ready to send to the hardware. 0 or 1 etc, for e.g.
            %heater channels
            channelStr = string(controlChannel);
        end

        %% GetControlModeIndex
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

        %% GetHeaterPowerPerOhmFromRange
        function powerPerOhm = GetHeaterPowerPerOhmFromRange(this, heaterRangeIdx)
            %Needs testing!
            switch(heaterRangeIdx)
                case(this.GetHeaterRangeIndex(this.HeaterRange("Off")))
                    powerPerOhm = 0;
                case(this.GetHeaterRangeIndex(this.HeaterRange("Range 1")))
                    powerPerOhm = 75e-5;
                case(this.GetHeaterRangeIndex(this.HeaterRange("Range 2")))
                    powerPerOhm = 0.75e-2;
                case(this.GetHeaterRangeIndex(this.HeaterRange("Range 3")))
                    powerPerOhm = 7.5e-2;
                case(this.GetHeaterRangeIndex(this.HeaterRange("Range 4")))
                    powerPerOhm = 75e-2;
                case(this.GetHeaterRangeIndex(this.HeaterRange("Range 5")))
                    powerPerOhm = 7.5;  %%??? Test!
                otherwise
                    error("Unsupported heater range index in LS340: " + string(heaterRangeIdx));
            end
        end

        %% GetHeaterRangeIndex
        function index = GetHeaterRangeIndex(this, heaterRangeEnumVal)
            switch(heaterRangeEnumVal)
                case(this.HeaterRange("Off"))
                    index = 0;
                case(this.HeaterRange("Range 1"))
                    index = 1;
                case(this.HeaterRange("Range 2"))
                    index = 2;
                case(this.HeaterRange("Range 3"))
                    index = 3;
                case(this.HeaterRange("Range 4"))
                    index = 4;
                case(this.HeaterRange("Range 5"))
                    index = 5;
                otherwise
                    error("Unsupported channel, should be Off, Closed Loop PID, Zone, Open Loop, Monitor Out or Warmup Supply, was " + string(heaterRangeEnumVal));
            end
        end

    end

end

