classdef Controller < handle
    %CONTROLLER Logic and measurement loop for CoakView Programme. 

    properties
        %Reference to the main figure window / GUI / View Implementation
        View;

        %Paths and Directories
        ApplicationPath;    %These will be set in StartUp Fcn of the UiFigure
        ApplicationDir;     %These will be set in StartUp Fcn of the UiFigure


        TimingLoopController;
    end

    properties(GetAccess = public, SetAccess = private)
        %Settings structs
        WindowSettings;
        PathSettings;
        PlotterSettings;

        %Data array
        DataTable;

    end

    properties(Access = private)

        DataWriter;
        PlottingPanels = {};
        PlottingTabs = {};
        BigNumDisplays;

        InstrumentController;
        SequenceEditorController;

        FileWriteDetails;
        DefaultDataDir;

        Headers = {};
        Units = {};

        SuppressedErrorMessages = {};

        AssignInstrumentRefsIntoWorkspace = true;
    end

    properties(Constant)
        PresetsDirectory = filesep + "+CoakViewPresets";
    end


    methods
        %% Constructor
        function this = Controller(Settings)
            arguments
                Settings.ApplicationDir {mustBeTextScalar};
                Settings.ApplicationPath {mustBeTextScalar};
                Settings.View (1,1);
            end

            this.ApplicationDir = Settings.ApplicationDir;
            this.ApplicationPath = Settings.ApplicationPath;
            this.View = Settings.View;

            %Create a helper class for managing Instruments
            this.InstrumentController = CoakView.Core.InstrumentController(this, this.View);
           
            %Create a helper class for controlling the main
            %measurement/timing loop, Start/Pause/Resume etc
            this.TimingLoopController = CoakView.Core.TimingLoopController(this);

            %Assign controllers into the View and have it subscribe to
            %their events
            this.View.AssignControllersAndHookUpEvents(this, this.TimingLoopController);

        end

        %% AddInstrument
        function instr = AddInstrument(this, instrumentClassName, settings)
            arguments
                this;
                instrumentClassName {mustBeTextScalar};
                settings.Name {mustBeTextScalar} = "Auto";
            end

            %This can be called either programmatically, from the wrapper,
            %or via events triggered in the View. 
            try
                % Pass on to Instrument Controller
                instr = this.InstrumentController.AddInstrument(instrumentClassName);

                %Set the instrument name if that optional parameter was
                %passed in. This is useful when setting up Instruments and
                %their GUI controls programmatically - we want the name to
                %be set before the control gets added in the line below..
                if ~strcmp(settings.Name, "Auto")
                    instr.Name = settings.Name;
                end


                %Check for any InstrumentControls that have EnabledByDefault
                %set to true, and add them
                this.InstrumentController.AddEnabledByDefaultInstrumentControls(instr);

                %Assign a reference to the instrument into the Matlab
                %workspace as well, so we can e.g. programmatically call
                %functions and adjust settings mid-measurement
                if(this.AssignInstrumentRefsIntoWorkspace)
                    try
                        safeName = genvarname(instr.Name);
                        assignin("base", safeName, instr);
                    catch err
                        warning("Failed to assign Instrument " + instr.Name + " into the workspace. Message: " + err.message);
                    end
                end

                %Verbose/debug message printing
                this.Log("Info", "Added Instrument: " + instrumentClassName, "Green", "Added Instrument");
            catch err
                this.HandleError("Error adding instrument " + instrumentClassName, err);
            end
        end

        %% AddInstrumentControl
        function cont = AddInstrumentControl(this, instrRef, controlDetailsStruct)
            try
                %Check that the control has not already been added (before
                %creating the new tab..)
                if ~isempty(instrRef.GetRegisteredControlObjectsFromName(controlDetailsStruct.Name))
                    error("A Control object of name " + controlDetailsStruct.Name + " has already been added to Instrument " + instrRef.Name);
                end

                %Create a new tab
                tabName = instrRef.Name + " - " + controlDetailsStruct.TabName;
                tab = this.CreateInstrumentControlTab(tabName);

                %Populate tab and hook up instrument to the GUI                
                cont = this.InstrumentController.AddInstrumentControl(this, tab, instrRef, controlDetailsStruct);

                %Subscribe it to Controller events
                addlistener(this, 'Started', @(src,evnt)cont.MeasurementsStarted(src, evnt));
                addlistener(this, 'Paused', @(src,evnt)cont.MeasurementsPaused(src, evnt));
                addlistener(this, 'Resumed', @(src,evnt)cont.MeasurementsResumed(src, evnt));
                addlistener(this, 'Stopped', @(src,evnt)cont.MeasurementsStopped(src, evnt));

                %Update the View
                this.View.OnControlEnabled(controlDetailsStruct.Name);

                %Verbose/debug message printing
                this.Log("Info", "Added Instrument Control: " + controlDetailsStruct.Name, "Green", "Added Instrument Control");
            catch err
                this.HandleError("Error adding instrument control " + controlDetailsStruct.Name, err);
            end
        end
        
        %% AddNewPlotter
        function pltr = AddNewPlotter(this, parent, size)
            %This is used by things like Instrument Control creating GUIs
            %and placing Plotters in exisiting Gridlayouts
            arguments
                this;
                parent;
                size = "Medium";
            end

            try
                %Pass through to View to handle GUI stuff
                pltr = this.View.AddNewPlotter(parent, size);
                
                %Register the plotter so it gets updated
                this.RegisterPlotterObject(pltr);
            catch err
                this.HandleError("Error adding new plotter", err);
            end
        end

        %% AddNewSimplePlotter
        function pltr = AddNewSimplePlotter(this, parent, size)
            %SimplePlotter is a barebones version of the Plotter class
            %that doesn't have dropdowns and is not plugged into the 
            %DataRow and update infrastructure. It can just take plot
            %commands programmtically from whatever made it. 
            %This is used by things like Instrument Control creating GUIs
            %and placing Plotters in exisiting Gridlayouts
            arguments
                this;
                parent;
                size = "Medium";
            end

            try
                %Pass through to View to handle GUI stuff
                pltr = this.View.AddNewSimplePlotter(parent, size);
                
                %Simple plotters do not get registered for auto-updates.
                %Whatever made them has to push data to them itself.
            catch err
                this.HandleError("Error adding new plotter", err);
            end
        end
        
        %% AddNewPlottingTab
        function listOfPltrs = AddNewPlottingTab(this, rows, cols)
            try
                % To be used by external calls, eg. presets
                [listOfPltrs, tab] = this.View.AddNewPlottingTab(rows, cols);

                %Add the plotters to the list of plotters to be updated
                for i = 1 : length(listOfPltrs)
                    this.RegisterPlotterObject(listOfPltrs(i));
                end

                %Add the tab to the list of plotter tabs too
                this.RegisterPlotterTab(tab);

            catch err
                this.HandleError("Error adding new plotting tab", err);
            end
        end

        %% AddNewPlottingWindow
        function listOfPltrs = AddNewPlottingWindow(this, rows, cols)
            try
                % To be used by external calls, eg. presets
                listOfPltrs = this.View.AddNewPlottingWindow(rows, cols);

                %Add the plotters to the list of plotters to be updated
                for i = 1 : length(listOfPltrs)
                    this.RegisterPlotterObject(listOfPltrs(i));
                end
            catch err
                this.HandleError("Error adding new plotting window", err);
            end
        end

        %% ApplyPreset
        function ApplyPreset(this, presetFn)
            try
                %Display a status message in the logger
                this.ShowStatus('Yellow', 'Applying Preset');
                presetFn(this);

                %Finalise the preset - basically, update the GUI to relfect
                %changes
                this.FinalisePreset();
            catch err
                this.HandleError("Error applying Preset", err);
            end
        end

        %% CanStart
        function canStart = CanStart(this)
            canStart = false;
            try
                %Verify directory and path valid
                if(~CoakView.Utilities.FileLoading.PathUtils.IsDirectoryValid(this.FileWriteDetails.Directory))
                    error(['Error - directory not valid: ' strrep(this.FileWriteDetails.Directory, '\', '\\')]);
                end
                if(~CoakView.Utilities.FileLoading.PathUtils.IsFileNameValid(this.FileWriteDetails.FileName))
                    error(['Error - file name not valid: ' strrep(this.FileWriteDetails.FileName, '\', '\\')]);
                end
            catch err
                this.View.OnMeasurementsStopped();
                this.Controller.HandleError('Invalid file path. Cannot start measurements', err);
                return;
            end

            canStart = true;
        end        

        %% GetPresetsDir
        function dirPath = GetPresetsDir(this)
            dirPath = fullfile(this.ApplicationDir,  this.PresetsDirectory);
        end

        %% HaltMeasurementsOnInstrumentError
        function HaltMeasurementsOnInstrumentError(this, instr, e)
            %Show error message and ask if we want to stop measurements
            halt = this.Controller.HandleError("Error in main measurement loop - Collect Data from " + instr.FullName, e);
            if(halt)
                CoakView.Logging.Logger.Log("Info", "Measurements aborted by User from Error Dialogue");
                this.TimingLoopController.Stop();
                this.TimingLoopController.OnStopped();
            end
        end

        %% HandleError
        function Halt = HandleError(this, message, error)
            %Assemble a full message from the message sent into the logger,
            %and the actual error details
            msg = string(message) + ": " + string(error.message);

            %If we have previously suppressed this error, no need to do
            %anything, just return (and do not halt)
            if any(strcmp(this.SuppressedErrorMessages, msg))
                Halt = false;
                return;
            end

            %Message about the error - Try to display a red light error status in the programme, and Log, but
            %don't fuss if that fails, just ignore the exception and throw
            %a warning
            try
                this.ShowStatus("Red", "Error: " + msg);
                drawnow();
                CoakView.Logging.Logger.Log("Error", msg, "FullMessage", msg + " : " + string(getReport(error, "extended", "hyperlinks", "on")));
            catch e
                warning("An error was thrown while.. trying to handle an error.. : " + string(e.message));
            end

            %Pass on the error to the Error Handler to show a dialogue box
            %- user can choose whether to stop the measurement loop, and
            %separately whether to suppress this error going forward
            uiFigureHandle = this.View.GetUIFigureHandle();
            [Halt, suppressError] = CoakView.Logging.Logger.HandleError(message, error, uiFigureHandle);

            %User could have chosen to Suppress this error message in the
            %dialogue box, so it will not be shown in the future - handle
            %that case. List of suppressed errors will (for now at least)
            %be a property of Controller, so will only be reset by
            %restarting the programme. Could reset it on measurement start
            %later if that turns out to be clearer for the user
            if(suppressError)
                %Log the fact that we are suppressing an error
                CoakView.Logging.Logger.Log("Info", "Error Suppressed by User: " + msg);

                %Add this error to the list
                this.SuppressedErrorMessages = [this.SuppressedErrorMessages, msg];
            end
        end

        %% HandleWarning
        function HandleWarning(this, msg, title)
            fig = this.View;
            try
                uifg = fig.CoakViewUIFigure;
                if matlab.ui.internal.isUIFigure(uifg)
                    %Our view is a UI Figure, show a modal warning box based on
                    %its handle
                    uialert(uifg, sprintf(msg), title, "Icon", "warning", "Interpreter", "HTML");
                else
                    %Our view is not a ui figure - just show a warning in the
                    %console
                    warning(msg);
                end
            catch
                warning(msg);
            end
        end

        %% Initialise
        function Initialise(this)
            %Initialise the Controller, loading and applying settings etc
            try
                %Load settings from .json config files in the Settings directory
                [logSettings, this.PathSettings, this.WindowSettings, this.PlotterSettings] = this.LoadSettings();
            catch e
                %Note that we don't pass this in to any nice error handling
                %because we haven't set that up yet
                error("Error in loading settings in Controller.Initialise: " + string(e.message));
            end

            %Now we know the settings to pass to it, create a Logger. Don't
            %need to keep a reference to it, as it has a pseudo-static
            %singleton model where it can then be accessed with static
            %calls while remembering these settings
            CoakView.Logging.Logger(this,...
                logSettings.LogFileDirectory, logSettings.LogFileFileName,...
                "CommandWindowMessageLevel", logSettings.CommandWindowMessageLevel,...
                "GUIMessageLevel", logSettings.GUIMessageLevel,...
                "LogFileMessageLevel", logSettings.LogFileMessageLevel,...
                "PrintStackTraceInCommandWindow", logSettings.PrintStackTraceInCommandWindow);

            %check that new enough Matlab version is installed, toolboxes
            %are there.. etc etc. Will throw error if not!
            this.ValidateInstall();

            try
                %Set logging/error setting parameters in Controller
                this.InstrumentController.ErrorOnAllInstrumentErrors = logSettings.ErrorOnAllInstrumentErrors;

                %Store default paths etc
                this.FileWriteDetails.Directory = this.PathSettings.DefaultDirectory;
                this.FileWriteDetails.DescriptionText = this.PathSettings.DefaultDescription;
                this.FileWriteDetails.FileExtension = this.PathSettings.DataFileExtension;
                this.FileWriteDetails.SaveFile = this.PathSettings.SaveFile;
                this.FileWriteDetails.WriteMode = this.PathSettings.FileWriteMode;

                %Do this one last, with a proper function call, as it has some code in, and then will
                %call the GUI update
                this.SetFilePathsFileName(this.PathSettings.DefaultFileName);

                %Set the default path for the DataViewer programme too
                this.DefaultDataDir = CoakView.Utilities.FileLoading.PathUtils.CleanPath(this.PathSettings.DefaultDirectory);

                %Retrieve iconPath to pass to a GUI
                this.WindowSettings.CoakViewIconPath = this.ApplicationDir + "\+CoakView\+Components\Graphics\CoakViewIcon.png";

                %Send settings to the GUI
                this.View.ApplySettings(this.PathSettings, this.WindowSettings);

                %Load plugins
                this.Log("Debug", "Initialising plugins", "Yellow", "Initialising plugins...");
                this.InstrumentController.LoadInstrumentClasses(this.ApplicationDir + "\+CoakView\+Instruments");
                this.Log("Debug", "Plugins intialised", "Green", "Plugins intialised");

                %Initialise TimingLoopController
                this.TimingLoopController.Initialise();

                %Display a status message in the logger
                this.Log("Info", "Ready", "Green", "Ready");
            catch err
                this.HandleError('Initialisation error in applying loaded Settings (Controller.Initialise)', err);
            end
        end

        %% InitialiseDataWriting
        function InitialiseDataWriting(this)
            %Create a DataWriter object to log all data
            this.DataWriter = CoakView.DataWriting.DataWriter(this.FileWriteDetails);
            this.FileWriteDetails.FileName = this.DataWriter.ValidateFilePath();

            %Update the View to display the file write settings
            this.View.OnFileWriteOptionsChanged(this.FileWriteDetails);

            %Clean up Plotters list, remove any that have been deleted
            this.CleanUpPlotters();
        end

        %% InitialiseMeasurements
        function [success, msg, title] = InitialiseMeasurements(this)
            %Reset and prepare all GUI and instruments ready to then run
            %the main update loop - note that Resume doesn't call this,
            %just gets the loop running again without it

            %Display a status message in the logger
            this.Log("Info", "Initialising measurements", "Yellow", "Initialising measurements");

            %Display a model progress bar so we can't go clicking things
            %while intialisation is underway - and also get clued in that a
            %slow operation is in fact running and we shouldn't click Start
            %100 times like my dad
            this.View.ShowProgressBar("Initialising measurements", "Initialising..");

            try
                %Generate column headers and validate
                [this.Headers, headersString, this.Units] = this.InstrumentController.InitialiseHeaders();

                %Initialise the (:, n) double array that will hold the
                %data
                this.DataTable = [];

                %Initialise all instruments
                [success, msg, title] = this.InstrumentController.InitialiseInstruments();

                %If there are no Plotting Tabs, add one
                if(isempty(this.PlottingTabs))
                    this.AddNewPlottingTab(2,1);
                end

                %Initialise all graphs
                this.UpdatePlotVariableNames(this.Headers);
                this.ClearPlots();

                %Display a status message in the logger
                this.Log("Info", "Measurements initialised", "Green", "Measurements initialised");
            catch e
                this.View.CloseProgressBar();
                this.HandleError("Error initialising measurements", e);
                return;
            end

            %Add a metadata/settings line to the top of the datafile (in
            %the header) for each instrument that defines one
            try
                %Update the progress bar
                this.View.UpdateProgressBar(1, "Writing metadata and headers");

                %Get the string to write from Instruments
                metadataLines = this.InstrumentController.GetMetadataLines();

                %Succesful end - close the progress bar
                this.View.CloseProgressBar();
            catch e
                this.View.CloseProgressBar();
                this.HandleError("Error collecting instrument metadata", e);
            end

            %Write the headers to file
            this.DataWriter.WriteHeaders(headersString, "MetadataLines", metadataLines);

            success = true;            
        end

        %% LoadPreset
        function presetFn = LoadPreset(this, presetName)
            %Display a status message in the logger
            this.ShowStatus('Yellow', 'Loading Preset');

            try
                %Fetch paths
                presetsDir = this.GetPresetsDir();
                presetPath = fullfile(presetsDir, presetName) + ".m";

                %Error checking
                assert(exist(presetsDir,"dir") == 7, "Presets directory " + presetsDir + " not found");
                assert(exist(presetPath,"file") == 2, "Preset file " + presetPath + " not found");

                %Load the present in as a function handle
                presetFn = CoakView.Utilities.FileLoading.PluginLoading.InstantiatePreset("CoakViewPresets", presetName);
            catch err
                this.HandleError("Error loading Preset", err);
            end
        end

        %% Log
        function Log(this, level, logText, colour, statusText)
            %Passes through to both the Logger and the GUI status panel
            arguments
                this;
                level       {mustBeText, mustBeMember(level, ["Debug", "Info", "Warning", "Error"])};
                logText     (1,1) string;
                colour      {mustBeText, mustBeMember(colour, ["Green", "Yellow", "Red"])};
                statusText  (1,1) string;
            end
            %Pass through to the Logger and to the status strip in the
            %bottom of the GUI
            CoakView.Logging.Logger.Log(level, logText);
            this.ShowStatus(colour, statusText);
        end
        
        %% Measure
        function Measure(this)
            %This is the core function that gets called by
            %TimingLoopController's Update call every tick, to actually
            %grab data from Instruments and do things with it.
            try
                %Collect Data
                this.ShowStatus("Green", "Running");
                dataRow = this.InstrumentController.CollectMeasurement();
            catch e
                CatchMeasurementLoopError(this, e);
                %Need to do something here to keep programme running when
                %CollectMeasurement errors - set the dataRow to NaNs.
                dataRow = nan([1, length(this.Headers)]);
                this.Controller.Log("Warning", "Data Row set to NaN values due to error thrown in CollectMeasurements", "Yellow", "Data Row set to NaN values due to error thrown in CollectMeasurements");
            end

            try
                %Write data to file
                this.DataWriter.WriteLine(dataRow);
            catch e
                CatchMeasurementLoopError(this, e);
            end

            try
                %Append data to array
                this.AppendToDataTable(dataRow);
            catch e
                CatchMeasurementLoopError(this, e);
            end

            try
                %Update data plots
                this.PlotData(dataRow);
            catch e
                CatchMeasurementLoopError(this, e);
            end

            try
                %Update any Big Number Display windows
                this.UpdateBigNumberDisplays(dataRow);
            catch e
                CatchMeasurementLoopError(this, e);
            end           

            %Want to catch the error pretty locally, so the rest of the
            %stuff in the Update Loop still happens in the expected order
            %if we choose to Ignore or Suppress. This is just a private
            %function here to avoid duplicating the code of handling an
            %error specifically in the Measurement Loop
            function CatchMeasurementLoopError(this, e)
                if(~ isvalid(this.View))
                    %Just break out of the loop if we've closed the
                    %window - it can trigger silly errors about
                    %event listeners still being subscribed which I
                    %don't care about
                    this.TimingLoopController.CloseTimer();
                    return;
                else
                    %Show error message and ask if we want to stop measurements
                    halt = this.HandleError("Error in main measurement loop", e);
                    if(halt)
                        CoakView.Logging.Logger.Log("Info", "Measurements aborted by User from Error Dialogue");
                        this.TimingLoopController.OnStopped();
                    end
                end
            end
        end

        %% NewBigNumberDisplay
        function NewBigNumberDisplay(this)
            iconPath = this.ApplicationDir + "\+CoakView\+Components\Graphics\BigNumDisplayIcon.png";

            %Create a dialogue box askign which value we want to display
            headers = this.Headers;

            %Quit here if there are no values to choose from yet - i.e. if
            %the programme is not yet running.
            if isempty(headers)
                return;
            end

            try

                [indx, tf] = listdlg('Name', 'Select value', 'PromptString', 'Select value to be displayed in Big Number Window.', 'SelectionMode', 'single', 'ListString', headers, 'ListSize', [250,350]);

                if(tf)
                    valHeader = string(this.Headers(indx));
                    unitsStr = string(this.Units(indx));

                    f= uifigure("Icon", iconPath);
                    g = uigridlayout(f, [1,1]);
                    b = CoakView.Components.BigNumberDisplay(g);

                    b.IndexToShow = indx;
                    b.SetTitle(valHeader);
                    b.SetUnits(unitsStr);

                    this.BigNumDisplays = [this.BigNumDisplays b];
                    this.View.RegisterDependentWindow(f);

                    %Prevent the display being sent to the back of the tab
                    %stack and everything minimising..
                    %this.RefocusWindow();
                    f.Visible = 'off';
                    f.Visible = 'on';
                end
            catch err
                this.HandleError("Error creating big number display", err);
            end
        end

        %% OnFigureClosed
        function OnFigureClosed(this)
            this.Log("Debug", "Coak View closed", "Yellow", "Closing");
            this.TimingLoopController.CloseTimer();
            this.InstrumentController.CloseAll();
        end

        %% OnLoaded
        function OnLoaded(this)
            %Display a status message in the logger
            this.Log("Info", "CoakView loaded", "Green", "Ready");

            try
                %Let the user interact with the GUI now it is loaded and ready
                this.View.UnlockInput();
            catch err
                this.HandleError("Error unlocking input in Controller.OnLoaded", err);
            end
        end

        %% OnMeasurementsStopped
        function OnMeasurementsStopped(this)
            this.InstrumentController.CloseAll();
        end

        %% OpenDataViewer
        function OpenDataViewer(this)
            try
                defaultDataPath = this.DefaultDataDir;
                extensions = this.FileWriteDetails.FileExtension;
                DataViewer("DefaultDir", defaultDataPath, "FileExtensions", extensions);
            catch err
                this.HandleError("Error opening DataViewer", err);
            end
        end

        %% OpenSequenceEditor
        function OpenSequenceEditor(this)
            try
                %Create a SequenceViewerController
                this.SequenceEditorController = CoakView.Sequence.SequenceEditorController(...
                    this,...
                    "DefaultSequenceDirectory", this.PathSettings.DefaultSequenceDirectory,...
                    "SequenceFileExtension", this.PathSettings.SequenceFileExtension);

                %Add a View/GUI to that
                this.SequenceEditorController.CreateView("SequenceEditor_DefaultGUI", this.ApplicationDir);

            catch err
                this.HandleError("Error opening Sequence Viewer", err);
            end
        end       

        %% PlotterAxesSelectionChange
        function PlotterAxesSelectionChange(this, pltr)
            %This is needed for the case where we want to change the
            %displayed data in a Plotter, but the loop is not running.
            %While measurement loop is running, the Plotter will get an
            %Update call with new data every tick, and if it has
            %established that a button has been pressed and it needs to
            %e.g. change the data plotted on a y axis, it sets a bool flag
            %to do a plot refresh next update tick. If there are no ticks
            %this does not happen, so in that case, we hook into the
            %Plotter's event and fire a manual replot in the case that
            %measurements are stopped
            if this.TimingLoopController.State ~= "Running"
                %Have to pass whole data table back in - Plotters do not
                %store/copy these, that would be very expensive.
                %If the data table is empty, for now just do nothing -
                %might be clearer UX to clear the plot, but then again
                %might be annoying to delete the data for no obvious reason
                if ~isempty(this.DataTable)
                    pltr.PlotData(this.DataTable);
                end
            end
        end       

        %% RegisterPlotterObject
        function RegisterPlotterObject(this, pltr)
            try
                %Add the plotter panel grid to the list of plotters
                if(isempty(this.PlottingPanels))
                    this.PlottingPanels = {pltr};
                else
                    this.PlottingPanels = [this.PlottingPanels, {pltr}];
                end

                %Update the variables avaliable to the plotter
                pltr.UpdateVariables(this.Headers);
            catch err
                this.HandleError("Error registering plotter object", err);
            end
        end

        %% RegisterPlotterTab
        function RegisterPlotterTab(this, tab)
            try
                %Add the tabs to the list of tracked plotter tabs. Just for
                %cleaning up later and to monitor if we have at least one
                %on programme Run
                if(isempty(this.PlottingTabs))
                    this.PlottingTabs = {tab};
                else
                    this.PlottingTabs = [this.PlottingTabs, {tab}];
                end

            catch err
                this.HandleError("Error registering plotter tab", err);
            end
        end

        %% RemoveInstrument
        function RemoveInstrument(this, instrRef)
            try
                %Store this, as we won't be able to retrieve it after deleting
                %the object
                instName = instrRef.Name;
                % Pass on to Instrument Controller
                this.InstrumentController.RemoveInstrument(instrRef);


                %Verbose/debug message printing
                this.Log("Info", "Removed Instrument: " + instName, "Green", "Removed Instrument");

            catch err
                this.HandleError("Error removing instrument " + instrRef.Name, err);
            end
        end

        %% RemoveInstrumentControl
        function RemoveInstrumentControl(this, instrRef, controlDetailsStruct)
            try
                this.InstrumentController.RemoveInstrumentControl(instrRef, controlDetailsStruct);
                this.View.RemoveTab(controlDetailsStruct.TabName);

                %Update the View
                this.View.OnControlDisabled(controlDetailsStruct.Name);

                %Verbose/debug message printing
                this.Log("Info", "Removed Instrument Control: " + controlDetailsStruct.Name, "Green", "Removed Instrument Control");
            catch err
                this.HandleError("Error removing instrument control " + controlDetailsStruct.Name, err);
            end
        end

        %% SavePlot
        function SavePlot(this, eventData)
            try
                fig = eventData.Figure;
                this.DataWriter.SaveFigure(fig, this.FileWriteDetails.Directory, this.FileWriteDetails.FileName);

                %Display a status message in the logger
                this.Log("Info", "Plot saved", "Green", "Plot saved");
            catch err
                this.HandleError("Error saving figure", err);
            end
        end

        %% SetFilePathsDirectory
        function SetFilePathsDirectory(this, directory)
            try
                this.FileWriteDetails.Directory = CoakView.Utilities.FileLoading.PathUtils.CleanPath(directory);

                %Update the View
                this.View.OnFileWriteOptionsChanged(this.FileWriteDetails);
            catch err
                this.HandleError("Error in SetFilePathsDirectory", err);
            end
        end

        %% SetFilePathsFileExtension
        function SetFilePathsFileExtension(this, fileExtension)
            try
                this.FileWriteDetails.FileExtension = fileExtension;

                %Pass through to View
                this.View.OnFileWriteOptionsChanged(this.FileWriteDetails);
            catch err
                this.HandleError("Error in SetFilePathsFileExtension", err);
            end
        end

        %% SetFilePathsDescription
        function SetFilePathsDescription(this, descriptionText)
            try
                this.FileWriteDetails.DescriptionText = descriptionText;

                %Pass through to View
                this.View.OnFileWriteOptionsChanged(this.FileWriteDetails);
            catch err
                this.HandleError("Error in SetFilePathsDescription", err);
            end
        end

        %% SetFilePathsFileName
        function SetFilePathsFileName(this, fileName)
            try
                %Make sure the filename doesn't have an extra file extension
                %included by user by mistake - we will add an extension on
                fileNameNoExt = CoakView.Utilities.FileLoading.PathUtils.StripExtension(fileName);

                %Helpfully replace <DATE> tag with today's actual date
                fileNameDateRp = CoakView.Utilities.FileLoading.PathUtils.ReplaceDateTag(fileNameNoExt);

                %Set the variable
                this.FileWriteDetails.FileName = fileNameDateRp;

                %Pass through to View
                this.View.OnFileWriteOptionsChanged(this.FileWriteDetails);
            catch err
                this.HandleError("Error setting file name", err);
            end
        end

        %% SetFilePathsSaveFileBool
        function SetFilePathsSaveFileBool(this, saveFileBool)
            try
                this.FileWriteDetails.SaveFile = saveFileBool;

                %Pass through to View
                this.View.OnFileWriteOptionsChanged(this.FileWriteDetails);
            catch err
                this.HandleError("Error setting save file bool", err);
            end
        end

        %% SetFilePathsWriteMode
        function SetFilePathsWriteMode(this, writeMode)
            try
                this.FileWriteDetails.WriteMode = writeMode;

                %Pass through to View
                this.View.OnFileWriteOptionsChanged(this.FileWriteDetails);
            catch err
                this.HandleError("Error setting write mode", err);
            end
        end

        %% ShowMessageInGUI
        function ShowMessageInGUI(this, colour, msg)
            %Note, this is for the moment deliberately seperate from the
            %ShowStatus call, even though it just calls that and nothing
            %else - this will be called from the Logger, and we might later
            %want to show messages from there in the GUI in different ways.
            this.ShowStatus(colour, msg);
        end

        %% ShowStatus
        function ShowStatus(this, colour, msg)
            switch(colour)
                case('Green')
                    this.View.ShowGreenStatus(msg);
                case('Yellow')
                    this.View.ShowYellowStatus(msg);
                case('Red')
                    this.View.ShowRedStatus(msg);
                otherwise
                    error('Colour unsupported in ShowStatus');
            end
        end
        
    end

    methods(Access=private)   

        %% AppendToDataTable
        function AppendToDataTable(this, dataRow)

            if isempty(this.DataTable)
                this.DataTable = dataRow;
            else
                this.DataTable = [this.DataTable; dataRow];
            end
        end

        %% CleanUpPlotters
        function CleanUpPlotters(this)
            %Remove any plotters that may have been deleted (as part of
            %e.g. an InstrumentControl tab that has been deleted from the
            %GUI), from the list to update
             for i = length(this.PlottingPanels) : -1 : 1
                 if ~isvalid(this.PlottingPanels{i})
                     this.PlottingPanels(i) = [];
                 end
             end
        end

        %% ClearPlots
        function ClearPlots(this)
            for i = 1 : length(this.PlottingPanels)
                this.PlottingPanels{i}.ClearData();
            end
        end              

        %% CreateInstrumentControlTab
        function tab = CreateInstrumentControlTab(this, tabName)
            tab = this.View.CreateInstrumentControlTab(tabName);
        end

        %% FinalisePreset
        function FinalisePreset(this)
            %Display a status message in the logger
            this.ShowStatus('Yellow', 'Finalising Preset');

            %Called once the preset changes are all applied, to do final
            %housekeeping like refreshing UI
            this.View.FinalisePreset();
        end     

        %% LoadSettings
        function [logSettings, pathSettings, windowSettings, plotterSettings] = LoadSettings(this)
            %Load the settings file into struct
            configIO = CoakView.Utilities.FileLoading.ConfigIO();
            settingsStruct = configIO.LoadConfig();

            %Parse the entries neatly into the PathSettings struct property
            logSettings = settingsStruct.LogSettings;
            pathSettings = settingsStruct.PathSettings;
            windowSettings = settingsStruct.WindowSettings;
            plotterSettings = settingsStruct.PlotterSettings;

            %Make relative path if specified
            if(pathSettings.DataDirectoryIsRelativePath)
                pathSettings.DefaultDirectory = fullfile(this.ApplicationDir, pathSettings.DefaultDirectory);
            end
            if(logSettings.LogFileDirectoryIsRelativePath)
                logSettings.LogFileDirectory = fullfile(this.ApplicationDir, logSettings.LogFileDirectory);
            end
            if(pathSettings.SequenceDirectoryIsRelativePath)
                pathSettings.DefaultSequenceDirectory = fullfile(this.ApplicationDir, pathSettings.DefaultSequenceDirectory);
            end
   
            %Clean the paths up, removing extra \\..\\.. loops etc
            pathSettings.DefaultDirectory = CoakView.Utilities.FileLoading.PathUtils.CleanPath(pathSettings.DefaultDirectory);
            logSettings.LogFileDirectory = CoakView.Utilities.FileLoading.PathUtils.CleanPath(logSettings.LogFileDirectory);
            pathSettings.DefaultSequenceDirectory = CoakView.Utilities.FileLoading.PathUtils.CleanPath(pathSettings.DefaultSequenceDirectory);

            %Verify that the DefaultDirectory exists - if it doesn't, try to make that folder. If that fails, set to a fallback
            %and warn user.
            if(~isfolder(pathSettings.DefaultDirectory))
                %Show a warning in the command window
                disp("Could not find directory " + pathSettings.DefaultDirectory + " specified in the config file. Creating new directory.");

                try
                    %Create the folder
                    mkdir(pathSettings.DefaultDirectory);

                    %Assert the creation was successful
                    assert(isfolder(pathSettings.DefaultDirectory), "Folder not found at path");
                catch exception
                    %Warn the user
                    warning("Could not find directory " + pathSettings.DefaultDirectory + " specified in the config file, and hit an error while trying to create it. Reverting to fallback for default directory. Error message: " + string(exception.message));
                    
                    %User folder eg c:/Matt/
                    userDir = fullfile(getenv('USERPROFILE'));

                    %Set the Default Dir
                    pathSettings.DefaultDirectory = userDir;
                    
                end
            end
        end

        %% PlotData
        function PlotData(this, newDataRow)
            %Check for any plotters that may have been closed by a
            %discourteous user - remove them from the list of plotters to
            %update if so.
            for i = length(this.PlottingPanels) : - 1 : 1
                if(~isvalid(this.PlottingPanels{i}))
                    this.PlottingPanels(i) = [];
                end
            end

            for i = 1 : length(this.PlottingPanels)
                pltr = this.PlottingPanels{i};

                %If possible, just append the new row of data to the
                %existing plot (for speed). If e.g. the axis selections
                %have changed on this Plotter and it needs a full refresh,
                %the TryAppendData call will return false and we should
                %call the full UpdatePlot method instead
                if(~pltr.TryAppendData(newDataRow))
                    pltr.PlotData(this.DataTable);
                end
            end
        end

        %% UpdateBigNumberDisplays
        function UpdateBigNumberDisplays(this, newDataRow)

            if isempty(this.BigNumDisplays)
                return;
            end

            %Check for any displays that may have been closed by a
            %discourteous user - remove them from the list of displays to
            %update if so.
            for i = length(this.BigNumDisplays) : - 1 : 1
                if(~isvalid(this.BigNumDisplays(i)))
                    this.BigNumDisplays(i) = [];
                end
            end

            for i = 1 : length(this.BigNumDisplays)
                bnd = this.BigNumDisplays(i);

                bnd.UpdateValue(newDataRow);
            end
        end

        %% UpdatePlotVariableNames
        function UpdatePlotVariableNames(this, varNames)
            for i = 1 : length(this.PlottingPanels)
                this.PlottingPanels{i}.UpdateVariables(varNames);
            end
        end

        %% ValidateInstall
        function ValidateInstall(this)
            try
                %Make sure user has the required matlab version first of all
                CoakView.Utilities.ErrorChecking.Verification.VerifyMatlabVersion("R2025b");
            catch err
                this.HandleError('Matlab version out of date! Cannot run.', err)
            end

            try
                %Make sure the user has the required toolboxes installed
                CoakView.Utilities.ErrorChecking.Verification.VerifyToolboxInstalled('Instrument Control Toolbox');

                %Log some information
                CoakView.Logging.Logger.Log("Debug", "Installation verified");
            catch err
                this.HandleError('Required Matlab Toolbox not installed, please install Toolbox', err)
            end
        end

    end

end

