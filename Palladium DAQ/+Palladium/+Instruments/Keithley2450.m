classdef Keithley2450 < Palladium.Core.Instrument
    %Keithley2450 - Instrument driver for the Keithley Model 2450 SourceMeter source-measure unit.
    %Sources a voltage or a current, and takes one reading per measurement
    %tick. Each tick records three columns: the reading, in the measure
    %units set on the instrument (current, voltage, resistance or power);
    %the source value (the measured value, with source readback on); and
    %whether the source was limited by its compliance limit for that
    %reading (1 or 0). Any errors the instrument logs are reported as
    %warnings.
    %
    %Set the source and measure functions, ranges, limits and NPLC on the
    %instrument before connecting: the driver reads the source function back
    %as `SourceMode`, and the measure function and units as `MeasMode`, when
    %it connects, and records the compliance limit, NPLC and sense mode in
    %the data-file header.
    %
    %The 2450 can be programmed with either its SCPI or its TSP command set.
    %`Language` must match the command set selected on the instrument (MENU >
    %System > Settings > Command Set), otherwise connecting stops with an
    %error. The 2450 has GPIB, USB and Ethernet (LAN) interfaces.
    %
    %Two Instrument Controls can be added:
    %* Sweep Control - steps the source level through a range, each step set
    %  by `SetNewSweepStepValue`
    %* Double 2450 Gate Sweep - a gate sweep run by two 2450s (both on the
    %  TSP command set), triggered over their digital I/O lines
    %
    %Probably also works with the Model 2470, but this is untested.

    %% Properties (Constant, Public)
    properties(Constant)
        %Wait in s after an abort, and after a device clear, in AbortScript. Even 0 s worked reliably on two 2450s (fw 1.7.12b/1.7.16a) with hung TSP scripts; this leaves a margin
        ABORT_PAUSE_S = 0.05;
    end

    %% Properties (Public)
    properties(Access = public)
        FullName = "Keithley 2450 Src Meter";                   %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "K2450_SrcMtr";                                  %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Language;                                               %Command set to use, TSP or SCPI. Must match the command set selected on the instrument, which only changes after a reboot.
    end

    %% Properties (Public, Private Set)
    properties(GetAccess = public, SetAccess = private)
        SourceMode;                                             %Source function, Voltage or Current, read from the instrument when connecting
        MeasMode;                                               %Quantity measured - Current, Voltage, Resistance or Power - from the measure function and units read when connecting
    end

    %% Properties (Private)
    properties(Access = private)
        MeasFunction;                                           %Underlying SCPI measure function (CURR, VOLT or RES), set when connecting in SCPI - e.g. VOLT for a voltage measured in Ohms (MeasMode Resistance)
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr);     catOut = this.ConvertToCategorical(inputStr, ["Resistance", "Voltage", "Current", "Power"]); end
        function catOut = SourceType(this, inputStr);   catOut = this.ConvertToCategorical(inputStr, ["Voltage", "Current"]); end
        function catOut = LanguageType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["TSP", "SCPI"]); end
    end

    %% Constructor
    methods
        function this = Keithley2450()
            %Set the supported connection types, default connection settings and Instrument Controls

            %The 2450 has GPIB, USB and LAN ports; VISA can address any of them
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "USB", "VISA"]);
            this.GPIB_Address = 18;     %Factory default
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
            %Stop anything running on the instrument, clear its interface and turn the output off.
            %Stops a running TSP script, or the trigger model in SCPI, then does a
            %device clear so the instrument is ready for new commands. Use to
            %recover from a hung script, e.g. one waiting forever for a trigger.
            %Settings and stored data are not affected.
            %
            %To stop several instruments quickly, call `SendAbortCommand`,
            %`ClearInterface` and `TurnOutputOff` on each in turn, sharing the
            %pauses between them (as the Double 2450 Gate Sweep control does).
            %
            %Inputs:
            %   Settings.Pause_s - wait in s after the abort and after the device
            %                      clear, for the instrument to process each
            %                      (default ABORT_PAUSE_S)

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
            %Open the connection, check the command set, and read the source and measure settings.
            %Clears the interface and the instrument's event log, errors if the
            %command set on the instrument does not match `Language`, then reads
            %`SourceMode` and `MeasMode` from the instrument

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
                    error("Keithley2450:LanguageMismatch", "%s", msg);
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
            %Remove all events (errors, warnings and info) from the instrument's event log.
            %This also clears the event log shown on the front panel

            if (this.SimulationMode); return; end

            switch(this.Language)
                case(this.LanguageType("SCPI"));    this.WriteCommand("SYST:CLE");
                case(this.LanguageType("TSP"));     this.WriteCommand("eventlog.clear()");
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end
        end

        function ClearInterface(this)
            %Device clear: empty the instrument's input buffer, output queue and command queue.
            %Leaves no stale replies or queued commands to be mistaken for the next
            %query's reply. Settings and stored data are not affected. This does
            %not stop a running script - use `AbortScript` for that

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
            %Source and measure settings, recorded in the data-file header.
            %
            %Outputs:
            %   metadataStruct - struct with fields ComplianceLevel (e.g. "0.1 mA"),
            %                    MeasurementMode, SourceMode, NumPowerLineCycles,
            %                    IntegrationTime_s and FourWireMode

            [~, metadataStruct.ComplianceLevel] = this.GetComplianceLevel();
            metadataStruct.MeasurementMode = this.MeasMode;
            metadataStruct.SourceMode = this.GetSourceMode();
            [metadataStruct.NumPowerLineCycles,  metadataStruct.IntegrationTime_s] = this.GetNPLC();
            metadataStruct.FourWireMode = this.GetFourWireEnabledStatus();
        end

        function [compValue, compStringWithUnits] = GetComplianceLevel(this)
            %Read the source's compliance limit: the current limit when sourcing voltage, or the voltage limit when sourcing current.
            %
            %Outputs:
            %   compValue           - the limit, in A or V
            %   compStringWithUnits - the limit in mA or mV, as text with its
            %                         units, e.g. "0.12 mA"

            if (this.SimulationMode)
                compValue = 120e-6;
            else
                %The limit is named after the source function, e.g.
                %SOUR:VOLT:ILIM is the current limit when sourcing voltage
                switch(this.Language)
                    case(this.LanguageType("SCPI"))
                        switch(this.SourceMode)
                            case(this.SourceType("Voltage"));   compValue = this.QueryDouble("SOUR:VOLT:ILIM?");
                            case(this.SourceType("Current"));   compValue = this.QueryDouble("SOUR:CURR:VLIM?");
                            otherwise
                                error("Keithley2450:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
                        end
                    case(this.LanguageType("TSP"))
                        switch(this.SourceMode)
                            case(this.SourceType("Voltage"));   compValue = this.QueryDouble("print(smu.source.ilimit.level)");
                            case(this.SourceType("Current"));   compValue = this.QueryDouble("print(smu.source.vlimit.level)");
                            otherwise
                                error("Keithley2450:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
                        end
                    otherwise
                        error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
                end
            end

            %Compliance is opposite to source
            switch(this.SourceMode)
                case(this.SourceType("Voltage"));   str = " mA";
                case(this.SourceType("Current"));   str = " mV";
                otherwise
                    error("Keithley2450:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

            %Multiply by 1000, millivolts or mA is easier to read. Round to 6
            %significant figures, as the hardware stores values like
            %2.0999999046 for a 2.1 V limit (6 not 5, so the maximum 210 V
            %limit prints as 210000 mV rather than in exponent form)
            compStringWithUnits = num2str(compValue*1000, 6) + str;
        end

        function errorCount = GetErrorCount(this)
            %Count the unread errors in the instrument's event log, without removing them.
            %Counts errors only, not warnings or info events
            %
            %Outputs:
            %   errorCount - number of unread errors

            if (this.SimulationMode)
                errorCount = 0;
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"));    errorCount = this.QueryDouble("SYST:ERR:COUN?");
                case(this.LanguageType("TSP"));     errorCount = this.QueryDouble("print(eventlog.getcount(eventlog.SEV_ERROR))");
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end
        end

        function errors = GetErrors(this)
            %Read and remove all unread errors from the instrument's event log, oldest first.
            %Once read, errors can no longer be read remotely (they stay visible in
            %the front-panel event log until cleared)
            %
            %Outputs:
            %   errors - struct array with fields Code (event number) and
            %            Message - empty if there are no errors

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
                        error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
                end

                %Code 0 means the log is empty (nothing left to read)
                if code == 0; break; end
                errors(end+1) = struct("Code", code, "Message", message); %#ok<AGROW>
            end
        end

        function fourWireEnabled = GetFourWireEnabledStatus(this)
            %Read whether the measure function uses 4-wire (remote) sensing.
            %
            %Outputs:
            %   fourWireEnabled - true for 4-wire sensing, false for 2-wire

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
                    else
                        error("Keithley2450:UnexpectedSenseResponse", "%s", "Unexpected sense mode response: " + result);
                    end
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %The reading (named after MeasMode), the source value, and the
            %compliance flag
            %
            %The source column is named after SourceMode. When the source and
            %measured quantities are the same (e.g. sourcing and measuring
            %current), it is prefixed "Source" so the two columns differ
            %
            %Outputs:
            %   Headers - e.g. ["K2450_SrcMtr - Resistance_Ohms", "K2450_SrcMtr - Current_A",
            %             "K2450_SrcMtr - Compliance Limited"], or with
            %             "K2450_SrcMtr - Source Current_A" as the second
            %   Units   - matching units, e.g. ["Ohms", "A", ""]

            switch(this.MeasMode)
                case(this.MeasType("Resistance"));  measHeader = "Resistance_Ohms";     measUnits = "Ohms";
                case(this.MeasType("Current"));     measHeader = "Current_A";           measUnits = "A";
                case(this.MeasType("Voltage"));     measHeader = "Voltage_V";           measUnits = "V";
                case(this.MeasType("Power"));       measHeader = "Power_W";             measUnits = "W";
                otherwise
                    error("Keithley2450:InvalidMeasureMode", "%s", "Mode must be Resistance, Voltage, Current or Power, this was " + string(this.MeasMode));
            end

            switch(this.SourceMode)
                case(this.SourceType("Current"));   srcHeader = "Current_A";    srcUnits = "A";
                case(this.SourceType("Voltage"));   srcHeader = "Voltage_V";    srcUnits = "V";
                otherwise
                    error("Keithley2450:InvalidSourceType", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end
            if srcHeader == measHeader
                srcHeader = "Source " + srcHeader;
            end

            Headers = [this.Name + " - " + measHeader, this.Name + " - " + srcHeader, this.Name + " - Compliance Limited"];
            Units = [measUnits, srcUnits, ""];
        end

        function lang = GetLanguage(this)
            %Read the command set selected on the instrument.
            %
            %Outputs:
            %   lang - LanguageType categorical, TSP or SCPI. Errors for any other
            %          command set, such as the Model 2400 emulation (SCPI2400)

            if this.SimulationMode
                lang = this.LanguageType("TSP");
                return;
            end

            result = strtrim(string(this.QueryString("*LANG?")));
            if strcmp(result, "TSP")
                lang = this.LanguageType("TSP");
            elseif strcmp(result, "SCPI")
                lang = this.LanguageType("SCPI");
            else
                error("Keithley2450:UnsupportedInstrumentLanguage", "%s", "Unsupported instrument language: " + result);
            end
        end

        function measMode = GetMeasurementMode(this)
            %Read the quantity being measured, from the instrument's measure function and units.
            %The quantity depends on both - e.g. a voltage measurement can be
            %reported in Ohms (R = V / I_source) or Watts - so both are queried,
            %and the mode set from the units. In SCPI this also sets MeasFunction
            %
            %Outputs:
            %   measMode - MeasType categorical: Current, Voltage, Resistance or Power

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
                        error("Keithley2450:UnsupportedMeasurementFunction", "%s", "Unsupported measurement function: " + result);
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
                        error("Keithley2450:UnsupportedMeasurementFunction", "%s", "Unsupported measurement function: " + result);
                    end

                    %Returns e.g. smu.UNIT_OHM - strip the prefix to match
                    %the SCPI unit names
                    unitStr = strtrim(string(this.QueryString("print(smu.measure.unit)")));
                    unitStr = upper(erase(unitStr, "smu.UNIT_"));
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end

            switch(unitStr)
                case("AMP");    measMode = this.MeasType("Current");
                case("VOLT");   measMode = this.MeasType("Voltage");
                case("OHM");    measMode = this.MeasType("Resistance");
                case("WATT");   measMode = this.MeasType("Power");
                otherwise
                    error("Keithley2450:UnsupportedMeasurementUnit", "%s", "Unsupported measurement unit: " + unitStr);
            end
        end

        function [nplc, integrationTime_s] = GetNPLC(this)
            %Read the integration time of each reading, as a number of power line cycles (NPLC) and in seconds.
            %The time in seconds uses the line frequency the instrument detected
            %at power-on (50 or 60 Hz)
            %
            %Outputs:
            %   nplc              - integration time, in power line cycles
            %   integrationTime_s - integration time, in s

            if (this.SimulationMode)
                nplc = 1;
                lineFrequency_Hz = 50;
            else
                switch(this.Language)
                    case(this.LanguageType("SCPI"))
                        %NPLC belongs to the underlying measure function, not
                        %the MeasMode (e.g. Resistance may be VOLT in Ohms)
                        nplc = this.QueryDouble("SENS:" + this.MeasFunction + ":NPLC?");
                        lineFrequency_Hz = this.QueryDouble("SYST:LFR?");
                    case(this.LanguageType("TSP"))
                        nplc = this.QueryDouble("print(smu.measure.nplc)");
                        lineFrequency_Hz = this.QueryDouble("print(localnode.linefreq)");
                    otherwise
                        error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
                end
            end

            integrationTime_s = nplc / lineFrequency_Hz;
        end

        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(this)
            %Units, limits and plot labels of the swept source level, for a Sweep Control.
            %Before connecting, when the source function is not yet known, the
            %units and x label are empty
            %
            %Outputs:
            %   str       - units of the source level, "V" or "A"
            %   limits    - default lowest and highest sweep values, [min, max]
            %   xlabelStr - label for the source level on plots, e.g. "Source Voltage (V)"
            %   ylabelStr - label for the measured value on plots (the first data column header)

            %Handle the case of having not yet connected - so we don't yet
            %know the source and measurement mode
            if isempty(this.SourceMode)
                xlabelStr = "";
                str = "";
                limits = [-0.1, 0.1];
                ylabelStr = "Measured value";
                return;
            end

            %The 2450 can source up to +/-210 V and +/-1.05 A - these
            %narrower limits also set the Sweep Control's starting values
            switch(this.SourceMode)
                case(this.SourceType("Voltage"));   xlabelStr = "Source Voltage (V)";   str = "V";  limits = [-50, 50];
                case(this.SourceType("Current"));   xlabelStr = "Source Current (A)";   str = "A";  limits = [-1, 1];
                otherwise
                    error("Keithley2450:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

            hdrs = this.GetHeaders();
            ylabelStr = hdrs(1);
        end

        function srcLevel = GetSourceLevel(this)
            %Read the programmed source level.
            %
            %Outputs:
            %   srcLevel - source level, in V or A depending on SourceMode. In
            %              SimulationMode, the last level set by SetSourceLevel

            if (this.SimulationMode)
                srcLevel = this.RetrieveSimulatedDataValue("SourceLevel");
                return;
            end

            switch(this.SourceMode)
                case(this.SourceType("Voltage"))
                    switch(this.Language)
                        case(this.LanguageType("SCPI"));    srcLevel = this.QueryDouble("SOUR:VOLT:LEV:AMPL?");
                        case(this.LanguageType("TSP"));     srcLevel = this.QueryDouble("print(smu.source.getattribute(smu.FUNC_DC_VOLTAGE, smu.ATTR_SRC_LEVEL))");
                        otherwise
                            error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
                    end
                case(this.SourceType("Current"))
                    switch(this.Language)
                        case(this.LanguageType("SCPI"));    srcLevel = this.QueryDouble("SOUR:CURR:LEV:AMPL?");
                        case(this.LanguageType("TSP"));     srcLevel = this.QueryDouble("print(smu.source.getattribute(smu.FUNC_DC_CURRENT, smu.ATTR_SRC_LEVEL))");
                        otherwise
                            error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
                    end
                otherwise
                    error("Keithley2450:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end
        end

        function srcMode = GetSourceMode(this)
            %Read the instrument's source function.
            %
            %Outputs:
            %   srcMode - SourceType categorical, Voltage or Current

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
                        error("Keithley2450:UnsupportedSourceMode", "%s", "Unsupported source mode: " + result);
                    end

                case(this.LanguageType("TSP"))
                    result = this.QueryString("print(smu.source.func)");

                    if strcmp(result, "smu.FUNC_DC_CURRENT")
                        srcMode = this.SourceType("Current");
                    elseif strcmp(result, "smu.FUNC_DC_VOLTAGE")
                        srcMode = this.SourceType("Voltage");
                    else
                        error("Keithley2450:UnsupportedSourceMode", "%s", "Unsupported source mode: " + result);
                    end
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end
        end

        function [ovp_V, ovpSetting] = GetVoltageSourceOVP(this)
            %Read the overvoltage protection level of the voltage source function.
            %OVP is stored per source function - this reads the voltage function's,
            %whichever function is active. A reset clears it to none
            %
            %Outputs:
            %   ovp_V      - the protection limit, in V (Inf for none)
            %   ovpSetting - the instrument's own value, e.g. "smu.PROTECT_40V"
            %                (TSP) or "PROT40" (SCPI), for passing back to
            %                SetVoltageSourceOVP

            if (this.SimulationMode)
                ovp_V = Inf;
                ovpSetting = "smu.PROTECT_NONE";
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"));    ovpSetting = strtrim(string(this.QueryString("SOUR:VOLT:PROT?")));
                case(this.LanguageType("TSP"));     ovpSetting = strtrim(string(this.QueryString("print(smu.source.getattribute(smu.FUNC_DC_VOLTAGE, smu.ATTR_SRC_PROTECT_LEVEL))")));
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end

            if contains(ovpSetting, "NONE")
                ovp_V = Inf;
            else
                ovp_V = str2double(regexp(ovpSetting, "\d+", "match", "once"));
                if isnan(ovp_V)
                    error("Keithley2450:UnexpectedOVPSetting", "%s", "Unexpected overvoltage protection setting: " + ovpSetting);
                end
            end
        end

        function [complianceLimited] = IsAtComplianceLimit(this)
            %Read whether the source was limited by its compliance limit in the last measurement.
            %The instrument's tripped flag reflects the last measurement taken, not
            %a live reading of the output - Measure takes its compliance flag
            %from each reading's source status instead
            %
            %Outputs:
            %   complianceLimited - true if the source was at its limit

            if (this.SimulationMode)
                complianceLimited = false;
                return;
            end

            %Compliance is opposite to source, e.g. SOUR:VOLT:ILIM:TRIP? is
            %the current limit when sourcing voltage. (This command differs
            %from the older 2400-series models)
            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    switch(this.SourceMode)
                        case(this.SourceType("Voltage"));   compValue = this.QueryDouble("SOUR:VOLT:ILIM:TRIP?");
                        case(this.SourceType("Current"));   compValue = this.QueryDouble("SOUR:CURR:VLIM:TRIP?");
                        otherwise
                            error("Keithley2450:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
                    end
                    complianceLimited = logical(compValue);
                case(this.LanguageType("TSP"))
                    switch(this.SourceMode)
                        case(this.SourceType("Voltage"));   result = this.QueryString("print(smu.source.ilimit.tripped)");
                        case(this.SourceType("Current"));   result = this.QueryString("print(smu.source.vlimit.tripped)");
                        otherwise
                            error("Keithley2450:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
                    end

                    %Hardware returns the enum name smu.ON / smu.OFF (the
                    %manual also documents 1 / 0, so accept either)
                    result = strtrim(string(result));
                    if any(strcmp(result, ["smu.ON", "1"]))
                        complianceLimited = true;
                    elseif any(strcmp(result, ["smu.OFF", "0"]))
                        complianceLimited = false;
                    else
                        error("Keithley2450:UnexpectedComplianceResponse", "%s", "Unexpected compliance tripped response: " + result);
                    end
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end
        end

        function tf = IsInterlockEngaged(this)
            %Read whether the safety interlock is engaged, which is needed to source more than 42 V.
            %Without it the output is silently limited to below 42 V. (The
            %instrument calls this state "tripped")
            %
            %Outputs:
            %   tf - true if the interlock is engaged

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
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end
        end

        function tf = IsReplyWaiting(this)
            %Check, without blocking, whether the instrument has a reply waiting to be read.
            %Over GPIB/VISA this is a serial poll, which works even while a TSP
            %script is running - so it can be used to wait for a script to print
            %its result while staying responsive (e.g. to an Abort button). An
            %error in the event log does not count as a reply
            %
            %Outputs:
            %   tf - true if a reply is waiting

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
            %Take a reading, and return it with the source value and compliance flag.
            %Any errors the instrument has logged are reported as warnings (and
            %cleared). An overrange reading is returned as NaN, and a failed
            %reading (e.g. output off in Resistance or 4-wire mode) is an error
            %
            %Outputs:
            %   dataRow - [reading, source value, compliance limited (1 or 0)],
            %             matching GetHeaders

            if(this.SimulationMode)
                %Return dummy values if in simulation mode
                sourceLevel = this.GetSourceLevel();
                value = this.GenerateSimulatedData(1, Baseline=1e-5, Variance=1e-7);
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
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
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
                error("Keithley2450:NoMeasurementReading", "Measurement failed - instrument returned no reading (e.g. output off in Resistance or 4-wire mode). See the instrument error reported in the warning above.");
            end

            values = str2double(parts(1:end-1));
            if numel(values) ~= 3 || any(isnan(values))
                error("Keithley2450:UnexpectedMeasurementResponse", "%s", "Unexpected measurement response: " + data);
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
            %Clear the interface, then reset all instrument settings to their defaults.
            %Clearing first means no stale replies or queued commands survive the
            %reset

            this.ClearInterface();

            switch(this.Language)
                case(this.LanguageType("SCPI"));    this.WriteCommand("*RST");
                case(this.LanguageType("TSP"));     this.WriteCommand("reset(true)");
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end
        end

        function SendAbortCommand(this)
            %Stop a running TSP script, or the trigger model in SCPI.
            %The abort is processed even while a script is running. Allow a short
            %time (ABORT_PAUSE_S) before sending further commands

            if (this.SimulationMode); return; end

            switch(this.Language)
                case(this.LanguageType("SCPI"));    this.WriteCommand("ABOR");
                case(this.LanguageType("TSP"));     this.WriteCommand("abort");
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end
        end

        function SetNewSweepStepValue(this, value)
            %Set the source to the next step of a Sweep Control's sweep, with the output on.
            %
            %Inputs:
            %   value - source level, in V or A depending on SourceMode

            this.SetSourceLevel(value, true);
        end

        function SetSourceLevel(this, level, enableOutput)
            %Turn the output on or off, and set the source level.
            %
            %Inputs:
            %   level        - source level, in V or A depending on SourceMode
            %   enableOutput - true to turn the output on, false to turn it off

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
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end

            %Set the output level
            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    switch(this.SourceMode)
                        case(this.SourceType("Voltage"));   this.WriteCommand("SOUR:VOLT:LEV " + num2str(level));
                        case(this.SourceType("Current"));   this.WriteCommand("SOUR:CURR:LEV " + num2str(level));
                        otherwise
                            error("Keithley2450:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
                    end
                case(this.LanguageType("TSP"))
                    this.WriteCommand("smu.source.level = " + num2str(level));
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end
        end

        function SetVoltageSourceOVP(this, ovpSetting)
            %Set the overvoltage protection level of the voltage source function.
            %Takes a value returned by GetVoltageSourceOVP, e.g. to restore it after
            %a reset. Set it before turning the output on
            %
            %Inputs:
            %   ovpSetting - the instrument's own value: e.g. "smu.PROTECT_40V" or
            %                "smu.PROTECT_NONE" in TSP, "PROT40" or "NONE" in SCPI

            arguments
                this;
                ovpSetting (1,1) string;
            end
            if (this.SimulationMode); return; end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    assert(~isempty(regexp(ovpSetting, "^(PROT\d+|NONE)$", "once")), "Keithley2450:InvalidOVPSetting", "%s", "Invalid SCPI overvoltage protection setting: " + ovpSetting);
                    this.WriteCommand("SOUR:VOLT:PROT " + ovpSetting);
                case(this.LanguageType("TSP"))
                    assert(~isempty(regexp(ovpSetting, "^smu\.PROTECT_(\d+V|NONE)$", "once")), "Keithley2450:InvalidOVPSetting", "%s", "Invalid TSP overvoltage protection setting: " + ovpSetting);
                    this.WriteCommand("smu.source.setattribute(smu.FUNC_DC_VOLTAGE, smu.ATTR_SRC_PROTECT_LEVEL, " + ovpSetting + ")");
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end
        end

        function TurnOutputOff(this)
            %Turn the source output off.

            if (this.SimulationMode); return; end

            switch(this.Language)
                case(this.LanguageType("SCPI"));    this.WriteCommand("OUTP OFF");
                case(this.LanguageType("TSP"));     this.WriteCommand("smu.source.output = smu.OFF");
                otherwise
                    error("Keithley2450:UnsupportedLanguage", "%s", "Unsupported language type " + string(this.Language));
            end
        end

    end
end
