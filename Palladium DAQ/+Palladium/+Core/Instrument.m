classdef(Abstract) Instrument < handle
    %Instrument - Abstract base class all instrument implementations must
    %inherit from.

    properties(Abstract, Constant)
        FullName;   %Will be displayed on eg instrument settings tab
    end

    properties(Abstract)
        Name;
        Connection_Type;   %Type of connection to use to communicate with the instrument. Value will be a member of the ConnectionType Enum
    end

    properties(Access = public, SetObservable)
        GPIB_Address    (1,1) {mustBeInteger, mustBeBetween(GPIB_Address, 0, 30)} = 0;
        IP_Address      {mustBeTextScalar}  = '192.0.0.0.0';
        Serial_Address  {mustBeTextScalar} = 'COM12';
        VISA_Address    {mustBeTextScalar} = "VISA_ADDRESS";
    end

    properties(Access = public) %Properties that will not get detected by the GUI and have buttons added for them
        LastFullDataRow = [];           %Each tick, the Controller will store the complete DataRow in each Instrument here. This is used when Instruments write their own data files, for things like independent sweeps
        FullHeadersRow = [];            %On measurements start, this will get cached with the full array of headers for the whole setup - again, for instrument-driven data writing.
        FileWriteDetails = [];
    end

    properties(Access = protected)
        SimulationMode = false;         %Set to true if testing code while not actually connected to a physical instrument - dummy data will be generated. Set via constructor of instance classes only.
        DeviceHandle = [];              %Reference to the instrument connection/session, set when calling Connect()     
        SettingsToApply = [];           %Either null, or a struct of all the settings to apply in the next Measure command (keep these calls synchronous, they come originally from events)
        SimulatedData = [];             %Empty placeholder where an Instrument can define struct properties like SimulatedData.SourceLevel for testing things like SweepControl

        %Default Connection Settings - override individual settings in implementation class
        %constructors
        ConnectionSettings = struct('GPIB_BoardIndex', 0,...
            'Port', 5025,...
            'GPIB_Terminators', ["CR/LF", "CR/LF"],...
            'SerialSettings', struct('BaudRate', 9600, 'DataBits', 8, 'Parity', 'none', 'StopBits', 2, 'Terminator', 'LF')...
            );
    end

    properties(Access = private)
        AllowedConnectionTypes = [...
                CoakView.Enums.ConnectionType.Debug,...
                CoakView.Enums.ConnectionType.GPIB,...
                CoakView.Enums.ConnectionType.VISA,...
                CoakView.Enums.ConnectionType.Ethernet,...
                CoakView.Enums.ConnectionType.Serial,...
                CoakView.Enums.ConnectionType.USB...
                ];
        ControlClasses = [];
        ControlDetailsStructs = []; % List of structs that define the options for later creating Control Classes
    end   
    
    % Events with associated public callbacks
    events (NotifyAccess = private)
        PropertyChanged;
    end

    methods(Abstract)
        [Headers, Units] = GetHeaders(this);
        [dataRow] = Measure(this);
    end 

    methods(Access = public)

        %% Constructor
        function this = Instrument()
            %Register events that will auto-fire when we modify
            %SetObservable events on this instance ("PropertyChanged")
            this.RegisterPropertyChangedEvents();
        end

        %% CheckForSettingsToApply
        function CheckForSettingsToApply(this)
            %Apply heater control settings, if Set has been pressed on a
            %ControlPanel somewhere
            if ~isempty(this.SettingsToApply)
                this.ApplySettings(this.SettingsToApply);
                this.SettingsToApply = [];
            end
        end

        %% Close
        function Close(this)
            %This (so far) looks to be common behaviour across all instruments.
            %Can override this function in implementing class if more behaviour needed.
            switch(this.Connection_Type)
                case(CoakView.Enums.ConnectionType.Debug)
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
                        CoakView.Utilities.ErrorHandler.HandleError("Error disconnecting from " + this.Name, e);
                    end
            end
        end

        %% CollectMetadata
        function metadataStruct = CollectMetaData(this)
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

        %% Connect
        function Connect(this)
            switch(this.Connection_Type)
                case(CoakView.Enums.ConnectionType.Debug)
                    %Do not make a physical connection to a real instrument
                    %- this places the class into SimulationMode, for
                    %testing without a real piece of hardware connected
                    disp("Connected to simulated " + this.Name + " instrument.");
                    this.SimulationMode = true;
                case(CoakView.Enums.ConnectionType.Ethernet)
                    this.ConnectTCPIP();
                case(CoakView.Enums.ConnectionType.GPIB)
                    this.ConnectGPIB();
                case(CoakView.Enums.ConnectionType.VISA)
                    this.ConnectVISA();
                case(CoakView.Enums.ConnectionType.USB)
                    this.ConnectUSB();
                case(CoakView.Enums.ConnectionType.Serial)
                    this.ConnectSerial();
                otherwise
                    error("Unsupported connection type: " + this.Connection_Type + ". ConnectionType can be tcpip, gpib, serial, usb, or visa.");
            end
        end
      
        %% GetControlOption
        function controlDetailsStruct = GetControlOption(this, controlName)
            arguments
                this;
                controlName {mustBeTextScalar}
            end

            controlDetailsStructs = this.GetAvailableControlOptions();

            controlDetailsStruct = [];
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

            error("Could not find Control Detail Struct with name " + string(controlName) + ". Supported options: " + listOfPotentialNames);
        end

        %% GetRegisteredControlObjects
        function [objsList, controlDetailsStructsList] = GetRegisteredControlObjects(this)
            objsList = [];
            controlDetailsStructsList = [];

            %Scan through all the Registered InstrumentControl classes and
            %return all the ones with Name matching the input name
            for i = 1 : length(this.ControlClasses)
                objsList = [objsList this.ControlClasses(i)];
                strct = this.ControlClasses(i).ControlDetailsStruct;
                controlDetailsStructsList = [controlDetailsStructsList strct];
            end
        end
            
        %% GetRegisteredControlObjectsFromName
        function objsList = GetRegisteredControlObjectsFromName(this, name)
            objsList = [];

            %Scan through all the Registered InstrumentControl classes and
            %return all the ones with Name matching the input name
            for i = 1 : length(this.ControlClasses)
                if(strcmp(name, this.ControlClasses(i).GetName()))
                    objsList = [objsList this.ControlClasses(i)];
                end
            end
        end
      
        %% GetSupportedConnectionTypes
        function connectionTypes = GetSupportedConnectionTypes(this)
            connectionTypes = this.AllowedConnectionTypes;
        end  

        %% DefineSupportedConnectionTypes
        function DefineSupportedConnectionTypes(this, connectionTypes)
            arguments
                this
                connectionTypes (:,1) CoakView.Enums.ConnectionType;
            end
            
            this.AllowedConnectionTypes = connectionTypes;
        end

        %% Initialise
        function [success, msg] = Initialise(this)
            try
                this.Connect();
            catch err
                
                success = false;
                msg = "Could not connect to Instrument:\n" + this.FullName + " - " + this.Name + "\n" + "Connection type " + string(this.Connection_Type) + "\n\nError message: " + err.message;
                return;
            end

            success = true;
            msg = "";

            this.OnInitialised();
        end

        %% RegisterControlObject
        function RegisterControlObject(this, classRef)
            name = classRef.GetName();

            %Check we didn't already register a control of this name to
            %avoid duplication
            if ~isempty(this.GetRegisteredControlObjectsFromName(name))
                error("A Control object of name " + name + " has already been added to Instrument " + this.Name);
            end

            %Add to the list of tracked things
            if isempty(this.ControlClasses)
                this.ControlClasses = classRef;
            else
                this.ControlClasses = [this.ControlClasses, classRef];
            end
        end

        %% RemoveControlObject
        function RemoveControlObject(this, className)
            for i = length(this.ControlClasses) : -1 : 1
                if(strcmp(className, this.ControlClasses(i).GetName()))
                    this.ControlClasses(i) = [];
                end
            end
        end

        %% SetNewSweepStepValue
        function SetNewSweepStepValue(this, value) %#ok<INUSD>
            warning("An override method for SetNewSweepStepValue has not been defined for this Instrument. A SweepController_Stepped is probably trying to tell this Instrument to go to the next step in its sweep but the Instrument doesn't have a function written to tell it how. Look at the Keithley2000 class for an example");
        end

        %% SettingsInput
        function SettingsInput(this, settings)
            %This is triggered by e.g. the event raised by a
            %LakeshoreTempControl component. Unpack the data and pass it on
            %to be acted on in the next update loop
            if isempty(this.SettingsToApply)    %Just to avoid any crazy async double setting of overriding halfway through giving command stuff
                this.SettingsToApply = settings;
            end
        end

        %% ShowProperty
        function value = ShowProperty(this, propertyName)
            %Returns true/false to determine whether a property should be
            %shown in the Instrument Options panel - primarily, if we are
            %in GPIB connection mode, don't show the Serial Address, etc

            switch(this.Connection_Type)
                case(CoakView.Enums.ConnectionType.Debug)
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address", "VISA_Address"};
                case(CoakView.Enums.ConnectionType.Ethernet)
                    propertiesToIgnore = {"GPIB_Address", "Serial_Address", "VISA_Address"};
                case(CoakView.Enums.ConnectionType.GPIB)
                    propertiesToIgnore = {"IP_Address", "Serial_Address", "VISA_Address"};
                case(CoakView.Enums.ConnectionType.VISA)
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address"};
                case(CoakView.Enums.ConnectionType.Serial)
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "VISA_Address"};
                case(CoakView.Enums.ConnectionType.USB)
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address", "VISA_Address"};
                otherwise
                    error("Unsupported connection type: " + this.ConnectionType + ". ConnectionType can be tcpip, gpib, serial, or visa.");
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

        %% AbortRamp
        function AbortRamp(this)
            %Override in base classes to support SweepController_Ramp
            %functionality
        end

        %% SetRampingToTarget
        function SetRampingToTarget(this, target, rate, settings)
            %Override in base classes to support SweepController_Ramp
            %functionality
        end
        
    end

    methods (Access = public, Sealed)
    
        %% GetAvailableControlOptions
        function [controlDetailsStructs] = GetAvailableControlOptions(this)
            controlDetailsStructs = this.ControlDetailsStructs;
        end

        %% GrabMetadataString
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
            assert(isstruct(result), "Return value of CollectMetadata is not Struct on Instrument " + this.Name);

            %Otherwise turn the struct into a human readable one-line
            %string...
            preInfStr = this.Name + " Settings: ";
            stringLine = CoakView.DataWriting.DataWriter.BuildMetadataLineStringFromStruct(preInfStr, result);
        end
        
        %% UpdateAndMeasure
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

    methods(Access = protected)

        %% ApplySettings
        function ApplySettings(this, settings)
            %Does nothing by default - implementations can override this to
            %give functionality
        end

        %% ConnectGPIB
        function ConnectGPIB(this)
            this.DeviceHandle = visadev("GPIB::" + num2str(this.GPIB_Address) + "::" + num2str(this.ConnectionSettings.GPIB_BoardIndex) + "::INSTR");
            configureTerminator(this.DeviceHandle, this.ConnectionSettings.GPIB_Terminators(1), this.ConnectionSettings.GPIB_Terminators(2));
        end

        %% ConnectSerial
        function ConnectSerial(this)
            %Connect to instrument via serial/COM interface
            this.DeviceHandle = serialport(this.Serial_Address, this.ConnectionSettings.SerialSettings.BaudRate);

            %Configure serial settings
            this.DeviceHandle.DataBits = this.ConnectionSettings.SerialSettings.DataBits;
            this.DeviceHandle.Parity = this.ConnectionSettings.SerialSettings.Parity;
            this.DeviceHandle.StopBits = this.ConnectionSettings.SerialSettings.StopBits;
            configureTerminator(this.DeviceHandle, this.ConnectionSettings.SerialSettings.Terminator);
        end

        %% ConnectTCPIP
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

        %% ConnectUSB
        function ConnectUSB(this)
            this.ConnectVISA();
        end

        %% ConnectVISA
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

        %% ConvertToCategorical
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
                error("Error in converting string to categorical in Instrument. Given value: " + inputStr + " was not found in the input category names: " + catNam);
            end
        end

        %% DefineInstrumentControl
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

        %% GetPropertiesToIgnore
        function propertiesToIgnore = GetPropertiesToIgnore(this)
            propertiesToIgnore = {};
        end

        %% OnInitialised
        function OnInitialised(this)
            %No default functionality - override in Implementation classes
        end

        %% ReadString
        function data = ReadString(this)
            if(this.SimulationMode)
                data = 'null';
            else
                %Quickly check to make sure we are (in theory at least)
                %connected before sending command - warn if not
                assert(~isempty(this.DeviceHandle), "Device Handle is empty - device is not connected yet when sending Query command (" + this.FullName + ")");

                data= fscanf(this.DeviceHandle);
            end
        end

        %% RetrieveSimulatedDataValue
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

        %% QueryDouble
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
                assert(~isempty(this.DeviceHandle), "Device Handle is empty - device is not connected yet when sending Query command (" + this.FullName + ")");

                %Send query
                val = str2double(query(this.DeviceHandle, command));
            end
        end

        %% QueryString
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
                assert(~isempty(this.DeviceHandle), "Device Handle is empty - device is not connected yet when sending Query command (" + this.FullName + ")");

                %Send query
                val = query(this.DeviceHandle, command);
            end
        end

        %% WriteCommand
        function WriteCommand(this, command)
            arguments
                this;
                command (1,1) string;
            end

            if(this.SimulationMode); return; end
            %Quickly check to make sure we are (in theory at least)
            %connected before sending command - warn if not
            assert(~isempty(this.DeviceHandle), "Device Handle is empty - device is not connected yet when sending Query command (" + this.FullName + ")");

            %Send command
            fprintf(this.DeviceHandle, command);
        end


    end

    methods (Access = private) 

        %% HandlePropEvents
        function HandlePropEvents(this, ~, evnt)
            %Gets called internally (by Matlab) on properties marked as
            %'properties (SetObservable)' - pass on events to tell GUIs we have
            %changed properties and that they should update
            %evnt contains the following info:
            %  PropertyEvent with properties:
            %AffectedObject: [1×1 CoakView.Instruments.Keithley2000]
            %  Source: [1×1 meta.property]
            %EventName: 'PostSet'

            %Trigger event
            notify(this, "PropertyChanged", evnt);
        end

        %% RegisterPropertyChangedEvents
        function RegisterPropertyChangedEvents(this)
            mc = metaclass(this);
            metaprops = [mc(:).Properties];
            prop = [];
            for i = length(metaprops): -1 : 1
                prop = metaprops(i);
                if(prop{1}.SetObservable)
                    %Add event listener to these properties changing
                    addlistener(this, prop{1}.Name, 'PostSet', @this.HandlePropEvents);
                end
            end
        end

        %% UpdateControls
        function UpdateControls(this)
            for i = 1 : length(this.ControlClasses)
                this.ControlClasses(i).Update();
            end
        end

        %% UpdateControlsData
        function UpdateControlsData(this, dataRow, headers)
            for i = 1 : length(this.ControlClasses)
                this.ControlClasses(i).UpdateData(dataRow, headers);
            end
        end

        
    end
end

