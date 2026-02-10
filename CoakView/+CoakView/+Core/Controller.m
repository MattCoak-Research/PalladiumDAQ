classdef Controller < handle
    %CONTROLLER Logic and measurement loop for CoakView Programme. This is
    %the Model, the GUI frontend is the view - doesn't actually do
    %anything, passes commands through to here

    properties
        %Reference to the main figure window / GUI / View Implementation
        View;

        %Paths and Directories
        ApplicationPath;    %These will be set in StartUp Fcn of the UiFigure
        ApplicationDir;     %These will be set in StartUp Fcn of the UiFigure


        Instruments;

        ErrorOnAllInstrumentErrors = false; %Note - gets set in LoadSettings from the Config.json file's value, overriding a value here. If this is set to true, a full error will be thrown every time an instruments fails to return data. Default (false) is to throw warnings and pad datafile with NaNs instead. Testing has shown that very rare communication errors do happen, and it's a shame to lose the whole experiment because a magnet not being used didn't return 0 properly..
    end

    properties(GetAccess = public, SetAccess = private)
        %Settings structs
        WindowSettings;
        PathSettings;
        PlotterSettings;

        %Data array
        DataTable;

        TargetUpdateTime = 0.2; %in s
    end

    properties(Access = private)
        State = categorical("Ready", ["Running", "Ready", "Pausing", "Stopping", "Paused"]);
        Timer;

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
        PresetsDirectory = "\+CoakViewPresets";
    end

    events
        Started;
        Paused;
        Resumed;
        Stopped;
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

            this.View.Controller = this;
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
                %their GUI controls programmtically - we want the name to
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

        %% GetPresetsDir
        function dirPath = GetPresetsDir(this)
            dirPath = fullfile(this.ApplicationDir,  this.PresetsDirectory);
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
                this.ErrorOnAllInstrumentErrors = logSettings.ErrorOnAllInstrumentErrors;

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
                this.InitialisePlugins();

                %Create a Timer object that will schedule all the
                %measurement loop calls
                this.Timer = timer('TimerFcn', @this.Update, 'ExecutionMode', 'fixedRate', 'Period', 0.1, 'ObjectVisibility','off');

                %Display a status message in the logger
                this.Log("Info", "Ready", "Green", "Ready");
            catch err
                this.HandleError('Initialisation error in applying loaded Settings (Controller.Initialise)', err);
            end
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

                    %Prevent the display being sent to teh back of the tab
                    %stack and everything minimising..
                    this.RefocusWindow();
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
            this.Timer.stop();
            delete(this.Timer);
            this.CloseAll();
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

        %% OpenDataViewer
        function OpenDataViewer(this)
            try
                defaultDataPath = this.DefaultDataDir;
                extensions = this.FileWriteDetails.FileExtension;
                dv = DataViewer("DefaultDir", defaultDataPath, "FileExtensions", extensions);
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

        %% Pause
        function Pause(this)
            %Display a status message in the logger
            this.ShowStatus("Yellow", "Pausing");

            this.State = "Pausing";
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
            if this.State ~= "Running"
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

        %% RefocusWindow
        function RefocusWindow(this)
            %Bring the window back to the front, after a filedialog or similar
            % Calling uigetfile or similar modal dialogs may send the app to the back.
            % Bring it back to the front. Also loses maximised state etc (argh!). Save current window state and restore it.
            this.View.RefocusWindow();
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

        %% Resume
        function Resume(this)
            %Similar to Start - but we don't clear anything first, just get
            %the measurement loop running again
            this.State = "Running";
            this.RunMeasurementLoop();
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
                fileNameDateRp = this.ReplaceDateTag(fileNameNoExt);

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

        %% SetUpdateTime
        function SetUpdateTime(this, targetTime_s)
            try
                %Need to stop the timer, change the period, then restart it -
                %get an error if we try to change the period while it is
                %running
                if(strcmp(this.Timer.Running, 'on'))
                    this.Timer.stop();
                    this.Timer.Period = targetTime_s;
                    this.Timer.start();
                else
                    this.Timer.Period = targetTime_s;
                end

                this.TargetUpdateTime = targetTime_s;

                %Update the View to reflect the change
                this.View.OnTargetUpdateTimeChanged(targetTime_s);
            catch err
                this.HandleError("Error setting update time", err);
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

        %% Start
        function Start(this)

            %Create a DataWriter object to log all data
            this.DataWriter = CoakView.DataWriting.DataWriter(this.FileWriteDetails);
            this.FileWriteDetails.FileName = this.DataWriter.ValidateFilePath();

            %Update the View to display the file write settings
            this.View.OnFileWriteOptionsChanged(this.FileWriteDetails);

            %Clean up Plotters list, remove any that have been deleted
            this.CleanUpPlotters();

            if(this.CanStart)
                this.OnStarted();
                [success, msg, title] = this.InitialiseMeasurements();
                if success
                    this.RunMeasurementLoop();
                else
                    %We get to here if we failed to connect to an
                    %instrument. We have already disconnected from all the
                    %ones we did manange to connect to. Now abort instead
                    %of starting the measurement loop, show a warning, and
                    %return to the Ready state
                    this.AbortStart(msg, title);
                end
            else
                %Abort and warn that we couldn't start - in fact should it
                %even be possible to get here if so?
                this.AbortStart("Could not start, aborting. Controller.CanStart was false, this really shouldn't have been possible..", "Intialisation failed");
            end
        end

        %% Stop
        function Stop(this)
            %Pressing the stop button sets the State to 'Stopping' only. Current loop
            %iteration will complete, then CloseAll will be called, and THERE
            %all instruments can be stopped.
            this.StopMeasurements();
        end
    end

    methods(Access=private)
   
        %% AbortStart
        function AbortStart(this, msg, title)
            %abort instead starting the measurement loop, show a warning, and return to the Ready state

            %Display a status message in the logger
            this.Log("Info", "Initialisation aborted", "Red", "Initialisation aborted");

            %Build out full string to print
            msg = msg + "\n\nInitialisation has been aborted.";

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

            this.OnStopped();
        end

        %% AppendToDataTable
        function AppendToDataTable(this, dataRow)

            if isempty(this.DataTable)
                this.DataTable = dataRow;
            else
                this.DataTable = [this.DataTable; dataRow];
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
                this.HandleError('Invalid file path. Cannot start measurements', err);
                return;
            end

            canStart = true;
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

        %% CloseAll
        function CloseAll(this)

            %Display a status message in the logger
            this.Log("Info", "Closing Instruments", "Yellow", "Closing Instruments");

            %Close all instruments
            for i = 1 : length(this.Instruments)
                this.Instruments{i}.Close();
            end

            %Display a status message in the logger
            this.Log("Info", "Instruments closed", "Green", "Instruments closed");
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
                        %Show error message and ask if we want to stop measurements
                        halt = this.HandleError("Error in main measurement loop - Collect Data from " + this.Instruments{i}.FullName, e);
                        if(halt)
                            CoakView.Logging.Logger.Log("Info", "Measurements aborted by User from Error Dialogue");
                            this.Stop();
                            this.OnStopped();
                        end
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
                    this.Instruments{i}.FileWriteDetails = this.FileWriteDetails;
                catch e
                    %Just show a warning, do not halt execution
                    reportStr = string(e.message);
                    CoakView.Logging.Logger.Log("Warning", "Last dataRow update call to instrument " + this.Instruments{i}.Name + " failed in CollectMeasurement. Error message: " + reportStr);

                end
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

        %% InitialiseMeasurements
        function [success, msg, title] = InitialiseMeasurements(this)
            %Reset and prepare all GUI and instruments ready to then run
            %the main update loop - note that Resume doesn't call this,
            %just gets the loop running again without it

            success = false;
            msg = "";
            title = "";

            %Display a status message in the logger
            this.Log("Info", "Initialising measurements", "Yellow", "Initialising measurements");

            %Display a model progress bar so we can't go clicking things
            %while intialisation is underway - and also get clued in that a
            %slow operation is in fact running and we shouldn't click Start
            %100 times like my dad
            this.View.ShowProgressBar("Initialising measurements", "Initialising..");

            try
                %Set the list of instruments from the selection panel's ItemData
                this.Instruments = this.InstrumentController.GetInstruments();

                %Generate column headers, for internal use and file writing
                [this.Headers, headersString, this.Units] = this.GetHeaders();

                %Verify that those headers are valid - no duplicates
                [duplicateHeaderValues, duplicateHeaderValuesString] = CoakView.Core.Controller.CheckForDuplicatesInHeadersArray(this.Headers);
                assert(isempty(duplicateHeaderValues), "Some variable names appear twice, this is not allowed. Duplicate variables: " + duplicateHeaderValuesString);
                    

                %Initialise the (:, n) double array that will hold the
                %data
                this.DataTable = [];

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

                metadataLines = [];
                for i = 1 : length(this.Instruments)
                    metadataNullableString = this.Instruments{i}.GrabMetadataString();
                    if ~isempty(metadataNullableString)
                        metadataLines = [metadataLines metadataNullableString];
                    end
                end

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

        %% InitialisePlugins
        function InitialisePlugins(this)
            %Display a status message in the logger
            this.Log("Debug", "Initialising plugins", "Yellow", "Initialising plugins...");

            %Create a helper class for managing Instruments
            this.InstrumentController = CoakView.Core.InstrumentController(this, this.View);

            % Load instrument classes into the instrument selection panel
            this.InstrumentController.LoadInstrumentClasses(this.ApplicationDir + "\+CoakView\+Instruments");


            %Log some information
            this.Log("Debug", "Plugins intialised", "Green", "Plugins intialised");
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


        %% OnPaused
        function OnPaused(this)
            %Called from the main loop after "Pausing" state has been set
            %by GUI event calls, and then the update loop has passed
            %through again to here. Stop the timer and basically halt
            %measurements - but we won't clear everything upon Resuming,
            %unlike Stop/Start
            this.Timer.stop();
            this.State = "Paused";

            %Log some information
            this.Log("Debug", "Measurements paused", "Yellow", "Paused");

            %Update the View
            this.View.OnPaused();

            %Fire event
            notify(this, "Paused");
        end

        %% OnResumed
        function OnResumed(this)
            %Log some information
            this.Log("Debug", "Measurements resumed", "Green", "Running");

            this.State = "Running";
            this.RunMeasurementLoop();

            %Update the View
            this.View.OnResumed();

            %Fire event
            notify(this, "Resumed");
        end

        %% OnStarted
        function OnStarted(this)
            this.State = "Running";

            %Update the View
            this.View.OnStarted();

            %Fire event
            notify(this, "Started");
        end

        %% OnStopped
        function OnStopped(this)
            this.Timer.stop();
            this.CloseAll();
            this.State = "Ready";

            %Log some information
            this.Log("Info", "Measurements stopped", "Green", "Ready");
            this.ShowStatus("Green", "Ready");

            %Update the View
            this.View.OnStopped();

            %Fire event
            notify(this, "Stopped");
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

        %% ReplaceDateTag
        function outstr = ReplaceDateTag(~, str)
            %If a string has '<DATE>' in it, let's replace that with today's
            %date for convenience
            d = datetime;
            format = 'yyyy-MM-dd';
            dateStr = string(d, format);  %Today's date

            outstr = strrep(str, '<DATE>', dateStr);
        end

        %% RunMeasurementLoop
        function RunMeasurementLoop(this)
            %Display a status message in the logger
            this.Log("Info", "Measurement Loop started", "Green", "Running");

            %Start the Timer object that calls the loop updates
            this.Timer.start();
        end

        %% StopMeasurements
        function StopMeasurements(this)
            %Pressing the stop button sets the State to 'Stopping' only. Current loop
            %iteration will complete, then CloseAll will be called, and THERE
            %all instruments can be stopped.

            %Display a status message in the logger           
            this.Log("Info", "Measurement Loop Stopping...", "Yellow", "Stopping measurements");

            
            if strcmp(this.State, "Paused") || strcmp(this.State, "Pausing")
                %If we are currently paused, the timer is suspended and
                %there will be no update calls, so Stop will never
                %properly fire. Call it manually here.
                this.State = "Stopping";
                this.OnStopped();
            else                
                %Normal behaviour - mark the programme as due to stop on
                %the next update tick
                this.State = "Stopping";
            end
        end

        %% Update
        function Update(this, ~, ~)
            %Execute one 'tick' of the measurement loop - poll each
            %instrument for one row of data, update all GUI and plots. This
            %keeps running, triggered async off a Timer object, until state
            %is changed to Pausing or Stopping by Pause or Stop events

            %Process GUI events like button presses and force the async
            %timer to check in with the GUI - get hangs without this if
            %update time is set too short
            drawnow();

            try
                %Check for exit conditions from the measurement loop - are we
                %trying to Pause or Stop the loop?
                switch(this.State)
                    case("Stopping")
                        this.OnStopped();
                    case("Pausing")
                        this.OnPaused();
                end
            catch e
                CatchMeasurementLoopError(this, e);
            end

            switch(this.State)
                case("Running")
                    try
                        %Collect Data
                        this.ShowStatus("Green", "Running");
                        dataRow = this.CollectMeasurement();
                    catch e
                        CatchMeasurementLoopError(this, e);
                        %Need to do something here to keep programme running when
                        %CollectMeasurement errors - set the dataRow to NaNs.
                        dataRow = nan([1, length(this.Headers)]);
                        this.Log("Warning", "Data Row set to NaN values due to error thrown in CollectMeasurements", "Yellow", "Data Row set to NaN values due to error thrown in CollectMeasurements");
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

                    try
                        %Update the time elapsed this frame in the GUI
                        elapsedTimeSinceLastTick_s = this.Timer.InstantPeriod;
                        this.View.DisplayUpdateTime(elapsedTimeSinceLastTick_s);
                    catch e
                        CatchMeasurementLoopError(this, e);
                    end
                    
                otherwise
                    %Do nothing if not Running
                    
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
                    this.Timer.stop();
                    delete(this.Timer);
                    return;
                else
                    %Show error message and ask if we want to stop measurements
                    halt = this.HandleError("Error in main measurement loop", e);
                    if(halt)
                        CoakView.Logging.Logger.Log("Info", "Measurements aborted by User from Error Dialogue");
                        this.OnStopped();
                    end
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

    methods(Static)    

        %% CheckForDuplicatesInHeadersArray
        function [duplicates, combinedString] = CheckForDuplicatesInHeadersArray(headers)
            combinedString = "";
            duplicates = [];

            %handle edge cases
            if isempty(headers)
                return;
            end
            if length(headers) < 2
                disp("length less tha 2");
                 return;
            end

            % Find the indices of the unique strings
            [~, uniqueIdx] =unique(headers);

            % Copy the original into a duplicate array
            duplicates = headers;
            
            % remove the unique strings, anything left is a duplicate
            duplicates(uniqueIdx) = [];
            
            % find the unique duplicates
            duplicates = unique(duplicates);

            for i = 1 : length(duplicates)
                if i == 1
                    combinedString = combinedString + string(duplicates(i));
                else
                    combinedString = combinedString + ", " + string(duplicates(i));
                end
            end
        end

    end
end

