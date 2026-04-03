classdef Mercury120_IPS < Palladium.Core.Instrument
    %Instrument implementation for Mercury 120 IPS Magnet power supply from
    %Oxford Instruments
    %Note on the communication commands - the instrument sends a reply to
    %all commands, even just writes of instructions, so we have
    %QueryStrings instead of WriteCommands everywhere, but at the moment at
    %least simply discard the result. It will return ? if the command isn't
    %recognised, and will echo the command if it worked, so we could build
    %in some verification on this.

    %% Properties (Constant, Public)
    properties(Constant, Access = public)
        FullName = "Mercury 120 IPS";     %Full name, just for displaying on GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "120IPS";             %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end

    %% Properties (Private)
    properties(Access = private)
        TargetFieldValue = 0;
    end

    %% Constructor
    methods
        function this = Mercury120_IPS()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial", "VISA"]);
            this.ConnectionSettings.GPIB_Terminators = ["CR" "CR"];
            this.ConnectionSettings.SerialSettings.Terminator = "CR";
            this.ConnectionSettings.SerialSettings.StopBits = 2;
            this.GPIB_Address = 25;
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
            this.SetState_Hold();
        end

        function rampStatus = CheckRampStatus(this, timeElapsed_s, tDiff, currentTarget, rampRate_min) %#ok<INUSD>
            %Return simulated data only if we are debugging without a
            %physical instrument connected
            if this.SimulationMode
                rampStatus = this.SweepController.SimulateRamping(tDiff, currentTarget, rampRate_min);
                this.SimulatedData.Field_T = rampStatus.CurrentField;
                this.SimulatedData.Current_A = rampStatus.CurrentField*12;
                return;
            end

            %Actual instrument commands here
            isRamping = this.GetRampStatus();
            rampStatus.TargetReached = ~isRamping;
        end

        function Close(this)
            %Place in local mode now we are done.. if we connected in the
            %first place (ie not if we are aborting a failed connect())
            if ~isempty(this.DeviceHandle)
                this.SetLocal();
            end

            %Override base class Close function - still call the base
            %function, but place instrument in local mode first
            Close@Palladium.Core.Instrument(this);
        end

        function Connect(this)
            %Override to also place instrument in remote mode, after
            %executing base functions here
            Connect@Palladium.Core.Instrument(this);

            %Response to a built-in IDN query will still be in the buffer
            %here - perform a Read to empty it
            this.QueryString("X");

            %Place in remote mode - or cannot send instructions
            %programmatically. Probably also a good safety measure to be
            %locking the front panel actually..
            this.SetRemote();
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


        function current_A = GetCurrent(this)
            if this.SimulationMode
                current_A = this.RetrieveSimulatedDataValue("Current_A");
                return;
            end

            current_A = this.QueryAndParseIPSCommand("R2");
        end

        function [upperLimit, lowerLimit] = GetCurrentLimits(this)
            if this.SimulationMode
                upperLimit = 60;
                lowerLimit = -60;
                return;
            end

            upperLimit = this.QueryAndParseIPSCommand("R22");
            lowerLimit = this.QueryAndParseIPSCommand("R21");
        end

        function currentRampRate_Amin = GetCurrentRampRate(this)
            if this.SimulationMode
                currentRampRate_Amin = 1.1;
                return;
            end

            currentRampRate_Amin = this.QueryAndParseIPSCommand("R6");
        end

        function field_T = GetField(this)
            if this.SimulationMode
                field_T = this.RetrieveSimulatedDataValue("Field_T");
                return;
            end

            field_T = this.QueryAndParseIPSCommand("R7");
        end

        function fieldRampRate_Tmin = GetFieldRampRate(this)
            if this.SimulationMode
                fieldRampRate_Tmin = 0.1;
                return;
            end

            fieldRampRate_Tmin = this.QueryAndParseIPSCommand("R9");
        end

        function [Headers, Units] = GetHeaders(this)
            Headers = [this.Name + " - Field (T)", this.Name + " - Current (A)"];
            Units = ["T", "A"];
        end

        function inductance_H = GetMagnetInductance(this)
            if this.SimulationMode
                inductance_H = 0;
                return;
            end

            inductance_H = this.QueryAndParseIPSCommand("R24");
        end

        function isRamping = GetRampStatus(this)
            %Query general status, then extract the ramp
            status = this.GetStatus();
            isRamping = ~strcmp(status.SweepStatus, "At rest");
        end

        function status = GetStatus(this)
            if this.SimulationMode
                %Example string, to test the parsing below
                statusString = 'X00A4C0H8M00P00';
            else
                %Query instrument. Deblank call removes trailing
                %whitespace, important for counting string length
                statusString = char(deblank(this.QueryString("X")));

                %Retry if the length is not as expected - we were seeing crashes because
                %we'd get an extra 'X' appendended to the front of the string..
                while length(statusString) ~= 15
                    %Empty the buffer with a read
                    this.QueryString("X");
                    warning("Status string of unexpected length read on IPS120, retrying: " + string(statusString));
                    pause(0.1);
                    statusString = char(deblank(this.QueryString("X")));
                end
            end

            %System status
            systemStatusString = statusString(2:2);
            switch(systemStatusString)
                case('0')
                    status.SystemStatus = "Normal";
                case('1')
                    status.SystemStatus = "Quenched";
                case('2')
                    status.SystemStatus = "Over Heated";
                case('4')
                    status.SystemStatus = "Warming Up";
                case('8')
                    status.SystemStatus = "Fault";
                otherwise
                    error("Error parsing IPS status - " + "System status string " + string(systemStatusString) + " not recognised." + "Total status string: " + string(statusString));
            end

            %Supply status
            supplyStatusString = statusString(3:3);
            switch(supplyStatusString)
                case('0')
                    status.SupplyStatus = "Normal";
                case('1')
                    status.SupplyStatus = "On Positive Voltage Limit";
                case('2')
                    status.SupplyStatus = "On Negative Voltage Limit";
                case('4')
                    status.SupplyStatus = "Outside Negative Current Limit";
                case('8')
                    status.SupplyStatus = "Outside Positive Current Limit";
                otherwise
                    error("Error parsing IPS status - " + "Supply status string " + string(supplyStatusString) + " not recognised." + "Total status string: " + string(statusString));
            end

            %Activity status
            activityStatusString = statusString(5:5);
            switch(activityStatusString)
                case('0')
                    status.ActivityStatus = "Hold";
                case('1')
                    status.ActivityStatus = "To Set Point";
                case('2')
                    status.ActivityStatus = "To Zero";
                case('4')
                    status.ActivityStatus = "Clamped";
                otherwise
                    error("Error parsing IPS status - " + "Activity status string " + string(activityStatusString) + " not recognised." + "Total status string: " + string(statusString));
            end

            %Command status
            commandStatusString = statusString(7:7);
            switch(commandStatusString)
                case('0')
                    status.CommandStatus = "Local and Locked";
                case('1')
                    status.CommandStatus = "Remote and Locked";
                case('2')
                    status.CommandStatus = "Local and Unlocked";
                case('3')
                    status.CommandStatus = "Remote and Unlocked";
                case('4')
                    status.CommandStatus = "Auto Run-Down";
                case('5')
                    status.CommandStatus = "Auto Run-Down";
                case('6')
                    status.CommandStatus = "Auto Run-Down";
                case('7')
                    status.CommandStatus = "Auto Run-Down";
                otherwise
                    error("Error parsing IPS status - " + "Command status string " + string(commandStatusString) + " not recognised." + "Total status string: " + string(statusString));
            end

            %Switch Heater status
            switchStatusString = statusString(9:9);
            switch(switchStatusString)
                case('0')
                    status.SwitchHeaterStatus = "Off Magnet at Zero (switch closed)";
                case('1')
                    status.SwitchHeaterStatus = "On (switch open)";
                case('2')
                    status.SwitchHeaterStatus = "Off Magnet at Field (switch closed)";
                case('5')
                    status.SwitchHeaterStatus = "Heater Fault";
                case('8')
                    status.SwitchHeaterStatus = "No Switch Fitted";
                otherwise
                    error("Error parsing IPS status - " + "Switch status string " + string(switchStatusString) + " not recognised." + "Total status string: " + string(statusString));
            end

            %DisplayAndSpeed status
            displayAndSpeedStatusString = statusString(11:11);
            switch(displayAndSpeedStatusString)
                case('0')
                    status.DisplayAndSpeedStatus = "Amps - Fast Sweep";
                case('1')
                    status.DisplayAndSpeedStatus = "Tesla - Fast Sweep";
                case('4')
                    status.DisplayAndSpeedStatus = "Amps - Slow Sweep";
                case('5')
                    status.DisplayAndSpeedStatus = "Tesla - Slow Sweep";
                otherwise
                    error("Error parsing IPS status - " + "DisplayAndSpeed status string " + string(displayAndSpeedStatusString) + " not recognised." + "Total status string: " + string(statusString));
            end

            %Sweep status
            sweepStatusString = statusString(12:12);
            switch(sweepStatusString)
                case('0')
                    status.SweepStatus = "At rest";                     %Output constant
                case('1')
                    status.SweepStatus = "Sweeping";                    %Output changing
                case('2')
                    status.SweepStatus = "Sweep Limiting";              %Output changing
                case('3')
                    status.SweepStatus = "Sweeping and Sweep Limiting"; %Output changing
                otherwise
                    error("Error parsing IPS status - " + "Sweep status string " + string(sweepStatusString) + " not recognised." + "Total status string: " + string(statusString));
            end

            %Polarity status
            polarityStatusString = statusString(14:14);
            switch(polarityStatusString)
                case('0')
                    status.PolarityStatus = "Mag Pos - Comm Pos";
                case('1')
                    status.PolarityStatus = "Mag Pos - Comm Neg";
                case('2')
                    status.PolarityStatus = "Mag Neg - Comm Pos";
                case('3')
                    status.PolarityStatus = "Mag Neg - Comm Neg";
                case('4')
                    status.PolarityStatus = "Mag Pos - Comm Pos";
                case('5')
                    status.PolarityStatus = "Mag Pos - Comm Neg";
                case('6')
                    status.PolarityStatus = "Mag Neg - Comm Pos";
                case('7')
                    status.PolarityStatus = "Mag Neg - Comm Neg";
                otherwise
                    error("Error parsing IPS status - " + "Polarity status string " + string(polarityStatusString) + " not recognised." + "Total status string: " + string(statusString));
            end
        end

        function setPtCurrent_A = GetSetPointCurrent(this)
            if this.SimulationMode
                setPtCurrent_A = 0;
                return;
            end
            setPtCurrent_A = NaN;

            while(isnan(setPtCurrent_A))
                setPtCurrent_A = this.QueryAndParseIPSCommand("R5");
                pause(0.01);
            end
        end

        function setPtField_T = GetSetPointField(this)
            if this.SimulationMode
                setPtField_T = 0;
                return;
            end

            setPtField_T = this.QueryAndParseIPSCommand("R8");
        end

        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(~)
            %Tells the Sweep controller what the units and limits are of
            %the parameter it is sweeping
            str = "T";
            limits = [-6, 6];
            xlabelStr = "Time (mins)";
            ylabelStr = "Field (T)";
        end

        function [dataRow] = Measure(this)
            %Get measurement values
            field = this.GetField();
            current = this.GetCurrent();

            %Assign data to output data row
            dataRow = [field, current];
        end

        function SetLocal(this)
            %C0 - Local & Locked (LOC/REM button) - default state
            %C1 - Remote & Locked
            %C2 - Local & Unlocked
            %C3 - Remote & Unlocked
            this.QueryString("C2");
        end

        function SetMode_Amps(this)
            %Selects CURRENT or FIELD mode for the display
            this.QueryString("M8");
        end

        function SetMode_Tesla(this)
            %Selects CURRENT or FIELD mode for the display
            this.QueryString("M9");
        end

        function SetRampRate_AmpsMin(this, currentRampRate_Amin)
            arguments
                this
                currentRampRate_Amin (1,1) double;
            end

            %Send the command
            commandStr = "S" + num2str(currentRampRate_Amin);
            this.QueryString(commandStr);
        end

        function SetRampRate_TeslaMin(this, fieldRampRate_Tmin)
            arguments
                this
                fieldRampRate_Tmin (1,1) double;
            end

            if this.SimulationMode
                disp("Field ramp rate set to " + num2str(fieldRampRate_Tmin) + " T per min");
                return;
            end

            %Send the command
            commandStr = "T" + num2str(fieldRampRate_Tmin);
            this.QueryString(commandStr);


            %Query the set point to make sure it set correctly
            achievedRate = this.GetFieldRampRate();

            %Error if these do not match
            assert(achievedRate == fieldRampRate_Tmin, "Failed to set magnet ramp rate on " + this.Name + ". Requested " + num2str(fieldRampRate_Tmin) + " T/min, achieved " + num2str(achievedRate) + " T/min.");

        end

        function SetRemote(this)
            %C0 - Local & Locked (LOC/REM button) - default state
            %C1 - Remote & Locked
            %C2 - Local & Unlocked
            %C3 - Remote & Unlocked
            this.QueryString("C3");
        end

        function SetRampingToTarget(this, target, rate, ~)
            %Called by SweepController_Ramp
            this.SetRampRate_TeslaMin(rate);
            this.SetTargetField(target);
            this.SetState_RampToSetPoint();
        end
        
        function SetState_Clamp(this)
            %Default state upon instrument power-up. Note that in this
            %state, Ramp to SetPt or Ramp to Zero commands will not be
            %recongnised - give SetState_Hold command first. So - give hold
            %at start of any Sweep Start commands in case the instrument
            %jsut powered on
            this.QueryString("A4");
        end

        function SetState_Hold(this)
            this.QueryString("A0");
        end

        function SetState_RampToSetPoint(this)
            %Check the current status of the power supply first. In
            %particular, if we are in the default 'Clamp' state, we need to
            %move to hold first before ramping..
            status = this.GetStatus();
            if strcmp(status.ActivityStatus, "Clamped")
                this.SetState_Hold();
                pause(0.1);
            end

            this.QueryString("A1");
        end

        function SetState_RampToZero(this)
            this.QueryString("A2");
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

            %Send the command
            commandStr = "I" + num2str(current_A);
            this.QueryString(commandStr);

            %Query the set point to make sure it set correctly
            achievedSetPt = this.GetSetPointCurrent();

            %Error if these do not match
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

            %Send the command
            commandStr = "J" + num2str(field_T);
            this.QueryString(commandStr);

            %Query the set point to make sure it set correctly
            achievedSetPt = this.GetSetPointField();

            %Error if these do not match
            assert(achievedSetPt == field_T, "Failed to set magnet set point on " + this.Name + ". Requested " + num2str(field_T) + " T, achieved " + num2str(achievedSetPt) + " T.");
        end

        function SweepComplete(this)
            %Called by a SweepController once the sweep is completed
            this.SetState_Hold();
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function value = QueryAndParseIPSCommand(this, commandStr)
            %Avoiding code duplication with a little wrapper function for
            %queries of values - just snips an extra character off the
            %front (found in testing) and converts string to double
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

