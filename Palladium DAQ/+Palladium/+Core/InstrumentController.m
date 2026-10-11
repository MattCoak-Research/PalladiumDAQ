classdef InstrumentController < handle
    %InstrumentController - Adds and removes instruments and their Instrument Controls, and collects each tick's data row.
    %Created by the Controller, which holds it as `InstrumentController`.
    %`Controller.Initialise` gives it the `PythonInstrumentController` (if
    %Python is set up) and `ErrorOnAllInstrumentErrors`, then calls
    %`LoadInstrumentClasses`, which raises `InstrumentListPopulated` so the
    %GUI's Instrument Browser lists the drivers that can be added.
    %
    %**Adding and removing.** `AddInstrument` is called by the Instrument
    %Browser, by `Palladium.AddInstrument` and when a preset is loaded. It
    %creates the driver, names it (e.g. "K2000_1"), puts it in the base
    %workspace, and raises `InstrumentAdded` and `InstrumentsChanged`. It
    %raises `DefaultEnabledInstrumentControlAdd` for each Instrument Control
    %the driver adds by default. The GUI creates the tab for each
    %Instrument Control, then calls `AddInstrumentControl`, which creates
    %the control, registers it with its instrument, and subscribes it to
    %the TimingLoopController's events and to `DataRowCollected`.
    %`RemoveInstrument` and `RemoveInstrumentControl` undo these.
    %
    %**Starting.** When `TimingLoopController.Start` starts measurements,
    %`Controller.InitialiseMeasurements` calls `InitialiseInstruments`
    %(connect each instrument, from the added ones in `SelectedInstruments`
    %to the measured ones in `Instruments`), `InitialiseHeaders` (the data
    %column headers) and `GetMetadataLines` (for the data file header).
    %
    %**Each tick.** `Controller.Measure` calls `CollectMeasurement`, after
    %the CommandController has run any queued commands. It returns one data
    %row - the time, then each instrument's reading from `UpdateAndMeasure`
    %- and raises `DataRowCollected`. An instrument that fails gives NaNs
    %for its columns.
    %
    %**Stopping.** `CloseAll` disconnects the instruments, called by
    %`Controller.OnMeasurementsStopped` when the TimingLoopController stops,
    %and when Palladium closes.

    %% Properties (Constant, Private)
    properties (Access = private, Constant)
        InstrumentsNamespace string = "Palladium.Instruments";                  %Namespace of the MATLAB instrument drivers, built-in and in the user files folder
        ControlsNamespace string = "Palladium.Instruments.Controls";            %Namespace of the Instrument Control classes
        InstrumentClassesToIgnore = {"TemplateInstrumentClass", "TemplatePythonInstrument"};   %Driver class names (MATLAB or Python) not offered in the Instrument Browser - the templates copied into every user files folder
    end

    %% Properties (Public)
    properties (Access = public)
        ErrorOnAllInstrumentErrors = false; %True to show the error dialogue, offering to stop, when an instrument fails to return data; false (default) logs a warning and records NaNs. Set from Config.json by Controller.Initialise
        PythonInstrumentController;         %The PythonInstrumentController that lists and creates Python drivers, set by the Controller if Python is set up - empty otherwise
    end

    %% Properties (Public, Private Set)
    properties (GetAccess = public, SetAccess = private)
        ListOfAvailableInstrumentClassNameStrings;  %Class names of all the drivers that can be added, MATLAB and Python - set by LoadInstrumentClasses
        SelectedInstrumentNames;                    %Class names of the added instruments, in the order of SelectedInstruments
        SelectedInstruments;                        %Cell array of the added instruments
        Instruments;                                %Cell array of the instruments being measured, copied from SelectedInstruments when measurements start
    end

    %% Properties (Private)
    properties (Access = private)
        Controller;                                 %Reference back to the overall Palladium Controller that handles all the main logic - feed things back to there
        AssignInstrumentRefsIntoWorkspace = true;   %True to put each added instrument in the base workspace, as a variable named after it
        EventListeners;                             %Listeners for the added instruments' PropertyChanged events
    end

    %% Events
    events
        DataRowCollected;                   %Raised every tick by CollectMeasurement, with a DataRowAddedEventData - each Instrument Control listens to it
        DefaultEnabledInstrumentControlAdd; %Raised for each EnabledByDefault Instrument Control of an added instrument, with an InstrumentControlAddEventData - the GUI then adds the control
        InstrumentAdded;                    %Raised when an instrument is added, with an InstrumentAddedEventData - the GUI shows it
        InstrumentsChanged;                 %Raised when an instrument is added or removed, with an InstrumentsChangedEventData - the Sequence Editor updates
        InstrumentListPopulated;            %Raised by PopulateInstrumentList, with a ValueChangedEventData of the driver class names - the GUI lists them
        InstrumentRemoved;                  %Raised when an instrument is about to be removed, with a ValueChangedEventData of it - the GUI removes it
    end

    %% Constructor
    methods
        function this = InstrumentController(controller)
            %Create the instrument controller - called by the Controller's constructor.
            %
            %Inputs:
            %   controller - the Palladium.Core.Controller creating it

            this.Controller = controller;
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function AddEnabledByDefaultInstrumentControls(this, instr)
            %Raise DefaultEnabledInstrumentControlAdd for each Instrument Control an instrument adds by default.
            %Called by AddInstrument. The GUI creates the controls, so with no
            %GUI none are added
            %
            %Inputs:
            %   instr - the newly added instrument

            cdsList = instr.GetAvailableControlOptions();

            if isempty(cdsList)
                return;
            end

            for i=1 : length(cdsList)
                cds = cdsList(i);

                if cds.EnabledByDefault
                    %The View needs to handle GUI object creation, so send
                    %an event upstream. Note, no View = No control made!
                    args = Palladium.Events.InstrumentControlAddEventData(instr, cds);
                    notify(this, "DefaultEnabledInstrumentControlAdd", args);
                end
            end
        end

        function instRef = AddInstrument(this, instrStringToAdd, settings)
            %Create an instrument from its driver class name, and add it to Palladium.
            %A Python driver of that name is used in preference to a MATLAB
            %one. The instrument is named with a number added (e.g.
            %"K2000_1") unless a unique Name is given, put in the base
            %workspace under that name, and its PropertyChanged event is
            %listened to. Raises InstrumentAdded and InstrumentsChanged, and
            %DefaultEnabledInstrumentControlAdd for each control it adds by
            %default. Errors go to the Controller's error handling
            %
            %Inputs:
            %   instrStringToAdd - the driver's class name, as a string, e.g.
            %                      "Keithley2000"
            %   Name             - name for the instrument. Default "Auto",
            %                      the driver's Name with a number added
            %   ConnectionType   - name of a Palladium.Enums.ConnectionType to
            %                      use, e.g. "GPIB". Default "Auto", the
            %                      driver's default
            %
            %Outputs:
            %   instRef - the instrument, or [] if it could not be added

            arguments
                this;
                instrStringToAdd {mustBeTextScalar};
                settings.Name {mustBeTextScalar} = "Auto";
                settings.ConnectionType {mustBeTextScalar} = "Auto";
            end

            %Initialise to empty so we always return something - empty is a
            %nice clue that this failed
            instRef = [];

            %Check for error cases like empty list box selection
            if(isempty(instrStringToAdd))
                return;
            end

            try
                %Make sure the instrName is valid, and other error checking
                assert(isstring(instrStringToAdd), "AddInstrumentError:InvalidInstrumentName", "Instrument name must be a string");
                assert(~isempty(this.ListOfAvailableInstrumentClassNameStrings), "AddInstrumentError:NoInstrumentClasses", "List of loaded instrument classes to select from is empty - file paths messed up?");
                assert(any(contains(this.ListOfAvailableInstrumentClassNameStrings, instrStringToAdd, "IgnoreCase", false)), "AddInstrumentError:InstrumentNotAvailable", "%s", string(instrStringToAdd) + " not found in list of avaliable Instruments");

                %Make an instance of the selected datasource class
                if ~isempty(this.PythonInstrumentController) && ~isempty(this.PythonInstrumentController.AvaialableInstrNames) && any(ismember(this.PythonInstrumentController.AvaialableInstrNames, instrStringToAdd))
                    %Create a python-defined instrument if the name is
                    %present in the PythonInstrumentController (ie is in
                    %the PythonInstruments user folder)
                    instRef = this.PythonInstrumentController.CreateInstrument(instrStringToAdd);
                elseif Palladium.Utilities.PluginLoading.CheckClassExistsInNamespace(this.InstrumentsNamespace, instrStringToAdd)
                    %If not, look for a standard built-in or user defined
                    %MATLAB instrument. Note that .py instruments take
                    %precedence by design - standalone user can overwrite a
                    %built-in instrument this way and otherwise would be
                    %unable to
                    instRef = Palladium.Utilities.PluginLoading.InstantiateClass(this.InstrumentsNamespace, instrStringToAdd);
                else
                    error("InstrumentCreation:NotFoundInNamespace", "%s", "Could not find Instrument " + string(instrStringToAdd) + " in built in or user namespace or Python library. This could indicate that the class file of this Instrument contains an error and MATLAB cannot compile it (missing END statement?).");
                end

                if isempty(instRef)
                    error("AddInstrumentError:CreationFailed", "%s", "Instrument creation failed: " + string(instrStringToAdd));
                end

                %Tell the instrument where the user's Instrument Drivers
                %folder is - the compiled app can't put it on the search path
                instRef.InstrumentDriversDir = string(this.Controller.UserInstrumentDriversDir);

                %Set the instrument name if that optional parameter was
                %passed in. This is useful when setting up Instruments and
                %their GUI controls programmatically - we want the name to
                %be set before the control gets added in the line below..
                if ~strcmp(settings.Name, "Auto")
                    instRef.Name = settings.Name;
                end

                if strcmp(settings.Name, "Auto") | Palladium.Utilities.PluginLoading.CheckForExistingInstrName(instRef.Name, this.SelectedInstruments)
                    %Give the newly created instrument a number at the end of its
                    %name ie Lakeshore350_1
                    instRef.Name = Palladium.Utilities.PluginLoading.GetIncrementedInstrName(instRef, this.SelectedInstruments);
                end

                %Set the instrument Connection Type if that optional parameter was
                %passed in.
                if ~strcmp(settings.ConnectionType, "Auto")
                    instRef.Connection_Type = Palladium.Enums.ConnectionType(settings.ConnectionType);
                end

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

                %Check for any InstrumentControls that have EnabledByDefault
                %set to true, and add them
                this.AddEnabledByDefaultInstrumentControls(instRef);

                %Assign a reference to the instrument into the Matlab
                %workspace as well, so we can e.g. programmatically call
                %functions and adjust settings mid-measurement
                if(this.AssignInstrumentRefsIntoWorkspace)
                    try
                        safeName = genvarname(instRef.Name);
                        assignin("base", safeName, instRef);
                    catch err
                        warning("AddInstrumentWarning:WorkspaceAssignFailed", "%s", "Failed to assign Instrument " + instRef.Name + " into the workspace. Message: " + err.message);
                    end
                end

                %Update the View
                args = Palladium.Events.InstrumentAddedEventData(instrStringToAdd, instRef);
                notify(this, "InstrumentAdded", args);

                args = Palladium.Events.InstrumentsChangedEventData(this.SelectedInstruments);
                notify(this, "InstrumentsChanged", args);

                %Subscribe to the event fired when instrument properties change.
                %Note that we have to store and register this listener handle
                %properly, or when we remove this control  the orphaned listener still lives on the instrument.
                %When you then change a dropdown (e.g., SourceMode), the PostSet → PropertyChanged event fires, the orphaned listener
                %tries to call RefreshUnitsAndLimits() on a deleted handle object, and MATLAB crashes.
                ltr = Palladium.Core.ErrorGuard.AddListener(instRef, 'PropertyChanged', @(src,evnt)this.InstrumentPropertyChanged(evnt), Controller = this.Controller, Context = "Error handling a property change on " + instRef.Name);
                this.RegisterEventListener(ltr);

                %Verbose/debug message printing
                this.Controller.Log("Info", "Added Instrument: " + instrStringToAdd, "Green", "Added Instrument");
            catch err
                this.Controller.HandleError("Error adding instrument " + instrStringToAdd, err);
            end
        end

        function cont = AddInstrumentControlFromName(this, instrRef, controlName, view, Settings)
            %Have the GUI add one of an instrument's Instrument Controls, by name.
            %For example, add a "Sweep Control" to a Keithley2000 that was
            %already added. Used by PluginLoading.ApplyPresetFromJson when
            %loading a preset, and does the same as
            %`Palladium.AddInstrumentControl`
            %
            %Inputs:
            %   instrRef    - the instrument to add the control to
            %   controlName - the control's Name, as given to
            %                 DefineInstrumentControl in the driver's
            %                 constructor, e.g. "Sweep Control"
            %   view        - the GUI, which creates the control's tab
            %   ControlName - name to give the control instead of its
            %                 default. Default [], keep the default
            %   TabName     - title of its tab instead of the default.
            %                 Default [], keep the default
            %
            %Outputs:
            %   cont - the new Instrument Control

            arguments
                this;
                instrRef (1,1) Palladium.Core.Instrument;
                controlName (1,1) {mustBeTextScalar};
                view (1,1);
                Settings.ControlName = [];
                Settings.TabName = [];
            end

            %Grab the default definition struct to build that control from
            %the instrument reference
            controlDetailsStruct = instrRef.GetControlOption(controlName);

            %Apply any optional configuration settings entered
            if ~isempty(Settings.ControlName); controlDetailsStruct.Name = Settings.ControlName; end
            if ~isempty(Settings.TabName); controlDetailsStruct.TabName = Settings.TabName; end

            %Pass on to the more general function below
            cont = this.AddInstrumentControlFromStruct(instrRef, controlDetailsStruct, view);
        end

        function cont = AddInstrumentControlFromStruct(~, instrRef, controlDetailsStruct, view)
            %Have the GUI add an Instrument Control to an instrument, from its definition.
            %The GUI creates a tab and then calls AddInstrumentControl.
            %AddInstrumentControlFromName is easier to use, needing only the
            %control's name
            %
            %Inputs:
            %   instrRef             - the instrument to add the control to
            %   controlDetailsStruct - the control's definition, e.g. from
            %                          `instrRef.GetControlOption(controlName)`
            %   view                 - the GUI, which creates the control's tab
            %
            %Outputs:
            %   cont - the new Instrument Control

            arguments
                ~;
                instrRef (1,1) Palladium.Core.Instrument;
                controlDetailsStruct (1,1) struct;
                view (1,1);
            end

            %Pass on to the View
            cont = view.AddInstrumentControl(instrRef, controlDetailsStruct);
        end

        function controlClassRef = AddInstrumentControl(this, tab, instrRef, controlDetailsStruct)
            %Create an Instrument Control in a GUI tab, register it with its instrument, and subscribe it to events.
            %Called by the GUI once it has made the tab. The control is
            %subscribed to the TimingLoopController's Started, Paused,
            %Resumed, Stopped, MeasurementsInitialised and
            %TargetUpdateTimeChanged events, and to DataRowCollected, through
            %ErrorGuard. Errors go to the Controller's error handling
            %
            %Inputs:
            %   tab                  - the GUI tab to build the control in
            %   instrRef             - the instrument the control belongs to
            %   controlDetailsStruct - the control's definition, from
            %                          DefineInstrumentControl
            %
            %Outputs:
            %   controlClassRef - the new Instrument Control

            try
                %Make an instance of the selected datasource class
                controlClassRef = Palladium.Utilities.PluginLoading.InstantiateClass(this.ControlsNamespace, controlDetailsStruct.ControlClassFileName);
                controlClassRef.ControlDetailsStruct = controlDetailsStruct;
                controlClassRef.Controller = this.Controller;   %Before CreateInstrumentControlGUI, which hooks up guarded listeners
                controlClassRef.ProgrammeTargetUpdateTime = this.Controller.TimingLoopController.TargetUpdateTime;

                %Tell the control class to create the required GUI etc
                controlClassRef.CreateInstrumentControlGUI(this.Controller, tab, instrRef);

                %Register the control class with the instrument
                instrRef.RegisterControlObject(controlClassRef);

                %Subscribe it to Controller events. Store the handle to the
                %Listener by calling RegisterEventListener, so we can
                %unsubscribe from events on deletion of the control.
                %All guarded, so errors in a control's handlers go to the
                %error handling instead of becoming warnings (see ErrorGuard)
                ctrlName = string(controlDetailsStruct.Name);
                tlc = this.Controller.TimingLoopController;
                ltr = Palladium.Core.ErrorGuard.AddListener(tlc, 'Started', @(src,evnt)controlClassRef.MeasurementsStarted(src, evnt), Controller = this.Controller, Context = "Error in " + ctrlName + " (Started)");
                controlClassRef.RegisterEventListener(ltr);
                ltr = Palladium.Core.ErrorGuard.AddListener(tlc, 'Paused', @(src,evnt)controlClassRef.MeasurementsPaused(src, evnt), Controller = this.Controller, Context = "Error in " + ctrlName + " (Paused)");
                controlClassRef.RegisterEventListener(ltr);
                ltr = Palladium.Core.ErrorGuard.AddListener(tlc, 'Resumed', @(src,evnt)controlClassRef.MeasurementsResumed(src, evnt), Controller = this.Controller, Context = "Error in " + ctrlName + " (Resumed)");
                controlClassRef.RegisterEventListener(ltr);
                ltr = Palladium.Core.ErrorGuard.AddListener(tlc, 'Stopped', @(src,evnt)controlClassRef.MeasurementsStopped(src, evnt), Controller = this.Controller, Context = "Error in " + ctrlName + " (Stopped)");
                controlClassRef.RegisterEventListener(ltr);
                ltr = Palladium.Core.ErrorGuard.AddListener(tlc, 'MeasurementsInitialised', @(src,evnt)controlClassRef.MeasurementsInitialised(src, evnt), Controller = this.Controller, Context = "Error in " + ctrlName + " (MeasurementsInitialised)");
                controlClassRef.RegisterEventListener(ltr);
                ltr = Palladium.Core.ErrorGuard.AddListener(tlc, 'TargetUpdateTimeChanged', @(src,evnt)controlClassRef.TargetUpdateTimeChanged(src, evnt), Controller = this.Controller, Context = "Error in " + ctrlName + " (TargetUpdateTimeChanged)");
                controlClassRef.RegisterEventListener(ltr);
                ltr = Palladium.Core.ErrorGuard.AddListener(this, 'DataRowCollected', @(src,evnt)controlClassRef.DataRowCollected(evnt.DataRow, evnt.Headers), Controller = this.Controller, Context = "Error in " + ctrlName + " (DataRowCollected)");
                controlClassRef.RegisterEventListener(ltr);


                %Verbose/debug message printing
                this.Controller.Log("Info", "Added Instrument Control: " + controlDetailsStruct.Name, "Green", "Added Instrument Control");
            catch err
                this.Controller.HandleError("Error adding instrument Control " + controlDetailsStruct.Name, err);
            end
        end

        function CloseAll(this)
            %Disconnect from all the instruments being measured.
            %Called by `Controller.OnMeasurementsStopped` when measurements
            %stop, and when Palladium closes

            %Display a status message in the logger
            this.Controller.Log("Info", "Closing Instruments", "Yellow", "Closing Instruments");

            %Close all instruments
            for i = 1 : length(this.Instruments)
                this.Instruments{i}.Close();
            end

            %Display a status message in the logger
            this.Controller.Log("Info", "Instruments closed", "Green", "Instruments closed");
        end

        function DataRow = CollectMeasurement(this, headers)
            %Take one row of data from all the instruments - called by Controller.Measure each tick.
            %The first column is the time, in minutes since 1970 (UTC). For
            %each instrument, applies any settings waiting from an Instrument
            %Control (CheckForSettingsToApply), then calls UpdateAndMeasure.
            %If an instrument errors, its columns are NaN, and either a
            %warning is logged or, with ErrorOnAllInstrumentErrors, the error
            %dialogue is shown (`Controller.HaltMeasurementsOnInstrumentError`).
            %The row is then stored in each instrument's LastFullDataRow, and
            %DataRowCollected is raised
            %
            %Inputs:
            %   headers - the data column headers of all instruments, passed
            %             to each instrument's UpdateAndMeasure
            %
            %Outputs:
            %   DataRow - the row of values, in the order of the headers

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
                    DataRow = [DataRow this.Instruments{i}.UpdateAndMeasure(headers)]; %#ok<AGROW>
                catch e
                    %Pop in a nan value, as we failed to grab the data from
                    %this instrument
                    %First need to know how many nans to insert.. match to
                    %Headers
                    hdrs = this.Instruments{i}.GetHeaders();
                    n = length(hdrs);
                    DataRow = [DataRow, nan(1, n)]; %#ok<AGROW>

                    if this.ErrorOnAllInstrumentErrors
                        this.Controller.HaltMeasurementsOnInstrumentError(this.Instruments{i}, e);
                    else
                        %Just show a warning, do not halt execution
                        reportStr = string(e.message);
                        Palladium.Logging.Logger.Log("Warning", "Measurement call to instrument " + this.Instruments{i}.Name + " failed in CollectMeasurement, data set to NaN for this tick. Error message: " + reportStr);
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
                    Palladium.Logging.Logger.Log("Warning", "Last dataRow update call to instrument " + this.Instruments{i}.Name + " failed in CollectMeasurement. Error message: " + reportStr);

                end
            end

            %Fire event for data row collected
            notify(this, "DataRowCollected", Palladium.Events.DataRowAddedEventData(DataRow, this.Controller.Headers));
        end

        function [Headers, HeadersString, Units] = GetHeaders(this)
            %Data column headers and units of all the instruments being measured, after the time column.
            %Also stores the headers, and the Controller's FileWriteDetails,
            %in each instrument (FullHeadersRow and FileWriteDetails), for
            %Instrument Controls that write their own data files
            %
            %Outputs:
            %   Headers       - cell array of headers, starting "Time (mins)"
            %   HeadersString - the headers as one tab-separated char vector
            %   Units         - cell array of their units, starting "mins"

            %Put time in as first header
            Headers = {"Time (mins)"};
            Units = {"mins"};

            %Scan through all instruments and get their data column
            %headers.
            for i = 1 : length(this.Instruments)
                [instrHeaders, instrUnits] = this.Instruments{i}.GetHeaders();
                for j = 1 : length(instrHeaders)
                    Headers = [Headers, string(instrHeaders{j})]; %#ok<AGROW>
                    Units = [Units, string(instrUnits{j})]; %#ok<AGROW>
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
                    Palladium.Logging.Logger.Log("Warning", "Last dataRow update call to instrument " + this.Instruments{i}.Name + " failed in CollectMeasurement. Error message: " + reportStr);

                end
            end
        end

        function instRef = GetInstrumentFromName(this, instName)
            %Find an added instrument by its Name.
            %Errors, listing the names of the added instruments, if none
            %matches
            %
            %Inputs:
            %   instName - the instrument's Name, e.g. "K2000_1"
            %
            %Outputs:
            %   instRef - the instrument

            arguments
                this;
                instName {mustBeTextScalar};
            end

            instRef = []; %#ok<NASGU>

            for i = 1 : length(this.SelectedInstruments)
                if this.SelectedInstruments{i}.Name == instName
                    instRef = this.SelectedInstruments{i};
                    return;
                end
            end

            %If we got here, none of the instruments matched
            instStringNameList = "";
            for i = 1 : length(this.SelectedInstruments)
                instStringNameList = instStringNameList + this.SelectedInstruments{i}.Name;
                if i ~= length(this.SelectedInstruments)
                    instStringNameList = instStringNameList + ", ";
                end
            end
            if instStringNameList == ""
                instStringNameList = "-NONE-";
            end

            error("GetInstrumentFromNameError:NotFound", "%s", "Could not find instrument of Name " + instName + ". Added Instruments: " + instStringNameList);
        end

        function instRefs = GetInstruments(this)
            %The added instruments.
            %
            %Outputs:
            %   instRefs - cell array of instruments (SelectedInstruments)

            instRefs = this.SelectedInstruments;
        end

        function metadataLines = GetMetadataLines(this)
            %Data file header lines of the instruments' settings, one per instrument that has any.
            %From each instrument's GrabMetadataString. Called by the
            %Controller when measurements start
            %
            %Outputs:
            %   metadataLines - string array of lines, or [] if there are none

            metadataLines = [];
            for i = 1 : length(this.Instruments)
                metadataNullableString = this.Instruments{i}.GrabMetadataString();
                if ~isempty(metadataNullableString)
                    metadataLines = [metadataLines metadataNullableString]; %#ok<AGROW>
                end
            end
        end

        function [headers, headersString, units] = InitialiseHeaders(this)
            %Make the data column headers when measurements start, and check none is repeated.
            %Called by `Controller.InitialiseMeasurements` after
            %InitialiseInstruments. Errors if two columns have the same
            %header. See GetHeaders for the outputs

            %Generate column headers, for internal use and file writing
            [headers, headersString, units] = this.GetHeaders();

            %Verify that those headers are valid - no duplicates
            [duplicateHeaderValues, duplicateHeaderValuesString] = Palladium.Utilities.Verification.CheckForDuplicatesInHeadersArray(headers);
            assert(isempty(duplicateHeaderValues), "InitialiseHeadersError:DuplicateHeaders", "%s", "Some variable names appear twice, this is not allowed. Duplicate variables: " + duplicateHeaderValuesString);

        end

        function [success, msg, title] = InitialiseInstruments(this)
            %Connect to every added instrument when measurements start.
            %Called by `Controller.InitialiseMeasurements`. Copies
            %SelectedInstruments to Instruments, then calls each instrument's
            %Initialise, updating the progress bar. If one fails to connect,
            %closes those already connected and stops there
            %
            %Outputs:
            %   success - true if all connected (or there are no instruments)
            %   msg     - if not, the message from the instrument that failed
            %   title   - if not, a title for the warning dialogue

            %Set starting values. Note, function will immediately return if
            %there are no Instruments, returning these
            success = true;
            msg = "";
            title = "";

            %Set the list of instruments from the selection panel's ItemData
            this.Instruments = this.GetInstruments();

            %Initialise all instruments
            for i = 1 : length(this.Instruments)

                %Update the progress bar
                this.Controller.UpdateProgress((i) / (length(this.Instruments)+1), "Connecting to " + this.Instruments{i}.Name);

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
                    this.Controller.CloseProgress();
                    return;
                end
            end
        end

        function LoadInstrumentClasses(this)
            %Find all the instrument drivers that can be added, and raise InstrumentListPopulated.
            %Lists the MATLAB drivers in Palladium.Instruments (built in and
            %in the user files folder) and the Python drivers, leaving out
            %InstrumentClassesToIgnore, and sorts them. Errors if two drivers
            %have the same name. Called by `Controller.Initialise`

            %Load the names of the classes from the built-in and User Files
            %Instruments directories - they are the same name, so a single
            %namespace, that just happens to split over two folders. MATLAB
            classNames = Palladium.Utilities.PluginLoading.LoadClassNamesInNamespace(this.InstrumentsNamespace);

            %Remove any entries that are specified to be excluded - like
            %TemplateInstrumentClass
            for i = 1 : length(this.InstrumentClassesToIgnore)
                classNames(strcmp(classNames, this.InstrumentClassesToIgnore{i})) = [];
            end

            %Error on any duplicates
            [duplicates, combinedString] = Palladium.Utilities.Verification.CheckForDuplicatesInCellArrayOfStrings(classNames);
            if ~isempty(duplicates)
                error("LoadInstrumentClass:DuplicatesError", "%s", "Error loading Instrument Classes - found duplicate names. Is an Instrument in the User Files Instrument folder named the same as one of the built in classes? " + newline + newline + " Duplicates found: " + string(combinedString));
            end

            %Load Python Instrument classes too
            if ~isempty(this.PythonInstrumentController)
                pyNames = this.PythonInstrumentController.AvaialableInstrNames;

                %Remove any entries that are specified to be excluded - like
                %TemplatePythonInstrument
                if ~isempty(pyNames)
                    pyNames = pyNames(~ismember(string(pyNames), string(this.InstrumentClassesToIgnore)));
                end

                %Append to the list of names
                classNames = [classNames pyNames];

                %Error on any duplicates
                [duplicates, combinedString] = Palladium.Utilities.Verification.CheckForDuplicatesInCellArrayOfStrings(classNames);
                if ~isempty(duplicates)
                    error("LoadInstrumentClass:DuplicatesError", "%s", "Error loading Instrument Classes - found duplicate names. Is an Instrument in the User Files Instrument folder named the same as one of the built in classes? " + newline + newline + " Duplicates found: " + string(combinedString));
                end
            end

            %Sort alphabetically - right now it is a design choice to have
            %one combined list, rather than a separation into User and
            %Built-In
            classNames = sort(classNames);

            %Set the list of instruments from these
            this.PopulateInstrumentList(classNames);
        end

        function PopulateInstrumentList(this, cellArrayOfInstrumentNameStrings)
            %Set the list of driver class names that can be added, and raise InstrumentListPopulated.
            %
            %Inputs:
            %   cellArrayOfInstrumentNameStrings - the class names

            %Update the stored list of instrument classes that can be
            %loaded, so we can check against it later for e.g. verification
            %and error checking
            this.ListOfAvailableInstrumentClassNameStrings = cellArrayOfInstrumentNameStrings;

            %Pass through to the View
            args = Palladium.Events.ValueChangedEventData(cellArrayOfInstrumentNameStrings);
            notify(this, "InstrumentListPopulated", args);
        end

        function RemoveInstrument(this, instrumentRef)
            %Remove an added instrument, and delete it.
            %Raises InstrumentRemoved first (so the GUI can remove it), then
            %InstrumentsChanged. Does nothing if instrumentRef is empty. When
            %removing from the GUI, its Instrument Controls are removed first
            %
            %Inputs:
            %   instrumentRef - the instrument to remove

            if isempty(instrumentRef)
                return;
            end

            %Update the View (before we delete the reference!)
            args = Palladium.Events.ValueChangedEventData(instrumentRef);
            notify(this, "InstrumentRemoved", args);


            %Remove it from the list held here
            for i = 1 : length(this.SelectedInstruments)
                if strcmp(this.SelectedInstruments{i}.Name, instrumentRef.Name)
                    this.SelectedInstruments(i) = [];
                    this.SelectedInstrumentNames(i) = [];
                    break;
                end
            end

            %Throw an InstrumentsChanged event, to update other things that
            %rely on this list
            args = Palladium.Events.InstrumentsChangedEventData(this.SelectedInstruments);
            notify(this, "InstrumentsChanged", args);

            %Remove the instrument class reference from memory
            delete(instrumentRef);
        end

        function RemoveInstrumentControl(~, instrRef, controlDetailsStruct)
            %Remove an Instrument Control from its instrument, and delete it.
            %Unregisters it from the instrument, unsubscribes it from events,
            %and calls its RemoveControl. Called by the GUI and
            %`Controller.RemoveInstrumentControl`. Errors unless exactly one
            %control of that name is found
            %
            %Inputs:
            %   instrRef             - the instrument the control belongs to
            %   controlDetailsStruct - the control's definition; its Name is used

            %Get a reference to the InstrumentControlBase object assigned
            %to this Instrument, of this name
            controlClassName = controlDetailsStruct.Name;
            objsList = instrRef.GetRegisteredControlObjectsFromName(controlClassName);

            %Error checking
            assert(~isempty(objsList), "RemoveInstrumentControlError:ControlNotFound", "%s", "Could not find control to remove on Instrument " + instrRef.Name);
            assert(isscalar(objsList), "RemoveInstrumentControlError:ControlNotUnique", "Expected to find exactly 1 InstrumentControl..");
            controlClass = objsList(1);

            %De-register the control class with the instrument
            instrRef.RemoveControlObject(controlClassName);

            %Un-subscribe from events
            controlClass.UnsubscribeFromEvents();

            %Send the remove command
            controlClass.RemoveControl(instrRef);

            %Delete the reference
            delete(controlClass);
        end
    end

    %% Methods (Private)
    methods(Access = private)

        function InstrumentPropertyChanged(this, evnt)
            %Pass an instrument's PropertyChanged event on to the Controller.

            instr = evnt.AffectedObject;
            this.Controller.InstrumentPropertyChanged(instr);
        end

        function RegisterEventListener(this, listnr)
            %Keep a listener's handle, so it lives as long as this controller.

            if isempty(this.EventListeners)
                this.EventListeners = listnr;
            else
                this.EventListeners = [this.EventListeners, listnr];
            end
        end

    end

end
