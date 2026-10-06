classdef Keithley2410 < Palladium.Core.Instrument
    %Keithley2410 - Instrument driver for Keithley 2400 and 2410 SourceMeters.
    %Sources a voltage or current and measures voltage, current and (with the
    %ohms function on) resistance. Each measurement tick records, depending on
    %`MeasMode`, the measured values, the programmed source level and whether
    %the instrument is at its compliance limit. With a Sweep Control added, the
    %source level is stepped through a sweep.
    %
    %Set the source function, compliance, ranges, integration time and
    %measurement functions on the front panel: `SourceMode` must match the
    %source function set on the instrument, which is checked when connecting.
    %Each reading is a `:READ?`, which keeps those settings (unlike
    %`:MEASure?`, which resets them). The output is turned on before a reading
    %if it is off, as `:READ?` needs it on. Connecting sets the data elements
    %to voltage, current and resistance (`:FORMat:ELEMents VOLT,CURR,RES`).
    %
    %The 2400 series has GPIB and RS-232 interfaces. Setting `OffsetComp` makes
    %offset-compensated resistance measurements, by measuring at the source
    %level and at zero.

    %% Properties (Constant, Private)
    properties(Constant, Access = private)
        MaxSourceVoltage_V = 1100;                              %Most the 2410 can source, in V (21 mA at 1100 V) - the Sweep Control limit when the protection limit can't be read
        MaxSourceCurrent_A = 1.05;                              %Most the 2410 can source, in A (at up to 21 V) - the Sweep Control limit
    end

    %% Properties (Public)
    properties(Access = public)
        FullName = "Keithley 2410 Src Meter";                   %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "K2410_SrcMtr";                                  %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;                                               %Which columns to record: Resistance (R, I, V), Voltage (V, I) or Current (I, V), each followed by the source level and compliance flag
        SourceMode;                                             %Source function, Voltage or Current - must match the source function set on the instrument
        OffsetComp (1,1) logical = false;                       %Make offset-compensated resistance measurements, subtracting a reading at zero source level (Resistance MeasMode only)
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr);     catOut = this.ConvertToCategorical(inputStr, ["Resistance", "Voltage", "Current"]); end
        function catOut = SourceType(this, inputStr);   catOut = this.ConvertToCategorical(inputStr, ["Voltage", "Current"]); end
    end

    %% Constructor
    methods
        function this = Keithley2410()
            %Set the supported connection types, default settings and Sweep Control.

            %The 2400 series has GPIB and RS-232 ports; VISA can address either
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial", "VISA"]);
            this.GPIB_Address = 24;     %Factory default
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

            %RS-232 uses 8 data bits, 1 stop bit and no parity. 9600 baud is the
            %factory setting, and the instrument acts on a command when it
            %receives a CR - the baud rate and terminator must match the
            %COMMUNICATION menu on the instrument
            this.ConnectionSettings.SerialSettings = struct('BaudRate', 9600, 'DataBits', 8, 'Parity', 'none', 'StopBits', 1, 'Terminator', 'CR');

            %Define the Instrument Controls that can be added
            this.DefineInstrumentControl(Name = "Sweep Control", ClassName = "SweepController_Stepped", TabName = "Sweep Control", EnabledByDefault = false);

            %Make sure to set values for Properties of Categorical type
            %like these
            this.MeasMode = this.MeasType("Resistance");
            this.SourceMode = this.SourceType("Current");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function ArmTrigger(this)
            %Turn the output on and start continuous triggered measurements.
            %Sets an infinite arm count and initiates the trigger model. Not used
            %by the driver itself: a building block for triggered measurements

            this.WriteCommand("TRIG:CLE");
            this.WriteCommand("OUTP ON");   %Turn output on - or it refuses to start
            this.WriteCommand("ARM:SEQ:LAY:COUN INF");
            this.WriteCommand("INIT:IMM");
        end

        function ClearStatus(this)
            %Clear the instrument's status registers and error queue.

            this.WriteCommand("*CLS");
        end

        function Close(this)
            %Return the instrument to local (front panel) control, then disconnect.

            if ~isempty(this.DeviceHandle)
                this.SetLocal();
            end
            Close@Palladium.Core.Instrument(this);
        end

        function metadataStruct = CollectMetaData(this)
            %Source and measurement settings, recorded in the data-file header.
            %
            %Outputs:
            %   metadataStruct - struct with fields ComplianceLevel (e.g. "10 mA"),
            %   SourceMode, NumPowerLineCycles, IntegrationTime_s and FourWireMode

            [~, metadataStruct.ComplianceLevel] = this.GetComplianceLevel();
            metadataStruct.SourceMode = this.GetSourceMode();
            [metadataStruct.NumPowerLineCycles,  metadataStruct.IntegrationTime_s] = this.GetNPLC();
            metadataStruct.FourWireMode = this.GetFourWireEnabledStatus();
        end

        function Connect(this)
            %Open the connection, set the data elements and check SourceMode.
            %Sets :READ? replies to voltage, current and resistance, in that
            %order. Errors if the source function set on the instrument is not
            %SourceMode

            Connect@Palladium.Core.Instrument(this);
            if ~this.SimulationMode
                this.WriteCommand(":FORM:ELEM VOLT,CURR,RES");
            end
            this.VerifyConnectionSettings();
        end

        function data = FetchLatestData(this)
            %Read the latest reading from the instrument without triggering one.
            %Not used by the driver: a building block for triggered measurements
            %(see ArmTrigger). It does not work in the standard configuration
            %
            %Outputs:
            %   data - the first element of the latest reading

            data = this.QueryDouble("SENS:DAT:LAT?");
        end

        function [compValue, compStringWithUnits] = GetComplianceLevel(this)
            %Read the compliance limit - the current limit when sourcing voltage, and vice versa.
            %
            %Outputs:
            %   compValue           - compliance limit, in A or V
            %   compStringWithUnits - the limit in mA or mV, as text, e.g. "10 mA"

            if (this.SimulationMode)
                compValue = 120e-6;
            else
                switch(this.SourceMode)
                    case(this.SourceType("Voltage"));   compValue = this.QueryDouble("SENS:CURR:PROT:LEV?");
                    case(this.SourceType("Current"));   compValue = this.QueryDouble("SENS:VOLT:PROT:LEV?");
                    otherwise
                        error("Keithley2410:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
                end
            end

            %Compliance is in the opposite quantity to the source
            switch(this.SourceMode)
                case(this.SourceType("Voltage"));   str = " mA";
                case(this.SourceType("Current"));   str = " mV";
                otherwise
                    error("Keithley2410:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

            %Multiply by 1000, millivolts or mA is easier to read
            compStringWithUnits = num2str(compValue*1000) + str;
        end

        function fourWireEnabled = GetFourWireEnabledStatus(this)
            %Read whether 4-wire (remote) sensing is on.
            %
            %Outputs:
            %   fourWireEnabled - true for 4-wire sensing, false for 2-wire

            if (this.SimulationMode)
                fourWireEnabled = true;
                return;
            end

            result = this.QueryDouble("SYST:RSEN?");
            fourWireEnabled = logical(result);
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %The measured values (set by MeasMode), then the source level and
            %compliance flag
            %
            %Outputs:
            %   Headers - e.g. ["K2410_SrcMtr - Resistance (Ohms)", ..., "K2410_SrcMtr - Compliance Limited"].
            %             The quantity MeasMode names is always first
            %   Units   - matching units, e.g. ["Ohms", "A", "V", "A", ""]

            switch(this.SourceMode)
                case(this.SourceType("Voltage"));   sourceStr = "Source Voltage (V)";   unitsstr = "V";
                case(this.SourceType("Current"));   sourceStr = "Source Current (A)";   unitsstr = "A";
                otherwise
                    error("Keithley2410:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    Headers = [this.Name + " - Resistance (Ohms)", this.Name + " - Current (A)", this.Name + " - Voltage (V)", this.Name + " - " + sourceStr, this.Name + " - Compliance Limited"];
                    Units = ["Ohms", "A", "V", unitsstr, ""];
                case(this.MeasType("Voltage"))
                    Headers = [this.Name + " - Voltage (V)", this.Name + " - Current (A)", this.Name + " - " + sourceStr, this.Name + " - Compliance Limited"];
                    Units = ["V", "A", unitsstr, ""];
                case(this.MeasType("Current"))
                    Headers = [this.Name + " - Current (A)", this.Name + " - Voltage (V)", this.Name + " - " + sourceStr, this.Name + " - Compliance Limited"];
                    Units = ["A", "V", unitsstr, ""];
                otherwise
                    error("Keithley2410:InvalidMeasureMode", "%s", "Mode must be Resistance, Voltage, or Current, this was " + string(this.MeasMode));
            end
        end

        function [nplc, integrationTime_s] = GetNPLC(this)
            %Read the integration time of the MeasMode function, in power line cycles.
            %
            %Outputs:
            %   nplc              - number of power line cycles (NPLC)
            %   integrationTime_s - the same integration time in seconds, using
            %                       the line frequency set on the instrument

            if (this.SimulationMode)
                nplc = 1;
                lineFrequency = 50;
            else
                switch(this.MeasMode)
                    case(this.MeasType("Resistance"));  nplc = this.QueryDouble("SENS:RES:NPLC?");
                    case(this.MeasType("Voltage"));     nplc = this.QueryDouble("SENS:VOLT:DC:NPLC?");
                    case(this.MeasType("Current"));     nplc = this.QueryDouble("SENS:CURR:DC:NPLC?");
                    otherwise
                        error("Keithley2410:InvalidMeasureMode", "%s", "Mode must be Resistance, Voltage, or Current, this was " + string(this.MeasMode));
                end
                lineFrequency = this.QueryDouble("SYST:LFR?");    %50 or 60 Hz
            end

            integrationTime_s = nplc / lineFrequency;
        end

        function [srcLevel, srcEnabled] = GetSourceLevel(this)
            %Read the programmed source level, and whether the output is on.
            %
            %Outputs:
            %   srcLevel   - source level, in V or A (see SourceMode)
            %   srcEnabled - true if the output is on

            if (this.SimulationMode)
                srcLevel = this.RetrieveSimulatedDataValue("SourceLevel");
                srcEnabled = this.RetrieveSimulatedDataValue("SourceEnabled", true);
                return;
            end

            %Query whether the source is enabled
            enabled = this.QueryDouble("OUTP?");
            srcEnabled = (enabled == 1);

            switch(this.SourceMode)
                case(this.SourceType("Voltage"));   srcLevel = this.QueryDouble("SOUR:VOLT:LEV:AMPL?");
                case(this.SourceType("Current"));   srcLevel = this.QueryDouble("SOUR:CURR:LEV:AMPL?");
                otherwise
                    error("Keithley2410:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end
        end

        function sourceMode = GetSourceMode(this)
            %Read the source function set on the instrument.
            %
            %Outputs:
            %   sourceMode - SourceType categorical, Voltage or Current

            if (this.SimulationMode)
                sourceMode = this.SourceMode;
                return;
            end

            result = string(strtrim(this.QueryString("SOUR:FUNC:MODE?")));
            switch(result)
                case("VOLT");   sourceMode = this.SourceType("Voltage");
                case("CURR");   sourceMode = this.SourceType("Current");
                otherwise
                    error("Keithley2410:InvalidInstrumentSourceMode", "%s", "Source mode must be VOLT or CURR, received " + string(result) + " when querying instrument");
            end
        end

        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(this)
            %Units, limits and plot labels of the source level, for a Sweep Control.
            %
            %When sourcing voltage and connected, the limits are the V-source
            %protection limit set on the instrument (:SOURce:VOLTage:PROTection,
            %e.g. 20 V), which reads as the model's maximum when no limit is set.
            %Otherwise they are the most the 2410 can source: 1100 V, or 1.05 A
            %
            %Outputs:
            %   str       - units of the source level, "V" or "A"
            %   limits    - lowest and highest source levels allowed in the Sweep
            %               Control, [min, max]
            %   xlabelStr - label for the source level on plots
            %   ylabelStr - label for the measured value on plots: the first data
            %               column header

            switch(this.SourceMode)
                case(this.SourceType("Voltage"));   xlabelStr = "Source Voltage (V)";   str = "V";  limits = this.GetSourceVoltageLimit() * [-1, 1];
                case(this.SourceType("Current"));   xlabelStr = "Source Current (A)";   str = "A";  limits = this.MaxSourceCurrent_A * [-1, 1];
                otherwise
                    error("Keithley2410:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

            hdrs = this.GetHeaders();
            ylabelStr = hdrs(1);
        end

        function [complianceLimited] = IsAtComplianceLimit(this)
            %Read whether the instrument is at its compliance limit.
            %
            %Outputs:
            %   complianceLimited - true if the measured current (when sourcing
            %                       voltage) or voltage (when sourcing current) is
            %                       at the compliance limit

            if (this.SimulationMode)
                compValue = 0;
            else
                %Compliance is in the opposite quantity to the source
                switch(this.SourceMode)
                    case(this.SourceType("Voltage"));   compValue = this.QueryDouble("SENS:CURR:PROT:TRIP?");
                    case(this.SourceType("Current"));   compValue = this.QueryDouble("SENS:VOLT:PROT:TRIP?");
                    otherwise
                        error("Keithley2410:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
                end
            end

            complianceLimited = logical(compValue);
        end

        function [dataRow] = Measure(this)
            %Take one reading, and record it with the source level and compliance flag.
            %With OffsetComp on, the resistance is offset-compensated: readings
            %are taken at zero and at the source level, and R = dV/dI
            %
            %Outputs:
            %   dataRow - the values, in the order of GetHeaders

            %Store the currently set source level. :READ? needs the output on,
            %so turn it on if it is off (as :MEASure? used to)
            [sourceLvl, srcEnabled] = this.GetSourceLevel();
            if ~srcEnabled && ~this.SimulationMode
                this.WriteCommand("OUTP ON");
            end

            if(this.OffsetComp)
                %Error if not in Ohms mode
                if(this.MeasMode ~= this.MeasType("Resistance"))
                    error("Keithley2410:OffsetCompNotResistanceMode", "OffsetComp only functions in Resistance Mode");
                end

                %Set to zero source level and measure
                this.SetSourceLevel(0, true);
                [voltage1, current1] = this.ReadData();

                %Set to initial source level and measure
                this.SetSourceLevel(sourceLvl, true);
                [voltage2, current2] = this.ReadData();

                %Offset-compensated ohms = dV/dI between the two source levels
                resistance = (voltage2 - voltage1) / (current2 - current1);
                voltage = voltage2; %Maybe should do something a bit more clever with these? Depending on source mode?
                current = current2;
            else
                [voltage, current, resistance] = this.ReadData();
            end

            %Check if we have hit compliance, save that (1 or 0) as a data column
            complianceLimited = this.IsAtComplianceLimit();

            %Assign data to output data row - the quantity MeasMode names first
            switch(this.MeasMode)
                case(this.MeasType("Resistance"));  dataRow = [resistance, current, voltage, sourceLvl, complianceLimited];
                case(this.MeasType("Voltage"));     dataRow = [voltage, current, sourceLvl, complianceLimited];
                case(this.MeasType("Current"));     dataRow = [current, voltage, sourceLvl, complianceLimited];
                otherwise
                    error("Keithley2410:InvalidMeasureMode", "%s", "Mode must be Resistance, Voltage, or Current, this was " + string(this.MeasMode));
            end
        end

        function [voltage, current, resistance] = MeasureSingleShotData(this)
            %Make one :MEASure? reading of voltage, current and resistance.
            %:MEASure? turns the output on, and resets the measurement settings
            %(range, integration time) to their defaults - Measure uses
            %ReadData instead. Resistance is NaN unless MeasMode is Resistance
            %
            %Outputs:
            %   voltage    - measured voltage, in V
            %   current    - measured current, in A
            %   resistance - measured resistance, in Ohms

            if(this.SimulationMode)
                %Dummy values
                resistance = this.GenerateSimulatedData(1, Baseline=10, Variance=0.1);
                current = this.GenerateSimulatedData(1, Baseline=5, Variance=0.01);
                voltage = this.GenerateSimulatedData(1, Baseline=1, Variance=0.01);
                return;
            end

            %Reply is the default data elements, e.g. for a 184 kOhm resistor
            %with 10 uA current:
            %'+1.839736E+00,+9.999968E-06,+1.839742E+05,+6.482821E+04,+4.506000E+04'
            data = this.QueryString("MEAS?");
            [voltage, current, resistance] = this.ParseDataString(data);
        end

        function [voltage, current, resistance] = ReadData(this)
            %Make one :READ? reading of voltage, current and resistance.
            %Keeps the measurement settings made on the instrument, unlike
            %:MEASure?. The output must be on (Measure turns it on)
            %
            %Outputs:
            %   voltage    - measured voltage, in V
            %   current    - measured current, in A
            %   resistance - measured resistance, in Ohms (NaN unless MeasMode is
            %                Resistance and the ohms function is on)

            if(this.SimulationMode)
                [voltage, current, resistance] = this.MeasureSingleShotData();  %Same dummy values
                return;
            end

            data = this.QueryString("READ?");
            [voltage, current, resistance] = this.ParseDataString(data);
        end

        function SetLocal(this)
            %Return the instrument to local (front panel) control, over RS-232.
            %:SYSTem:LOCal is only accepted over RS-232; over GPIB, press LOCAL
            %on the front panel

            if this.Connection_Type == Palladium.Enums.ConnectionType.Serial
                this.WriteCommand("SYST:LOC");
            end
        end

        function SetNewSweepStepValue(this, value)
            %Set the source level to a Sweep Control's next step, with the output on.
            %
            %Inputs:
            %   value - new source level, in V or A (see SourceMode)

            this.SetSourceLevel(value, true);
        end

        function SetSourceLevel(this, level, enableOutput)
            %Set the source level, and turn the output on or off.
            %
            %Inputs:
            %   level        - source level, in V or A (see SourceMode)
            %   enableOutput - true to turn the output on, false to turn it off

            if(this.SimulationMode)
                %Store in SimulatedData struct, otherwise do nothing, just print
                disp("Setting source to " + num2str(level) + ", output enabled: " + num2str(enableOutput));
                this.SimulatedData.SourceLevel = level;
                this.SimulatedData.SourceEnabled = enableOutput;
                return;
            end

            %Turn output on or off
            if(enableOutput)
                this.WriteCommand("OUTP ON");
            else
                this.WriteCommand("OUTP OFF");
            end

            switch(this.SourceMode)
                case(this.SourceType("Voltage"));   this.WriteCommand("SOUR:VOLT:LEV " + num2str(level));
                case(this.SourceType("Current"));   this.WriteCommand("SOUR:CURR:LEV " + num2str(level));
                otherwise
                    error("Keithley2410:InvalidSourceMode", "%s", "Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function [voltage, current, resistance] = ParseDataString(this, data)
            %Split a reading into voltage, current and resistance.
            %
            %Inputs:
            %   data - comma-separated reading starting voltage, current,
            %          resistance (as set by Connect; :MEASure? also adds
            %          timestamp and status, which are ignored)
            %
            %Outputs:
            %   voltage    - in V
            %   current    - in A
            %   resistance - in Ohms, or NaN unless MeasMode is Resistance.
            %                Any value the instrument reports as 9.91e37 (not
            %                measured) or 9.9e37 (overflow) is NaN

            splitData = str2double(strsplit(data, ','));
            splitData(splitData >= 9.9e37) = NaN;
            voltage = splitData(1);
            current = splitData(2);

            switch(this.MeasMode)
                case(this.MeasType("Resistance"));  resistance = splitData(3);
                case(this.MeasType("Voltage"));     resistance = NaN;
                case(this.MeasType("Current"));     resistance = NaN;
                otherwise
                    error("Keithley2410:InvalidMeasureMode", "%s", "Mode must be Resistance, Voltage, or Current, this was " + string(this.MeasMode));
            end
        end

        function limit_V = GetSourceVoltageLimit(this)
            %Read the V-source protection limit set on the instrument, in V.
            %Falls back to the 2410's maximum source voltage when not connected
            %(or in Debug mode), or if the query fails
            %
            %Outputs:
            %   limit_V - the limit, as a positive voltage

            limit_V = this.MaxSourceVoltage_V;
            if this.SimulationMode || isempty(this.DeviceHandle)
                return;
            end
            try
                reading = abs(this.QueryDouble(":SOUR:VOLT:PROT?"));
                if ~isnan(reading) && reading > 0
                    limit_V = reading;
                end
            catch err
                Palladium.Logging.Logger.Log("Warning", this.Name + " could not read its voltage protection limit, so the Sweep Control allows up to " + limit_V + " V: " + err.message);
            end
        end

        function VerifyConnectionSettings(this)
            %Check that SourceMode matches the source function set on the instrument.

            instsrcMode = this.GetSourceMode();
            assert(instsrcMode == this.SourceMode, "Keithley2410:SourceModeMismatch", "Source Mode set in Palladium does not match that set in the Hardware");
        end

    end
end
