classdef Lakeshore331 < CoakView.Core.Instrument
    %Instrument implementation for a Lakeshore 331 temperature controller.

    properties(Constant, Access = public)
        FullName = "Lakeshore 331";                             %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = "Ls331";                                         %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.GPIB;                 %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Ch_A_Reading;              %Measure Temperature (K) or Resistance, or do not measure, for each channel ABCD
        Ch_B_Reading;              %Measure Temperature (K) or Resistance, or do not measure, for each channel ABCD
        Ch_A_Name = "Channel A Temperature (K)"                 %Change these to change how the readings are displayed in headers and graph axes
        Ch_B_Name = "Channel B Temperature (K)"                 %Change these to change how the readings are displayed in headers and graph axes
        HeaterResistance = 100;                                 %When instrument is being used to supply heater power, it needs to know the resistance of that external heater (in Ohms) to calculate power.
        ControlChannel; %Channel (A,B) that the heater is regulated by, if using the HeaterControl in ClosedLoop or Zone mode - equivalent to Loop 1 and Loop 2 on a 340
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
        function this = Lakeshore331()
            this.GPIB_Address = this.DefaultGPIB_Address;

            %Make sure to set values for Properties of Categorical type
            %like these
            this.Ch_A_Reading = this.MeasType("Temperature");
            this.Ch_B_Reading = this.MeasType("Temperature");
            this.ControlChannel = this.Channel("A");
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

            hterPower = this.GetHeaterPower();  
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

