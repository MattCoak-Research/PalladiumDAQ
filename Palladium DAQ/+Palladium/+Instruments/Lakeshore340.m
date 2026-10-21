classdef Lakeshore340 < Palladium.Core.Instrument
    %Lakeshore340 - Instrument driver for the Lake Shore Model 340 temperature controller.
    %Reads sensor inputs A and B (as temperature, sensor units or neither)
    %each measurement tick, plus the power going into the heater. A control
    %loop can be run from the Heater Control tab: setpoint, ramp, PID
    %values, control mode, heater range and manual output.
    %
    %`ControlLoop` picks the loop: Loop 1 drives the heater output (up to
    %100 W); Loop 2 drives Analog Output 2 (a voltage, e.g. to program an
    %external power supply - its ANALOG mode must be Loop). `ControlChannel`
    %is the sensor input the loop regulates on, sent to the instrument when
    %heater settings are applied (None leaves the instrument's choice). The
    %heater range, the heater power column and the heater's resistance,
    %maximum current and display mode are loop 1's: with Loop 2, the Heater
    %Control tab shows Analog Output 2's output and its heater range does
    %nothing.
    %
    %The sensor-units readings are in V or Ω, as each input's sensor type
    %reads (INTYPE?, when connecting). The heater's resistance is the one
    %set in the instrument's Control Setup (CDISP?).
    %
    %The Model 340 has GPIB (IEEE-488) and RS-232 interfaces. Its command set
    %is close to the Model 331's (see `Lakeshore331`). (Commands from the
    %Model 340 User's Manual, chapter 9.)

    %% Properties (Public)
    properties(Access = public)
        FullName = "Lakeshore 340";                             %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "Ls340";                                         %Instrument name, used as the prefix of its sensor-units and heater power column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Ch_A_Reading;                                           %What to read on input A: Temperature (K), Sensor Units (V or Ω, from the sensor type), or Disabled to not measure it
        Ch_B_Reading;                                           %What to read on input B: Temperature (K), Sensor Units (V or Ω, from the sensor type), or Disabled to not measure it
        Ch_A_Name = "Channel A Temperature (K)"                 %Data column header for input A when reading temperature, e.g. "Sample Temp (K)"
        Ch_B_Name = "Channel B Temperature (K)"                 %Data column header for input B when reading temperature
        ControlLoop;                                            %Control loop the Heater Control tab acts on: Loop 1 (the heater output) or Loop 2 (Analog Output 2)
        ControlChannel;                                         %Sensor input (A or B) the control loop regulates on - sent to the instrument when heater settings are applied. None leaves the instrument's choice unchanged.
    end

    %% Properties (Private)
    properties(Access = private)
        HeaterOutputIsPower = true;                             %Whether the heater output percentage (HTR?) is of full-scale power (true) or current (false), as set on the instrument (CDISP?) and read when connecting
        HeaterResistance_Ohms = 25;                             %The heater's resistance, as set on the instrument (CDISP?) - read when connecting. 25 Ohms is the instrument's default
        MaxHeaterCurrent = 1;                                   %Maximum heater current setting, in A - the full-scale current of range 5 - read when connecting (CLIMIT?, and CLIMI? for User). NaN if it can't be read
        SensorUnits = ["Ω", "Ω"];                               %Units of inputs A and B's sensor-units readings, from their sensor type (INTYPE?) - read when connecting
    end

    %% Categoricals
    methods
        function catOut = Channel(this, inputStr);          catOut = this.ConvertToCategorical(inputStr, ["A", "B", "None"]); end
        function catOut = ControlMode(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Manual PID", "Zone", "Open Loop", "AutoTune PID", "AutoTune PI", "AutoTune P"]); end
        function catOut = HeaterRange(this, inputStr);      catOut = this.ConvertToCategorical(inputStr, ["Off", "Range 1", "Range 2", "Range 3", "Range 4", "Range 5"]); end
        function catOut = LoopType(this, inputStr);         catOut = this.ConvertToCategorical(inputStr, ["Loop 1 (Heater)", "Loop 2 (Analog Output 2)"]); end
        function catOut = MeasType(this, inputStr);         catOut = this.ConvertToCategorical(inputStr, ["Temperature", "Sensor Units", "Disabled"]); end
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
            this.ControlLoop = this.LoopType("Loop 1 (Heater)");
            this.ControlChannel = this.Channel("A");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [settings, heaterLevelPct, heaterEnabled, heaterPower] = CollectHeaterControlSettings(this)
            %Read the control loop's settings and output, for the Heater Control tab.
            %The loop is set by ControlLoop. With Loop 2, the output is
            %Analog Output 2's (AOUT? 2) and the heater power isn't known
            %
            %Outputs:
            %   settings       - struct of the heater settings, with fields ControlMode,
            %                    HeaterRange, SetPoint, RampEnabled, RampRate, ManualOutput
            %                    and PID_Settings (with fields P, I and D). The same
            %                    struct, edited, is passed back to ApplySettings
            %   heaterLevelPct - the loop's output, in percent
            %   heaterEnabled  - false if the heater range is Off (always true for Loop 2)
            %   heaterPower    - heater power, in W (NaN for Loop 2)

            loop = this.ControlLoop;
            settings.ControlMode = this.GetControlMode(loop);
            settings.HeaterRange = this.GetHeaterRangeFromIndex(this.GetHeaterRange());
            settings.SetPoint = this.GetHeaterSetpoint();
            [settings.RampEnabled, settings.RampRate] = this.GetRamp();
            settings.ManualOutput = this.GetManualOutputPercent(loop);
            [P, I, D] = this.GetPIDValues(loop);
            settings.PID_Settings.P = P;
            settings.PID_Settings.I = I;
            settings.PID_Settings.D = D;

            if this.GetLoopString(loop) == "1"
                [heaterPower, heaterLevelPct, rangeIdx] = this.ReadHeaterOutput();
                heaterEnabled = rangeIdx ~= 0;
            else
                heaterLevelPct = this.GetAnalogOutput2Percent();
                heaterEnabled = true;
                heaterPower = NaN;
            end
        end

        function controlMode = GetControlMode(this, loop)
            %Read a control loop's control mode
            %
            %Inputs:
            %   loop - LoopType categorical, or the loop number (1 or 2). (A
            %          Channel A or B is also taken as loop 1 or 2, as this used to)
            %
            %Outputs:
            %   controlMode - ControlMode categorical, e.g. Manual PID

            loopStr = this.GetLoopString(loop);

            if(this.SimulationMode)
                modeIndex = 1;
            else
                modeIndex = this.QueryDouble("CMODE? " + loopStr);
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
            %One per enabled input, then the heater power
            %
            %Outputs:
            %   Headers - e.g. ["Channel A Temperature (K)", "Ls340 - Ch B Sensor (V)",
            %             "Ls340 Heater Power (W)"]. Temperature columns use
            %             Ch_A_Name / Ch_B_Name
            %   Units   - matching units, e.g. ["K", "V", "W"]

            Headers = [];
            Units = [];

            %Add a column for each input that isn't Disabled
            letters = ["A", "B"];
            for i = 1:2
                switch(this.("Ch_" + letters(i) + "_Reading"))
                    case(this.MeasType("Temperature"));     Headers = [Headers string(this.("Ch_" + letters(i) + "_Name"))];                   Units = [Units "K"]; %#ok<AGROW>
                    case(this.MeasType("Sensor Units"));    Headers = [Headers this.Name + " - Ch " + letters(i) + " Sensor (" + this.SensorUnits(i) + ")"];   Units = [Units this.SensorUnits(i)]; %#ok<AGROW>
                end
            end

            %The heater power is always recorded
            Headers = [Headers, this.Name + " Heater Power (W)"];
            Units = [Units, "W"];
        end

        function [htrLevel, htrEnabled] = GetHeaterLevel(this)
            %Read the heater (loop 1) output percentage, and whether the heater is on.
            %The output is a percentage of full scale for the heater range
            %
            %Outputs:
            %   htrLevel   - heater output, in percent of full-scale power or
            %                current (as set on the instrument)
            %   htrEnabled - false if the heater range is Off

            [~, htrLevel, rangeIdx] = this.ReadHeaterOutput();
            htrEnabled = rangeIdx ~= 0;
        end

        function power = GetHeaterPower(this)
            %Calculate the power going into the heater (loop 1), in W.
            %From the heater output, heater range, maximum current and the
            %heater's resistance - see ReadHeaterOutput
            %
            %Outputs:
            %   power - heater power, in W. NaN if the maximum current can't be read

            power = this.ReadHeaterOutput();
        end

        function htrRange = GetHeaterRange(this)
            %Read the heater (loop 1) range number
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
            %Read the control setpoint of the loop set by ControlLoop
            %
            %Outputs:
            %   setPt - setpoint, in the setpoint units set on the instrument
            %           (usually K)

            if(this.SimulationMode)
                setPt = 25.4;
                return;
            end

            setPt = this.QueryDouble("SETP? " + this.GetLoopString(this.ControlLoop));
        end

        function output = GetManualOutputPercent(this, loop)
            %Read a control loop's manual output setting, in percent.
            %Used in Open Loop mode, and added to the PID output in the other modes
            %
            %Inputs:
            %   loop - LoopType categorical, or the loop number (1 or 2)
            %
            %Outputs:
            %   output - manual output, in percent

            loopStr = this.GetLoopString(loop);

            if(this.SimulationMode)
                output = 78;
                return;
            end

            output = this.QueryDouble("MOUT? " + loopStr);
        end

        function [P, I, D] = GetPIDValues(this, loop)
            %Read a control loop's PID control values
            %
            %Inputs:
            %   loop - LoopType categorical, or the loop number (1 or 2)
            %
            %Outputs:
            %   P - proportional gain
            %   I - integral, or reset
            %   D - derivative, or rate

            loopStr = this.GetLoopString(loop);

            if(this.SimulationMode)
                P = 50;
                I = 10;
                D = 5;
            else
                readings = str2double(split(string(this.QueryString("PID? " + loopStr)), ","));
                P = readings(1);
                I = readings(2);
                D = readings(3);
            end
        end

        function [enabled, rate] = GetRamp(this)
            %Read whether the setpoint of the ControlLoop loop ramps, and how fast
            %
            %Outputs:
            %   enabled - true if setpoint ramping is on
            %   rate    - ramp rate, in K/min

            if(this.SimulationMode)
                enabled = true;
                rate = 1.2;
            else
                result = split(string(this.QueryString("RAMP? " + this.GetLoopString(this.ControlLoop))), ",");
                enabled = str2double(result(1)) == 1;
                rate = str2double(result(2));
            end
        end

        function reading = GetSensorReading(this, channel)
            %Read a sensor input in sensor units - V or Ω, as its sensor type reads
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
            %Read each enabled input, then the heater power.
            %In the same order as GetHeaders
            %
            %Outputs:
            %   dataRow - the readings, in K or sensor units, then the heater power in W

            dataRow = [];
            letters = ["A", "B"];
            for i = 1:2
                channel = this.Channel(letters(i));
                switch(this.("Ch_" + letters(i) + "_Reading"))
                    case(this.MeasType("Temperature"));     dataRow = [dataRow this.GetTemperature(channel)]; %#ok<AGROW>
                    case(this.MeasType("Sensor Units"));    dataRow = [dataRow this.GetSensorReading(channel)]; %#ok<AGROW>
                end
            end

            dataRow = [dataRow this.GetHeaterPower()];
        end

        function SetControlInput(this, loop, channel)
            %Set the sensor input a control loop regulates on (CSET), keeping the loop's other settings.
            %
            %Inputs:
            %   loop    - LoopType categorical, or the loop number (1 or 2)
            %   channel - Channel categorical: A or B. None changes nothing

            if channel == this.Channel("None")
                return;
            end

            %The other CSET parameters are optional - left out, they are kept
            this.WriteCommand("CSET " + this.GetLoopString(loop) + "," + this.GetChannelString(channel));
        end

        function SetControlMode(this, loop, controlMode)
            %Set a control loop's control mode
            %
            %Inputs:
            %   loop        - LoopType categorical, or the loop number (1 or 2)
            %   controlMode - ControlMode categorical, e.g. Manual PID

            loopStr = this.GetLoopString(loop);
            modeIndex = this.GetControlModeIndex(controlMode);

            this.WriteCommand("CMODE " + loopStr + "," + Palladium.Core.Instrument.NumberToCommandString(modeIndex));
        end

        function SetHeaterRange(this, range)
            %Set the heater (loop 1) range, which sets the maximum heater power
            %
            %Inputs:
            %   range - HeaterRange categorical: Off or Range 1 to Range 5. Off
            %           turns the heater off

            rangeIdx = this.GetHeaterRangeIndex(range);
            this.WriteCommand("RANGE " + Palladium.Core.Instrument.NumberToCommandString(rangeIdx));
        end

        function SetHeaterSetpoint(this, setPt)
            %Set the control setpoint of the loop set by ControlLoop.
            %With ramping on, the setpoint ramps to the new value at the ramp rate
            %
            %Inputs:
            %   setPt - setpoint, in the setpoint units set on the instrument
            %           (usually K)

            this.WriteCommand("SETP " + this.GetLoopString(this.ControlLoop) + "," + Palladium.Core.Instrument.NumberToCommandString(setPt));
        end

        function SetManualOutputPercent(this, loop, percentage)
            %Set a control loop's manual output, in percent.
            %Used in Open Loop mode, and added to the PID output in the other modes
            %
            %Inputs:
            %   loop       - LoopType categorical, or the loop number (1 or 2)
            %   percentage - manual output, 0 to 100 %

            loopStr = this.GetLoopString(loop);
            assert(percentage <= 100 && percentage >= 0, "Lakeshore340:InvalidOutputPercentage", "Invalid output percentage");
            this.WriteCommand("MOUT " + loopStr + "," + Palladium.Core.Instrument.NumberToCommandString(percentage));
        end

        function SetPIDValues(this, loop, P, I, D)
            %Set a control loop's PID control values
            %
            %Inputs:
            %   loop - LoopType categorical, or the loop number (1 or 2)
            %   P    - proportional gain
            %   I    - integral, or reset
            %   D    - derivative, or rate

            loopStr = this.GetLoopString(loop);
            this.WriteCommand("PID " + loopStr + "," + Palladium.Core.Instrument.NumberToCommandString(P) + "," + Palladium.Core.Instrument.NumberToCommandString(I) + "," + Palladium.Core.Instrument.NumberToCommandString(D));
        end

        function SetRamp(this, enabled, rate)
            %Turn setpoint ramping on or off for the ControlLoop loop, and set its rate
            %
            %Inputs:
            %   enabled - true to ramp the setpoint to new values, false to
            %             step it
            %   rate    - ramp rate, in K/min (0.1 to 100)

            this.WriteCommand("RAMP " + this.GetLoopString(this.ControlLoop) + "," + Palladium.Core.Instrument.NumberToCommandString(double(logical(enabled))) + "," + Palladium.Core.Instrument.NumberToCommandString(rate));
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function OnConnected(this)
            %Read the inputs' sensor units and the heater's set-up, after connecting.
            %Each input's units (INTYPE?), and loop 1's maximum current
            %(CLIMIT?, and CLIMI? when it is User), heater resistance and
            %output display (CDISP?) - all needed for the heater power. Change
            %these on the instrument, then reconnect

            if this.SimulationMode
                return;
            end

            %<type>,<units>,<coefficient>,<excitation>,<range> - units 1 = volts, 2 = ohms
            letters = ["A", "B"];
            for i = 1:2
                intype = str2double(split(string(this.QueryString("INTYPE? " + letters(i))), ","));
                if intype(2) == 1
                    this.SensorUnits(i) = "V";
                else
                    this.SensorUnits(i) = "Ω";
                end
            end

            %Reply is "<SP limit>,<positive slope>,<negative slope>,<max current>,<max range>",
            %where max current is 1 = 0.25 A, 2 = 0.5 A, 3 = 1 A, 4 = 2 A, 5 = User
            climit = str2double(split(string(this.QueryString("CLIMIT? 1")), ","));
            switch(climit(4))
                case(1);    this.MaxHeaterCurrent = 0.25;
                case(2);    this.MaxHeaterCurrent = 0.5;
                case(3);    this.MaxHeaterCurrent = 1;
                case(4);    this.MaxHeaterCurrent = 2;
                case(5);    this.MaxHeaterCurrent = this.QueryDouble("CLIMI?");     %User - main firmware 01.03.08 and later
                otherwise;  this.MaxHeaterCurrent = NaN;
            end
            if isnan(this.MaxHeaterCurrent)
                Palladium.Logging.Logger.Log("Warning", this.Name + ": the heater's maximum current could not be read, so the heater power cannot be calculated and is recorded as NaN.");
            end

            %Reply is "<number of loops>,<resistance>,<current/power>,<large output enable>",
            %where current/power is 1 = current, 2 = power
            cdisp = str2double(split(string(this.QueryString("CDISP? 1")), ","));
            this.HeaterResistance_Ohms = cdisp(2);
            this.HeaterOutputIsPower = cdisp(3) == 2;
        end

        function ApplySettings(this, settings)
            %Send the Heater Control tab's settings to the instrument.
            %They go to the control loop set by ControlLoop, regulating on
            %ControlChannel. In one pass: the control input and mode, then
            %the PID values, ramp (before the setpoint, so a new setpoint
            %ramps), setpoint and (in Open Loop) manual output, and the
            %heater range last - so the heater is only switched on once
            %everything it acts on is set. The heater range is loop 1's, so
            %isn't sent for Loop 2
            %
            %Inputs:
            %   settings - struct with the fields returned by
            %              CollectHeaterControlSettings

            loop = this.ControlLoop;
            isLoop1 = this.GetLoopString(loop) == "1";
            if ~isLoop1
                this.CheckAnalogOutput2IsLoop();
            end

            this.SetControlInput(loop, this.ControlChannel);
            this.SetControlMode(loop, settings.ControlMode);
            this.SetPIDValues(loop, settings.PID_Settings.P, settings.PID_Settings.I, settings.PID_Settings.D);
            this.SetRamp(settings.RampEnabled, settings.RampRate);
            this.SetHeaterSetpoint(settings.SetPoint);
            if(settings.ControlMode == this.ControlMode("Open Loop"))
                this.SetManualOutputPercent(loop, settings.ManualOutput);
            end
            if isLoop1
                this.SetHeaterRange(settings.HeaterRange);
            end
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function CheckAnalogOutput2IsLoop(this)
            %Warn if Analog Output 2 isn't in Loop mode - loop 2 then drives nothing.

            if this.SimulationMode
                return;
            end

            %<bipolar enable>,<mode>,... - mode 3 = loop
            analog = str2double(split(string(this.QueryString("ANALOG? 2")), ","));
            if numel(analog) < 2 || analog(2) ~= 3
                Palladium.Logging.Logger.Log("Warning", this.Name + ": Analog Output 2 is not in Loop mode, so control loop 2 drives nothing - set its mode to Loop on the instrument (ANALOG).");
            end
        end

        function percent = GetAnalogOutput2Percent(this)
            %Read Analog Output 2's output (loop 2's output, in Loop mode), in percent.

            if this.SimulationMode
                percent = this.GenerateSimulatedData(1, Baseline=40, Variance=3);
                return;
            end

            percent = this.QueryDouble("AOUT? 2");
        end

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

        function loopStr = GetLoopString(this, loop)
            %Control loop number to send to the instrument, "1" or "2".
            %
            %Inputs:
            %   loop - LoopType categorical, the loop number (1 or 2), or - as
            %          these methods used to take - Channel A (loop 1) or B (loop 2)

            if iscategorical(loop) && any(string(loop) == ["A", "B", "None"])
                assert(loop ~= this.Channel("None"), "Lakeshore340:NoControlLoop", "%s", "No control loop given - use LoopType(""Loop 1 (Heater)"") or LoopType(""Loop 2 (Analog Output 2)"")");
                loopStr = string(this.GetChannelIndex(loop));
            elseif iscategorical(loop)
                switch(loop)
                    case(this.LoopType("Loop 1 (Heater)"));             loopStr = "1";
                    case(this.LoopType("Loop 2 (Analog Output 2)"));    loopStr = "2";
                    otherwise
                        error("Lakeshore340:UnsupportedLoop", "%s", "Unsupported control loop, should be Loop 1 (Heater) or Loop 2 (Analog Output 2), was " + string(loop));
                end
            else
                assert(isscalar(loop) && any(loop == [1 2]), "Lakeshore340:UnsupportedLoop", "%s", "Unsupported control loop, should be 1 or 2, was " + string(loop));
                loopStr = string(loop);
            end
        end

        function [power, level, rangeIdx] = ReadHeaterOutput(this)
            %Read the heater (loop 1) output (HTR?) and range, and work out the power going into the heater, in W.
            %Range 5's full-scale current is the maximum current setting, and
            %each lower range is a decade lower in power, so power =
            %resistance x I^2, with the heater's resistance as set on the
            %instrument. Full-scale current is also limited by the 50 V
            %compliance voltage. The heater output is a percentage of
            %full-scale power or current, depending on the instrument's
            %setting - squared for current
            %
            %Outputs:
            %   power    - heater power, in W (NaN if the maximum current is unknown)
            %   level    - heater output, in percent
            %   rangeIdx - heater range number, 0 (Off) to 5

            if(this.SimulationMode)
                level = this.GenerateSimulatedData(1, Baseline=60, Variance=3);
            else
                level = this.QueryDouble("HTR?");
            end
            rangeIdx = this.GetHeaterRange();

            fraction = level / 100;
            if ~this.HeaterOutputIsPower
                fraction = fraction^2;
            end
            if rangeIdx == 0
                power = 0;
                return;
            end
            resistance = this.HeaterResistance_Ohms;
            fullScaleCurrent = min(this.MaxHeaterCurrent * sqrt(10^(rangeIdx - 5)), 50 / resistance);
            power = resistance * fullScaleCurrent^2 * fraction;
        end

    end

end
