classdef Lakeshore350 < CoakView.Core.Instrument
    %Instrument implementation for a Lakeshore 350 temperature controller.

    properties(Constant, Access = public)
        FullName = "Lakeshore 350";                             %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = "Ls350";                                         %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Ch_A_Reading;                                           %Measure Temperature (K) or Resistance, or do not measure, for each channel ABCD
        Ch_B_Reading;                                           %Measure Temperature (K) or Resistance, or do not measure, for each channel ABCD
        Ch_C_Reading;                                           %Measure Temperature (K) or Resistance, or do not measure, for each channel ABCD
        Ch_D_Reading;                                           %Measure Temperature (K) or Resistance, or do not measure, for each channel ABCD
        Ch_A_Name = "Channel A Temperature (K)"                 %Change these to change how the readings are displayed in headers and graph axes
        Ch_B_Name = "Channel B Temperature (K)"                 %Change these to change how the readings are displayed in headers and graph axes
        Ch_C_Name = "Channel C Temperature (K)"                 %Change these to change how the readings are displayed in headers and graph axes
        Ch_D_Name = "Channel D Temperature (K)"                 %Change these to change how the readings are displayed in headers and graph axes
        HeaterResistance = 100;                                 %When instrument is being used to supply heater power, it needs to know the resistance of that external heater (in Ohms) to calculate power.
        HeaterChannel;                                          %Channel (1 or 2) that the heater is connected to, if using the HeaterControl
        ControlChannel;                                         %Channel (A,B,C,D) that the heater is regulated by, if using the HeaterControl in ClosedLoop or Zone mode
    end

    properties(Access = private)
        DefaultGPIB_Address = 12;                               %GPIB address
    end

    methods

        %% Categoricals
        function catOut = Channel(this, inputStr);          catOut = this.ConvertToCategorical(inputStr, ["A", "B", "C", "D", "None"]); end
        function catOut = ControlMode(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Off", "Closed Loop PID", "Zone", "Open Loop", "Monitor Out", "Warmup Supply"]); end
        function catOut = HeaterRange(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Off", "Range 1", "Range 2", "Range 3", "Range 4", "Range 5"]); end
        function catOut = MeasType(this, inputStr);         catOut = this.ConvertToCategorical(inputStr, ["Temperature", "Resistance", "Disabled"]); end
        function catOut = OutputChannel(this, inputStr);    catOut = this.ConvertToCategorical(inputStr, ["Ch1", "Ch2"]); end

        %% Constructor
        function this = Lakeshore350()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = this.DefaultGPIB_Address;

            %Define the Instrument Controls that can be added 
            this.DefineInstrumentControl(Name = "🕹️ Heater Control", ClassName = "LakeshoreHeaterControl", TabName = "Heater Control", EnabledByDefault = true);
     
            %Make sure to set values for Properties of Categorical type
            %like these
            this.Ch_A_Reading = this.MeasType("Temperature");
            this.Ch_B_Reading = this.MeasType("Temperature");
            this.Ch_C_Reading = this.MeasType("Temperature");
            this.Ch_D_Reading = this.MeasType("Temperature");
            this.ControlChannel = this.Channel("A");
            this.HeaterChannel = this.OutputChannel("Ch1");
        end

        %% CollectHeaterControlSettings
        function [settings, heaterLevelPct, heaterEnabled, heaterPower] = CollectHeaterControlSettings(this)
            settings.ControlMode = this.GetControlMode(this.HeaterChannel);
            settings.HeaterRange = this.GetHeaterRange(this.HeaterChannel);
            settings.SetPoint = this.GetHeaterSetpoint(this.HeaterChannel);
            [settings.RampEnabled, settings.RampRate] = this.GetRamp(this.HeaterChannel);
            settings.ManualOutput = this.GetManualOutputPercent(this.HeaterChannel);
            [P, I, D] = this.GetPIDValues(this.HeaterChannel);
            settings.PID_Settings.P = P;
            settings.PID_Settings.I = I;
            settings.PID_Settings.D = D;

            [heaterLevelPct, heaterEnabled] = this.GetHeaterLevel(this.HeaterChannel);
            heaterPower = this.GetHeaterPower(this.HeaterChannel);
        end
  
        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
            Headers = [];
            Units = [];

            Headers = [Headers, string(this.Ch_A_Name), "ResChA", string(this.Ch_B_Name), "ResChB", string(this.Ch_C_Name), "ResChC", string(this.Ch_D_Name), "ResChD"];
            Units = [Units, "K", "Ohms", "K", "Ohms", "K", "Ohms", "K", "Ohms"];

            % Add columns for heater control data too
            Headers = [Headers, this.Name + " Heater Power (W)"];
            Units = [Units, "W"];
        end

        %% Measure
        function [dataRow] = Measure(this)
            dataRow = [];
            %Query all parameters
            [T_A, T_B, T_C, T_D] = this.GetTemperatureAllChannels();
            [R_A, R_B, R_C, R_D] = this.GetResistanceAllChannels();

            %Append data to the table
            dataRow = [dataRow, T_A, R_A, T_B, R_B, T_C, R_C, T_D, R_D];

            %Append heater status columns to the data row
            hterPower = this.GetHeaterPower(this.HeaterChannel);
            dataRow = [dataRow hterPower];
        end

        %% GetTemperature
        function temp = GetTemperature(this, controlChannel)
            arguments
                this;
                controlChannel {mustBeTextScalar, mustBeMember(controlChannel, ["A","B","C","D"])};
            end

            if this.SimulationMode
                %Dummy values
                temp = 273 + rand()*1;
                return;
            end

            %Note - using this.QueryDouble didn't work properly here, not
            %sure why. Gave garbled badly parsed numbers
            data = query(this.DeviceHandle, "KRDG? " + controlChannel);
            temp = str2double(data);
        end

        %% GetTemperatureAllChannels
        function [T_ChA, T_ChB, T_ChC, T_ChD] = GetTemperatureAllChannels(this)
            if this.SimulationMode
                %Dummy values
                T_ChA = this.GetTemperature("A");
                T_ChB = this.GetTemperature("B");
                T_ChC = this.GetTemperature("C");
                T_ChD = this.GetTemperature("D");
                return;
            end

            data = query(this.DeviceHandle, "KRDG? 0");

            %Parse string
            vals = strsplit(data, ",");
            if length(vals) ~= 4
                %This is handling an error - some (older??) LS350s don't
                %return all readings on a KRDG 0 Query. Vals will not be 4
                %strings and the code will break. Instead, just perform 4
                %discrete GetTemperature calls
                T_ChA = this.GetTemperature("A");
                T_ChB = this.GetTemperature("B");
                T_ChC = this.GetTemperature("C");
                T_ChD = this.GetTemperature("D");
            else
                %Normal (faster, expected) execution branch - just parse
                %the split string from previous single query
                T_ChA = str2double(vals{1});
                T_ChB = str2double(vals{2});
                T_ChC = str2double(vals{3});
                T_ChD = str2double(vals{4});
            end
        end

        %% GetResistance
        function res = GetResistance(this, controlChannel)
            arguments
                this;
                controlChannel {mustBeTextScalar, mustBeMember(controlChannel, ["A","B","C","D"])};
            end

            if this.SimulationMode
                %Dummy values
                res = 160 + rand()*3;
                return;
            end

            %Note - using this.QueryDouble didn't work properly here, not
            %sure why. Gave garbled badly parsed numbers
            data = query(this.DeviceHandle, "SRDG? " + controlChannel);
            res = str2double(data);
        end

        %% GetResistanceAllChannels
        function [R_ChA, R_ChB, R_ChC, R_ChD] = GetResistanceAllChannels(this)

            if this.SimulationMode
                %Dummy values
                R_ChA = this.GetResistance("A");
                R_ChB = this.GetResistance("B");
                R_ChC = this.GetResistance("C");
                R_ChD = this.GetResistance("D");
                return;
            end

            data = query(this.DeviceHandle, "SRDG? 0");

            %Parse string
            vals = strsplit(data, ",");
            if length(vals) ~= 4
                %This is handling an error - some (older??) LS350s don't
                %return all readings on a KRDG 0 Query. Vals will not be 4
                %strings and the code will break. Instead, just perform 4
                %discrete GetTemperature calls
                R_ChA = this.GetResistance("A");
                R_ChB = this.GetResistance("B");
                R_ChC = this.GetResistance("C");
                R_ChD = this.GetResistance("D");
            else
                R_ChA = str2double(vals{1});
                R_ChB = str2double(vals{2});
                R_ChC = str2double(vals{3});
                R_ChD = str2double(vals{4});
            end
        end

        %% GetHeaterPower
        function power = GetHeaterPower(this, heaterChannel)
            %Returns heater power, in W, taking into account the entered heater
            %resistance
            level = this.GetHeaterLevel(heaterChannel);
            range = this.GetHeaterRange(heaterChannel);
            power = this.HeaterResistance * this.GetHeaterPowerPerOhmFromRange(range) * level / 100;    %Level is a percent
        end

        %% GetHeaterLevel
        function [htrLevel, htrEnabled] = GetHeaterLevel(this, heaterChannel)
            %Returns the heater output, in %, and if it is currently on.
            %HeaterChannel should be an LS350_HeaterChannel enum
            %Convert the heaterChannel enum or str into the '1' or '2' the
            %instrument expects.

            if(this.SimulationMode)
                %Dummy values
                htrLevel = 60 + rand()*3;
                htrEnabled = true;
                return;
            end

            htrChannelStr = num2str(this.GetHeaterChannelIndex(heaterChannel));

            %Query heater output level
            htrLevel = this.QueryDouble("HTR? " + htrChannelStr);

            %Check if the heater is in 'Off' range or not
            htrRange = this.GetHeaterRange(heaterChannel);
            if(htrRange == 0)
                htrEnabled = false;
            else
                htrEnabled = true;
            end
        end

        %% GetHeaterRange
        function htrRange = GetHeaterRange(this, outputChannel)
            %Returns the int signifying the range currently selected
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetHeaterChannelIndex(outputChannel);

            if(this.SimulationMode)
                htrRange = 2;
            else
                htrRange = this.QueryDouble("RANGE? " + channelStr);
            end
        end

        %% SetHeaterRange
        function SetHeaterRange(this, heaterChannel, range)
            %Set the heater range on specified channel (1 or 2, as ints).
            %The range setting has no effect if an output is in the Off mode, and does not apply to an output in Monitor Out mode.
            %range is an int. 0 = Off, 1 = Range 1, 2 = Range 2, 3 = Range 3, 4 = Range 4, 5 = Range 5

            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetHeaterChannelIndex(heaterChannel);

            %Convert the heater range enum value into an index
            rangeIdx = this.GetHeaterRangeIndex(range);

            this.WriteCommand("RANGE " + channelStr + "," + num2str(rangeIdx));
        end

        %% SetHeaterSetpoint
        function SetHeaterSetpoint(this, heaterChannel, setPt)
            %Set a heater setpoint on specified channel
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetHeaterChannelIndex(heaterChannel);

            this.WriteCommand("SETP " + channelStr + "," + num2str(setPt));
        end

        %% GetHeaterSetpoint
        function setPt = GetHeaterSetpoint(this, heaterChannel)
            %Get the current heater setpoint value on specified channel. controlChannel should be an LS350_Channel enum member

            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetHeaterChannelIndex(heaterChannel);

            if(this.SimulationMode)
                setPt = 25.4;
                return;
            end

            setPt = this.QueryDouble("SETP? " + channelStr);
        end

        %% GetRamp
        function [enabled, rate] = GetRamp(this, heaterChannel)
            %Get status (enabled on/off and rate) of ramping on channel/control loop.
            %controlChannel should be an LS350_Channel enum member
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetHeaterChannelIndex(heaterChannel);

            if(this.SimulationMode)
                enabled = true;
                rate = 1.2;
            else
                %Query real values for all other connection types
                result = strsplit(this.QueryString("RAMP? " + channelStr),',');
                enabled = strcmp(result{1}, '1');
                rate = str2double(result{2});
            end
        end

        %% SetRamp
        function SetRamp(this, outputChannel, enabled, rate)
            %Set status (enabled on/off and rate) of ramping on channel/control loop.
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetHeaterChannelIndex(outputChannel);

            if(enabled)
                enabledStr = "1";
            else
                enabledStr = "0";
            end

            this.WriteCommand("RAMP " + channelStr + "," + enabledStr + "," + num2str(rate));
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
        function SetControlMode(this, outputChannel, controlChannel, controlMode)
            %Set the control mode: Off, Closed Loop PID,
            %Zone, or Open Loop. Channel A B C D to use for control,
            %outputChannel 1 or 2
            %Convert the heaterChannel enum or str into the '1' or '2' the
            %instrument expects.
            %Call like this: l.SetControlMode("Ch1", "A", "Open Loop")
            htrChannelStr = num2str(this.GetHeaterChannelIndex(outputChannel));

            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetChannelString(controlChannel);

            modeIndex = this.GetControlModeIndex(controlMode);
            powerupEnable = "1";

            %Write command
            this.WriteCommand("OUTMODE " + htrChannelStr + "," + num2str(modeIndex) + "," + channelStr + "," + powerupEnable);
        end

        %% GetControlMode
        function controlMode = GetControlMode(this, ouputChannel)
            %Returns the currently selected control mode, off, closed loop pid,
            %zone, open loop. Channel

            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetHeaterChannelIndex(ouputChannel);

            if(this.SimulationMode)
                modeIndex = 1;
            else
                results = strsplit(this.QueryString("OUTMODE? " + channelStr), ',');
                modeIndex = str2double(results{1});
            end

            switch(modeIndex)
                case(0)
                    controlMode = this.ControlMode("Off");
                case(1)
                    controlMode = this.ControlMode("Closed Loop PID");
                case(2)
                    controlMode = this.ControlMode("Zone");
                case(3)
                    controlMode = this.ControlMode("Open Loop");
                case(4)
                    controlMode = this.ControlMode("Monitor Out");
                case(5)
                    controlMode = this.ControlMode("Warmup Supply");
                otherwise
                    error("Control mode error");
            end
        end

        %% SetPIDValues
        function SetPIDValues(this, heaterChannel, P, I, D)
            %Set PID Values (numerical inputs)
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = this.GetHeaterChannelIndex(heaterChannel);

            this.WriteCommand("PID " + channelStr + "," + num2str(P) + "," + num2str(I) + "," + num2str(D));
        end

        %% GetPIDValues
        function [P, I, D] = GetPIDValues(this, heaterChannel)
            %Get PID settings
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
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

        %% GetManualOutputPercent
        function output = GetManualOutputPercent(this, heaterChannel)
            %Get the manual output setting if active. Channel 1, 2
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = num2str(this.GetHeaterChannelIndex(heaterChannel));

            if(this.SimulationMode)
                %Return dummy value
                output = 78;
                return;
            end

            output = this.QueryDouble("MOUT? " + channelStr);
        end

        %% SetManualOutputPercent
        function SetManualOutputPercent(this, heaterChannel, percentage)
            %Set the manual output setting. Channel 1, 2
            %Get the selected channel, as a string '0' to '4', from the
            %enum value
            channelStr = num2str(this.GetHeaterChannelIndex(heaterChannel));

            %Check that the value is between 0 and 100
            assert(percentage <= 100 && percentage  >=0, "Invalid output percentage");

            %Write the command
            this.WriteCommand("MOUT " + channelStr + "," + num2str(percentage));
        end
    end

    methods (Access = protected)

        %% ApplySettings
        function ApplySettings(this, settings)
            this.SetControlMode(this.HeaterChannel, this.ControlChannel, settings.ControlMode);
            this.SetHeaterRange(this.HeaterChannel, settings.HeaterRange);
            this.SetHeaterSetpoint(this.HeaterChannel, settings.SetPoint);
            this.SetRamp(this.HeaterChannel, settings.RampEnabled, settings.RampRate);

            if(settings.ControlMode == this.ControlMode("Open Loop"))
                this.SetManualOutputPercent(this.HeaterChannel, settings.ManualOutput);
            end

            %Update PID values
            this.SetPIDValues(this.HeaterChannel, settings.PID_Settings.P, settings.PID_Settings.I, settings.PID_Settings.D);
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
                case(this.Channel("C"))
                    channelIndex = 3;
                case(this.Channel("D"))
                    channelIndex = 4;
                otherwise
                    error("Unsupported channel, should be None, A, B, C or D, was " + string(channel));
            end
        end

        %% GetChannelString
        function channelStr = GetChannelString(this, controlChannel)
            %Turn a Categorical channel property into the channel index, as
            %a string, ready to send to the hardware
            channelStr = string(this.GetChannelIndex(controlChannel));
        end


        %% GetControlModeIndex
        function index = GetControlModeIndex(this, controlMode)
            switch(controlMode)
                case (this.ControlMode("Off"))
                    index = 0;
                case(this.ControlMode("Closed Loop PID"))
                    index = 1;
                case(this.ControlMode("Zone"))
                    index = 2;
                case(this.ControlMode("Open Loop"))
                    index = 3;
                case(this.ControlMode("Monitor Out"))
                    index = 4;
                case(this.ControlMode("Warmup Supply"))
                    index = 5;
                otherwise
                    error("Unsupported channel, should be Off, Closed Loop PID, Zone, Open Loop, Monitor Out or Warmup Supply, was " + string(controlMode));
            end
        end

        %% GetHeaterChannelIndex
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
                    error("Unsupported heater range index in LS350: " + string(heaterRangeIdx));
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

