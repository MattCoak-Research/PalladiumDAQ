classdef(Abstract) Instrument < Palladium.Core.Entity
    %Instrument - Abstract base class all instrument implementations must
    %inherit from.

    %% Properties (Abstract, Constant, Public)
    properties(Abstract, Constant, Access = public)
    end

    %% Properties (Abstract, Public)
    properties(Abstract, Access = public)
        FullName;   %Will be displayed on eg instrument settings tab
        Name;
        Connection_Type;   %Type of connection to use to communicate with the instrument. Value will be a member of the ConnectionType Enum
    end

    %% Properties (Public, SetObservable)
    properties(Access = public, SetObservable)
        GPIB_Address    (1,1) {mustBeInteger, mustBeBetween(GPIB_Address, 0, 30)} = 0;
        IP_Address      {mustBeTextScalar}  = '192.0.0.0.0';
        Serial_Address  {mustBeTextScalar} = 'COM12';
        VISA_Address    {mustBeTextScalar} = "VISA_ADDRESS";
    end

    %% Properties (Public)
    properties(Access = public) %Properties that will not get detected by the GUI and have buttons added for them
        LastFullDataRow = [];           %Each tick, the Controller will store the complete DataRow in each Instrument here. This is used when Instruments write their own data files, for things like independent sweeps
        FullHeadersRow = [];            %On measurements start, this will get cached with the full array of headers for the whole setup - again, for instrument-driven data writing.
        FileWriteDetails = [];
    end

    %% Properties (Protected)
    properties(GetAccess = public, SetAccess = protected)
        SimulationMode = false;         %Set to true if testing code while not actually connected to a physical instrument - dummy data will be generated. Set via constructor of instance classes only.
    end

    %% Properties (Protected)
    properties(Access = protected)
        DeviceHandle = [];              %Reference to the instrument connection/session, set when calling Connect()
        SettingsToApply = [];           %Either null, or a struct of all the settings to apply in the next Measure command (keep these calls synchronous, they come originally from events)
        SimulatedData = [];             %Empty placeholder where an Instrument can define struct properties like SimulatedData.SourceLevel for testing things like SweepControl

        %Default Connection Settings - override individual settings in implementation class
        %constructors
        ConnectionSettings = struct('GPIB_BoardIndex', 0,...
            'Port', 5025,...
            'GPIB_Terminators', ["CR/LF", "CR/LF"],...
            'GPIB_Timeout', 10,...
            'SerialSettings', struct('BaudRate', 9600, 'DataBits', 8, 'Parity', 'none', 'StopBits', 2, 'Terminator', 'LF')...
            );
    end

    %% Properties (Private)
    properties(Access = private)
        AllowedConnectionTypes = [...
            Palladium.Enums.ConnectionType.Debug,...
            Palladium.Enums.ConnectionType.GPIB,...
            Palladium.Enums.ConnectionType.VISA,...
            Palladium.Enums.ConnectionType.Ethernet,...
            Palladium.Enums.ConnectionType.Serial,...
            Palladium.Enums.ConnectionType.USB...
            ];
        ControlClasses = [];
        ControlDetailsStructs = []; % List of structs that define the options for later creating Control Classes
    end

    %% Events
    events (NotifyAccess = private)
        PropertyChanged;
    end

    %% Methods (Abstract, Public)
    methods(Abstract, Access = public)
        [Headers, Units] = GetHeaders(this);
        [dataRow] = Measure(this);
    end

    %% Constructor
    methods
        function this = Instrument()
            %Register events that will auto-fire when we modify
            %SetObservable events on this instance ("PropertyChanged")
            this.RegisterPropertyChangedEvents();
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function AbortRamp(this)
            %Override in base classes to support SweepController_Ramp
            %functionality
        end

        function CheckForSettingsToApply(this)
            %Apply heater control settings, if Set has been pressed on a
            %ControlPanel somewhere
            if ~isempty(this.SettingsToApply)
                this.ApplySettings(this.SettingsToApply);
                this.SettingsToApply = [];
            end
        end

        function Close(this)
            %This (so far) looks to be common behaviour across all instruments.
            %Can override this function in implementing class if more behaviour needed.
            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    %Just print a message
                    disp("Disconnected from simulated " + this.Name + " instrument.");
                otherwise
                    %Warn and return if there is no connection to disconnect from
                    if(isempty(this.DeviceHandle))
                        disp("Tried to close " + this.Name + " but it is not connected, or has no device handle. Returning Disconnect() with no action taken.");
                        return;
                    end

                    %Terminate the connection, reporting any errors if
                    %found
                    try
                        this.DeviceHandle = [];
                    catch e
                        error("CloseError:DisconnectFailed", "%s", "Error disconnecting from " + this.Name + ": " + e.message);
                    end
            end
        end

        function metadataStruct = CollectMetaData(this) %#ok<*MANU>
            %Does nothing by default - implementations of individual
            %instruments can override this to give functionality.
            %This returns an empty [] and therefore no line will be added
            %to the datafile header.
            %If a struct is instead returned by the overriding version (see
            %the InstrumentTemplate class for an example) it will be parsed
            %into a string and that added as a line in the data file
            %header.
            %Use this to record instrument settings and metadata like
            %frequency, voltage, measurement mode, that will not change
            %during the measurement and therefore don't merit logging each
            %step
            metadataStruct = [];
        end

        function Connect(this)
            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    %Do not make a physical connection to a real instrument
                    %- this places the class into SimulationMode, for
                    %testing without a real piece of hardware connected
                    disp("Connected to simulated " + this.Name + " instrument.");
                    this.SimulationMode = true;
                case(Palladium.Enums.ConnectionType.Ethernet)
                    this.ConnectTCPIP();
                case(Palladium.Enums.ConnectionType.GPIB)
                    this.ConnectGPIB();
                case(Palladium.Enums.ConnectionType.VISA)
                    this.ConnectVISA();
                case(Palladium.Enums.ConnectionType.USB)
                    this.ConnectUSB();
                case(Palladium.Enums.ConnectionType.Serial)
                    this.ConnectSerial();
                otherwise
                    error("ConnectError:UnsupportedConnectionType", "%s", "Unsupported connection type: " + this.Connection_Type + ". ConnectionType can be tcpip, gpib, serial, usb, or visa.");
            end
        end

        function datArray = GenerateSimulatedData(~, numRows, numCols, Settings)
            %GENERATESIMULATEDDATA - Create synthetic data with optional row or column grouping
            %
            % Input arguments:
            %   numRows  - number of simulated rows
            %   numCols  - number of simulated columns
            %   Settings - struct controlling baseline, transpose, and variance
            %
            % Output arguments:
            %   datArray - generated numeric array. Values are normally
            %   distributed about Baseline with standard deviation
            %   Variance, but clamped to within MaxStdDeviations (5)
            %   standard deviations of Baseline, so the output is
            %   strictly bounded however many values are generated.
            arguments
                ~;
                numRows (1,1) {mustBeInteger};
                numCols (1,1) {mustBeInteger} = 1;
                Settings.Baseline (:,1) double = nan; %Default = nan - (nx1) double, make n be the number of rows/cols. Random baseline value will be generated for each column/row if not set. Set a value to have all rows/columns scatter around this mean value if a single value is given, set for each row/col if an array is passed in.
                Settings.Transpose (1,1) logical = false; % By default, columns are created with random but cohesive numbers. Tranpose=true switches to having rows be the simulated 'data column' instead
                Settings.Variance (:,1) double = nan; %Default = nan - (nx1) double, make n be the number of rows/cols. Random variance value will be generated for each column/row if not set. Set a value to have all rows/columns scatter by this set value instead if a single value is given, set for each row/col if an array is passed in.
            end

            %Pre-initialise array
            datArray = nan(numRows, numCols);

            %Outliers beyond this many standard deviations are clamped, so
            %extremely rare large randn draws can't give wild values
            MaxStdDeviations = 5;

            %Choose whether to fill row-wise or column-wise
            if Settings.Transpose
                for i = 1 : numRows
                    seed = rand*100;
                    exp = round(rand*10 - 6);

                    if isnan(Settings.Baseline)
                        baseline = seed*10^exp;
                    elseif isscalar(Settings.Baseline)
                        baseline = Settings.Baseline;
                    else
                        assert(length(Settings.Baseline) == numRows, "GenerateSimulatedDataError:BaselineLengthMismatch", "Baseline must match number of rows (GenerateSimulatedData)");
                        baseline = Settings.Baseline(i);
                    end

                    if isnan(Settings.Variance)
                        var = rand*5*10^exp;
                    elseif isscalar(Settings.Variance)
                        var = Settings.Variance;
                    else
                        assert(length(Settings.Variance) == numRows, "GenerateSimulatedDataError:VarianceLengthMismatch", "Variance must match number of rows (GenerateSimulatedData)");
                        var = Settings.Variance(i);
                    end

                    deviations = max(min(randn(1, numCols), MaxStdDeviations), -MaxStdDeviations);
                    datArray(i, :) = deviations * var + baseline;
                end
            else
                for i = 1 : numCols
                    seed = rand*100;
                    exp = round(rand*10 - 6);

                    if isnan(Settings.Baseline)
                        baseline = seed*10^exp;
                    elseif isscalar(Settings.Baseline)

                        baseline = Settings.Baseline;
                    else
                        assert(length(Settings.Baseline) == numCols, "GenerateSimulatedDataError:BaselineLengthMismatch", "Baseline must match number of columns (GenerateSimulatedData)");
                        baseline = Settings.Baseline(i);
                    end

                    if isnan(Settings.Variance)
                        var = rand*5*10^exp;
                    elseif isscalar(Settings.Variance)
                        var = Settings.Variance;
                    else
                        assert(length(Settings.Variance) == numCols, "GenerateSimulatedDataError:VarianceLengthMismatch", "Variance must match number of columns (GenerateSimulatedData)");
                        var = Settings.Variance(i);
                    end

                    deviations = max(min(randn(numRows, 1), MaxStdDeviations), -MaxStdDeviations);
                    datArray(:, i) = deviations * var + baseline;
                end
            end


        end

        function controlDetailsStruct = GetControlOption(this, controlName)
            arguments
                this;
                controlName {mustBeTextScalar}
            end

            controlDetailsStructs = this.GetAvailableControlOptions();

            listOfPotentialNames = "";

            for i = 1 : length(controlDetailsStructs)
                listOfPotentialNames = listOfPotentialNames + string(controlDetailsStructs(i).Name);

                if i < length(controlDetailsStructs)
                    listOfPotentialNames = listOfPotentialNames + ", ";
                end

                if strcmp(controlName, controlDetailsStructs(i).Name)
                    controlDetailsStruct = controlDetailsStructs(i);
                    return;
                end
            end

            error("GetControlOptionError:NotFound", "%s", "Could not find Control Detail Struct with name " + string(controlName) + ". Supported options: " + listOfPotentialNames);
        end

        function names = GetRegisteredControlNames(this)
            names = [];

            for i = 1 : length(this.ControlClasses)
                names = [names, string(this.ControlClasses(i).GetName())]; %#ok<AGROW>
            end
        end

        function [objsList, controlDetailsStructsList] = GetRegisteredControlObjects(this)
            objsList = [];
            controlDetailsStructsList = [];

            %Scan through all the Registered InstrumentControl classes and
            %return all
            for i = 1 : length(this.ControlClasses)
                objsList = [objsList this.ControlClasses(i)]; %#ok<AGROW>
                strct = this.ControlClasses(i).ControlDetailsStruct;
                controlDetailsStructsList = [controlDetailsStructsList strct]; %#ok<AGROW>
            end
        end

        function objsList = GetRegisteredControlObjectsFromName(this, name)
            objsList = [];

            %Scan through all the Registered InstrumentControl classes and
            %return all the ones with Name matching the input name
            for i = 1 : length(this.ControlClasses)
                if(strcmp(name, this.ControlClasses(i).GetName()))
                    objsList = [objsList this.ControlClasses(i)]; %#ok<AGROW>
                end
            end
        end

        function connectionTypes = GetSupportedConnectionTypes(this)
            connectionTypes = this.AllowedConnectionTypes;
        end

        function [success, msg] = Initialise(this)
            try
                this.Connect();
            catch err

                success = false;
                msg = "Could not connect to Instrument:" + newline + this.FullName + " - " + this.Name + newline + "Connection type " + string(this.Connection_Type) + newline + newline + "Error message: " + err.message;
                return;
            end

            success = true;
            msg = "";

            this.OnInitialised();
        end

        function str = PrintIdentifier(this)
            %PRINTIDENTIFIER - just prints some information about this
            %instrument to the command window (and returns it as a string). Basically for
            %debugging/verification purposes
            str = "Palladium Instrument " + this.FullName;
            disp(str);
        end

        function val = QueryDouble(this, command)
            arguments
                this;
                command (1,1) string;
            end

            if(this.SimulationMode)
                val = rand() + 100;
            else
                %Quickly check to make sure we are (in theory at least)
                %connected before sending command - warn if not
                assert(~isempty(this.DeviceHandle), "QueryDoubleError:NotConnected", "%s", "Device Handle is empty - device is not connected yet when sending Query command (" + this.FullName + ")");

                %Send query
                val = str2double(query(this.DeviceHandle, command));
            end
        end

        function val = QueryString(this, command)
            arguments
                this;
                command (1,1) string;
            end

            if(this.SimulationMode)
                val = 'null';
            else
                %Quickly check to make sure we are (in theory at least)
                %connected before sending command - warn if not
                assert(~isempty(this.DeviceHandle), "QueryStringError:NotConnected", "%s", "Device Handle is empty - device is not connected yet when sending Query command (" + this.FullName + ")");

                %Send query
                val = query(this.DeviceHandle, command);

                %Strip any leading or trailing whitespace or newlines
                val = strip(val);
            end
        end

        function data = ReadString(this)
            if(this.SimulationMode)
                data = 'null';
            else
                %Quickly check to make sure we are (in theory at least)
                %connected before sending command - warn if not
                assert(~isempty(this.DeviceHandle), "ReadStringError:NotConnected", "%s", "Device Handle is empty - device is not connected yet when reading from the instrument (" + this.FullName + ")");

                data= fscanf(this.DeviceHandle);
            end
        end

        function SetNewSweepStepValue(this, value) %#ok<INUSD>
            warning("SetNewSweepStepValueWarning:NotOverridden", "An override method for SetNewSweepStepValue has not been defined for this Instrument. A SweepController_Stepped is probably trying to tell this Instrument to go to the next step in its sweep but the Instrument doesn't have a function written to tell it how. Look at the Keithley2000 class for an example");
        end

        function SetRampingToTarget(this, target, rate, settings) %#ok<INUSD>
            %Override in base classes to support SweepController_Ramp
            %functionality
        end

        function SettingsInput(this, settings)
            %This is triggered by e.g. the event raised by a
            %LakeshoreTempControl component. Unpack the data and pass it on
            %to be acted on in the next update loop
            if isempty(this.SettingsToApply)    %Just to avoid any crazy async double setting of overriding halfway through giving command stuff
                this.SettingsToApply = settings;
            end
        end

        function value = ShowProperty(this, propertyName)
            %Returns true/false to determine whether a property should be
            %shown in the Instrument Options panel - primarily, if we are
            %in GPIB connection mode, don't show the Serial Address, etc

            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address", "VISA_Address"};
                case(Palladium.Enums.ConnectionType.Ethernet)
                    propertiesToIgnore = {"GPIB_Address", "Serial_Address", "VISA_Address"};
                case(Palladium.Enums.ConnectionType.GPIB)
                    propertiesToIgnore = {"IP_Address", "Serial_Address", "VISA_Address"};
                case(Palladium.Enums.ConnectionType.VISA)
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address"};
                case(Palladium.Enums.ConnectionType.Serial)
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "VISA_Address"};
                case(Palladium.Enums.ConnectionType.USB)
                    %USB connects through VISA (see ConnectUSB), so it uses
                    %the VISA address
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address"};
                otherwise
                    error("ShowPropertyError:UnsupportedConnectionType", "%s", "Unsupported connection type: " + this.Connection_Type + ". ConnectionType can be tcpip, gpib, serial, usb, or visa.");
            end

            for i = 1 : length(propertiesToIgnore)
                if(strcmp(propertiesToIgnore{i}, propertyName))
                    value = false;
                    return;
                end
            end

            %Allow ignoring additional properties specified by an
            %Instrument by overriding this call:
            propertiesToIgnore = this.GetPropertiesToIgnore();
            for i = 1 : length(propertiesToIgnore)
                if(strcmp(propertiesToIgnore{i}, propertyName))
                    value = false;
                    return;
                end
            end

            value = true;
        end

        function WriteCommand(this, command)
            arguments
                this;
                command (1,1) string;
            end

            if(this.SimulationMode); return; end
            %Quickly check to make sure we are (in theory at least)
            %connected before sending command - warn if not
            assert(~isempty(this.DeviceHandle), "WriteCommandError:NotConnected", "%s", "Device Handle is empty - device is not connected yet when sending a command (" + this.FullName + ")");

            %Send command
            fprintf(this.DeviceHandle, command);
        end

    end

    %% Methods (Public, Sealed)
    methods (Access = public, Sealed)

        function DefineSupportedConnectionTypes(this, connectionTypes)
            arguments
                this
                connectionTypes (:,1) Palladium.Enums.ConnectionType;
            end

            this.AllowedConnectionTypes = connectionTypes;
        end

        function [controlDetailsStructs] = GetAvailableControlOptions(this)
            controlDetailsStructs = this.ControlDetailsStructs;
        end

        function stringLine = GrabMetadataString(this)
            %This function calls the CollectMetadata function, which should
            %be defined/overwritten in any Instrument that wants
            %metadata/settings to be recorded in the data file header.
            %Controller.InitialiseMeasurements is going to call this
            %automatically.

            %Get the metadata, which is either empty or a struct
            result = this.CollectMetaData();

            %Return empty if this is empty (default)
            if isempty(result)
                stringLine = [];
                return;
            end

            %Error checking
            assert(isstruct(result), "GrabMetadataStringError:MetadataNotStruct", "%s", "Return value of CollectMetadata is not Struct on Instrument " + this.Name);

            %Otherwise turn the struct into a human readable one-line
            %string...
            preInfStr = this.Name + " Settings: ";
            stringLine = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct(preInfStr, result);
        end

        function RegisterControlObject(this, classRef)
            name = classRef.GetName();

            %Check we didn't already register a control of this name to
            %avoid duplication
            if ~isempty(this.GetRegisteredControlObjectsFromName(name))
                error("RegisterControlObjectError:DuplicateName", "%s", "A Control object of name " + name + " has already been added to Instrument " + this.Name);
            end

            %Add to the list of tracked things
            if isempty(this.ControlClasses)
                this.ControlClasses = classRef;
            else
                this.ControlClasses = [this.ControlClasses, classRef];
            end
        end

        function RemoveControlObject(this, className)
            for i = length(this.ControlClasses) : -1 : 1
                if(strcmp(className, this.ControlClasses(i).GetName()))
                    this.ControlClasses(i) = [];
                end
            end
        end

        function dataRow = UpdateAndMeasure(this, headers)
            %UpdateAndMeasure is the entry point to Measure commands from
            %the InstrumentController Loop. It will call Update methods on
            %all InstrumentControls and then do the Measure call

            %First Update any added Controls
            this.UpdateControls();

            %Pass through and do the actual measure command
            dataRow = this.Measure();

            %And then UpdateData any added Controls, handing them that
            %last-acquired dataRow
            this.UpdateControlsData(dataRow, headers);
        end

    end

    %% Methods (Protected)
    methods(Access = protected)

        function ApplySettings(this, settings) %#ok<INUSD>
            %Does nothing by default - implementations can override this to
            %give functionality
        end

        function ConnectGPIB(this)
            this.DeviceHandle = visadev("GPIB::" + num2str(this.GPIB_Address) + "::" + num2str(this.ConnectionSettings.GPIB_BoardIndex) + "::INSTR");
            configureTerminator(this.DeviceHandle, this.ConnectionSettings.GPIB_Terminators(1), this.ConnectionSettings.GPIB_Terminators(2));
            this.DeviceHandle.Timeout = this.ConnectionSettings.GPIB_Timeout;%In seconds
        end

        function ConnectSerial(this)
            %Connect to instrument via serial/COM interface
            this.DeviceHandle = serialport(this.Serial_Address, this.ConnectionSettings.SerialSettings.BaudRate);

            %Configure serial settings
            this.DeviceHandle.DataBits = this.ConnectionSettings.SerialSettings.DataBits;
            this.DeviceHandle.Parity = this.ConnectionSettings.SerialSettings.Parity;
            this.DeviceHandle.StopBits = this.ConnectionSettings.SerialSettings.StopBits;
            configureTerminator(this.DeviceHandle, this.ConnectionSettings.SerialSettings.Terminator);
        end

        function ConnectTCPIP(this)
            %Connect to instrument via ethernet/tcpip

            %Note that 2022 Matlab has changed the syntax for these -
            %removing fopen and fclose in particular:
            %https://uk.mathworks.com/help/instrument/transition-your-code-to-tcpclient-interface.html

            %Check for existing connection -  Find a tcpip object at this address and port.
            existingHandle = tcpclientfind("Address", char(this.IP_Address), 'RemotePort', this.ConnectionSettings.Port); %This requires Matlab 2024a

            if(~isempty(existingHandle))    %If we already are connected, don't try to connect again - will error
                this.DeviceHandle = existingHandle;
                disp("Existing connection to " + this.Name + " found, using that");
            else                            %Make a new connection
                %Connect to the device
                this.DeviceHandle = tcpclient(char(this.IP_Address), this.ConnectionSettings.Port);
                this.DeviceHandle.ByteOrder = "big-endian";
            end
        end

        function ConnectUSB(this)
            this.ConnectVISA();
        end

        function ConnectVISA(this)
            %Connect to instrument via VISA interface

            %Note that 2022 Matlab has changed the syntax for these -
            %removing fopen and fclose in particular:
            %https://uk.mathworks.com/help/instrument/transition-your-code-to-visadev-interface.html

            %Check for existing connection -  Find a tcpip object at this address and port.
            existingHandle = visadevfind(Name=this.VISA_Address);   %This requires Matlab 2024a
            if(~isempty(existingHandle))    %If we already are connected, don't try to connect again - will error
                this.DeviceHandle = existingHandle;
                disp("Existing connection to " + this.Name + " found, using that");
            else
                this.DeviceHandle = visadev(this.VISA_Address);
            end
        end

        function catOut = ConvertToCategorical(~, inputStr, catNamesStrArray)
            %Convert an input string into a categorical with categories set
            %by catNameStrArray. This function mainly handles the
            %boilerplate of argument validation and error checking, to keep
            %implementation classes simpler
            arguments
                ~;
                inputStr (1,1) string;
                catNamesStrArray (1,:) string;
            end

            %Convert the string to a categorical (which is basically an
            %enum)
            catOut = categorical(inputStr, catNamesStrArray);

            %Check that the conversion was successful - ie that the input
            %could be found in the catNames
            if isundefined(catOut)
                catNam = "";
                for i = 1 : length(catNamesStrArray)
                    catNam = catNam + catNamesStrArray(i) + " ";
                end
                error("ConvertToCategoricalError:ValueNotInCategories", "%s", "Error in converting string to categorical in Instrument. Given value: " + inputStr + " was not found in the input category names: " + catNam);
            end
        end

        function DefineInstrumentControl(this, Settings)
            %Normally call this in the Constructor of an Instrument
            %implementation - specify a Control class, like a
            %SweepController or the Control Panel GUI for a magnet power
            %supply, that will then appear as an option to be added to this
            %Instrument
            arguments
                this;
                Settings.Name               {mustBeTextScalar}
                Settings.ClassName          {mustBeTextScalar}
                Settings.TabName            {mustBeTextScalar}
                Settings.EnabledByDefault   (1,1) logical = false;
                Settings.UserData = []; %Spare field to use for specific Control data flexibly
            end

            s = struct(...
                "Name", Settings.Name,...
                "ControlClassFileName", Settings.ClassName,...
                "TabName", Settings.TabName,...
                "EnabledByDefault", Settings.EnabledByDefault,...
                "UserData", Settings.UserData);

            this.ControlDetailsStructs = [this.ControlDetailsStructs, s];
        end

        function propertiesToIgnore = GetPropertiesToIgnore(this)
            propertiesToIgnore = {};
        end

        function OnInitialised(this)
            %No default functionality - override in Implementation classes
        end


        function val = RetrieveSimulatedDataValue(this, propName, defaultValue)
            arguments
                this;
                propName {mustBeTextScalar};
                defaultValue = 0;
            end
            %Handle retrieving a previously stored SimulatedData struct
            %field, like SimulatedData.SourceLevel, but dealing with edge
            %cases like it not being set yet, SimulatedData being empty,
            %etc

            if isempty(this.SimulatedData)
                this.SimulatedData.(propName) = defaultValue;
                val = defaultValue;
                return;
            end

            if ~isfield(this.SimulatedData, propName)
                this.SimulatedData.(propName) = defaultValue;
                val = defaultValue;
                return;
            end

            %We made it past all the error handling! Now we can just
            %extract the field, knowing it's there
            val = this.SimulatedData.(propName);
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function HandlePropEvents(this, ~, evnt)
            %Gets called internally (by Matlab) on properties marked as
            %'properties (SetObservable)' - pass on events to tell GUIs we have
            %changed properties and that they should update
            %evnt contains the following info:
            %  PropertyEvent with properties:
            %AffectedObject: [1×1 Palladium.Instruments.Keithley2000]
            %  Source: [1×1 meta.property]
            %EventName: 'PostSet'

            %Trigger event
            notify(this, "PropertyChanged", evnt);
        end

        function RegisterPropertyChangedEvents(this)
            mc = metaclass(this);
            metaprops = [mc(:).Properties];
            for i = length(metaprops): -1 : 1
                prop = metaprops(i);
                if(prop{1}.SetObservable)
                    %Add event listener to these properties changing
                    addlistener(this, prop{1}.Name, 'PostSet', @this.HandlePropEvents);
                end
            end
        end

        function UpdateControls(this)
            for i = 1 : length(this.ControlClasses)
                this.ControlClasses(i).Update();
            end
        end

        function UpdateControlsData(this, dataRow, headers)
            for i = 1 : length(this.ControlClasses)
                this.ControlClasses(i).UpdateData(dataRow, headers);
            end
        end

    end
end

