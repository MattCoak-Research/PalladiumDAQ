classdef Keithley2410 < Palladium.Core.Instrument
    %Instrument implementation for Keithley 2400 and 2410 source meters.
    %Note that this assumes the instrument is measuring already - just reads data.

    %% Properties (Constant, Public)
    properties(Constant, Access = public)
        FullName = "Keithley 2410 Src Meter";       %Full name, just for displaying on GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "K2410_SrcMtr";                            %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;                                   %Resistance, Voltage, Current
        SourceMode;                                 %Current, Voltage
        OffsetComp = false;
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Resistance", "Voltage", "Current"]); end
        function catOut = SourceType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Voltage", "Current"]); end
    end

    %% Constructor
    methods
        function this = Keithley2410()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = 24;      %Default Address
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

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
            this.WriteCommand("TRIG:CLE");
            this.WriteCommand("OUTP ON");%Turn output on - or it refuses to start
            this.WriteCommand("ARM:SEQ:LAY:COUN INF");
            this.WriteCommand("INIT:IMM");
        end

        function ClearStatus(this)
            this.WriteCommand("*CLS");
        end

        function Close(this)
            %Execute normal base class Close behaviour, but first place
            %instrument in Local mode
            if ~isempty(this.DeviceHandle)
                this.SetLocal();
            end
            Close@Palladium.Core.Instrument(this);
        end

        function metadataStruct = CollectMetaData(this)             
            %Record instrument settings and metadata like compliance,
            %voltage, measurement mode, that will not change during the
            %measurement and therefore don't merit logging each step
            [~, metadataStruct.ComplianceLevel] = this.GetComplianceLevel();
            metadataStruct.SourceMode = this.GetSourceMode();
            [metadataStruct.NumPowerLineCycles,  metadataStruct.IntegrationTime_s] = this.GetNPLC();
            metadataStruct.FourWireMode = this.GetFourWireEnabledStatus();
        end

        function Connect(this)
            %Execute normal base class Connect behaviour, but then verify
            %that the given settings match the hardware ones
            Connect@Palladium.Core.Instrument(this);
            this.VerifyConnectionSettings();
        end

        function [compValue, compStringWithUnits] = GetComplianceLevel(this)
            if (this.SimulationMode)
                compValue = 120e-6;
            else
                switch(this.SourceMode)
                    case(this.SourceType("Voltage"))   %Compliance is opposite to source..
                        compValue = this.QueryDouble("SENS:CURR:PROT:LEV?");
                    case(this.SourceType("Current"))
                        compValue = this.QueryDouble("SENS:VOLT:PROT:LEV?");
                    otherwise
                        error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
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

            %Multiply by 1000, millivolts or mA is easier to read
            compStringWithUnits = num2str(compValue*1000) + str;
        end

        function [Headers, Units] = GetHeaders(this)

            switch(this.SourceMode)
                case(this.SourceType("Voltage"))
                    sourceStr = "Source Voltage (V)";
                    unitsstr = "V";
                case(this.SourceType("Current"))
                    sourceStr = "Source Current (A)";
                    unitsstr = "A";
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    Headers = [this.Name + " - Resistance (Ohms)", this.Name + " - Current (A)", this.Name + " - Voltage (V)", this.Name + " - " + sourceStr, this.Name + " - Compliance Limited"];
                    Units = ["Ohms", "A", "V", unitsstr, ""];
                case(this.MeasType("Voltage"))
                    Headers = [this.Name + " - Current (A)", this.Name + " - Voltage (V)", this.Name + " - " + sourceStr, this.Name + " - Compliance Limited"];
                    Units = ["A", "V", unitsstr, ""];
                case(this.MeasType("Current"))
                    Headers = [this.Name + " - Voltage (V)", this.Name + " - Current (A)", this.Name + " - " + sourceStr, this.Name + " - Compliance Limited"];
                    Units = ["V", "A", unitsstr, ""];
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + string(this.MeasMode));
            end
        end

        function fourWireEnabled = GetFourWireEnabledStatus(this)
            result = this.QueryDouble("SYST:RSEN?");
            fourWireEnabled = logical(result);
        end

        function [nplc, integrationTime_s] = GetNPLC(this)
            %Get the Number of Power Line Cycles for the selected
            %measurement - the integration time for each reading. second
            %output helpfully converts this into a time in seconds
            if (this.SimulationMode)
                nplc = 1;
            else
                switch(this.MeasMode)
                    case(this.MeasType("Resistance"))
                        nplc = this.QueryDouble("SENS:RES:NPLC?");
                    case(this.MeasType("Voltage"))
                        nplc = this.QueryDouble("SENS:VOLT:DC:NPLC?");
                    case(this.MeasType("Current"))
                        nplc = this.QueryDouble("SENS:CURR:DC:NPLC?");
                    otherwise
                        error("Mode must be Resistance, Voltage, or Current, this was " + this.MeasMode);
                end
            end

            integrationTime_s = nplc / 60;
        end

        function sourceMode = GetSourceMode(this)
            if (this.SimulationMode)
                sourceMode = this.SourceMode;
                return;
            end

            result = string(strtrim(this.QueryString("SOUR:FUNC:MODE?")));
            switch(result)
                case("VOLT")   %Compliance is opposite to source..
                    sourceMode = this.SourceType("Voltage");
                case("CURR")
                    sourceMode = this.SourceType("Current");
                otherwise
                    error("Source mode must be VOLT or CURR, received " + string(result) + " when querying instrument");
            end
        end

        function [srcLevel, srcEnabled] = GetSourceLevel(this)
            if (this.SimulationMode)
                srcLevel = this.RetrieveSimulatedDataValue("SourceLevel");
                srcEnabled = this.RetrieveSimulatedDataValue("SourceEnabled", true);
                return;
            end

            %Query whether the source is enabled
            enabled = this.QueryDouble("OUTP?");
            srcEnabled = (enabled == 1);

            switch(this.SourceMode)
                case(this.SourceType("Voltage"))
                    srcLevel = this.QueryDouble("SOUR:VOLT:LEV:AMPL?");
                case(this.SourceType("Current"))
                    srcLevel = this.QueryDouble("SOUR:CURR:LEV:AMPL?");
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end
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

        function [complianceLimited] = IsAtComplianceLimit(this)
            if (this.SimulationMode)
                compValue = 0;
            else
                %Run volt or current queries depending on measurement mode
                switch(this.SourceMode)
                    case(this.SourceType("Voltage"))   %Compliance is opposite to source..
                        compValue = this.QueryDouble("SENS:CURR:PROT:TRIP?");
                    case(this.SourceType("Current"))
                        compValue = this.QueryDouble("SENS:VOLT:PROT:TRIP?");
                    otherwise
                        error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
                end
            end

            complianceLimited = logical(compValue);
        end

        function [dataRow] = Measure(this)

            %Store the currently set source level
            sourceLvl = this.GetSourceLevel();
            %Query the source meter for latest measurement and get a string
            %returned. example for a 184 kOhm resistor with 10 microA current: '+1.839736E+00,+9.999968E-06,+1.839742E+05,+6.482821E+04,+4.506000E+04'
            if(this.OffsetComp)
                %Error if not in Ohms mode
                if(this.MeasMode ~= this.MeasType("Resistance"))
                    error("OffsetComp only functions in Resistance Mode");
                end


                %Set to zero source level and measure
                this.SetSourceLevel(0, true);
                [voltage1, current1, resistance1] = this.MeasureSingleShotData(); %#ok<ASGLU>

                %Set to initial source level and measure
                this.SetSourceLevel(sourceLvl, true);
                [voltage2, current2, resistance2] = this.MeasureSingleShotData();

                resistance = resistance2 - resistance1;
                voltage = voltage2; %Maybe should do something a bit more clever with these? Depending on source mode?
                current = current2;
            else
                [voltage, current, resistance] = this.MeasureSingleShotData();
            end

            %Check if we have hit compliance, save that (1 or 0) as a data column
            complianceLimited = this.IsAtComplianceLimit();

            %Assign data to output data row
            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    dataRow = [resistance, current, voltage, sourceLvl, complianceLimited];
                case(this.MeasType("Voltage"))
                    dataRow = [current, voltage, sourceLvl, complianceLimited];
                case(this.MeasType("Current"))
                    %Assign data to output data row
                    dataRow = [voltage, current, sourceLvl, complianceLimited];
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + this.MeasMode);
            end
        end

        function [voltage, current, resistance] = MeasureSingleShotData(this)
            if(this.SimulationMode)
                %Dummy values
                resistance = 10 + 0.1*rand();
                current = 5 + 0.01*rand();
                voltage =1 + 0.01*rand;
                return;                
            end

            data = this.QueryString("MEAS?");
            [voltage, current, resistance] = this.ParseDataString(data);

        end

        function SetLocal(this)
            this.WriteCommand("SYST:LOC");
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
            if(enableOutput)
                this.WriteCommand("OUTP ON");
            else
                this.WriteCommand("OUTP OFF");
            end

            switch(this.SourceMode)
                case(this.SourceType("Voltage"))
                    this.WriteCommand("SOUR:VOLT:LEV " + num2str(level));
                case(this.SourceType("Current"))
                    this.WriteCommand("SOUR:CURR:LEV " + num2str(level));
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

        end

        function data = FetchLatestData(this)
            %This does not work in standard configuration. Here as a
            %building block for future more complex triggered stuff
            data = this.QueryDouble("SENS:DAT:LAT?");
        end

        function [voltage, current, resistance] = ReadData(this)
            %This does not work
            data = this.QueryDouble("READ?");
            [voltage, current, resistance] = this.ParseDataString(data);
        end        

    end

    %% Methods (Private)
    methods (Access = private)

        function [voltage, current, resistance] = ParseDataString(this, data)
            %Split the string into a cell array, split at the commas
            splitData = strsplit(data, ',');

            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    %Get measurement values from the split string
                    voltage = str2double(splitData{1});
                    current = str2double(splitData{2});
                    resistance = str2double(splitData{3});
                    %Not sure what 4 and 5 are right now..

                case(this.MeasType("Voltage"))
                    %Get measurement values from the split string
                    voltage = str2double(splitData{1});
                    current = str2double(splitData{2});
                    resistance = NaN;

                case(this.MeasType("Current"))
                    %Get measurement values from the split string
                    voltage = str2double(splitData{1});
                    current = str2double(splitData{2});
                    resistance = NaN;
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + string(this.MeasMode));
            end
        end

        function VerifyConnectionSettings(this)
            instsrcMode = this.GetSourceMode();
            assert(instsrcMode == this.SourceMode, "Source Mode set in Palladium does not match that set in the Hardware");
        end
        
    end
end

