classdef Keithley2450 < Palladium.Core.Instrument
    %Instrument implementation for Keithley 2450 source meter - use this rather than the 24X0 more general (and deprecated) option.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Keithley 2450 Src Meter";       %Full name, just for displaying on GUI
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
        MeasMode;                                   %Measurement mode: Resistance, Voltage or Current. Will be queried from the hardware right after connecting.
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Resistance", "Voltage", "Current"]); end
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

            %Make sure to set values for Properties of Categorical type
            %like these
            this.Language = this.LanguageType("TSP");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function metadataStruct = CollectMetaData(this)             
            %Record instrument settings and metadata like compliance,
            %voltage, measurement mode, that will not change during the
            %measurement and therefore don't merit logging each step
            [~, metadataStruct.ComplianceLevel] = this.GetComplianceLevel();
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
                            case(this.SourceType("Voltage"))   %Compliance is opposite to source..
                                compValue = this.QueryDouble("SENS:CURR:PROT:LEV?");
                            case(this.SourceType("Current"))
                                compValue = this.QueryDouble("SENS:VOLT:PROT:LEV?");
                            otherwise
                                error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
                        end
                    case(this.LanguageType("TCP"))
                        switch(this.SourceMode)
                            case(this.SourceType("Voltage"))   %Compliance is opposite to source..
                                compValue = this.QueryDouble("smu.source.ilimit.level"); 
                            case(this.SourceType("Current"))
                                compValue = this.QueryDouble("smu.source.vlimit.level"); 
                            otherwise
                                error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
                        end
                    otherwise
                        error("Unsupported language type " + string(this.LanguageType));
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

        function fourWireEnabled = GetFourWireEnabledStatus(this)
            if (this.SimulationMode)
                fourWireEnabled = true;
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    result = this.QueryDouble("SYST:RSEN?");
                    fourWireEnabled = logical(result);
                case(this.LanguageType("TCP"))
                     result = this.QueryString("smu.measure.sense");
                     if strcmp(result, "smu.SENSE_2WIRE")
                         fourWireEnabled = false;
                     elseif strcmp(result, "smu.SENSE_4WIRE")
                         fourWireEnabled = true;
                     end

                otherwise
                    error("Unsupported language type " + string(this.LanguageType));
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
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + string(this.Mode));
            end

            
        end

        function measMode = GetMeasurementMode(this)
            if (this.SimulationMode)
                measMode = this.MeasType("Resistance");
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    result = this.QueryString("SENS:FUNC?");

                    if strcmp(result, "CURR")
                        measMode = this.MeasType("Current");
                    elseif strcmp(result, "VOLT")
                        measMode = this.MeasType("Voltage");
                    elseif strcmp(result, "RES")
                        measMode = this.MeasType("Resistance");
                    else
                        error("Unsupported source mode: " + result);
                    end

                case(this.LanguageType("TCP"))
                    result = this.QueryString("smu.measure.func");

                    if strcmp(result, "smu.FUNC_DC_CURRENT")
                        measMode = this.MeasType("Current");
                    elseif strcmp(result, "smu.FUNC_DC_VOLTAGE")
                        measMode = this.MeasType("Voltage");
                    elseif strcmp(result, "smu.FUNC_DC_RESISTANCE")
                        measMode = this.MeasType("Resistance");
                    else
                        error("Unsupported source mode: " + result);
                    end
                otherwise
                    error("Unsupported language type " + string(this.LanguageType));
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
                    case(this.LanguageType("TCP"))
                        nplc = this.QueryDouble("smu.measure.nplc");
                    otherwise
                        error("Unsupported language type " + string(this.LanguageType));
                end
            end

            integrationTime_s = nplc / 60;
        end

        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(this)
            switch(this.SourceMode)
                case(this.MeasType("Voltage"))
                    xlabelStr = "Source Voltage (V)";
                    str = "V";
                    limits = [-50, 50];    %Need to check what these physical limits actually are and improve this
                case(this.MeasType("Current"))
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
                        case(this.LanguageType("TCP"))
                            srcLevel = this.QueryDouble("smu.source.getattribute(smu.FUNC_DC_VOLTAGE, smu.ATTR_SRC_LEVEL)");
                        otherwise
                            error("Unsupported language type " + string(this.LanguageType));
                    end
                case(this.SourceType("Current"))
                    switch(this.Language)
                        case(this.LanguageType("SCPI"))
                            srcLevel = this.QueryDouble("SOUR:CURR:LEV:AMPL?");
                        case(this.LanguageType("TCP"))
                            srcLevel = this.QueryDouble("smu.source.getattribute(smu.FUNC_DC_CURRENT, smu.ATTR_SRC_LEVEL)");
                        otherwise
                            error("Unsupported language type " + string(this.LanguageType));
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

                case(this.LanguageType("TCP"))
                    result = this.QueryString("smu.source.func");

                    if strcmp(result, "smu.FUNC_DC_CURRENT")
                        srcMode = this.SourceType("Current");
                    elseif strcmp(result, "smu.FUNC_DC_VOLTAGE")
                        srcMode = this.SourceType("Voltage");
                    else
                        error("Unsupported source mode: " + result);
                    end
                otherwise
                    error("Unsupported language type " + string(this.LanguageType));
            end
        end
        
        function [complianceLimited] = IsAtComplianceLimit(this)
            if (this.SimulationMode)
                complianceLimited = false;
                return;
            end

            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    %Run volt or current queries depending on measurement mode
                    switch(this.SourceMode)
                        case(this.SourceType("Voltage"))   %Compliance is opposite to source.. and note that this command is different in the newer 2450 to the older models
                            compValue = this.QueryDouble("SENS:CURR:VLIM:TRIP?");
                        case(this.SourceType("Current"))
                            compValue = this.QueryDouble("SENS:VOLT:ILIM:TRIP?");
                        otherwise
                            error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
                    end
                case(this.LanguageType("TCP"))
                    compValue = this.QueryDouble("smu.source.xlimit.tripped");
                otherwise
                    error("Unsupported language type " + string(this.LanguageType));
            end

            complianceLimited = logical(compValue);
        end

        function [dataRow] = Measure(this)
            %Retrieve source level (will work for simulated and real data
            %both)
            sourceLevel = this.GetSourceLevel();

            if(this.SimulationMode)
                %Return dummy values if in simulation mode
                value = rand(1)*1e-7 + 2e-6;
                dataRow = [value sourceLevel, 0];
                return;
            end

            %Query the source meter for latest measurement and get a string
            switch(this.Language)
                case(this.LanguageType("SCPI"))
                    %returned. example for a 184 kOhm resistor with 10 microA current: '+1.839736E+00,+9.999968E-06,+1.839742E+05,+6.482821E+04,+4.506000E+04'
                    data = this.QueryString("READ?");   %TODO - can this be a Querydouble instead? And avoid the splitting and converting below? Check how Srv Meas I etc work, only tried resistance so far..

                case(this.LanguageType("TCP"))
                    data = this.QueryString("smu.measure.read()");
                otherwise
                    error("Unsupported language type " + string(this.LanguageType));
            end

            %Split the string into a cell array, split at the commas
            splitData = strsplit(data, ',');

            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    %Get measurement values from the split string
                    resistance = str2double(splitData{1});

                    %Assign data to output data row
                    dataRow = [resistance, sourceLevel];

                case(this.MeasType("Voltage"))
                    %Get measurement values
                    voltage = str2double(data);

                    %Assign data to output data row
                    dataRow = [voltage, sourceLevel];

                case(this.MeasType("Current"))
                    %Get measurement values
                    current = str2double(data);

                    %Assign data to output data row
                    dataRow = [current, sourceLevel];
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + string(this.Mode));
            end

            %Check if we have hit compliance, save that (1 or 0) as a data column
            complianceLimited = this.IsAtComplianceLimit();
            dataRow = [dataRow, complianceLimited];
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
                case(this.LanguageType("TCP"))
                    if(enableOutput)
                        this.WriteCommand("smu.source.output = smu.ON");
                    else
                        this.WriteCommand("smu.source.output = smu.OFF");
                    end
                otherwise
                    error("Unsupported language type " + string(this.LanguageType));
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
                case(this.LanguageType("TCP"))
                    this.WriteCommand("smu.source.level = " + num2str(level));
                otherwise
                    error("Unsupported language type " + string(this.LanguageType));
            end
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function OnInitialised(this)
            %Function that gets fired after successful Connect()
            %Query hardware options and setup, set properties like
            %MeasurementMode based on this
            this.SourceMode = this.GetSourceMode();
            this.MeasMode = this.GetMeasurementMode();
        end

    end
end


