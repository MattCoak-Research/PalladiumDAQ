classdef InstrumentController < handle
    %INSTRUMENTCONTROLLER - logic/container/manager class for handling
    %instrument creation and management in CoakView, and liaising with
    %Instrument selection GUIs in the View
    
    properties
        ErrorOnAllInstrumentErrors = false; %Note - gets set in LoadSettings from the Config.json file's value, overriding a value here. If this is set to true, a full error will be thrown every time an instruments fails to return data. Default (false) is to throw warnings and pad datafile with NaNs instead. Testing has shown that very rare communication errors do happen, and it's a shame to lose the whole experiment because a magnet not being used didn't return 0 properly..
    end

    properties (GetAccess = public, SetAccess = private)
        ListOfAvailableInstrumentClassNameStrings;
        SelectedInstrumentNames;
        SelectedInstruments;
        Instruments;
    end

    
    properties (Access = private)
        Controller; %Reference back to the overall CoakView Controller that handles all the main logic - feed things back to there
        View;   %FrontEnd or GUI that this will plug into to display changes and trigger functions in here
    end

    properties (Access = private, Constant)
        Namespace string = "CoakView.Instruments";
        ControlsNamespace string = "CoakView.Instruments.Controls";
    end
    
    methods

        %% Constructor
        function this = InstrumentController(controller, view)
            this.Controller = controller;
            this.View = view;
        end

        %% AddEnabledByDefaultInstrumentControls
        function AddEnabledByDefaultInstrumentControls(this, instr)
            cdsList = instr.GetAvailableControlOptions();

            if isempty(cdsList)
                return;
            end

            for i=1 : length(cdsList)
                cds = cdsList(i);

                if cds.EnabledByDefault
                    this.Controller.AddInstrumentControl(instr, cds);
                end
            end
        end     
        
        %% AddInstrument
        function instRef = AddInstrument(this, instrStringToAdd)
            %Add an instrument just from a string of the name of its class

            %Check for error cases like empty list box selection
            if(isempty(instrStringToAdd))
                instRef = [];
                return;
            end

            %Make sure the instrName is valid, and other error checking
            assert(isstring(instrStringToAdd), "Instrument name must be a string");
            assert(~isempty(this.ListOfAvailableInstrumentClassNameStrings), "List of loaded instrument classes to select from is empty - file paths messed up?");
            assert(any(contains(this.ListOfAvailableInstrumentClassNameStrings, instrStringToAdd, "IgnoreCase", false)), string(instrStringToAdd) + " not found in list of avaliable Instruments");
          

            %Make an instance of the selected datasource class
            instRef = CoakView.Utilities.FileLoading.PluginLoading.InstantiateClass(this.Namespace, instrStringToAdd);
            
            %Give the newly created instrument a number at the end of its
            %name ie Lakeshore350_1
            instRef.Name = CoakView.Utilities.FileLoading.PluginLoading.GetIncrementedInstrName(instRef, this.SelectedInstruments);
            
            %Add the new instrument, and the name of its class, to the
            %lists of each held in this class (will also be done in the
            %View, which hopefully will match!)
            if(isempty(this.SelectedInstrumentNames))
                this.SelectedInstrumentNames = instrStringToAdd;
                this.SelectedInstruments = {instRef};                
            else
                this.SelectedInstrumentNames = [this.SelectedInstrumentNames, instrStringToAdd];
                this.SelectedInstruments = [this.SelectedInstruments, {instRef}];
            end
            
            %Update the View
            this.View.OnInstrumentAdded(instrStringToAdd, instRef);
        end    

        %% AddInstrumentControl
        function controlClassRef = AddInstrumentControl(this, controller, tab, instrRef, controlDetailsStruct)
            
            %Make an instance of the selected datasource class
            controlClassRef = CoakView.Utilities.FileLoading.PluginLoading.InstantiateClass(this.ControlsNamespace, controlDetailsStruct.ControlClassFileName);      
            controlClassRef.ControlDetailsStruct = controlDetailsStruct;

            %Tell the control class to create the required GUI etc
            controlClassRef.CreateInstrumentControlGUI(controller, tab, instrRef);

            %Register the control class with the instrument
            instrRef.RegisterControlObject(controlClassRef);
        end

        %% CloseAll
        function CloseAll(this)

            %Display a status message in the logger
            this.Controller.Log("Info", "Closing Instruments", "Yellow", "Closing Instruments");

            %Close all instruments
            for i = 1 : length(this.Instruments)
                this.Instruments{i}.Close();
            end

            %Display a status message in the logger
            this.Controller.Log("Info", "Instruments closed", "Green", "Instruments closed");
        end

        %% CollectMeasurement
        function DataRow = CollectMeasurement(this)
            %Get current time in universal coordinated time (seconds since 1970) then divide by 60 to get minutes
            Time = posixtime(datetime('now')) /60;

            %Start the DataRow with the Time column, always
            DataRow = Time;

            %Scan through all instruments and get their data
            for i = 1 : length(this.Instruments)
                try
                    %Check if any GUIs/controls have sent Settings to apply
                    %to the instrument
                    this.Instruments{i}.CheckForSettingsToApply();

                    %Measure
                    DataRow = [DataRow this.Instruments{i}.Measure()];
                catch e
                    %Pop in a nan value, as we failed to grab the data from
                    %this instrument
                    %First need to know how many nans to insert.. match to
                    %Headers
                    hdrs = this.Instruments{i}.GetHeaders();
                    n = length(hdrs);
                    DataRow = [DataRow, nan(1, n)];

                    if this.ErrorOnAllInstrumentErrors
                        this.Controller.HaltMeasurementsOnInstrumentError(this.Instruments{i}, e);
                    else
                        %Just show a warning, do not halt execution
                        reportStr = string(e.message);
                        CoakView.Logging.Logger.Log("Warning", "Measurement call to instrument " + this.Instruments{i}.Name + " failed in CollectMeasurement, data set to NaN for this tick. Error message: " + reportStr);
                    end
                end
            end

            %Scan through all instruments and cache that full dataRow into
            %their LastDataRow property, which they can use if doing
            %independent data writing
            for i = 1 : length(this.Instruments)
                try
                    this.Instruments{i}.LastFullDataRow = DataRow;
                catch e
                    %Just show a warning, do not halt execution
                    reportStr = string(e.message);
                    CoakView.Logging.Logger.Log("Warning", "Last dataRow update call to instrument " + this.Instruments{i}.Name + " failed in CollectMeasurement. Error message: " + reportStr);

                end
            end
        end

        %% GetHeaders
        function [Headers, HeadersString, Units] = GetHeaders(this)
            %Put time in as first header
            Headers = {"Time (mins)"};
            Units = {"mins"};

            %Scan through all instruments and get their data column
            %headers.
            for i = 1 : length(this.Instruments)
                [instrHeaders, instrUnits] = this.Instruments{i}.GetHeaders();
                for j = 1 : length(instrHeaders)
                    Headers = [Headers, string(instrHeaders{j})];
                    Units = [Units, string(instrUnits{j})];
                end
            end

            %Make a simple string of all these headers, tab seperated
            HeadersString = '';
            for i= 1 : length(Headers)
                HeadersString = sprintf('%s%s\t', HeadersString, Headers{i});
            end

            %Scan through all instruments and cache that full headers row into
            %their FullHeadersRow property, which they can use if doing
            %independent data writing
            for i = 1 : length(this.Instruments)
                try
                    this.Instruments{i}.FullHeadersRow = Headers;
                    this.Instruments{i}.FileWriteDetails = this.Controller.FileWriteDetails;
                catch e
                    %Just show a warning, do not halt execution
                    reportStr = string(e.message);
                    CoakView.Logging.Logger.Log("Warning", "Last dataRow update call to instrument " + this.Instruments{i}.Name + " failed in CollectMeasurement. Error message: " + reportStr);

                end
            end
        end

        %% GetInstruments
        function instRefs = GetInstruments(this)            
            instRefs = this.SelectedInstruments;
        end

        %% GetMetadataLines
        function metadataLines = GetMetadataLines(this)
            metadataLines = [];
            for i = 1 : length(this.Instruments)
                metadataNullableString = this.Instruments{i}.GrabMetadataString();
                if ~isempty(metadataNullableString)
                    metadataLines = [metadataLines metadataNullableString];
                end
            end
        end

        %% InitialiseHeaders
        function [headers, headersString, units] = InitialiseHeaders(this)

            %Set the list of instruments from the selection panel's ItemData
            this.Instruments = this.GetInstruments();

            %Generate column headers, for internal use and file writing
            [headers, headersString, units] = this.GetHeaders();

            %Verify that those headers are valid - no duplicates
            [duplicateHeaderValues, duplicateHeaderValuesString] = CoakView.Utilities.ErrorChecking.Verification.CheckForDuplicatesInHeadersArray(headers);
            assert(isempty(duplicateHeaderValues), "Some variable names appear twice, this is not allowed. Duplicate variables: " + duplicateHeaderValuesString);

        end

        %% InitialiseInstruments
        function [success, msg, title] = InitialiseInstruments(this)
            %Set starting values. Note, function will immediately return if
            %there are no Instruments, returning these
            success = false;
            msg = "";
            title = "";

            %Initialise all instruments
            for i = 1 : length(this.Instruments)

                %Update the progress bar
                this.View.UpdateProgressBar((i) / (length(this.Instruments)+1), "Connecting to " + this.Instruments{i}.Name);

                %Try to connect to the instrument
                [success, instr_msg] = this.Instruments{i}.Initialise();

                if ~success
                    %We failed to connect to an Instrument. Rather than
                    %just an error throw, placing us in an unknown
                    %state, disconnect from all previously-successful
                    %instruments, abort cleanly, show an explanatory
                    %dialogue, including the message that the failed
                    %connection returned.

                    %Disconnect from previous instruments
                    for j = 1 : i-1
                        this.Instruments{j}.Close();
                    end

                    %Abort, with warning message
                    success = false;
                    msg = instr_msg;
                    title = "Could not connect to Instrument";
                    this.View.CloseProgressBar();
                    return;
                end
            end
        end

        %% LoadInstrumentClasses
        function LoadInstrumentClasses(this, folderPath)
            classNames = CoakView.Utilities.FileLoading.PluginLoading.LoadPluginNames(folderPath);
            this.PopulateInstrumentList(classNames);
        end

        %% PopulateInstrumentList
        function PopulateInstrumentList(this, cellArrayOfInstrumentNameStrings)
            %Update the stored list of instrument classes that can be
            %loaded, so we can check against it later for e.g. verification
            %and error checking
            this.ListOfAvailableInstrumentClassNameStrings = cellArrayOfInstrumentNameStrings;

            %Pass through to the View
            this.View.PopulateInstrumentList(cellArrayOfInstrumentNameStrings);
        end     
              
        %% RemoveInstrument
        function RemoveInstrument(this, instrumentRef)
            if isempty(instrumentRef)
                return;
            end

            %Update the View (before we delete the reference!)
            this.View.OnInstrumentRemoved(instrumentRef);

            %Remove it from the list held here
            for i = 1 : length(this.SelectedInstruments)
                if strcmp(this.SelectedInstruments{i}.Name, instrumentRef.Name)
                    this.SelectedInstruments(i) = [];
                    this.SelectedInstrumentNames(i) = [];
                    break;
                end
            end

            %Remove the instrument class reference from memory
            delete(instrumentRef);
        end

        %% RemoveInstrumentControl
        function RemoveInstrumentControl(~, instrRef, controlDetailsStruct)
       
            %Get a reference to the InstrumentControlBase object assigned
            %to this Instrument, of this name
            controlClassName = controlDetailsStruct.Name;
            objsList = instrRef.GetRegisteredControlObjectsFromName(controlClassName);
          
            %Error checking
            assert(~isempty(objsList), "Could not find control to remove on Instrument " + instrRef.Name);
            assert(isscalar(objsList), "Expected to find exactly 1 InstrumentControl..");
            controlClass = objsList(1);

            %Send the remove command
            controlClass.RemoveControl(instrRef);

            %De-register the control class with the instrument
            instrRef.RemoveControlObject(controlClassName);

            %Delete the reference
            delete(controlClass);
        end
    end
    
    
end

