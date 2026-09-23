classdef MercuryIPS < Palladium.Core.Instrument
    %Instrument implementation for the Oxford Instruments MercuryiPS power
    %supply for superconducting magnets. Commands are taken from the
    %"MercuryiPS Power Supply" Operator's Manual (Issue 14, Mar 2016,
    %UMC0071), Chapter 10 "Command Reference Guide", section 10.3.5.2
    %"Addressing a magnet power supply device".
    %
    %The iPS uses the same SCPI-derived READ:/SET: protocol as the
    %MercuryITC (see MercuryITC.m), so the low-level communication helpers
    %here follow that class as a pattern. Magnet devices/groups are
    %addressed as DEV:<UID>:PSU, where <UID> is either an individual power
    %supply device name (eg "PSU.M1") or an axis group name (eg "GRPZ").
    %This class assumes a single-axis (solenoid / split-pair) magnet, so
    %AxisAddress defaults to the group UID "GRPZ" used in that
    %configuration - change it to address an individual device, or a
    %different axis group on a multi-axis (Vector Rotate) system.
    %
    %This class implements the same public interface as the older
    %Mercury120_IPS.m (GetField, SetTargetField, SetState_Hold, etc, plus
    %the CheckRampStatus/SetRampingToTarget/GatherStatusStructForControlPanel/
    %GetSweepUnitsString methods expected by the MagnetController and
    %SweepController_Ramp Instrument Controls) so it can be used as a
    %drop-in alternative for magnets driven by the newer Mercury protocol.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Oxford Instruments MercuryiPS";     %Full name, just for displaying on GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "MercuryIPS";                                          %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.Ethernet;    %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.

        %UID used to address the magnet power supply, eg the axis group
        %name "GRPZ" (default, single-axis solenoid/split-pair systems),
        %"GRPY"/"GRPX" for other axes on a Vector Rotate system, or an
        %individual device name such as "PSU.M1". Send READ:SYS:CAT to
        %the instrument to list the UIDs it actually has configured.
        AxisAddress = "GRPZ";

        FieldLimits_T = [-16 16];    %Expected operating field range (T), used to configure the Sweep Control GUI
    end

    %% Constructor
    methods
        function this = MercuryIPS()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "Ethernet", "GPIB", "Serial", "VISA"]);

            this.ConnectionSettings.Port = 7020;   %MercuryiPS SCPI Ethernet port
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
            %Called by SweepController_Ramp to abort a running sweep
            this.SetState_Hold();
        end

        function rampStatus = CheckRampStatus(this, ~, tDiff, currentTarget, rampRate_min)
            %Called by SweepController_Ramp to check whether a ramp has
            %reached its target. Return simulated data only if we are
            %debugging without a physical instrument connected
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

            %Real instrument - the unit drops back into "Hold" once a
            %ramp (to set point, or to zero) is complete
            actionCode = this.GetPSUString(this.AxisAddress, "ACTN");
            isRamping = ismember(upper(actionCode), ["RTOS", "RTOZ"]);
            rampStatus.TargetReached = ~isRamping;
        end

        function statusStruct = GatherStatusStructForControlPanel(this)
            %This will get called by the MagnetController Control, if added
            statusStruct.Current_A = this.GetCurrent();
            statusStruct.Field_T = this.GetField();
            statusStruct.RampRate_Tmin = this.GetFieldRampRate();
            statusStruct.SetPoint_T = this.GetSetPointField();

            status = this.GetStatus();
            statusStruct.StatusString = status.SweepStatus;
        end

        function rampRate_Amin = GetActualCurrentRampRate(this)
            %Actual current ramp rate (A/min) - only meaningful when
            %addressing a power supply group (eg AxisAddress = "GRPZ")
            if this.SimulationMode
                rampRate_Amin = 1.1;
                return;
            end

            rampRate_Amin = this.GetPSUValue(this.AxisAddress, "SIG:RCUR");
        end

        function rampRate_Tmin = GetActualFieldRampRate(this)
            %Actual field ramp rate (T/min) - only meaningful when
            %addressing a power supply group (eg AxisAddress = "GRPZ")
            if this.SimulationMode
                rampRate_Tmin = 0.1;
                return;
            end

            rampRate_Tmin = this.GetPSUValue(this.AxisAddress, "SIG:RFLD");
        end

        function current_A = GetCurrent(this)
            if this.SimulationMode
                current_A = this.RetrieveSimulatedDataValue("Current_A");
                return;
            end

            current_A = this.GetPSUValue(this.AxisAddress, "SIG:CURR");
        end

        function currentLimit_A = GetCurrentLimit(this)
            %Maximum current for the power supply group (CLIM)
            if this.SimulationMode
                currentLimit_A = 120;
                return;
            end

            currentLimit_A = this.GetPSUValue(this.AxisAddress, "CLIM");
        end

        function rampRate_Amin = GetCurrentRampRate(this)
            %Target current ramp rate (A/min)
            if this.SimulationMode
                rampRate_Amin = 1.1;
                return;
            end

            rampRate_Amin = this.GetPSUValue(this.AxisAddress, "SIG:RCST");
        end

        function ratio_AperT = GetCurrentToFieldRatio(this)
            %Current to field ratio (A/T), ATOB - only meaningful when
            %addressing a power supply group (eg AxisAddress = "GRPZ")
            if this.SimulationMode
                ratio_AperT = 10;
                return;
            end

            ratio_AperT = this.GetPSUValue(this.AxisAddress, "ATOB");
        end

        function catalogString = GetDeviceCatalog(this)
            %Query the instrument for the catalogue of devices/boards it
            %can see (SYS:CAT). Use this to find the UIDs of the power
            %supply devices/groups actually configured (eg "PSU.M1",
            %"GRPZ") to set AxisAddress correctly.
            if this.SimulationMode
                catalogString = "SIMULATED DEVICE CATALOG";
                return;
            end

            catalogString = this.ReadValue("SYS:CAT");
        end

        function field_T = GetField(this)
            if this.SimulationMode
                field_T = this.RetrieveSimulatedDataValue("Field_T");
                return;
            end

            field_T = this.GetPSUValue(this.AxisAddress, "SIG:FLD");
        end

        function rampRate_Tmin = GetFieldRampRate(this)
            %Target field ramp rate (T/min)
            if this.SimulationMode
                rampRate_Tmin = 0.1;
                return;
            end

            rampRate_Tmin = this.GetPSUValue(this.AxisAddress, "SIG:RFST");
        end

        function [Headers, Units] = GetHeaders(this)
            Headers = [this.Name + " - Field (T)", this.Name + " - Current (A)"];
            Units = ["T", "A"];
        end

        function idnString = GetIDN(this)
            %Query the instrument identity string (*IDN?)
            if this.SimulationMode
                idnString = "SIMULATED MERCURY IPS";
                return;
            end

            idnString = this.ReadValue("*IDN?", "");
        end

        function inductance_H = GetMagnetInductance(this)
            if this.SimulationMode
                inductance_H = 0;
                return;
            end

            inductance_H = this.GetPSUValue(this.AxisAddress, "IND");
        end

        function persistentCurrent_A = GetPersistentCurrent(this)
            if this.SimulationMode
                persistentCurrent_A = 0;
                return;
            end

            persistentCurrent_A = this.GetPSUValue(this.AxisAddress, "SIG:PCUR");
        end

        function persistentField_T = GetPersistentField(this)
            if this.SimulationMode
                persistentField_T = 0;
                return;
            end

            persistentField_T = this.GetPSUValue(this.AxisAddress, "SIG:PFLD");
        end

        function setPtCurrent_A = GetSetPointCurrent(this)
            if this.SimulationMode
                setPtCurrent_A = 0;
                return;
            end

            setPtCurrent_A = this.GetPSUValue(this.AxisAddress, "SIG:CSET");
        end

        function setPtField_T = GetSetPointField(this)
            if this.SimulationMode
                setPtField_T = 0;
                return;
            end

            setPtField_T = this.GetPSUValue(this.AxisAddress, "SIG:FSET");
        end

        function status = GetStatus(this)
            %Query the ramp action status (ACTN) and switch heater status
            %(SIG:SWHT) and decode them into human-readable strings
            if this.SimulationMode
                status.SweepStatus = "Hold";
                status.SwitchHeaterStatus = "Off";
                return;
            end

            actionCode = upper(this.GetPSUString(this.AxisAddress, "ACTN"));
            switch(actionCode)
                case("HOLD")
                    status.SweepStatus = "Hold";
                case("RTOS")
                    status.SweepStatus = "Ramping To Set Point";
                case("RTOZ")
                    status.SweepStatus = "Ramping To Zero";
                case("CLMP")
                    status.SweepStatus = "Clamped";
                otherwise
                    error("Error parsing MercuryiPS status - ramp action code " + string(actionCode) + " not recognised.");
            end

            if this.GetSwitchHeaterOn()
                status.SwitchHeaterStatus = "On";
            else
                status.SwitchHeaterStatus = "Off";
            end
        end

        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(this)
            %Tells the Sweep controller what the units and limits are of
            %the parameter it is sweeping
            str = "T";
            limits = this.FieldLimits_T;
            xlabelStr = "Time (mins)";
            ylabelStr = "Field (T)";
        end

        function current_A = GetSwitchHeaterCurrent(this)
            %Static switch heater current (SHTC)
            if this.SimulationMode
                current_A = 0;
                return;
            end

            current_A = this.GetPSUValue(this.AxisAddress, "SHTC");
        end

        function isOn = GetSwitchHeaterOn(this)
            if this.SimulationMode
                isOn = true;
                return;
            end

            statusStr = this.GetPSUString(this.AxisAddress, "SIG:SWHT");
            isOn = strcmpi(statusStr, "ON");
        end

        function voltage_V = GetVoltage(this)
            if this.SimulationMode
                voltage_V = 0;
                return;
            end

            voltage_V = this.GetPSUValue(this.AxisAddress, "SIG:VOLT");
        end

        function voltageLimit_V = GetVoltageLimit(this)
            %Maximum normal operation voltage / quench threshold (VLIM)
            if this.SimulationMode
                voltageLimit_V = 10;
                return;
            end

            voltageLimit_V = this.GetPSUValue(this.AxisAddress, "VLIM");
        end

        function [dataRow] = Measure(this)
            %Get measurement values
            field = this.GetField();
            current = this.GetCurrent();

            %Assign data to output data row
            dataRow = [field, current];
        end

        function resultString = ReadValue(this, command, readPrefix)
            %Low level read - writes readPrefix + command to the
            %instrument and returns the reply string. readPrefix defaults
            %to "READ:", matching the instrument's SCPI-like command set.
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
            arguments
                this
                currentRampRate_Amin (1,1) double;
            end

            if this.SimulationMode
                disp("Current ramp rate set to " + num2str(currentRampRate_Amin) + " A per min");
                return;
            end

            achievedRate = this.SetPSUValue(this.AxisAddress, "SIG:RCST", currentRampRate_Amin);
            assert(achievedRate == currentRampRate_Amin, "Failed to set magnet current ramp rate on " + this.Name + ". Requested " + num2str(currentRampRate_Amin) + " A/min, achieved " + num2str(achievedRate) + " A/min.");
        end

        function SetFieldRampRate_TeslaMin(this, fieldRampRate_Tmin)
            arguments
                this
                fieldRampRate_Tmin (1,1) double;
            end

            if this.SimulationMode
                disp("Field ramp rate set to " + num2str(fieldRampRate_Tmin) + " T per min");
                return;
            end

            achievedRate = this.SetPSUValue(this.AxisAddress, "SIG:RFST", fieldRampRate_Tmin);
            assert(achievedRate == fieldRampRate_Tmin, "Failed to set magnet field ramp rate on " + this.Name + ". Requested " + num2str(fieldRampRate_Tmin) + " T/min, achieved " + num2str(achievedRate) + " T/min.");
        end

        function SetRampingToTarget(this, target, rate, ~)
            %Called by SweepController_Ramp
            this.SetFieldRampRate_TeslaMin(rate);
            this.SetTargetField(target);
            this.SetState_RampToSetPoint();
        end

        function SetState_Clamp(this)
            %Output stages are clamped - the default state on power-up.
            %Ramp To Set Point / To Zero commands are not recognised from
            %this state, so give a Hold command first.
            if this.SimulationMode
                disp("Magnet state set to Clamp");
                return;
            end

            this.SetPSUString(this.AxisAddress, "ACTN", "CLMP");
        end

        function SetState_Hold(this)
            if this.SimulationMode
                disp("Magnet state set to Hold");
                return;
            end

            this.SetPSUString(this.AxisAddress, "ACTN", "HOLD");
        end

        function SetState_RampToSetPoint(this)
            if this.SimulationMode
                disp("Magnet ramping to set point");
                return;
            end

            this.SetPSUString(this.AxisAddress, "ACTN", "RTOS");
        end

        function SetState_RampToZero(this)
            if this.SimulationMode
                disp("Magnet ramping to zero");
                return;
            end

            this.SetPSUString(this.AxisAddress, "ACTN", "RTOZ");
        end

        function SetSwitchHeaterOff(this)
            if this.SimulationMode
                disp("Switch heater turned OFF (simulated)");
                return;
            end

            this.SetPSUString(this.AxisAddress, "SIG:SWHT", "OFF");
        end

        function SetSwitchHeaterOn(this)
            %Turns the persistent switch heater on. The instrument checks
            %the output current matches the persistent current before
            %allowing this (SWHT).
            if this.SimulationMode
                disp("Switch heater turned ON (simulated)");
                return;
            end

            this.SetPSUString(this.AxisAddress, "SIG:SWHT", "ON");
        end

        function SetSwitchHeaterOn_Forced(this)
            %Forces the persistent switch heater on without the
            %instrument's current-matching safety check (SWHN). Only use
            %this if you know what you are doing - forcing the heater on
            %with mismatched currents can quench the magnet.
            if this.SimulationMode
                disp("Switch heater force-turned ON (simulated)");
                return;
            end

            this.SetPSUString(this.AxisAddress, "SIG:SWHN", "ON");
        end

        function SetTargetCurrent(this, current_A)
            arguments
                this
                current_A (1,1) double;
            end

            if this.SimulationMode
                disp("Current setpoint set to " + num2str(current_A) + " A");
                return;
            end

            achievedSetPt = this.SetPSUValue(this.AxisAddress, "SIG:CSET", current_A);
            assert(achievedSetPt == current_A, "Failed to set magnet set point on " + this.Name + ". Requested " + num2str(current_A) + " A, achieved " + num2str(achievedSetPt) + " A.");
        end

        function SetTargetField(this, field_T)
            arguments
                this
                field_T (1,1) double;
            end

            if this.SimulationMode
                disp("Field setpoint set to " + num2str(field_T) + " T");
                return;
            end

            achievedSetPt = this.SetPSUValue(this.AxisAddress, "SIG:FSET", field_T);
            assert(achievedSetPt == field_T, "Failed to set magnet set point on " + this.Name + ". Requested " + num2str(field_T) + " T, achieved " + num2str(achievedSetPt) + " T.");
        end

        function resultString = SetValue(this, command)
            %Low level set - writes "SET:" + command to the instrument
            %and returns the (echoed) reply string.
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
            %Called by a SweepController once the sweep is completed
            this.SetState_Hold();
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function value = GetPSUValue(this, uid, noun)
            %Generic numeric read of a DEV:<uid>:PSU:<noun> value, eg
            %noun = "SIG:FLD" or "CLIM"
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
            %Generic string read of a DEV:<uid>:PSU:<noun> value, eg
            %noun = "ACTN" or "SIG:SWHT"
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
            %Convert an SI-prefixed unit string (eg "mT", "kA") into its
            %multiplier. A bare unit with no recognised prefix (eg "T",
            %"A") returns a multiplier of 1, matching the manual's own
            %definition of "# - none" as one of the possible scales.
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

        function value = ParseSIPrefixedValue(~, valueString)
            %Parse a value string of the form "<number><prefix><unit>" or
            %"<number><unit>" (no prefix) into a double, applying the SI
            %unit prefix if present. Used as a fallback for the case
            %where the numeric value and its unit are concatenated into a
            %single token rather than being separate colon-delimited
            %tokens (see ParseSignalResponse).
            siPrefixes = containers.Map(...
                {'M', 'k', 'm', char(181), 'n', 'p'}, ...
                {1e6, 1e3, 1e-3, 1e-6, 1e-9, 1e-12});

            prefixChar = valueString(end-1);

            if isstrprop(prefixChar, 'digit')
                value = str2double(valueString(1:end-1));
            elseif isKey(siPrefixes, prefixChar)
                value = str2double(valueString(1:end-2)) * siPrefixes(prefixChar);
            else
                error("Could not parse SI-prefixed value: " + string(valueString));
            end
        end

        function value = ParseSignalResponse(this, responseString)
            %Parse a STAT:...:<value> response into a double. Handles a
            %SET confirmation echoing back a plain unscaled number (eg
            %"...:TSET:4.321:VALID"), a READ of a signal returning the
            %number and its SI-prefixed unit as separate colon-delimited
            %tokens (eg "...:SIG:VOLT:12.345:mV:VALID"), and (as a
            %fallback) the number and unit concatenated into one token.
            tokens = strsplit(char(responseString), ":");

            if ~isempty(tokens) && any(strcmpi(tokens{end}, ["VALID", "INVALID"]))
                if strcmpi(tokens{end}, "INVALID")
                    error("MercuryiPS returned INVALID for command response: " + string(responseString));
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
            %Parse a STAT:...:<value> response where the value is a
            %string/enumerated status (eg ON/OFF, HOLD/RTOS/RTOZ/CLMP)
            %rather than a number.
            tokens = strsplit(char(responseString), ":");

            if ~isempty(tokens) && any(strcmpi(tokens{end}, ["VALID", "INVALID"]))
                if strcmpi(tokens{end}, "INVALID")
                    error("MercuryiPS returned INVALID for command response: " + string(responseString));
                end
                tokens(end) = [];
            end

            strVal = string(tokens{end});
        end

        function confirmedValue = SetPSUValue(this, uid, noun, value)
            %Generic numeric write to a DEV:<uid>:PSU:<noun> value, eg
            %noun = "SIG:FSET" or "CLIM". Verifies the instrument
            %confirmed the value was VALID and returns the confirmed
            %(echoed) value.
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
            %Generic string write to a DEV:<uid>:PSU:<noun> value, eg
            %noun = "ACTN" or "SIG:SWHT". Verifies the instrument
            %confirmed the value was VALID and returns the confirmed
            %(echoed) value.
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
