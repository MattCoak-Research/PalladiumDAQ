classdef Keithley2450 < Palladium.Core.Instrument
    %Instrument implementation for Keithley 2450 source meter. Most likely
    %works for a 2470 too, but is not tested.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Keithley 2450 Src Meter";       %Full name, just for displaying on GUI
    end
    
    %% Properties (Constant)
    properties(Constant)
        ABORT_PAUSE_S = 0.05;       %s, wait after sending abort, and after a device clear, before the next step of AbortScript. Tested on two 2450s (fw 1.7.12b/1.7.16a) with hung TSP scripts: even 0 s worked reliably, this leaves a margin
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "K2450_SrcMtr";                            %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Language;                                   %Command scripting language to use - TSP or SCPI. Must match the option configured on the hardware, and Instrument needs a reset to change this setting. If this is set wrong, commands will all error
     end

    %% Properties (Public, Private Set)
    properties(GetAccess = public, SetAccess = private)
        SourceMode;                                 %Source function/mode: Current or Voltage. Will be queried from the hardware right after connecting.
        MeasMode;                                   %Measurement mode: Resistance, Voltage, Current or Power. Will be queried from the hardware (measure function and units) right after connecting.
    end

    %% Properties (Private)
    properties(Access = private)
        MeasFunction;                               %Underlying SCPI measure function (CURR, VOLT or RES) - differs from MeasMode when units are changed, e.g. VOLT measured in Ohms gives Resistance
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Resistance", "Voltage", "Current", "Power"]); end
        function catOut = SourceType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Voltage", "Current"]); end
        function catOut = LanguageType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["TSP", "SCPI"]); end
    end

    %% Constructor
    methods
        function this = Keithley2450()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "USB", "VISA"]);
            this.GPIB_Address = 18;      %Default Address
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];
            this.VISA_Address = 'USB0::0x05E6::0x2450::04602266::0::INSTR';

            %Define the Instrument Controls that can be added to the
            %Instrument
            this.DefineInstrumentControl(Name = "Sweep Control", ClassName = "SweepController_Stepped", TabName = "Sweep Control", EnabledByDefault = false);
            this.DefineInstrumentControl(Name = "Double 2450 Gate Sweep", ClassName = "Keithley2450_Double_GateSweep", TabName = "Double 2450 Gate Sweep", EnabledByDefault = false);

            %Make sure to set values for Properties of Categorical type
            %like these
            this.Language = this.LanguageType("TSP");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function AbortScript(this, Settings)
            %Stop anything running on the instrument (a TSP script, or the
            %trigger model in SCPI), clear the GPIB interface so it is
            %ready for new commands, and turn the output off. Use to
            %recover from a hung script, e.g. one waiting forever for a
            %trigger. Settings and stored data are not affected. To stop
            %several instruments quickly, call SendAbortCommand,
            %ClearInterface and TurnOutputOff on each in turn, sharing the
            %pauses between them (see Keithley2450_Double_GateSweep)
            arguments
                this;
                Settings.Pause_s (1,1) double {mustBeNonnegative} = this.ABORT_PAUSE_S;    %Wait after the abort and after the device clear, for the instrument to process each
            end
            if (this.SimulationMode); return; end

            this.SendAbortCommand();
            pause(Settings.Pause_s);

            %Device clear - empties the input buffer, output queue and
            %command queue, so no stale responses or queued commands remain
            this.ClearInterface();
            pause(Settings.Pause_s);

            this.TurnOutputOff();
        end

        function Connect(this)
            %Call base class functionality
            Connect@Palladium.Core.Instrument(this);

            %Discard anything left over from an earlier session (e.g. a
            %late reply to a query that timed out), so the first query below
            %gets its own reply
            this.ClearInterface();

            %Check the command language set on the hardware matches our
            %Language setting - it can only be changed on the instrument
            %with a reboot, so error with instructions if not
            if ~this.SimulationMode
                hardwareLanguage = this.GetLanguage();
                if hardwareLanguage ~= this.Language
                    msg = this.Name + " is configured on the hardware to use the " + string(hardwareLanguage) + ...
                        " command set, but its Language setting is " + string(this.Language) + ". Set Language to " + string(hardwareLanguage) + ...
                        ", or change the command set on the instrument (MENU > System > Settings > Command Set, or send *LANG " + ...
                        string(this.Language) + ") and reboot it.";
                    error(msg);
                end
            end

            %Start with an empty event log, so any errors reported during
            %measurements come from this session
            this.ClearErrorQueue();

            %Query hardware options and setup, set properties like
            %MeasurementMode based on this
            this.SourceMode = this.GetSourceMode();
            this.MeasMode = this.GetMeasurementMode();
        end

        function ClearErrorQueue(this)
            %Remove all events from the instrument's event log (errors,
            %warnings and info) - note this also clears the front-panel
            %event log
            if (this.SimulationMode); return; end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    this.WriteCommand("SYST:CLE");
                case(this.LanguageType("TSP"))
                    this.WriteCommand("eventlog.clear()");
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end
        end

        function ClearInterface(this)
            %Device clear: empties the instrument's input buffer, output
            %queue and command queue, so no stale replies or queued
            %commands are left to be mistaken for the next query's reply.
            %Settings and stored data are not affected. Does not stop a
            %running script - use AbortScript for that
            if (this.SimulationMode); return; end

            try
                clrdevice(this.DeviceHandle);
            catch
                %Device clear only exists for VISA connections (GPIB, USB,
                %VISA) - for Ethernet (tcpclient) just empty MATLAB's own
                %buffers
                flush(this.DeviceHandle);
            end
        end

        function metadataStruct = CollectMetaData(this)
            %Record instrument settings and metadata like compliance,
            %voltage, measurement mode, that will not change during the
            %measurement and therefore don't merit logging each step
            [~, metadataStruct.ComplianceLevel] = this.GetComplianceLevel();
            metadataStruct.MeasurementMode = this.MeasMode;
            metadataStruct.SourceMode = this.GetSourceMode();
            [metadataStruct.NumPowerLineCycles,  metadataStruct.IntegrationTime_s] = this.GetNPLC();
            metadataStruct.FourWireMode = this.GetFourWireEnabledStatus();
        end

        function [compValue, compStringWithUnits] = GetComplianceLevel(this)
            if (this.SimulationMode)
                compValue = 120e-6;
            else
                switch(this.Language)
                    case(this.LanguageType("SCPI"))
                        switch(this.SourceMode)
                            case(this.SourceType("Voltage"))   %Compliance is opposite to source.. the 2450 names it after the source function, e.g. SOUR:VOLT:ILIM is the current limit when sourcing voltage
                                compValue = this.QueryDouble("SOUR:VOLT:ILIM?");
                            case(this.SourceType("Current"))
                                compValue = this.QueryDouble("SOUR:CURR:VLIM?");
                            otherwise
                                error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
                        end
                    case(this.LanguageType("TSP"))
                        switch(this.SourceMode)
                            case(this.SourceType("Voltage"))   %Compliance is opposite to source..
                                compValue = this.QueryDouble("print(smu.source.ilimit.level)"); 
                            case(this.SourceType("Current"))
                                compValue = this.QueryDouble("print(smu.source.vlimit.level)"); 
                            otherwise
                                error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
                        end
                    otherwise
                        error("Unsupported language type " + string(this.Language));
                end
            end

            switch(this.SourceMode)
                case(this.SourceType("Voltage"))   %Compliance is opposite to source..
                    str = " mA";
                case(this.SourceType("Current"))
                    str = " mV";
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

            %Multiply by 1000, millivolts or mA is easier to read. Round to 6
            %significant figures, as the hardware stores values like
            %2.0999999046 for a 2.1 V limit (6 not 5, so the maximum 210 V
            %limit prints as 210000 mV rather than in exponent form)
            compStringWithUnits = num2str(compValue*1000, 6) + str;
        end

        function errorCount = GetErrorCount(this)
            %Number of unread errors in the instrument's event log (errors
            %only, not warnings or info). Does not remove them
            if (this.SimulationMode)
                errorCount = 0;
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    errorCount = this.QueryDouble("SYST:ERR:COUN?");
                case(this.LanguageType("TSP"))
                    errorCount = this.QueryDouble("print(eventlog.getcount(eventlog.SEV_ERROR))");
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end
        end

        function errors = GetErrors(this)
            %Read and remove all unread errors from the instrument's event
            %log, oldest first. Returns a struct array with fields Code
            %(event number) and Message - empty if there are no errors. Once
            %read, errors can no longer be read remotely (they stay visible
            %in the front-panel event log until cleared)
            errors = struct("Code", {}, "Message", {});
            if (this.SimulationMode); return; end

            numErrors = this.GetErrorCount();
            for i = 1:numErrors
                switch(this.Language)
                    case(this.LanguageType("SCPI"))
                        %Returns e.g. -109,"Missing parameter;1;2017/05/06 12:57:04.484"
                        %- the quoted part is message;type;timestamp
                        result = strtrim(string(this.QueryString("SYST:ERR?")));
                        code = str2double(extractBefore(result, ","));
                        quoted = strip(extractAfter(result, ","), """");
                        fields = split(quoted, ";");
                        message = join(fields(1:max(1, end-2)), ";");
                    case(this.LanguageType("TSP"))
                        %Returns tab-separated: code, message, severity,
                        %node, seconds, nanoseconds
                        result = strtrim(string(this.QueryString("print(eventlog.next(eventlog.SEV_ERROR))")));
                        fields = split(result, sprintf('\t'));
                        code = str2double(fields(1));
                        message = fields(min(2, end));
                    otherwise
                        error("Unsupported language type " + string(this.Language));
                end

                %Code 0 means the log is empty (nothing left to read)
                if code == 0; break; end
                errors(end+1) = struct("Code", code, "Message", message); %#ok<AGROW>
            end
        end

        function fourWireEnabled = GetFourWireEnabledStatus(this)
            if (this.SimulationMode)
                fourWireEnabled = true;
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    %Remote sense is set per measure function on the 2450
                    %(there is no global SYST:RSEN as on the 2400)
                    result = this.QueryDouble("SENS:" + this.MeasFunction + ":RSEN?");
                    fourWireEnabled = logical(result);
                case(this.LanguageType("TSP"))
                     result = this.QueryString("print(smu.measure.sense)");
                     if strcmp(result, "smu.SENSE_2WIRE")
                         fourWireEnabled = false;
                     elseif strcmp(result, "smu.SENSE_4WIRE")
                         fourWireEnabled = true;
                     end

                otherwise
                    error("Unsupported language type " + string(this.Language));
            end
        end


        function [Headers, Units] = GetHeaders(this)
            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    switch(this.SourceMode)
                        case(this.SourceType("Current"))
                            Headers = [this.Name + " - Resistance_Ohms", this.Name + " - Current_A", this.Name + " - Compliance Limited"];
                            Units = ["Ohms", "A", ""];
                        case(this.SourceType("Voltage"))
                            Headers = [this.Name + " - Resistance_Ohms", this.Name + " - Voltage_V", this.Name + " - Compliance Limited"];
                            Units = ["Ohms", "V", ""];
                        otherwise
                            error("Invalid type");
                    end
                case(this.MeasType("Current"))
                    Headers = [this.Name + " - Current_A", this.Name + " - Voltage_V", this.Name + " - Compliance Limited"];
                    Units = ["A", "V", ""];
                case(this.MeasType("Voltage"))
                    Headers = [this.Name + " - Voltage_V", this.Name + " - Current_A", this.Name + " - Compliance Limited"];
                    Units = ["V", "A", ""];
                case(this.MeasType("Power"))
                    switch(this.SourceMode)
                        case(this.SourceType("Current"))
                            Headers = [this.Name + " - Power_W", this.Name + " - Current_A", this.Name + " - Compliance Limited"];
                            Units = ["W", "A", ""];
                        case(this.SourceType("Voltage"))
                            Headers = [this.Name + " - Power_W", this.Name + " - Voltage_V", this.Name + " - Compliance Limited"];
                            Units = ["W", "V", ""];
                        otherwise
                            error("Invalid type");
                    end
                otherwise
                    error("Mode must be Resistance, Voltage, Current or Power, this was " + string(this.MeasMode));
            end

            
        end

        function lang = GetLanguage(this)
            result = strtrim(string(this.QueryString("*LANG?")));
            if strcmp(result, "TSP")
                lang = this.LanguageType("TSP");
            elseif strcmp(result, "SCPI")
                lang = this.LanguageType("SCPI");
            else
                error("Unsupported instrument language: " + result);
            end
        end

        function measMode = GetMeasurementMode(this)
            %The quantity actually measured depends on both the measure
            %function and its units - e.g. a voltage measurement can be
            %reported in Ohms (R = V / I_source) or Watts - so query both
            %and set the mode from the units
            if (this.SimulationMode)
                measMode = this.MeasType("Resistance");
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    %Response is a quoted string with a possible suffix, e.g.
                    %"CURR:DC" - strip quotes/whitespace and match on the start
                    result = this.QueryString("SENS:FUNC?");
                    funcStr = upper(strtrim(erase(string(result), ["""", "'"])));

                    if startsWith(funcStr, "CURR")
                        this.MeasFunction = "CURR";
                    elseif startsWith(funcStr, "VOLT")
                        this.MeasFunction = "VOLT";
                    elseif startsWith(funcStr, "RES")
                        this.MeasFunction = "RES";
                    else
                        error("Unsupported measurement function: " + result);
                    end

                    %Resistance function is always in Ohms, only voltage and
                    %current have a selectable unit (AMP/VOLT, OHM or WATT)
                    if this.MeasFunction == "RES"
                        unitStr = "OHM";
                    else
                        unitStr = upper(strtrim(string(this.QueryString("SENS:" + this.MeasFunction + ":UNIT?"))));
                    end

                case(this.LanguageType("TSP"))
                    result = strtrim(string(this.QueryString("print(smu.measure.func)")));
                    if ~any(strcmp(result, ["smu.FUNC_DC_CURRENT", "smu.FUNC_DC_VOLTAGE", "smu.FUNC_RESISTANCE"]))
                        error("Unsupported measurement function: " + result);
                    end

                    %Returns e.g. smu.UNIT_OHM - strip the prefix to match
                    %the SCPI unit names
                    unitStr = strtrim(string(this.QueryString("print(smu.measure.unit)")));
                    unitStr = upper(erase(unitStr, "smu.UNIT_"));
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end

            switch(unitStr)
                case("AMP")
                    measMode = this.MeasType("Current");
                case("VOLT")
                    measMode = this.MeasType("Voltage");
                case("OHM")
                    measMode = this.MeasType("Resistance");
                case("WATT")
                    measMode = this.MeasType("Power");
                otherwise
                    error("Unsupported measurement unit: " + unitStr);
            end
        end

        function [nplc, integrationTime_s] = GetNPLC(this)
            %Get the Number of Power Line Cycles for the selected
            %measurement - the integration time for each reading. second
            %output helpfully converts this into a time in seconds
            if (this.SimulationMode)
                nplc = 1;
            else
                switch(this.Language)
                    case(this.LanguageType("SCPI"))
                        %NPLC belongs to the underlying measure function, not
                        %the MeasMode (e.g. Resistance may be VOLT in Ohms)
                        nplc = this.QueryDouble("SENS:" + this.MeasFunction + ":NPLC?");
                    case(this.LanguageType("TSP"))
                        nplc = this.QueryDouble("print(smu.measure.nplc)");
                    otherwise
                        error("Unsupported language type " + string(this.Language));
                end
            end

            integrationTime_s = nplc / 60;
        end

        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(this)
            switch(this.SourceMode)
                case(this.SourceType("Voltage"))
                    xlabelStr = "Source Voltage (V)";
                    str = "V";
                    limits = [-50, 50];    %Need to check what these physical limits actually are and improve this
                case(this.SourceType("Current"))
                    xlabelStr = "Source Current (A)";
                    str = "A";
                    limits = [-1, 1]; %Need to check what these physical limits actually are and improve this
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

            hdrs = this.GetHeaders();
            ylabelStr = hdrs(1);
        end

        function srcLevel = GetSourceLevel(this)
            if (this.SimulationMode)
                srcLevel = this.RetrieveSimulatedDataValue("SourceLevel");
                return;
            end            

            switch(this.SourceMode)
                case(this.SourceType("Voltage"))
                    switch(this.Language)
                        case(this.LanguageType("SCPI"))                            
                            srcLevel = this.QueryDouble("SOUR:VOLT:LEV:AMPL?");
                        case(this.LanguageType("TSP"))
                            srcLevel = this.QueryDouble("print(smu.source.getattribute(smu.FUNC_DC_VOLTAGE, smu.ATTR_SRC_LEVEL))");
                        otherwise
                            error("Unsupported language type " + string(this.Language));
                    end
                case(this.SourceType("Current"))
                    switch(this.Language)
                        case(this.LanguageType("SCPI"))
                            srcLevel = this.QueryDouble("SOUR:CURR:LEV:AMPL?");
                        case(this.LanguageType("TSP"))
                            srcLevel = this.QueryDouble("print(smu.source.getattribute(smu.FUNC_DC_CURRENT, smu.ATTR_SRC_LEVEL))");
                        otherwise
                            error("Unsupported language type " + string(this.Language));
                    end
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end
        end

        function srcMode = GetSourceMode(this)
            if (this.SimulationMode)
                srcMode = this.SourceType("Current");
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    result = this.QueryString("SOUR:FUNC?");

                    if strcmp(result, "CURR")
                        srcMode = this.SourceType("Current");
                    elseif strcmp(result, "VOLT")
                        srcMode = this.SourceType("Voltage");
                    else
                        error("Unsupported source mode: " + result);
                    end

                case(this.LanguageType("TSP"))
                    result = this.QueryString("print(smu.source.func)");

                    if strcmp(result, "smu.FUNC_DC_CURRENT")
                        srcMode = this.SourceType("Current");
                    elseif strcmp(result, "smu.FUNC_DC_VOLTAGE")
                        srcMode = this.SourceType("Voltage");
                    else
                        error("Unsupported source mode: " + result);
                    end
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end
        end

        function [ovp_V, ovpSetting] = GetVoltageSourceOVP(this)
            %Overvoltage protection level for the voltage source function
            %(OVP is stored per source function - this reads the voltage
            %one whichever function is active). ovp_V is the limit in volts
            %(Inf for none); ovpSetting is the instrument's own value, e.g.
            %"smu.PROTECT_40V" (TSP) or "PROT40" (SCPI), for passing back to
            %SetVoltageSourceOVP - a reset clears it to none
            if (this.SimulationMode)
                ovp_V = Inf;
                ovpSetting = "smu.PROTECT_NONE";
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    ovpSetting = strtrim(string(this.QueryString("SOUR:VOLT:PROT?")));
                case(this.LanguageType("TSP"))
                    ovpSetting = strtrim(string(this.QueryString("print(smu.source.getattribute(smu.FUNC_DC_VOLTAGE, smu.ATTR_SRC_PROTECT_LEVEL))")));
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end

            if contains(ovpSetting, "NONE")
                ovp_V = Inf;
            else
                ovp_V = str2double(regexp(ovpSetting, "\d+", "match", "once"));
                if isnan(ovp_V)
                    error("Unexpected overvoltage protection setting: " + ovpSetting);
                end
            end
        end

        function [complianceLimited] = IsAtComplianceLimit(this)
            %Note the hardware's tripped flag reflects the LAST measurement
            %taken, it is not a live reading of the output - Measure takes
            %its compliance flag from each reading's source status instead
            if (this.SimulationMode)
                complianceLimited = false;
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    %Run volt or current queries depending on measurement mode
                    switch(this.SourceMode)
                        case(this.SourceType("Voltage"))   %Compliance is opposite to source.. and note that this command is different in the newer 2450 to the older models
                            compValue = this.QueryDouble("SOUR:VOLT:ILIM:TRIP?");
                        case(this.SourceType("Current"))
                            compValue = this.QueryDouble("SOUR:CURR:VLIM:TRIP?");
                        otherwise
                            error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
                    end
                    complianceLimited = logical(compValue);
                case(this.LanguageType("TSP"))
                    switch(this.SourceMode)
                        case(this.SourceType("Voltage"))   %Compliance is opposite to source.. and note that this command is different in the newer 2450 to the older models
                            result = this.QueryString("print(smu.source.ilimit.tripped)");
                        case(this.SourceType("Current"))
                            result = this.QueryString("print(smu.source.vlimit.tripped)");
                        otherwise
                            error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
                    end

                    %Hardware returns the enum name smu.ON / smu.OFF (the
                    %manual also documents 1 / 0, so accept either)
                    result = strtrim(string(result));
                    if any(strcmp(result, ["smu.ON", "1"]))
                        complianceLimited = true;
                    elseif any(strcmp(result, ["smu.OFF", "0"]))
                        complianceLimited = false;
                    else
                        error("Unexpected compliance tripped response: " + result);
                    end
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end
        end

        function tf = IsInterlockEngaged(this)
            %true if the safety interlock is engaged - required to source
            %more than 42 V; without it the output is silently limited to
            %below 42 V. (The instrument calls this state "tripped")
            if (this.SimulationMode)
                tf = true;
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    tf = this.QueryDouble("OUTP:INT:TRIP?") == 1;
                case(this.LanguageType("TSP"))
                    result = strtrim(string(this.QueryString("print(smu.interlock.tripped)")));
                    tf = any(result == ["smu.ON", "1"]);
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end
        end

        function tf = IsReplyWaiting(this)
            %true if the instrument has a reply waiting to be read. Unlike
            %a read, this never blocks: over GPIB/VISA it is a serial poll,
            %which works even while a TSP script is running - so it can be
            %used to wait for a script to print its result while staying
            %responsive (e.g. to an Abort button). An error in the event
            %log does not count as a reply
            if (this.SimulationMode)
                tf = true;
                return;
            end

            try
                tf = visastatus(this.DeviceHandle);
            catch
                %No serial poll for Ethernet (tcpclient) - check MATLAB's
                %receive buffer instead
                tf = this.DeviceHandle.NumBytesAvailable > 0;
            end
        end

        function [dataRow] = Measure(this)
            %Retrieve source level (will work for simulated and real data
            %both)
            if(this.SimulationMode)
                %Return dummy values if in simulation mode
                sourceLevel = this.GetSourceLevel();
                value = rand(1)*1e-7 + 2e-6;
                dataRow = [value sourceLevel, 0];
                return;
            end

            %Take a reading and retrieve it along with the source value and
            %source status stored with it in the buffer, plus the number of
            %unread instrument errors, all in one query. With source
            %readback on (the default) the source value is the measured one,
            %not the programmed level - these differ when in compliance. The
            %reading's units (Ohms, V, A or W) follow MeasMode
            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    %Returns "reading,source,sourcestatus;errorcount"
                    data = this.QueryString("READ? ""defbuffer1"", READ, SOUR, SOURSTAT;:SYST:ERR:COUN?");
                case(this.LanguageType("TSP"))
                    %Returns "reading<TAB>source<TAB>sourcestatus<TAB>errorcount".
                    %defbuffer1 is a continuous (ring) buffer, so the newest
                    %entry is at endindex - n stops increasing once it wraps
                    data = this.QueryString("local r = smu.measure.read() print(r, defbuffer1.sourcevalues[defbuffer1.endindex], defbuffer1.sourcestatuses[defbuffer1.endindex], eventlog.getcount(eventlog.SEV_ERROR))");
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end

            parts = strsplit(strtrim(string(data)), {',', ';', sprintf('\t')});

            %The error count is always the last field - report any errors
            %the instrument has logged (e.g. why a reading failed) as
            %warnings before checking the reading. Reading them also clears
            %them
            if str2double(parts(end)) > 0
                errors = this.GetErrors();
                for i = 1:numel(errors)
                    Palladium.Logging.Logger.Log("Warning", this.Name + " reported instrument error " + errors(i).Code + ": " + errors(i).Message);
                end
            end

            %A failed read (e.g. output off in resistance/4-wire mode)
            %returns no data in SCPI, leaving only the error count, while in
            %TSP it prints nil for the reading with the source value and
            %status from the previous reading in the buffer - so reject it
            %rather than record stale values
            if isscalar(parts) || parts(1) == "nil"
                error("Measurement failed - instrument returned no reading (e.g. output off in Resistance or 4-wire mode). See the instrument error reported in the warning above.");
            end

            values = str2double(parts(1:end-1));
            if numel(values) ~= 3 || any(isnan(values))
                error("Unexpected measurement response: " + data);
            end

            %The instrument returns 9.9e37 for an overrange reading (fixed
            %range overflow) - record these as NaN rather than a huge number
            dataRow = values(1:2);
            dataRow(abs(dataRow) >= 9.9e37) = NaN;

            %Source status bit 5 (value 32, STAT_LIMIT) is set when the
            %source was limited (in compliance) for this reading - save that
            %(1 or 0) as a data column
            complianceLimited = bitand(values(3), 32) ~= 0;
            dataRow = [dataRow, complianceLimited];
        end

        function Reset(this)
            %Clear the interface first, so no stale replies or queued
            %commands survive the reset, then reset all settings to defaults
            this.ClearInterface();

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    this.WriteCommand("*RST");
                case(this.LanguageType("TSP"))
                    this.WriteCommand("reset(true)");
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end
        end

        function SendAbortCommand(this)
            %Stop a running TSP script (or the trigger model in SCPI).
            %abort is processed even while a script is running. Allow a
            %short time (ABORT_PAUSE_S) before sending further commands
            if (this.SimulationMode); return; end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    this.WriteCommand("ABOR");
                case(this.LanguageType("TSP"))
                    this.WriteCommand("abort");
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end
        end

        function SetNewSweepStepValue(this, value)
            %This built-in function is defined in the Instrument base class
            %(does nothing) and called by any added
            %SweepController_Stepped. Define here what action to take when
            %a new step is triggered (set the new source voltage/current)
            this.SetSourceLevel(value, true);
        end

        function SetSourceLevel(this, level, enableOutput)
            if(this.SimulationMode)
                %Store in SimulatedData struct, otherwise do nothing, just print
                disp("Setting source to " + num2str(level) + ", output enabled: " + num2str(enableOutput));
                this.SimulatedData.SourceLevel = level;
                this.SimulatedData.SourceEnabled = enableOutput;
                return;
            end

            %Turn output on or off
            switch(this.Language)
                case(this.LanguageType("SCPI"))    
                    if(enableOutput)
                        this.WriteCommand("OUTP ON");
                    else
                        this.WriteCommand("OUTP OFF");
                    end
                case(this.LanguageType("TSP"))
                    if(enableOutput)
                        this.WriteCommand("smu.source.output = smu.ON");
                    else
                        this.WriteCommand("smu.source.output = smu.OFF");
                    end
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end

            %Set the output level
            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    switch(this.SourceMode)
                        case(this.SourceType("Voltage"))
                            this.WriteCommand("SOUR:VOLT:LEV " + num2str(level));
                        case(this.SourceType("Current"))
                            this.WriteCommand("SOUR:CURR:LEV " + num2str(level));
                        otherwise
                            error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
                    end
                case(this.LanguageType("TSP"))
                    this.WriteCommand("smu.source.level = " + num2str(level));
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end
        end

        function SetVoltageSourceOVP(this, ovpSetting)
            %Set the voltage source function's overvoltage protection, from
            %a value returned by GetVoltageSourceOVP (e.g. to restore it
            %after a reset). Set it before turning the output on
            arguments
                this;
                ovpSetting (1,1) string;
            end
            if (this.SimulationMode); return; end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    assert(~isempty(regexp(ovpSetting, "^(PROT\d+|NONE)$", "once")), "Invalid SCPI overvoltage protection setting: " + ovpSetting);
                    this.WriteCommand("SOUR:VOLT:PROT " + ovpSetting);
                case(this.LanguageType("TSP"))
                    assert(~isempty(regexp(ovpSetting, "^smu\.PROTECT_(\d+V|NONE)$", "once")), "Invalid TSP overvoltage protection setting: " + ovpSetting);
                    this.WriteCommand("smu.source.setattribute(smu.FUNC_DC_VOLTAGE, smu.ATTR_SRC_PROTECT_LEVEL, " + ovpSetting + ")");
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end
        end

        function TurnOutputOff(this)
            if (this.SimulationMode); return; end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    this.WriteCommand("OUTP OFF");
                case(this.LanguageType("TSP"))
                    this.WriteCommand("smu.source.output = smu.OFF");
                otherwise
                    error("Unsupported language type " + string(this.Language));
            end
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

     

    end
end


