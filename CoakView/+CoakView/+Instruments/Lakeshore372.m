classdef Lakeshore372 < CoakView.Core.Instrument
    %Instrument implementation for a Lakeshore 372 temperature controller.

    properties(Constant, Access = public)
        FullName = "Lakeshore 372";                             %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = "Ls372";                                         %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Ch_Name = "Sample Temperature (K)";                     %Change these to change how the readings are displayed in headers and graph axes
        Reading;                                                %Measure Temperature (K) or Resistance.
        HeaterResistance = 100;                                 %When instrument is being used to supply heater power, it needs to know the resistance of that external heater (in Ohms) to calculate power.
    end  

    properties(Access = private)
        DefaultGPIB_Address = 11;           %GPIB address
    end

    methods

        %% Categoricals
        function catOut = MeasType(this, inputStr);     catOut = this.ConvertToCategorical(inputStr, ["Temperature", "Resistance"]); end
        function catOut = HeaterRange(this, inputStr);  catOut = this.ConvertToCategorical(inputStr, ["Off (0)", "32 muA (1)", "100 muA (2)", "316 muA (3)", "  1 mA (4)", "  3 mA (5)", " 10 mA (6)", " 32 mA (7)", "100 mA (8)"]); end
        function catOut = ControlMode(this, inputStr);  catOut = this.ConvertToCategorical(inputStr, ["Closed Loop PID", "Zone", "Open Loop", "Off"]); end
    
        %% Constructor
        function this = Lakeshore372()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = this.DefaultGPIB_Address;

            %Define the Instrument Controls that can be added 
            this.DefineInstrumentControl(Name = "🕹️ Heater Control", ClassName = "LakeshoreHeaterControl", TabName = "Heater Control", EnabledByDefault = true);
     
            %Make sure to set values for Properties of Categorical type
            %like these
            this.Reading = this.MeasType("Temperature");
        end

        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
            Headers = [];
            Units = [];
            
            switch(this.Reading)
                case(this.MeasType("Temperature"))
                    Headers = [Headers, this.Ch_Name, this.Name + " - Resistance (Ohms)"];
                    Units = [Units "K" "Ohms"];
                case(this.MeasType("Resistance"))
                    Headers = [Headers, this.Name + " - Resistance (Ohms)"];
                    Units = [Units "Ohms"];
            end

            % Add columns for heater control data too
            Headers = [Headers, this.Name + " Heater Power (W)"];
            Units = [Units, "W"];
        end

        %% Measure
        function [dataRow] = Measure(this)
            dataRow = [];
            %Query all parameters
            switch(this.Reading)
                case(this.MeasType("Temperature"))
                    dataRow = [dataRow this.GetTemperature(), dataRow this.GetResistance()];
                case(this.MeasType("Resistance"))
                    dataRow = [dataRow this.GetResistance()];
                otherwise
                    error("Unsupported measurement type " + string(this.Reading));
            end

            %Append heater status columns to the data row
            hterPower = this.GetHeaterPower();
            dataRow = [dataRow hterPower];
        end     

        %% CollectHeaterControlSettings
        function [settings, heaterLevelPct, heaterEnabled, heaterPower] = CollectHeaterControlSettings(this)
            %This is all the same as for the LS350.. except as there is
            %only one channel we don't need to tell each function which
            %channel to measure
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

        %% GetTemperature
        function temp = GetTemperature(this)
            if this.SimulationMode
                temp = 24.6 + 0.05*rand();
            else
                temp = this.QueryDouble("RDGK?1");
            end
        end

        %% GetResistance
        function res = GetResistance(this)
            if this.SimulationMode
                res = 1024.6 + 0.05*rand();
            else
                res = this.QueryDouble("RDGR?1");
            end
        end

        %% GetHeaterPower
        function power = GetHeaterPower(this)
            %Returns heater power, in W, taking into account the entered heater
            %resistance
            level = this.GetHeaterLevel();
            range = this.GetHeaterRange();
            current = this.GetHeaterCurrentFromRange(range) * level / 100; %Level is a percent
            power = this.HeaterResistance * current * current;
        end

        %% GetHeaterLevel
        function [htrLevel, htrEnabled] = GetHeaterLevel(this)
            if this.SimulationMode
                %Dummy values for testing
                htrLevel = 60 + rand();
                htrEnabled = true;
                return;
            end

            %Returns the heater output, in %, and if it is currently on.
            %HeaterChannel should be an int, 1 or 2
            %Query heater output level
            htrLevel = this.QueryDouble("HTR?");

            %Check if the heater is in 'Off' range or not
            htrRange = this.GetHeaterRange();
            if(htrRange == this.GetHeaterRangeIndex(this.HeaterRange("Off (0)")))
                htrEnabled = false;
            else
                htrEnabled = true;
            end
        end

        %% GetHeaterRange
        function htrRange = GetHeaterRange(this)
            %Returns the int signifying the range currently selected
            if(this.SimulationMode)
                %Dummy values
                htrRange = 1;
            else
                htrRange = this.QueryDouble("HTRRNG?");
            end
        end

        %% SetHeaterRange
        function SetHeaterRange(this, range)
            %Set the heater range 
            %The range setting has no effect if an output is in the Off mode, and does not apply to an output in Monitor Out mode.
            %range is a member of the LS370_Heaterrange enum, or string matching one of its members. 0 = Off, 1 = 31.6 ?A, 2 = 100 ?A, 3 = 316 ?A, 4 = 1.00 mA, 5 = 3.16 mA, 6 = 10.0 mA, 7 = 31.6 mA, 8 = 100 mA

            index = this.GetHeaterRangeIndex(range);
            this.WriteCommand("HTRRNG " + num2str(index));
        end

        %% SetHeaterSetpoint
        function SetHeaterSetpoint(this, setPt)
            %Set a heater setpoint on specified channel
            this.WriteCommand("SETP " + num2str(setPt));
        end

        %% GetHeaterSetpoint
        function setPt = GetHeaterSetpoint(this)
            %Get the current heater setpoint value on specified channel
            setPt = this.QueryDouble("SETP?");
        end

        %% GetRamp
        function [enabled, rate] = GetRamp(this)
            %Get status (enabled on/off and rate) of ramping on channel/control loop.

            %Select channel (hard coded right now)
            output = "0";   %0 = sample heater, 1 = output 1 (warm-up heater).

            if(this.SimulationMode)
                %Dummy values
                enabled = true;
                rate = 1.2;
            else
                %Query real values for all other connection types
                result = strsplit(this.QueryString("RAMP? " + output),',');
                enabled = strcmp(result{1}, '1');
                rateStr = strsplit(result{2},':');
                rateStr1 = rateStr{1};
                rate = str2double(rateStr1);
            end
        end

        %% SetRamp
        function SetRamp(this, enabled, rate)
            %Set status (enabled on/off and rate) of ramping on channel/control loop.
            if(enabled)
                enabledStr = "1";
            else
                enabledStr = "0";
            end

            output = "0";   %0 = sample heater, 1 = output 1 (warm-up heater).
            rate = abs(rate); %positive value expected
            this.WriteCommand("RAMP " + output + "," + enabledStr + "," + num2str(rate));
        end

        %% GetSensorReading
        function reading = GetSensorReading(this, channel)
            %Get the currently displayed reading
            reading = this.QueryDouble("SRDG? " + channel);
        end

        %% SetControlMode
        function SetControlMode(this, controlMode)
            %Set the control mode: Off, Closed Loop PID,
            %Zone, or Open Loop.
            modeIndex = this.GetControlModeIndex(controlMode);
            this.WriteCommand("CMODE " + num2str(modeIndex) +"\n");
        end

        %% GetControlMode
        function controlMode = GetControlMode(this)
            %Returns the currently selected control mode, off, closed loop pid,
            %zone, open loop. Channel 1 or 2
            if(this.SimulationMode)
                %Dummy values
                modeIndex = 2;
            else
                modeIndex = this.QueryDouble("CMODE?");
            end

            switch(modeIndex)
                case(1)
                    controlMode = this.ControlMode("Closed Loop PID");
                case(2)
                    controlMode = this.ControlMode("Zone");
                case(3)
                    controlMode = this.ControlMode("Open Loop");
                case(4)
                    controlMode = this.ControlMode("Off");
                otherwise
                    error("Error in control mode");
            end
        end

        %% SetPIDValues
        function SetPIDValues(this, P, I, D)
            %Set PID Values (numerical inputs)
            this.WriteCommand(['PID' ' ' num2str(P) ',' num2str(I) ',' num2str(D)]);
        end

        %% GetPIDValues
        function [P, I, D] = GetPIDValues(this)
            %Get PID settings
            if(this.SimulationMode)
                %Dummy values
                P = 50;
                I = 10;
                D = 5;
            else
                readings = strsplit(this.QueryString("PID?"), ',');
                P = str2double(readings{1});
                istr = readings{2};
                I = str2double(istr(2:end));    %I string was returning as 'E20.000' - manual says the values should be +10.00 or -10.00 but.. interpreting strings eh. Just snip off the first character before converting to double
                dStr = strsplit(readings{3}, ':');
                D = str2double(dStr{1});
            end
        end

        %% GetManualOutputPercent
        function output = GetManualOutputPercent(this)
            %Note - set display on instrument to be in 'Current' Units not
            %'Power',  on the ControlSetup button on the front panel
            if this.SimulationMode
                output = 60;
                return;
            end

            %Get the manual output setting if active. Channel 1, 2
            output = this.QueryDouble("MOUT?");
        end

        %% SetManualOutputPercent
        function SetManualOutputPercent(this, percentage)
            %Set the manual output setting.
            assert(percentage <= 100 && percentage  >=0, 'Invalid output percentage');
            this.WriteCommand("MOUT " + num2str(percentage));
        end
    end

    methods (Access = protected)

        %% ApplySettings
        function ApplySettings(this, settings)
            this.SetControlMode(settings.ControlMode);
            this.SetHeaterRange(settings.HeaterRange);
            this.SetHeaterSetpoint(settings.SetPoint);
            this.SetRamp(settings.RampEnabled, settings.RampRate);

            %Do it again, to make sure we have stuff in the right order..
            this.SetControlMode(settings.ControlMode);
            this.SetHeaterRange(settings.HeaterRange);
            this.SetHeaterSetpoint(settings.SetPoint);
            this.SetRamp(settings.RampEnabled, settings.RampRate);

            if(settings.ControlMode == this.ControlMode("Open Loop"))
                this.SetManualOutputPercent(settings.ManualOutput);
            end

            this.SetPIDValues(settings.PID_Settings.P, settings.PID_Settings.I, settings.PID_Settings.D);
        end

    end

    methods (Access = private)

        %% GetControlModeIndex
        function index = GetControlModeIndex(this, controlMode)
            switch(controlMode)
                case(this.ControlMode("Closed Loop PID"))
                    index = 1;
                case(this.ControlMode("Zone"))
                    index = 2;
                case(this.ControlMode("Open Loop"))
                    index = 3;
                case(this.ControlMode("Off"))
                    index = 4;
                otherwise
                    error("Unsupported control mode, should be Off, Closed Loop PID, Zone, Open Loop, was " + string(controlMode));
            end
        end

        %% GetHeaterRangeIndex
        function index = GetHeaterRangeIndex(this, heaterRange)
            switch(heaterRange)
                case(this.HeaterRange("Off (0)"))
                    index = 0;
                case(this.HeaterRange(" 32 muA (1)"))
                    index = 1;
                case(this.HeaterRange("100 muA (2)"))
                    index = 2;
                case(this.HeaterRange("316 muA (3)"))
                    index = 3;
                case(this.HeaterRange("  1 mA (4)"))
                    index = 4;
                case(this.HeaterRange("  3 mA (5)"))
                    index = 5;
                case(this.HeaterRange(" 10 mA (6)"))
                    index = 6;
                case(this.HeaterRange(" 32 mA (7)"))
                    index = 7;
                case(this.HeaterRange("100 mA (8)"))
                    index = 8;
                otherwise
                    error("Unsupported heater range, should be Off (0), 32 muA (1), 100 muA (2), 316 muA (3),   1 mA (4),   3 mA (5),  10 mA (6),  32 mA (7), 100 mA (8), was " + string(heaterRange));
            end
        end

    end

    methods(Static, Access = private)

        %% GetHeaterCurrentFromRange
        function currentRange = GetHeaterCurrentFromRange(heaterRangeIdx)
            %See p134 of LS370 manual, HTRRNG documentation
            switch(heaterRangeIdx)
                case(0)
                    currentRange = 0;
                case(1)
                    currentRange = 31.6e-6;
                case(2)
                    currentRange = 100e-6;
                case(3)
                    currentRange = 316e-6;
                case(4)
                    currentRange = 1e-3;
                case(5)
                    currentRange = 3.16e-3;
                case(6)
                    currentRange = 10e-3;
                case(7)
                    currentRange = 31.6e-3;
                case(8)
                    currentRange = 100e-3;
                otherwise
                    error("Unsupported heater range index in LS370: " + string(heaterRangeIdx));
            end
        end
    
    end

end

