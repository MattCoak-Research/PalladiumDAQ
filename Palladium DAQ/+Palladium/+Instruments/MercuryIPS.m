classdef MercuryIPS < Palladium.Core.Instrument
    %MercuryIPS - Instrument driver for the Oxford Instruments MercuryiPS superconducting magnet power supply.
    %Records the magnet field (T) and current (A) each measurement tick. The
    %Magnet Control tab sets the target field and field ramp rate and gives
    %Hold, To Set Point and To Zero commands; the optional Sweep Control tab
    %ramps the field through a sequence of target points. The persistent
    %switch heater can be read and set from scripts.
    %
    %The MercuryiPS uses the same SCPI-like `READ:`/`SET:` protocol as the
    %MercuryITC (see `MercuryITC`), from chapter 10 "Command Reference
    %Guide" of the MercuryiPS Operator's Manual (Issue 14, Mar 2016,
    %UMC0071). Every command is answered with a `STAT:` reply, ending in
    %`:VALID` or `:INVALID` for `SET:` commands; an `INVALID` reply raises an
    %error. The magnet is addressed as `DEV:<UID>:PSU`, where `<UID>` is set
    %by `AxisAddress`: an axis group such as `GRPZ` (the default, for a
    %single-axis solenoid or split pair) or an individual power supply board
    %such as `PSU.M1`. Groups accept more commands than boards - the ramp
    %status, switch heater, target and ramp rate are only settable on a
    %group.
    %
    %Ethernet (port 7020, always), GPIB, RS-232 and USB (a virtual serial
    %port, 115200 baud, 8 data bits, 1 stop bit) are supported, all with
    %LF terminators.
    %
    %It has the same public methods as `Mercury120_IPS` (GetField,
    %SetTargetField, SetState_Hold, and so on), so either can drive the
    %Magnet Control and Sweep Control tabs.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Oxford Instruments MercuryiPS";             %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "MercuryIPS";                                    %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.Ethernet;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.

        %UID of the magnet power supply to address: an axis group, e.g. "GRPZ" (the default) or "GRPX"/"GRPY" on a vector magnet, or a board, e.g. "PSU.M1". GetDeviceCatalog lists them.
        AxisAddress {mustBeTextScalar} = "GRPZ";

        FieldLimits_T (1,2) double = [-16 16];                  %Lowest and highest target field allowed in the Sweep Control, in T
    end

    %% Constructor
    methods
        function this = MercuryIPS()
            %Set the connection options and the Magnet and Sweep Control tabs.

            this.DefineSupportedConnectionTypes(["Debug", "Ethernet", "GPIB", "Serial", "VISA"]);

            %Commands and replies end in LF on every interface. The Ethernet
            %port is always 7020. 115200 baud, 8 data bits and 1 stop bit
            %are the USB virtual serial port's fixed settings; the RS-232
            %port's baud rate is set on the instrument
            this.ConnectionSettings.Port = 7020;
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];
            this.ConnectionSettings.SerialSettings.BaudRate = 115200;
            this.ConnectionSettings.SerialSettings.StopBits = 1;
            this.ConnectionSettings.SerialSettings.Terminator = "LF";

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

        function rampStatus = CheckRampStatus(this, ~, tDiff, currentTarget, rampRate_min, ~)
            %Check whether the field has finished ramping, for the Sweep Control.
            %The ramp is taken as finished when the ramp status (ACTN) is no
            %longer To Set Point or To Zero. In SimulationMode the field is
            %ramped towards the target at the ramp rate
            %
            %Inputs (in the order the Sweep Control passes them):
            %   timeElapsed_s   - time since the sweep started, in s (not used)
            %   tDiff           - time since the last check, in s
            %   currentTarget   - target field of this ramp, in T
            %   rampRate_min    - ramp rate, in T/min
            %   sweepController - the SweepController_Ramp calling this (not used)
            %
            %Outputs:
            %   rampStatus - struct with field TargetReached

            if this.SimulationMode
                lastField = this.RetrieveSimulatedDataValue("Field_T");
                newField = lastField + tDiff * sign(currentTarget - lastField) * rampRate_min / 60;

                rampStatus.TargetReached = false;
                if newField * sign(currentTarget - lastField) >= abs(currentTarget)
                    newField = currentTarget;
                    rampStatus.TargetReached = true;
                end

                this.SimulatedData.Field_T = newField;
                this.SimulatedData.Current_A = newField * this.GetCurrentToFieldRatio();
                return;
            end

            actionCode = this.GetPSUString(this.AxisAddress, "ACTN");
            isRamping = ismember(upper(actionCode), ["RTOS", "RTOZ"]);
            rampStatus.TargetReached = ~isRamping;
        end

        function statusStruct = GatherStatusStructForControlPanel(this)
            %Read the field, current, ramp rate, set point and ramp status, for the Magnet Control tab.
            %
            %Outputs:
            %   statusStruct - struct with fields Current_A, Field_T,
            %                  RampRate_Tmin, SetPoint_T and StatusString (the
            %                  SweepStatus from GetStatus, e.g. "Hold")

            statusStruct.Current_A = this.GetCurrent();
            statusStruct.Field_T = this.GetField();
            statusStruct.RampRate_Tmin = this.GetFieldRampRate();
            statusStruct.SetPoint_T = this.GetSetPointField();

            status = this.GetStatus();
            statusStruct.StatusString = status.SweepStatus;
        end

        function rampRate_Amin = GetActualCurrentRampRate(this)
            %Read the rate the current is actually changing at, in A/min (SIG:RCUR).
            %Only available on an axis group, e.g. AxisAddress = "GRPZ"

            if this.SimulationMode
                rampRate_Amin = 1.1;
                return;
            end

            rampRate_Amin = this.GetPSUValue(this.AxisAddress, "SIG:RCUR");
        end

        function rampRate_Tmin = GetActualFieldRampRate(this)
            %Read the rate the field is actually changing at, in T/min (SIG:RFLD).
            %Only available on an axis group, e.g. AxisAddress = "GRPZ"

            if this.SimulationMode
                rampRate_Tmin = 0.1;
                return;
            end

            rampRate_Tmin = this.GetPSUValue(this.AxisAddress, "SIG:RFLD");
        end

        function current_A = GetCurrent(this)
            %Read the output current, in A (SIG:CURR).
            %On an axis group, this is the sum of its power supply boards' currents

            if this.SimulationMode
                current_A = this.RetrieveSimulatedDataValue("Current_A");
                return;
            end

            current_A = this.GetPSUValue(this.AxisAddress, "SIG:CURR");
        end

        function currentLimit_A = GetCurrentLimit(this)
            %Read the maximum current set for the power supply, in A (CLIM).

            if this.SimulationMode
                currentLimit_A = 120;
                return;
            end

            currentLimit_A = this.GetPSUValue(this.AxisAddress, "CLIM");
        end

        function rampRate_Amin = GetCurrentRampRate(this)
            %Read the target current ramp rate, in A/min (SIG:RCST).

            if this.SimulationMode
                rampRate_Amin = 1.1;
                return;
            end

            rampRate_Amin = this.GetPSUValue(this.AxisAddress, "SIG:RCST");
        end

        function ratio_AperT = GetCurrentToFieldRatio(this)
            %Read the magnet's current to field ratio, in A/T (ATOB).
            %Only available on an axis group, e.g. AxisAddress = "GRPZ"

            if this.SimulationMode
                ratio_AperT = 10;
                return;
            end

            ratio_AperT = this.GetPSUValue(this.AxisAddress, "ATOB");
        end

        function catalogString = GetDeviceCatalog(this)
            %Read the list of devices the instrument has (SYS:CAT).
            %Use it to find the UIDs of the axis groups and power supply boards
            %(e.g. "GRPZ" and "PSU.M1") to set AxisAddress to
            %
            %Outputs:
            %   catalogString - the reply, listing each device as
            %                   DEV:<UID>:<type>, e.g. DEV:GRPZ:PSU

            if this.SimulationMode
                catalogString = "SIMULATED DEVICE CATALOG";
                return;
            end

            catalogString = this.ReadValue("SYS:CAT");
        end

        function field_T = GetField(this)
            %Read the output field, in T (SIG:FLD).
            %This is the field the supply is driving - in persistent mode it is not
            %the field in the magnet (see GetPersistentField)

            if this.SimulationMode
                field_T = this.RetrieveSimulatedDataValue("Field_T");
                return;
            end

            field_T = this.GetPSUValue(this.AxisAddress, "SIG:FLD");
        end

        function rampRate_Tmin = GetFieldRampRate(this)
            %Read the target field ramp rate, in T/min (SIG:RFST).

            if this.SimulationMode
                rampRate_Tmin = 0.1;
                return;
            end

            rampRate_Tmin = this.GetPSUValue(this.AxisAddress, "SIG:RFST");
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

        function idnString = GetIDN(this)
            %Read the instrument's identity string (*IDN?).
            %
            %Outputs:
            %   idnString - e.g. "IDN:OXFORD INSTRUMENTS:MERCURY iPS:<serial>:<firmware>"

            if this.SimulationMode
                idnString = "SIMULATED MERCURY IPS";
                return;
            end

            idnString = this.ReadValue("*IDN?", "");
        end

        function inductance_H = GetMagnetInductance(this)
            %Read the magnet inductance set on the supply, in H (IND).

            if this.SimulationMode
                inductance_H = 0;
                return;
            end

            inductance_H = this.GetPSUValue(this.AxisAddress, "IND");
        end

        function persistentCurrent_A = GetPersistentCurrent(this)
            %Read the persistent current in the magnet, in A (SIG:PCUR).

            if this.SimulationMode
                persistentCurrent_A = 0;
                return;
            end

            persistentCurrent_A = this.GetPSUValue(this.AxisAddress, "SIG:PCUR");
        end

        function persistentField_T = GetPersistentField(this)
            %Read the persistent field in the magnet, in T (SIG:PFLD).

            if this.SimulationMode
                persistentField_T = 0;
                return;
            end

            persistentField_T = this.GetPSUValue(this.AxisAddress, "SIG:PFLD");
        end

        function setPtCurrent_A = GetSetPointCurrent(this)
            %Read the target current, in A (SIG:CSET).

            if this.SimulationMode
                setPtCurrent_A = 0;
                return;
            end

            setPtCurrent_A = this.GetPSUValue(this.AxisAddress, "SIG:CSET");
        end

        function setPtField_T = GetSetPointField(this)
            %Read the target field, in T (SIG:FSET).

            if this.SimulationMode
                setPtField_T = 0;
                return;
            end

            setPtField_T = this.GetPSUValue(this.AxisAddress, "SIG:FSET");
        end

        function status = GetStatus(this)
            %Read the ramp status (ACTN) and switch heater status (SIG:SWHT).
            %
            %Outputs:
            %   status - struct with fields SweepStatus ("Hold", "Ramping To Set
            %            Point", "Ramping To Zero" or "Clamped") and
            %            SwitchHeaterStatus ("On" or "Off")

            if this.SimulationMode
                status.SweepStatus = "Hold";
                status.SwitchHeaterStatus = "Off";
                return;
            end

            actionCode = upper(this.GetPSUString(this.AxisAddress, "ACTN"));
            switch(actionCode)
                case("HOLD");   status.SweepStatus = "Hold";
                case("RTOS");   status.SweepStatus = "Ramping To Set Point";
                case("RTOZ");   status.SweepStatus = "Ramping To Zero";
                case("CLMP");   status.SweepStatus = "Clamped";
                otherwise
                    error("MercuryIPS:UnrecognisedRampAction", "%s", "Error parsing MercuryiPS status - ramp action code " + string(actionCode) + " not recognised.");
            end

            if this.GetSwitchHeaterOn()
                status.SwitchHeaterStatus = "On";
            else
                status.SwitchHeaterStatus = "Off";
            end
        end

        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(this)
            %Units, limits and plot labels of the swept field, for the Sweep Control.
            %
            %Outputs:
            %   str       - units, "T"
            %   limits    - allowed range of target fields, FieldLimits_T
            %   xlabelStr - plot x-axis label, "Time (mins)"
            %   ylabelStr - plot y-axis label, "Field (T)"

            str = "T";
            limits = this.FieldLimits_T;
            xlabelStr = "Time (mins)";
            ylabelStr = "Field (T)";
        end

        function current_A = GetSwitchHeaterCurrent(this)
            %Read the switch heater current set on the supply (SHTC).

            if this.SimulationMode
                current_A = 0;
                return;
            end

            current_A = this.GetPSUValue(this.AxisAddress, "SHTC");
        end

        function isOn = GetSwitchHeaterOn(this)
            %Read whether the persistent switch heater is on (SIG:SWHT).
            %
            %Outputs:
            %   isOn - true if the heater is on (switch open, magnet driven by the
            %          supply)

            if this.SimulationMode
                isOn = true;
                return;
            end

            statusStr = this.GetPSUString(this.AxisAddress, "SIG:SWHT");
            isOn = strcmpi(statusStr, "ON");
        end

        function voltage_V = GetVoltage(this)
            %Read the output voltage, in V (SIG:VOLT).

            if this.SimulationMode
                voltage_V = 0;
                return;
            end

            voltage_V = this.GetPSUValue(this.AxisAddress, "SIG:VOLT");
        end

        function voltageLimit_V = GetVoltageLimit(this)
            %Read the maximum normal operating voltage (the quench threshold), in V (VLIM).

            if this.SimulationMode
                voltageLimit_V = 10;
                return;
            end

            voltageLimit_V = this.GetPSUValue(this.AxisAddress, "VLIM");
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

        function resultString = ReadValue(this, command, readPrefix)
            %Send a read command and return the reply.
            %
            %Inputs:
            %   command    - what to read, e.g. "DEV:GRPZ:PSU:SIG:FLD"
            %   readPrefix - text sent before command; "READ:" (the default), or ""
            %                for commands such as *IDN?
            %
            %Outputs:
            %   resultString - the reply, e.g. "STAT:DEV:GRPZ:PSU:SIG:FLD:1.2345T"

            arguments
                this;
                command {mustBeTextScalar};
                readPrefix {mustBeTextScalar} = "READ:";
            end

            if this.SimulationMode
                resultString = "null";
                return;
            end

            resultString = char(this.QueryString(string(readPrefix) + string(command)));
        end

        function SetCurrentRampRate_AminMin(this, currentRampRate_Amin)
            %Set the target current ramp rate, in A/min (SIG:RCST), and check it was set.
            %Errors if the value the supply confirms does not match
            %
            %Inputs:
            %   currentRampRate_Amin - ramp rate, in A/min

            arguments
                this
                currentRampRate_Amin (1,1) double;
            end

            if this.SimulationMode
                disp("Current ramp rate set to " + num2str(currentRampRate_Amin) + " A per min");
                return;
            end

            achievedRate = this.SetPSUValue(this.AxisAddress, "SIG:RCST", currentRampRate_Amin);
            assert(achievedRate == currentRampRate_Amin, "MercuryIPS:RampRateNotSet", "%s", "Failed to set magnet current ramp rate on " + this.Name + ". Requested " + num2str(currentRampRate_Amin) + " A/min, achieved " + num2str(achievedRate) + " A/min.");
        end

        function SetFieldRampRate_TeslaMin(this, fieldRampRate_Tmin)
            %Set the target field ramp rate, in T/min (SIG:RFST), and check it was set.
            %Errors if the value the supply confirms does not match
            %
            %Inputs:
            %   fieldRampRate_Tmin - ramp rate, in T/min

            arguments
                this
                fieldRampRate_Tmin (1,1) double;
            end

            if this.SimulationMode
                disp("Field ramp rate set to " + num2str(fieldRampRate_Tmin) + " T per min");
                return;
            end

            achievedRate = this.SetPSUValue(this.AxisAddress, "SIG:RFST", fieldRampRate_Tmin);
            assert(achievedRate == fieldRampRate_Tmin, "MercuryIPS:RampRateNotSet", "%s", "Failed to set magnet field ramp rate on " + this.Name + ". Requested " + num2str(fieldRampRate_Tmin) + " T/min, achieved " + num2str(achievedRate) + " T/min.");
        end

        function SetRampingToTarget(this, target, rate, ~)
            %Set the field ramp rate and target field, then start ramping to it, for the Sweep Control.
            %
            %Inputs:
            %   target - target field, in T
            %   rate   - field ramp rate, in T/min

            this.SetFieldRampRate_TeslaMin(rate);
            this.SetTargetField(target);
            this.SetState_RampToSetPoint();
        end

        function SetRampRate_TeslaMin(this, fieldRampRate_Tmin)
            %Set the target field ramp rate, in T/min - the same as SetFieldRampRate_TeslaMin.
            %The Magnet Control tab calls this name, which Mercury120_IPS and
            %Mercury120_10_IPS use
            %
            %Inputs:
            %   fieldRampRate_Tmin - ramp rate, in T/min

            this.SetFieldRampRate_TeslaMin(fieldRampRate_Tmin);
        end

        function SetState_Clamp(this)
            %Clamp the supply's output (ACTN CLMP).
            %Clamped is the state at power-up. To Set Point and To Zero are not
            %recognised while clamped, so give a Hold command first

            if this.SimulationMode
                disp("Magnet state set to Clamp");
                return;
            end

            this.SetPSUString(this.AxisAddress, "ACTN", "CLMP");
        end

        function SetState_Hold(this)
            %Hold the output at its present value (ACTN HOLD).

            if this.SimulationMode
                disp("Magnet state set to Hold");
                return;
            end

            this.SetPSUString(this.AxisAddress, "ACTN", "HOLD");
        end

        function SetState_RampToSetPoint(this)
            %Start ramping the output to the target field or current (ACTN RTOS).

            if this.SimulationMode
                disp("Magnet ramping to set point");
                return;
            end

            this.SetPSUString(this.AxisAddress, "ACTN", "RTOS");
        end

        function SetState_RampToZero(this)
            %Start ramping the output to zero (ACTN RTOZ).

            if this.SimulationMode
                disp("Magnet ramping to zero");
                return;
            end

            this.SetPSUString(this.AxisAddress, "ACTN", "RTOZ");
        end

        function SetSwitchHeaterOff(this)
            %Turn the persistent switch heater off (SIG:SWHT OFF), closing the switch.

            if this.SimulationMode
                disp("Switch heater turned OFF (simulated)");
                return;
            end

            this.SetPSUString(this.AxisAddress, "SIG:SWHT", "OFF");
        end

        function SetSwitchHeaterOn(this)
            %Turn the persistent switch heater on (SIG:SWHT ON), opening the switch.
            %The instrument checks that the output current matches the persistent
            %current before turning it on

            if this.SimulationMode
                disp("Switch heater turned ON (simulated)");
                return;
            end

            this.SetPSUString(this.AxisAddress, "SIG:SWHT", "ON");
        end

        function SetSwitchHeaterOn_Forced(this)
            %Turn the persistent switch heater on without the instrument's current check (SIG:SWHN ON).
            %Only use this if you know the output and persistent currents match:
            %opening the switch with them mismatched can quench the magnet

            if this.SimulationMode
                disp("Switch heater force-turned ON (simulated)");
                return;
            end

            this.SetPSUString(this.AxisAddress, "SIG:SWHN", "ON");
        end

        function SetTargetCurrent(this, current_A)
            %Set the target current, in A (SIG:CSET), and check it was set.
            %Errors if the value the supply confirms does not match. Does not start
            %a ramp - see SetState_RampToSetPoint
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

            achievedSetPt = this.SetPSUValue(this.AxisAddress, "SIG:CSET", current_A);
            assert(achievedSetPt == current_A, "MercuryIPS:SetPointNotSet", "%s", "Failed to set magnet set point on " + this.Name + ". Requested " + num2str(current_A) + " A, achieved " + num2str(achievedSetPt) + " A.");
        end

        function SetTargetField(this, field_T)
            %Set the target field, in T (SIG:FSET), and check it was set.
            %Errors if the value the supply confirms does not match. Does not start
            %a ramp - see SetState_RampToSetPoint
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

            achievedSetPt = this.SetPSUValue(this.AxisAddress, "SIG:FSET", field_T);
            assert(achievedSetPt == field_T, "MercuryIPS:SetPointNotSet", "%s", "Failed to set magnet set point on " + this.Name + ". Requested " + num2str(field_T) + " T, achieved " + num2str(achievedSetPt) + " T.");
        end

        function resultString = SetValue(this, command)
            %Send a set command and return the reply.
            %
            %Inputs:
            %   command - what to set, with its value, e.g.
            %             "DEV:GRPZ:PSU:SIG:FSET:1.5" ("SET:" is added in front)
            %
            %Outputs:
            %   resultString - the reply, e.g.
            %                  "STAT:DEV:GRPZ:PSU:SIG:FSET:1.5:VALID"

            arguments
                this;
                command {mustBeTextScalar};
            end

            if this.SimulationMode
                resultString = "null";
                return;
            end

            resultString = char(this.QueryString("SET:" + string(command)));
        end

        function SweepComplete(this)
            %Put the supply into Hold once a Sweep Control sweep has finished.

            this.SetState_Hold();
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function value = GetPSUValue(this, uid, noun)
            %Read a numeric DEV:<uid>:PSU:<noun> value, e.g. noun = "SIG:FLD" or "CLIM".
            %
            %Outputs:
            %   value - the value, scaled by its SI prefix (so mT is returned in T)

            arguments
                this;
                uid {mustBeTextScalar};
                noun {mustBeTextScalar};
            end

            if this.SimulationMode
                value = 0;
                return;
            end

            responseString = this.ReadValue("DEV:" + string(uid) + ":PSU:" + string(noun));
            value = this.ParseSignalResponse(responseString);
        end

        function strVal = GetPSUString(this, uid, noun)
            %Read a text DEV:<uid>:PSU:<noun> value, e.g. noun = "ACTN" or "SIG:SWHT".
            %
            %Outputs:
            %   strVal - the value, e.g. "HOLD" or "ON"

            arguments
                this;
                uid {mustBeTextScalar};
                noun {mustBeTextScalar};
            end

            if this.SimulationMode
                strVal = "";
                return;
            end

            responseString = this.ReadValue("DEV:" + string(uid) + ":PSU:" + string(noun));
            strVal = this.ParseStringResponse(responseString);
        end

        function mult = GetSIPrefixMultiplier(~, unitToken)
            %Multiplier for the SI prefix at the start of a unit, e.g. 1e-3 for "mT".
            %A unit with no recognised prefix, e.g. "T", "A" or "T/m", gives 1
            %
            %Inputs:
            %   unitToken - the unit, e.g. "mT"
            %
            %Outputs:
            %   mult - the multiplier

            prefixMap = containers.Map(...
                {'n', 'u', char(181), 'm', 'k', 'M'}, ...   %char(181) is the micro sign
                {1e-9, 1e-6, 1e-6, 1e-3, 1e3, 1e6});

            if isempty(unitToken) || strlength(string(unitToken)) < 2
                mult = 1;
                return;
            end

            firstChar = char(unitToken);
            firstChar = firstChar(1);

            if isKey(prefixMap, firstChar)
                mult = prefixMap(firstChar);
            else
                mult = 1;
            end
        end

        function value = ParseSIPrefixedValue(this, valueString)
            %Parse a number followed by its unit, e.g. "1.2345mT", into a double scaled by the unit's SI prefix.
            %Used where the reply has the number and unit in one token (see
            %ParseSignalResponse). The unit can contain any characters, e.g.
            %"T/m" for a ramp rate
            %
            %Inputs:
            %   valueString - e.g. "1.2345mT" or "0.2000T/m"
            %
            %Outputs:
            %   value - e.g. 1.2345e-3 or 0.2

            parts = regexp(char(valueString), '^\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)(.*)$', 'tokens', 'once');
            if isempty(parts)
                error("MercuryIPS:SIValueParseFailed", "%s", "Could not parse SI-prefixed value: " + string(valueString));
            end

            value = str2double(parts{1}) * this.GetSIPrefixMultiplier(strtrim(parts{2}));
        end

        function value = ParseSignalResponse(this, responseString)
            %Parse a STAT:...:<value> reply into a double.
            %Handles a plain number, as echoed by a SET (e.g.
            %"...:FSET:1.5:VALID"); a number and its unit as separate tokens
            %(e.g. "...:SIG:VOLT:12.345:mV"); and a number and its unit as one
            %token (e.g. "...:SIG:FLD:1.2345T"). Errors on an INVALID reply
            %
            %Inputs:
            %   responseString - the reply
            %
            %Outputs:
            %   value - the value, scaled by its SI prefix

            tokens = strsplit(char(responseString), ":");

            if ~isempty(tokens) && any(strcmpi(tokens{end}, ["VALID", "INVALID"]))
                if strcmpi(tokens{end}, "INVALID")
                    error("MercuryIPS:InvalidResponse", "%s", "MercuryiPS returned INVALID for command response: " + string(responseString));
                end
                tokens(end) = [];
            end

            lastToken = tokens{end};

            %Case 1 - plain unscaled numeric value
            directValue = str2double(lastToken);
            if ~isnan(directValue)
                value = directValue;
                return;
            end

            %Case 2 - number and SI-prefixed unit as separate tokens
            if numel(tokens) >= 2 && ~isnan(str2double(tokens{end-1}))
                value = str2double(tokens{end-1}) * this.GetSIPrefixMultiplier(lastToken);
                return;
            end

            %Case 3 - number and unit concatenated into a single token
            value = this.ParseSIPrefixedValue(lastToken);
        end

        function strVal = ParseStringResponse(~, responseString)
            %Parse a STAT:...:<value> reply whose value is text, e.g. ON/OFF or HOLD/RTOS/RTOZ/CLMP.
            %Errors on an INVALID reply
            %
            %Inputs:
            %   responseString - the reply
            %
            %Outputs:
            %   strVal - the value

            tokens = strsplit(char(responseString), ":");

            if ~isempty(tokens) && any(strcmpi(tokens{end}, ["VALID", "INVALID"]))
                if strcmpi(tokens{end}, "INVALID")
                    error("MercuryIPS:InvalidResponse", "%s", "MercuryiPS returned INVALID for command response: " + string(responseString));
                end
                tokens(end) = [];
            end

            strVal = string(tokens{end});
        end

        function confirmedValue = SetPSUValue(this, uid, noun, value)
            %Set a numeric DEV:<uid>:PSU:<noun> value, e.g. noun = "SIG:FSET", and return the value the supply confirms.
            %
            %Inputs:
            %   uid   - power supply UID, e.g. "GRPZ"
            %   noun  - what to set, e.g. "SIG:FSET"
            %   value - the value to set
            %
            %Outputs:
            %   confirmedValue - the value echoed in the supply's VALID reply

            arguments
                this;
                uid {mustBeTextScalar};
                noun {mustBeTextScalar};
                value (1,1) double;
            end

            if this.SimulationMode
                confirmedValue = value;
                return;
            end

            commandStr = "DEV:" + string(uid) + ":PSU:" + string(noun) + ":" + num2str(value);
            responseString = this.SetValue(commandStr);
            confirmedValue = this.ParseSignalResponse(responseString);
        end

        function confirmedStr = SetPSUString(this, uid, noun, valueStr)
            %Set a text DEV:<uid>:PSU:<noun> value, e.g. noun = "ACTN", and return the value the supply confirms.
            %
            %Inputs:
            %   uid      - power supply UID, e.g. "GRPZ"
            %   noun     - what to set, e.g. "ACTN" or "SIG:SWHT"
            %   valueStr - the value to set, e.g. "HOLD" or "ON"
            %
            %Outputs:
            %   confirmedStr - the value echoed in the supply's VALID reply

            arguments
                this;
                uid {mustBeTextScalar};
                noun {mustBeTextScalar};
                valueStr {mustBeTextScalar};
            end

            if this.SimulationMode
                confirmedStr = string(valueStr);
                return;
            end

            commandStr = "DEV:" + string(uid) + ":PSU:" + string(noun) + ":" + string(valueStr);
            responseString = this.SetValue(commandStr);
            confirmedStr = this.ParseStringResponse(responseString);
        end

    end
end
