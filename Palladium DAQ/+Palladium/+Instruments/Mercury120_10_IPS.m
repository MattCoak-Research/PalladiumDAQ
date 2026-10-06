classdef Mercury120_10_IPS < Palladium.Core.Instrument
    %Mercury120_10_IPS - Instrument driver for the Oxford Instruments PS120-10 superconducting magnet power supply.
    %Records the magnet field (T) and current (A) each measurement tick. The
    %Magnet Control tab sets the target field and field ramp rate and gives
    %Hold, To Set Point and To Zero commands; the optional Sweep Control tab
    %ramps the field through a sequence of target points.
    %
    %The PS120-10 (120 A, 10 V; beige case, c. 1991) is the predecessor of
    %the IPS120 driven by `Mercury120_IPS`. It uses the same single-letter
    %command set, but every number sent or returned is a scaled integer:
    %currents in units of 0.01 A (so `I2000` sets a 20 A target, and 23.09 A
    %is returned as `+02309`) and fields in units of 0.001 T. Its manual was
    %obtained from Oxford Instruments as a scanned copy.
    %
    %The PS120-10 has an RS-232 interface only: 9600 baud, 8 data bits, 2
    %stop bits, CR terminators. It replies to every command, including ones
    %that only set something, so this driver sends them all with
    %`QueryString` and discards the reply. The reply is `?` followed by the
    %command if the command was not recognised or could not be obeyed (for
    %example when the supply is in Local control). Connecting puts the
    %supply into Remote and Unlocked control, and closing the connection
    %puts it back into Local and Unlocked control.
    %
    %Target fields and currents are sent as positive numbers on this
    %supply, with the polarity set separately (P command). This driver does
    %not set the polarity, or control the switch heater - use the front
    %panel. Their state is reported by `GetStatus`.
    %
    %Note on numeric value command syntax - from the manual: All numeric
    %parameters are treated as signed integers. The range of numbers is
    %-32768 to 32767. For positive numbers, the + sign is optional, as are
    %leading zeroes. Thus to set a target current of 20 Amps, the preferred
    %command form is: I2000 The alternative: I20.00 would be accepted and
    %correctly obeyed, but the alternatives I20 and I20.0 would result in
    %set currents of 0.2 or 2.0 amps respectively. Hence unless you can be
    %confident your computer will always send a specific number of decimal
    %places, it is preferable to convert all data to integers. Similarly
    %for returned number, 23.09 Amps would be returned as +02309 (multiply/divide
    %everything by 100?)

    %% Properties (Public)
    properties(Access = public)
        FullName = "Mercury 120-10 IPS";                        %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "120-10IPS";                                     %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.Serial;    %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end

    %% Constructor
    methods
        function this = Mercury120_10_IPS()
            %Set the connection options and the Magnet and Sweep Control tabs.

            %RS-232 only (directly, or as a VISA serial resource): 9600 baud,
            %8 data bits, 2 stop bits, CR terminators
            this.DefineSupportedConnectionTypes(["Debug", "Serial", "VISA"]);
            this.ConnectionSettings.SerialSettings.Terminator = "CR";
            this.ConnectionSettings.SerialSettings.StopBits = 2;
            this.VISA_Address = "ASRL4::INSTR";
            this.Serial_Address = "COM4";

            %Define the Instrument Controls that can be added
            this.DefineInstrumentControl(Name = "Magnet Control", ClassName = "MagnetController", TabName = "Magnet Control", EnabledByDefault = true);
            this.DefineInstrumentControl(Name = "Sweep Control", ClassName = "SweepController_Ramp", TabName = "Sweep Control", EnabledByDefault = false);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function AbortRamp(this)
            %Stop a running sweep by putting the supply into Hold.

            this.SetState_Hold();
        end

        function rampStatus = CheckRampStatus(this, timeElapsed_s, tDiff, currentTarget, rampRate_min, sweepController) %#ok<INUSD>
            %Check whether the field has finished ramping, for the Sweep Control.
            %The ramp is finished when the supply reports its output as At rest.
            %In SimulationMode the field is ramped by the Sweep Control instead
            %
            %Inputs:
            %   timeElapsed_s   - time since the sweep started, in s (not used)
            %   tDiff           - time since the last check, in s
            %   currentTarget   - target field of this ramp, in T
            %   rampRate_min    - ramp rate, in T/min
            %   sweepController - the SweepController_Ramp calling this
            %
            %Outputs:
            %   rampStatus - struct with field TargetReached (and CurrentField,
            %                in T, in SimulationMode)

            if this.SimulationMode
                rampStatus = sweepController.SimulateRamping(tDiff, currentTarget, rampRate_min);
                this.SimulatedData.Field_T = rampStatus.CurrentField;
                this.SimulatedData.Current_A = rampStatus.CurrentField*12;
                return;
            end

            isRamping = this.GetRampStatus();
            rampStatus.TargetReached = ~isRamping;
        end

        function Close(this)
            %Put the supply back into Local and Unlocked control, then disconnect.
            %Local control is only set if the connection was opened, so a failed
            %Connect can still be closed

            if ~isempty(this.DeviceHandle)
                this.SetLocal();
            end

            Close@Palladium.Core.Instrument(this);
        end

        function Connect(this)
            %Open the connection and put the supply into Remote and Unlocked control.
            %The supply only obeys control commands in Remote control

            Connect@Palladium.Core.Instrument(this);

            %Read the status once and discard it, before sending any commands
            this.QueryString("X");

            %Remote and Unlocked: commands are accepted, and the front panel
            %LOC/REM button can still return the supply to Local control
            this.SetRemote();
        end

        function statusStruct = GatherStatusStructForControlPanel(this)
            %Read the field, current, ramp rate, set point and sweep status, for the Magnet Control tab.
            %
            %Outputs:
            %   statusStruct - struct with fields Current_A, Field_T,
            %                  RampRate_Tmin, SetPoint_T and StatusString (the
            %                  SweepStatus from GetStatus, e.g. "At rest")

            statusStruct.Current_A = this.GetCurrent();
            statusStruct.Field_T = this.GetField();
            statusStruct.RampRate_Tmin = this.GetFieldRampRate();
            statusStruct.SetPoint_T = this.GetSetPointField();

            status = this.GetStatus();
            statusStruct.StatusString = status.SweepStatus;
        end

        function current_A = GetCurrent(this)
            %Read the measured magnet current, in A (R2).

            if this.SimulationMode
                current_A = this.RetrieveSimulatedDataValue("Current_A");
                return;
            end

            current_A = this.QueryAndParseIPSCommand("R2") / 100;
        end

        function [upperLimit, lowerLimit] = GetCurrentLimits(this)
            %Read the supply's safe current limits, in A (R22 and R21).
            %
            %Outputs:
            %   upperLimit - most positive allowed current, in A
            %   lowerLimit - most negative allowed current, in A

            if this.SimulationMode
                upperLimit = 60;
                lowerLimit = -60;
                return;
            end

            upperLimit = this.QueryAndParseIPSCommand("R22") / 100;
            lowerLimit = this.QueryAndParseIPSCommand("R21") / 100;
        end

        function currentRampRate_Amin = GetCurrentRampRate(this)
            %Read the current sweep rate, in A/min (R6).

            if this.SimulationMode
                currentRampRate_Amin = 1.1;
                return;
            end

            currentRampRate_Amin = this.QueryAndParseIPSCommand("R6") / 100;
        end

        function field_T = GetField(this)
            %Read the output field, in T (R7).
            %This is the field the supply is driving, calculated from its output
            %current - in persistent mode it is not the field in the magnet

            if this.SimulationMode
                field_T = this.RetrieveSimulatedDataValue("Field_T");
                return;
            end

            field_T = this.QueryAndParseIPSCommand("R7") / 1000;
        end

        function fieldRampRate_Tmin = GetFieldRampRate(this)
            %Read the field sweep rate, in T/min (R9).

            if this.SimulationMode
                fieldRampRate_Tmin = 0.1;
                return;
            end

            fieldRampRate_Tmin = this.QueryAndParseIPSCommand("R9") / 1000;
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %
            %Outputs:
            %   Headers - [Name + " - Field (T)", Name + " - Current (A)"]
            %   Units   - ["T", "A"]

            Headers = [this.Name + " - Field (T)", this.Name + " - Current (A)"];
            Units = ["T", "A"];
        end

        function inductance_H = GetMagnetInductance(this)
            %Read the magnet inductance, in H (R24).
            %R24 is not in the PS120-10 manual's list of parameters (R0 to R22),
            %so this probably returns NaN on this supply

            if this.SimulationMode
                inductance_H = 0;
                return;
            end

            inductance_H = this.QueryAndParseIPSCommand("R24") / 100;
        end

        function isRamping = GetRampStatus(this)
            %Read whether the output is changing, from the sweep status.
            %
            %Outputs:
            %   isRamping - false if the sweep status is At rest, true otherwise

            status = this.GetStatus();
            isRamping = ~strcmp(status.SweepStatus, "At rest");
        end

        function setPtCurrent_A = GetSetPointCurrent(this)
            %Read the target current, in A (R5).
            %Repeats the query until it returns a number

            if this.SimulationMode
                setPtCurrent_A = 0;
                return;
            end
            setPtCurrent_A = NaN;

            while(isnan(setPtCurrent_A))
                setPtCurrent_A = this.QueryAndParseIPSCommand("R5") / 100;
                pause(0.01);
            end
        end

        function setPtField_T = GetSetPointField(this)
            %Read the target field, in T (R8).

            if this.SimulationMode
                setPtField_T = 0;
                return;
            end

            setPtField_T = this.QueryAndParseIPSCommand("R8") / 1000;
        end

        function status = GetStatus(this)
            %Read and decode the supply's status (X command).
            %The reply has the form `XmnAnCnHnMmnPmn`. The display and sweep
            %mode (M) codes differ from the IPS120's
            %
            %Outputs:
            %   status - struct of status strings, with fields SystemStatus
            %            (e.g. "Normal" or "Quenched"), SupplyStatus,
            %            ActivityStatus ("Hold", "To Set Point", "To Zero" or
            %            "Clamped"), CommandStatus (Local/Remote and
            %            Locked/Unlocked), SwitchHeaterStatus,
            %            DisplayAndSpeedStatus, SweepStatus ("At rest" when the
            %            output is constant) and PolarityStatus

            if this.SimulationMode
                %Example string, to test the parsing below
                statusString = 'X00A4C3H8M20P04';
            else
                statusString = char(this.QueryString("X"));
            end

            %System status - Xmn, m
            systemStatusString = statusString(2:2);
            switch(systemStatusString)
                case('0');      status.SystemStatus = "Normal";
                case('1');      status.SystemStatus = "Quenched";
                case('2');      status.SystemStatus = "Over Heated";
                case('4');      status.SystemStatus = "Warming Up";
                otherwise
                    error("Mercury120_10_IPS:UnrecognisedSystemStatus", "%s", "Error parsing IPS status - " + "System status string " + string(systemStatusString) + " not recognised. " + "Total status string: " + string(statusString));
            end

            %Supply status - Xmn, n
            supplyStatusString = statusString(3:3);
            switch(supplyStatusString)
                case('0');      status.SupplyStatus = "Normal";
                case('1');      status.SupplyStatus = "On Positive Voltage Limit";
                case('2');      status.SupplyStatus = "On Negative Voltage Limit";
                case('4');      status.SupplyStatus = "Outside Negative Current Limit";
                case('8');      status.SupplyStatus = "Outside Positive Current Limit";
                otherwise
                    error("Mercury120_10_IPS:UnrecognisedSupplyStatus", "%s", "Error parsing IPS status - " + "Supply status string " + string(supplyStatusString) + " not recognised. " + "Total status string: " + string(statusString));
            end

            %Activity status - An
            activityStatusString = statusString(5:5);
            switch(activityStatusString)
                case('0');      status.ActivityStatus = "Hold";
                case('1');      status.ActivityStatus = "To Set Point";
                case('2');      status.ActivityStatus = "To Zero";
                case('4');      status.ActivityStatus = "Clamped";
                otherwise
                    error("Mercury120_10_IPS:UnrecognisedActivityStatus", "%s", "Error parsing IPS status - " + "Activity status string " + string(activityStatusString) + " not recognised. " + "Total status string: " + string(statusString));
            end

            %Command status (Local/Remote/Lock) - Cn
            commandStatusString = statusString(7:7);
            switch(commandStatusString)
                case('0');      status.CommandStatus = "Local and Locked";
                case('1');      status.CommandStatus = "Remote and Locked";
                case('2');      status.CommandStatus = "Local and Unlocked";
                case('3');      status.CommandStatus = "Remote and Unlocked";
                case('4');      status.CommandStatus = "Auto Run-Down";
                case('5');      status.CommandStatus = "Auto Run-Down";
                case('6');      status.CommandStatus = "Auto Run-Down";
                case('7');      status.CommandStatus = "Auto Run-Down";
                otherwise
                    error("Mercury120_10_IPS:UnrecognisedCommandStatus", "%s", "Error parsing IPS status - " + "Command status string " + string(commandStatusString) + " not recognised. " + "Total status string: " + string(statusString));
            end

            %Switch heater status - Hn
            switchStatusString = statusString(9:9);
            switch(switchStatusString)
                case('0');      status.SwitchHeaterStatus = "Off Magnet at Zero (switch closed)";
                case('1');      status.SwitchHeaterStatus = "On (switch open)";
                case('2');      status.SwitchHeaterStatus = "Off Magnet at Field (switch closed)";
                case('5');      status.SwitchHeaterStatus = "Heater Fault";
                case('8');      status.SwitchHeaterStatus = "No Switch Fitted";
                otherwise
                    error("Mercury120_10_IPS:UnrecognisedSwitchStatus", "%s", "Error parsing IPS status - " + "Switch status string " + string(switchStatusString) + " not recognised. " + "Total status string: " + string(statusString));
            end

            %Display, sweep/immediate mode and sweep speed - Mmn, m
            displayAndSpeedStatusString = statusString(11:11);
            switch(displayAndSpeedStatusString)
                case('0');      status.DisplayAndSpeedStatus = "Amps - Immediate - Fast";
                case('1');      status.DisplayAndSpeedStatus = "Tesla - Immediate - Fast";
                case('2');      status.DisplayAndSpeedStatus = "Amps - Sweep - Fast";
                case('3');      status.DisplayAndSpeedStatus = "Tesla - Sweep - Fast";
                case('4');      status.DisplayAndSpeedStatus = "Amps - Immediate - Train";
                case('5');      status.DisplayAndSpeedStatus = "Tesla - Immediate - Train";
                case('6');      status.DisplayAndSpeedStatus = "Amps - Sweep - Train";
                case('7');      status.DisplayAndSpeedStatus = "Tesla - Sweep - Train";
                otherwise
                    error("Mercury120_10_IPS:UnrecognisedDisplayAndSpeedStatus", "%s", "Error parsing IPS status - " + "DisplayAndSpeed status string " + string(displayAndSpeedStatusString) + " not recognised. " + "Total status string: " + string(statusString));
            end

            %Sweep status - Mmn, n. Only At rest has a constant output; the
            %manual calls 2 "Rate Limiting"
            sweepStatusString = statusString(12:12);
            switch(sweepStatusString)
                case('0');      status.SweepStatus = "At rest";
                case('1');      status.SweepStatus = "Sweeping";
                case('2');      status.SweepStatus = "Sweep Limiting";
                case('3');      status.SweepStatus = "Sweeping and Sweep Limiting";
                otherwise
                    error("Mercury120_10_IPS:UnrecognisedSweepStatus", "%s", "Error parsing IPS status - " + "Sweep status string " + string(sweepStatusString) + " not recognised. " + "Total status string: " + string(statusString));
            end

            %Polarity - Pmn, m. The magnet and commanded polarities; 4-7
            %repeat 0-3 with the desired polarity reversed
            polarityStatusString = statusString(14:14);
            switch(polarityStatusString)
                case('0');      status.PolarityStatus = "Mag Pos - Comm Pos";
                case('1');      status.PolarityStatus = "Mag Pos - Comm Neg";
                case('2');      status.PolarityStatus = "Mag Neg - Comm Pos";
                case('3');      status.PolarityStatus = "Mag Neg - Comm Neg";
                case('4');      status.PolarityStatus = "Mag Pos - Comm Pos";
                case('5');      status.PolarityStatus = "Mag Pos - Comm Neg";
                case('6');      status.PolarityStatus = "Mag Neg - Comm Pos";
                case('7');      status.PolarityStatus = "Mag Neg - Comm Neg";
                otherwise
                    error("Mercury120_10_IPS:UnrecognisedPolarityStatus", "%s", "Error parsing IPS status - " + "Polarity status string " + string(polarityStatusString) + " not recognised. " + "Total status string: " + string(statusString));
            end
        end

        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(~)
            %Units, limits and plot labels of the swept field, for the Sweep Control.
            %
            %Outputs:
            %   str       - units, "T"
            %   limits    - allowed range of target fields, [-6, 6] T
            %   xlabelStr - plot x-axis label, "Time (mins)"
            %   ylabelStr - plot y-axis label, "Field (T)"

            str = "T";
            limits = [-6, 6];
            xlabelStr = "Time (mins)";
            ylabelStr = "Field (T)";
        end

        function [dataRow] = Measure(this)
            %Read the field and current.
            %
            %Outputs:
            %   dataRow - [field in T, current in A]

            field = this.GetField();
            current = this.GetCurrent();

            dataRow = [field, current];
        end

        function SetLocal(this)
            %Put the supply into Local and Unlocked control (C2).
            %The other options are C0 (Local and Locked, the power-up state), C1
            %(Remote and Locked) and C3 (Remote and Unlocked)

            this.QueryString("C2");
        end

        function SetMode_Amps(this)
            %Show current (A) on the front-panel display (M8).
            %Sweep mode and speed are unchanged

            this.QueryString("M8");
        end

        function SetMode_Tesla(this)
            %Show field (T) on the front-panel display (M9).
            %Sweep mode and speed are unchanged

            this.QueryString("M9");
        end

        function SetRampingToTarget(this, target, rate, settings) %#ok<INUSD>
            %Set the field ramp rate and target field, then start ramping to it, for the Sweep Control.
            %
            %Inputs:
            %   target   - target field, in T
            %   rate     - field ramp rate, in T/min
            %   settings - not used

            this.SetRampRate_TeslaMin(rate);
            this.SetTargetField(target);
            this.SetState_RampToSetPoint();
        end

        function SetRampRate_AmpsMin(this, currentRampRate_Amin)
            %Set the current sweep rate, in A/min (S command).
            %Sent in units of 0.01 A/min
            %
            %Inputs:
            %   currentRampRate_Amin - sweep rate, in A/min

            arguments
                this
                currentRampRate_Amin (1,1) double;
            end

            commandStr = "S" + this.NumToIntText(currentRampRate_Amin, 100);
            this.QueryString(commandStr);
        end

        function SetRampRate_TeslaMin(this, fieldRampRate_Tmin)
            %Set the field sweep rate, in T/min (T command).
            %Sent in units of 0.001 T/min. Unlike Mercury120_IPS, the rate is not
            %read back to check it
            %
            %Inputs:
            %   fieldRampRate_Tmin - sweep rate, in T/min

            arguments
                this
                fieldRampRate_Tmin (1,1) double;
            end

            if this.SimulationMode
                disp("Field ramp rate set to " + num2str(fieldRampRate_Tmin) + " T per min");
                return;
            end

            commandStr = "T" + this.NumToIntText(fieldRampRate_Tmin, 1000);
            this.QueryString(commandStr);
        end

        function SetRemote(this)
            %Put the supply into Remote and Unlocked control (C3).
            %Control commands are only obeyed in Remote control. Unlocked
            %leaves the front-panel LOC/REM button active

            this.QueryString("C3");
        end

        function SetState_Clamp(this)
            %Clamp the supply's output (A4).
            %Clamped is the state at power-up. To Set Point and To Zero are not
            %recognised while clamped - SetState_RampToSetPoint puts the supply
            %into Hold first if needed

            this.QueryString("A4");
        end

        function SetState_Hold(this)
            %Hold the output at its present value (A0).

            this.QueryString("A0");
        end

        function SetState_RampToSetPoint(this)
            %Start ramping the output to the target field or current (A1).
            %If the supply is Clamped, puts it into Hold first, since A1 is not
            %recognised while clamped

            status = this.GetStatus();
            if strcmp(status.ActivityStatus, "Clamped")
                this.SetState_Hold();
                pause(0.1);
            end

            this.QueryString("A1");
        end

        function SetState_RampToZero(this)
            %Start ramping the output to zero (A2).

            this.QueryString("A2");
        end

        function SetTargetCurrent(this, current_A)
            %Set the target current, in A (I command), and check it was set.
            %Sent in units of 0.01 A, and read back afterwards - errors if it
            %does not match. Should be positive: the polarity is set separately.
            %Does not start a ramp - see SetState_RampToSetPoint
            %
            %Inputs:
            %   current_A - target current, in A

            arguments
                this
                current_A (1,1) double;
            end

            if this.SimulationMode
                disp("Current setpoint set to " + num2str(current_A) + " A");
                return;
            end

            commandStr = "I" + this.NumToIntText(current_A, 100);
            this.QueryString(commandStr);

            %Query the set point to make sure it set correctly
            achievedSetPt = this.GetSetPointCurrent();
            assert(achievedSetPt == current_A, "Mercury120_10_IPS:SetPointNotSet", "%s", "Failed to set magnet set point on " + this.Name + ". Requested " + num2str(current_A) + " A, achieved " + num2str(achievedSetPt) + " A.");
        end

        function SetTargetField(this, field_T)
            %Set the target field, in T (J command).
            %Sent in units of 0.001 T. Should be positive: the polarity is set
            %separately. Unlike Mercury120_IPS, the target is not read back to
            %check it. Does not start a ramp - see SetState_RampToSetPoint
            %
            %Inputs:
            %   field_T - target field, in T

            arguments
                this
                field_T (1,1) double;
            end

            if this.SimulationMode
                disp("Field setpoint set to " + num2str(field_T) + " T");
                return;
            end

            commandStr = "J" + this.NumToIntText(field_T, 1000);
            this.QueryString(commandStr);
        end

        function SweepComplete(this)
            %Put the supply into Hold once a Sweep Control sweep has finished.

            this.SetState_Hold();
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function str = NumToIntText(~, val, scale)
            %Format a value as the scaled integer the supply expects.
            %Numbers are sent as integers in units of the command's resolution -
            %0.01 A for currents (scale 100) and 0.001 T for fields (scale 1000)
            %
            %Inputs:
            %   val   - the value, in A, A/min, T or T/min
            %   scale - 100 for currents, 1000 for fields
            %
            %Outputs:
            %   str - val * scale, rounded to an integer and zero-padded to 5
            %         digits, e.g. "02000" for 20 A

            str = num2str(int32(val*scale), '%05.0f');
        end

        function value = QueryAndParseIPSCommand(this, commandStr)
            %Send a read command and return its value, as the integer the supply sends.
            %The reply is the command letter followed by the value, e.g.
            %"R+02309" - the first character is dropped. Callers divide by the
            %parameter's scale
            %
            %Inputs:
            %   commandStr - the command to send, e.g. "R7"
            %
            %Outputs:
            %   value - the value, or NaN if the reply was not a number (e.g. an
            %           error reply starting with ?)

            arguments
                this;
                commandStr {mustBeTextScalar};
            end

            resultStr = this.QueryString(commandStr);
            resultSubStr = resultStr(2:end);
            value = str2double(resultSubStr);
        end

    end
end
