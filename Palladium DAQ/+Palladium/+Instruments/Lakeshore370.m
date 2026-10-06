classdef Lakeshore370 < Palladium.Core.Instrument
    %Lakeshore370 - Instrument driver for the Lake Shore Model 370 AC resistance bridge.
    %Reads the bridge's resistance each measurement tick - and, if `Reading`
    %is Temperature, the temperature calculated from it using the channel's
    %calibration curve - plus the power going into the sample heater. The
    %sample heater can be controlled from the Heater Control tab: setpoint,
    %ramp, PID values, control mode, heater range (31.6 uA to 100 mA) and
    %manual output. The channel it regulates on, the setpoint units and the
    %heater range limit are set on the instrument, in Control Setup.
    %
    %The Model 370 has GPIB and RS-232 interfaces.
    %
    %The heater output and manual output are read and set as a percentage of
    %full-scale current, so set the heater output display to Current, not
    %Power, in the instrument's Control Setup.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Lakeshore 370";                             %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "Ls370";                                         %Instrument name, used as the prefix of its resistance and heater power column headers
        Connection_Type = Palladium.Enums.ConnectionType.Debug; %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Ch_Name = "Sample Temperature (K)";                     %Data column header for the temperature reading, e.g. "Mixing Chamber Temp (K)"
        Reading;                                                %What to read: Temperature (K, plus the resistance) or Resistance (Ohms) only
        HeaterResistance = 100;                                 %Resistance of the heater connected to the sample heater output, in Ohms - used to calculate heater power
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr);     catOut = this.ConvertToCategorical(inputStr, ["Temperature", "Resistance"]); end
        function catOut = HeaterRange(this, inputStr);  catOut = this.ConvertToCategorical(inputStr, ["Off (0)", "32 muA (1)", "100 muA (2)", "316 muA (3)", "  1 mA (4)", "  3 mA (5)", " 10 mA (6)", " 32 mA (7)", "100 mA (8)"]); end
        function catOut = ControlMode(this, inputStr);  catOut = this.ConvertToCategorical(inputStr, ["Closed Loop PID", "Zone", "Open Loop", "Off"]); end
    end

    %% Constructor
    methods
        function this = Lakeshore370()
            %Set the connection options, default reading and Heater Control tab.

            %The Model 370 has GPIB and RS-232 ports; VISA can address either
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial", "VISA"]);
            this.GPIB_Address = 12;     %Factory default

            %RS-232 is fixed at 7 data bits, odd parity and 1 stop bit, with
            %CR LF terminators. 9600 baud is the factory setting - it must
            %match the Computer Interface menu on the instrument
            this.ConnectionSettings.SerialSettings = struct('BaudRate', 9600, 'DataBits', 7, 'Parity', 'odd', 'StopBits', 1, 'Terminator', 'CR/LF');

            %Define the Instrument Controls that can be added
            this.DefineInstrumentControl(Name = "🕹️ Heater Control", ClassName = "LakeshoreHeaterControl", TabName = "Heater Control", EnabledByDefault = true);

            %Make sure to set values for Properties of Categorical type
            %like these
            this.Reading = this.MeasType("Temperature");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [settings, heaterLevelPct, heaterEnabled, heaterPower] = CollectHeaterControlSettings(this)
            %Read the heater's settings and output, for the Heater Control tab.
            %
            %Outputs:
            %   settings       - struct of the heater settings, with fields ControlMode,
            %                    HeaterRange (as the range number 0 to 8), SetPoint,
            %                    RampEnabled, RampRate, ManualOutput and PID_Settings
            %                    (with fields P, I and D)
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

        function controlMode = GetControlMode(this)
            %Read the heater's control mode
            %
            %Outputs:
            %   controlMode - ControlMode categorical: Closed Loop PID, Zone,
            %                 Open Loop or Off

            if(this.SimulationMode)
                modeIndex = 2;
            else
                modeIndex = this.QueryDouble("CMODE?");
            end

            switch(modeIndex)
                case(1);    controlMode = this.ControlMode("Closed Loop PID");
                case(2);    controlMode = this.ControlMode("Zone");
                case(3);    controlMode = this.ControlMode("Open Loop");
                case(4);    controlMode = this.ControlMode("Off");
                otherwise
                    error("Lakeshore370:InvalidControlMode", "%s", "Unknown control mode index returned by " + this.Name + ": " + string(modeIndex));
            end
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %The temperature (if Reading is Temperature), the resistance, then the
            %heater power
            %
            %Outputs:
            %   Headers - e.g. ["Sample Temperature (K)", "Ls370 - Resistance (Ohms)",
            %             "Ls370 Heater Power (W)"]. The temperature column uses Ch_Name
            %   Units   - matching units, e.g. ["K", "Ohms", "W"]

            switch(this.Reading)
                case(this.MeasType("Temperature"));     Headers = [string(this.Ch_Name), this.Name + " - Resistance (Ohms)"];   Units = ["K" "Ohms"];
                case(this.MeasType("Resistance"));      Headers = this.Name + " - Resistance (Ohms)";                           Units = "Ohms";
                otherwise
                    error("Lakeshore370:UnsupportedMeasurementType", "%s", "Unsupported measurement type " + string(this.Reading));
            end

            %The heater power is always recorded
            Headers = [Headers, this.Name + " Heater Power (W)"];
            Units = [Units, "W"];
        end

        function [htrLevel, htrEnabled] = GetHeaterLevel(this)
            %Read the heater output percentage, and whether the heater is on.
            %The output is a percentage of the heater range's full-scale current,
            %if the instrument's heater output display is set to Current
            %
            %Outputs:
            %   htrLevel   - heater output, in percent of full-scale current
            %   htrEnabled - false if the heater range is Off

            if this.SimulationMode
                htrLevel = this.GenerateSimulatedData(1, Baseline=60, Variance=10);
                htrEnabled = true;
                return;
            end

            htrLevel = this.QueryDouble("HTR?");
            htrEnabled = this.GetHeaterRange() ~= this.GetHeaterRangeIndex(this.HeaterRange("Off (0)"));
        end

        function power = GetHeaterPower(this)
            %Calculate the power going into the heater, in W.
            %From the heater output, heater range and HeaterResistance:
            %power = HeaterResistance x I^2, with I the output percentage of the
            %range's full-scale current
            %
            %Outputs:
            %   power - heater power, in W

            level = this.GetHeaterLevel();
            range = this.GetHeaterRange();
            current = this.GetHeaterCurrentFromRange(range) * level / 100; %Level is a percent
            power = this.HeaterResistance * current * current;
        end

        function htrRange = GetHeaterRange(this)
            %Read the heater range, as its range number
            %
            %Outputs:
            %   htrRange - 0 = Off, 1 = 31.6 uA, 2 = 100 uA, 3 = 316 uA, 4 = 1 mA,
            %              5 = 3.16 mA, 6 = 10 mA, 7 = 31.6 mA, 8 = 100 mA

            if(this.SimulationMode)
                htrRange = 1;
            else
                htrRange = this.QueryDouble("HTRRNG?");
            end
        end

        function setPt = GetHeaterSetpoint(this)
            %Read the heater's control setpoint
            %
            %Outputs:
            %   setPt - setpoint, in the setpoint units set on the instrument
            %           (K or Ohms)

            setPt = this.QueryDouble("SETP?");
        end

        function output = GetManualOutputPercent(this)
            %Read the heater's manual output setting, in percent.
            %Used in Open Loop mode. This is a percentage of full-scale current
            %only if the instrument's heater output display is set to Current
            %
            %Outputs:
            %   output - manual output, in percent

            if this.SimulationMode
                output = 60;
                return;
            end

            output = this.QueryDouble("MOUT?");
        end

        function [P, I, D] = GetPIDValues(this)
            %Read the heater's PID control values
            %
            %Outputs:
            %   P - proportional gain (0.001 to 1000)
            %   I - integral, or reset, in s (0 to 10000)
            %   D - derivative, or rate, in s (0 to 2500)

            if(this.SimulationMode)
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
                %Reply is "<off/on>,<rate value>"
                result = strsplit(this.QueryString("RAMP?"), ',');
                enabled = strcmp(strtrim(result{1}), '1');
                rateStr = strsplit(result{2}, ':');
                rate = str2double(rateStr{1});
            end
        end

        function res = GetResistance(this)
            %Read the resistance reading
            %
            %Outputs:
            %   res - the reading, in Ohms

            if this.SimulationMode
                res = this.GenerateSimulatedData(1, Baseline=1024, Variance=0.01);
            else
                res = this.QueryDouble("RDGR?");
            end
        end

        function reading = GetSensorReading(this, channel)
            %Read a channel in sensor units with the SRDG? query.
            %SRDG? is a Model 372 query - it is not listed in the Model 370
            %manual, and is not used by this driver
            %
            %Inputs:
            %   channel - channel number to read
            %
            %Outputs:
            %   reading - the reading, in sensor units

            reading = this.QueryDouble("SRDG? " + channel);
        end

        function temp = GetTemperature(this)
            %Read the temperature reading
            %
            %Outputs:
            %   temp - the reading, in K. Zero if the channel has no calibration
            %          curve

            if this.SimulationMode
                temp = this.GenerateSimulatedData(1, Baseline=24.6, Variance=0.02);
            else
                temp = this.QueryDouble("RDGK?");
            end
        end

        function [dataRow] = Measure(this)
            %Read the temperature (if Reading is Temperature) and resistance, then the heater power.
            %In the same order as GetHeaders
            %
            %Outputs:
            %   dataRow - the readings, in K and Ohms, then the heater power in W

            switch(this.Reading)
                case(this.MeasType("Temperature"));     dataRow = [this.GetTemperature() this.GetResistance()];
                case(this.MeasType("Resistance"));      dataRow = this.GetResistance();
                otherwise
                    error("Lakeshore370:UnsupportedMeasurementType", "%s", "Unsupported measurement type " + string(this.Reading));
            end

            dataRow = [dataRow this.GetHeaterPower()];
        end

        function SetControlMode(this, controlMode)
            %Set the heater's control mode
            %
            %Inputs:
            %   controlMode - ControlMode categorical: Closed Loop PID, Zone,
            %                 Open Loop or Off

            modeIndex = this.GetControlModeIndex(controlMode);
            this.WriteCommand("CMODE " + num2str(modeIndex));
        end

        function SetHeaterRange(this, range)
            %Set the heater range, which sets the full-scale heater current
            %
            %Inputs:
            %   range - HeaterRange categorical, from Off (0) to 100 mA (8). The
            %           range has no effect while the control mode is Off

            index = this.GetHeaterRangeIndex(range);
            this.WriteCommand("HTRRNG " + num2str(index));
        end

        function SetHeaterSetpoint(this, setPt)
            %Set the heater's control setpoint.
            %With ramping on, the setpoint ramps to the new value at the ramp rate
            %
            %Inputs:
            %   setPt - setpoint, in the setpoint units set on the instrument
            %           (K or Ohms)

            this.WriteCommand("SETP " + num2str(setPt));
        end

        function SetManualOutputPercent(this, percentage)
            %Set the heater's manual output, in percent.
            %Used in Open Loop mode. This is a percentage of full-scale current
            %only if the instrument's heater output display is set to Current
            %
            %Inputs:
            %   percentage - manual output, 0 to 100 %

            assert(percentage <= 100 && percentage >= 0, "Lakeshore370:InvalidOutputPercentage", "Invalid output percentage");
            this.WriteCommand("MOUT " + num2str(percentage));
        end

        function SetPIDValues(this, P, I, D)
            %Set the heater's PID control values
            %
            %Inputs:
            %   P - proportional gain (0.001 to 1000)
            %   I - integral, or reset, in s (0 to 10000)
            %   D - derivative, or rate, in s (0 to 2500)

            this.WriteCommand(['PID' ' ' num2str(P) ',' num2str(I) ',' num2str(D)]);
        end

        function SetRamp(this, enabled, rate)
            %Turn setpoint ramping on or off, and set its rate
            %
            %Inputs:
            %   enabled - true to ramp the setpoint to new values, false to
            %             step it
            %   rate    - ramp rate, in K/min (0.001 to 10). Its sign is
            %             ignored - the setpoint ramps up or down as needed

            if(enabled)
                enabledStr = "1";
            else
                enabledStr = "0";
            end

            rate = abs(rate);
            this.WriteCommand("RAMP " + enabledStr + "," + num2str(rate));
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function ApplySettings(this, settings)
            %Send the Heater Control tab's settings to the instrument.
            %The control mode, range, setpoint and ramp are sent twice, to make
            %sure each is applied after the others
            %
            %Inputs:
            %   settings - struct with the fields returned by
            %              CollectHeaterControlSettings, with HeaterRange as a
            %              HeaterRange categorical

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

    %% Methods (Private)
    methods (Access = private)

        function index = GetControlModeIndex(this, controlMode)
            %Control mode number used by the CMODE command
            %
            %Inputs:
            %   controlMode - ControlMode categorical
            %
            %Outputs:
            %   index - 1 = Closed Loop PID, 2 = Zone, 3 = Open Loop, 4 = Off

            switch(controlMode)
                case(this.ControlMode("Closed Loop PID"));  index = 1;
                case(this.ControlMode("Zone"));             index = 2;
                case(this.ControlMode("Open Loop"));        index = 3;
                case(this.ControlMode("Off"));              index = 4;
                otherwise
                    error("Lakeshore370:UnsupportedControlMode", "%s", "Unsupported control mode, should be Off, Closed Loop PID, Zone, Open Loop, was " + string(controlMode));
            end
        end

        function index = GetHeaterRangeIndex(this, heaterRange)
            %Heater range number used by the HTRRNG command
            %
            %Inputs:
            %   heaterRange - HeaterRange categorical
            %
            %Outputs:
            %   index - 0 (Off) to 8 (100 mA)

            switch(heaterRange)
                case(this.HeaterRange("Off (0)"));      index = 0;
                case(this.HeaterRange("32 muA (1)"));   index = 1;
                case(this.HeaterRange("100 muA (2)"));  index = 2;
                case(this.HeaterRange("316 muA (3)"));  index = 3;
                case(this.HeaterRange("  1 mA (4)"));   index = 4;
                case(this.HeaterRange("  3 mA (5)"));   index = 5;
                case(this.HeaterRange(" 10 mA (6)"));   index = 6;
                case(this.HeaterRange(" 32 mA (7)"));   index = 7;
                case(this.HeaterRange("100 mA (8)"));   index = 8;
                otherwise
                    error("Lakeshore370:UnsupportedHeaterRange", "%s", "Unsupported heater range, should be Off (0), 32 muA (1), 100 muA (2), 316 muA (3),   1 mA (4),   3 mA (5),  10 mA (6),  32 mA (7), 100 mA (8), was " + string(heaterRange));
            end
        end

    end

    %% Methods (Static, Private)
    methods(Static, Access = private)

        function currentRange = GetHeaterCurrentFromRange(heaterRangeIdx)
            %Full-scale heater current of a heater range, from the HTRRNG command description
            %
            %Inputs:
            %   heaterRangeIdx - heater range number, 0 to 8
            %
            %Outputs:
            %   currentRange - full-scale current, in A

            switch(heaterRangeIdx)
                case(0);    currentRange = 0;
                case(1);    currentRange = 31.6e-6;
                case(2);    currentRange = 100e-6;
                case(3);    currentRange = 316e-6;
                case(4);    currentRange = 1e-3;
                case(5);    currentRange = 3.16e-3;
                case(6);    currentRange = 10e-3;
                case(7);    currentRange = 31.6e-3;
                case(8);    currentRange = 100e-3;
                otherwise
                    error("Lakeshore370:UnsupportedHeaterRangeIndex", "%s", "Unsupported heater range index in LS370: " + string(heaterRangeIdx));
            end
        end

    end

end
