classdef Controller < handle
    %Controller - Central logic class of a Palladium DAQ instance, which runs with or without a GUI.
    %`Palladium.m` creates one Controller, attaches the View (the GUI) to it
    %with `AttachView`, then calls `Initialise` and, once everything is set
    %up, `OnLoaded`. Nothing here needs a View: `Palladium(View=[])` runs
    %headless, with the Controller alone.
    %
    %The work is shared out between sub-controllers, which the Controller
    %creates in its constructor and owns:
    %
    %* `InstrumentController` - adds, connects and closes instruments, loads
    %  the instrument classes available (MATLAB and Python), and collects
    %  each tick's measurements and the data column headers.
    %* `TimingLoopController` - the measurement loop: Start, Pause, Resume
    %  and Stop, and a timer that calls `Measure` every tick.
    %* `CommandController` - queues instrument commands and sequences, and
    %  runs them at the start of each tick.
    %* `PlottingController` (private) - creates the plotters (`AddNewPlotter`)
    %  and updates them with new data.
    %* `SequenceEditorController` (private) - the Sequence Editor, whose
    %  queued commands and sequences are passed on to the CommandController.
    %* `DataWriter` - writes the data file. A new one is made by
    %  `InitialiseDataWriting` each time measurements start.
    %
    %**Settings and user files.** `Initialise` loads the config file (see
    %`ConfigIO`), starts the Logger, creates the user files folder and its
    %subfolders, copies starter files (templates, the example Preset) into
    %them, sets up Python instruments and loads the instrument classes.
    %
    %**Measuring.** `TimingLoopController.Start` calls `InitialiseDataWriting`,
    %`CanStart` and `InitialiseMeasurements`, then the timer calls `Measure`
    %each tick: run queued commands, collect a data row, write it to the
    %file, add it to `DataTable` and update the plots.
    %
    %**Errors and warnings.** `HandleError` logs an error and shows the error
    %dialogue, where the user can stop the measurements or suppress the
    %message. `HandleCallbackError` is the entry point for errors caught in
    %GUI callbacks, event listeners and the measurement loop: the Controller
    %registers itself as `ErrorGuard.DefaultController`, and guards its own
    %listeners with `ErrorGuard.AddListener`. `HandleWarning` shows a warning
    %box.
    %
    %**Events.** The View listens to the Controller's events to show status
    %messages (`GreenStatus`, `YellowStatus`, `RedStatus`), progress bars,
    %the file write options, the loaded settings and new data rows. The View
    %calls back in through the public methods, such as the `SetFilePaths...`
    %setters, `LoadPreset`, `OpenSequenceEditor` and `OpenHelp`.

    %% Properties (Constant, Private)
    properties(Constant, Access = private)
        PythonInstrumentNamespace = "PythonInstruments";    %Namespace folder of the user's Python instruments, in the user files folder
        UserFolderName = "Palladium DAQ - User Files";      %Name of the user files folder, created inside UserFilesDir
        UserInstrumentFolderName = "+Palladium" + filesep + "+Instruments";    %Folder of the user's MATLAB instrument drivers, in the user files folder - so they are in the Palladium.Instruments namespace
        UserPresetFolderName = "Presets";                   %Folder of Preset .json files, in the user files folder
        UserInstrumentDriversFolderName = "Instrument Drivers"; %Folder for vendor driver files (e.g. dlls), in the user files folder - added to the MATLAB path with its subfolders on start
    end

    %% Properties (Public)
    properties (Access = public)
        ApplicationDir;     %Folder Palladium DAQ runs from: the folder of Palladium.m, or of PalladiumDAQ.exe in an installed app
        UserFilesDir;       %Folder that holds the user files folder ("Palladium DAQ - User Files"), from PathSettings.UserFilesDirectory in the config
    end

    %% Properties (Public, Private Set)
    properties(GetAccess = public, SetAccess = private)
        WindowSettings;     %WindowSettings section of the config, plus PalladiumIconPath (the windows' icon, or [] if not found), set in Initialise
        PathSettings;       %PathSettings section of the config, with relative paths made absolute, set in Initialise
        FileWriteDetails;   %Data file settings: Directory, FileName, FileExtension, DescriptionText, SaveFile and WriteMode - change them with the SetFilePaths... methods

        DataTable;          %All data rows measured since measurements started, one row per tick, with columns as in Headers
        Headers = {};       %Data column headers of all the instruments, set when measurements start
        Units = {};         %Units of the data columns, matching Headers

        TimingLoopController;   %Runs the measurement loop (Start, Pause, Resume, Stop), calling Measure every tick
        InstrumentController;   %Adds, connects and closes instruments, and collects their measurements
        CommandController;      %Queues instrument commands and sequences, run at the start of each tick
        DataWriter;             %Writes the data file - a new one is made by InitialiseDataWriting each time measurements start

        UserInstrumentsDir;         %The user files folder's +Palladium/+Instruments folder, for MATLAB instrument drivers - empty in the installed app
        UserPythonInstrumentsDir;   %The user files folder, which holds the PythonInstruments namespace folder of Python instruments
        UserPresetsDir;             %The user files folder's Presets folder
        UserInstrumentDriversDir;   %The user files folder's Instrument Drivers folder, for vendor driver files such as QDInterface.dll
    end

    %% Properties (Private)
    properties(Access = private)
        PlottingController;         %Creates the plotters and updates them with new data each tick
        SequenceEditorController;   %Runs the Sequence Editor, whose queued commands and sequences go to the CommandController

        ConfigFilePath = "";        %Path of the config file in use
        HeadersString = "";         %Column header line of the data file, set when measurements start
        PythonSettings;             %PythonSettings section of the config
        PythonSetupStatus = [];     %Result of setting up Python (see PythonUtils.CheckPythonSetup), set in Initialise
        WarningSettings;            %WarningSettings section of the config

        DebugMode = false;          %Set by Palladium(DebugMode=true) for debugging - passed to the CommandController, which then logs each command it runs
        DefaultDataDir;             %Folder the Data Viewer opens in: PathSettings.DefaultDirectory

        Closing = false;            %Set by OnFigureClosed when the GUI closes, so errors no longer go to the now-invalid GUI

        SuppressedErrorMessages = {};   %Error messages the user chose to suppress in the error dialogue, until Palladium DAQ is restarted
        ErrorDialogOpen = false;    %True while an error dialogue is showing, so further errors get logged without stacking more dialogues
        UIFigureHandle = [];        %The main GUI window, set by RegisterUIFigure - error dialogues and warnings are shown in it, or free-floating if there is none
    end

    %% Events
    events
        DataRowUpdated;             %Raised each tick with the new data row and the headers (DataRowAddedEventData), e.g. for Big Number Displays
        FileWriteOptionsChanged;    %Raised when FileWriteDetails changes, with the new details (ValueChangedEventData), for the View to show
        FinalisePreset;             %Raised by Palladium.LoadPreset once a Preset has been applied, for the View to update to match
        GreenStatus;                %Status message for the GUI's status strip, with a green light: all is well (MessageEventData)
        Loaded;                     %Raised by OnLoaded once start-up has finished, for the View to let the user interact
        RedStatus                   %Status message for the GUI's status strip, with a red light: an error (MessageEventData)
        SettingsApplied;            %Raised by Initialise with the path and window settings (SettingsChangedEventData), for the View to apply
        StartedShowingProgress;     %Raised to show a progress bar, with its message and title (MessageEventData)
        StoppedShowingProgress;     %Raised to close the progress bar
        UpdatedProgress;            %Raised to move the progress bar on, with the fraction done and a message (ProgressUpdateEventData)
        YellowStatus;               %Status message for the GUI's status strip, with a yellow light: busy, or a warning (MessageEventData)
    end

    %% Constructor
    methods
        function this = Controller(Settings)
            %Create the sub-controllers and connect their events to each other.
            %Called by `Palladium.m`. Settings are not loaded until
            %`Initialise`. Also registers this Controller as
            %`ErrorGuard.DefaultController`, where errors from GUI callbacks go
            %
            %Inputs (name-value):
            %   ApplicationDir - folder Palladium DAQ runs from (see the ApplicationDir property)
            %   DebugMode      - true to log each command the CommandController runs. Default false
            arguments
                Settings.ApplicationDir {mustBeTextScalar};
                Settings.DebugMode (1,1) logical = false;
            end

            this.DebugMode = Settings.DebugMode;

            %Register as the default place for GUI callback errors to go - see ErrorGuard.HandleError
            Palladium.Core.ErrorGuard.DefaultController(this);

            this.ApplicationDir = Settings.ApplicationDir;

            %Create a helper class for managing Instruments
            this.InstrumentController = Palladium.Core.InstrumentController(this);

            %Create a helper class for controlling the main
            %measurement/timing loop, Start/Pause/Resume etc
            this.TimingLoopController = Palladium.Core.TimingLoopController(this);

            %And one for handling all things Plotting
            this.PlottingController = Palladium.Core.PlottingController();

            %And a controller for handling sending arbitrary instrument
            %commands and sequences
            this.CommandController = Palladium.Core.CommandController(DebugMode = this.DebugMode);

            %Create a SequenceViewerController
            this.SequenceEditorController = Palladium.Sequence.SequenceEditorController();
            this.SequenceEditorController.Controller = this;

            %Hook up events
            %(Guarded, so that errors in the handlers are caught and
            %handled instead of just becoming warnings - see ErrorGuard)
            Palladium.Core.ErrorGuard.AddListener(this.InstrumentController, "InstrumentsChanged", @(s,e)this.SequenceEditorController.InstrumentsChanged(e), Controller = this);
            Palladium.Core.ErrorGuard.AddListener(this.SequenceEditorController, "SingleCommandQueue", @(s,args)this.CacheInstrumentCommand(args.InstrumentRef, string(args.CommandString), args.ControlName, FunctionOnComplete = args.FunctionToRunOnComplete), Controller = this);
            Palladium.Core.ErrorGuard.AddListener(this.SequenceEditorController, "SequenceQueue", @(s,args)this.QueueSequence(args), Controller = this);
            Palladium.Core.ErrorGuard.AddListener(this.SequenceEditorController, "SequenceAbort", @(s, args)this.AbortSequence(), Controller = this);
            Palladium.Core.ErrorGuard.AddListener(this.CommandController, "CommandsFinished", @(s, args)this.SequenceEditorController.CommandsFinished(), Controller = this);
            Palladium.Core.ErrorGuard.AddListener(this.CommandController, "DataFileCommandRun", @(s, args)this.SetFilePathWhileRunning(args.FileWriteDetails.FullPath, args.FileWriteDetails.SaveFile), Controller = this);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function AbortSequence(this)
            %Abort the sequence running in the CommandController, when the Sequence Editor asks.

            this.CommandController.AbortSequence();
        end

        function pltr = AddNewPlotter(this, parent, parentFigure, Settings)
            %Create a Plotter, with axis dropdowns, in a GUI container such as a grid layout.
            %Used by the GUI's plot tabs and windows, and by Instrument
            %Controls that show a plot. A registered plotter is updated with
            %new data every tick; an unregistered one only shows what its
            %owner pushes to it. On error, shows the error dialogue
            %
            %Inputs:
            %   parent         - container to put the plotter in. Empty (the default) makes a new uifigure
            %   parentFigure   - uifigure to attach the plotter's context menu to. Empty (the default) uses the main window
            %   Size           - (name-value) "Medium" (the default), or another size the Plotter supports
            %   RegisterPlotter - (name-value) true (the default) to update the plotter with the data every tick
            %
            %Outputs:
            %   pltr - the new Plotter
            arguments
                this;
                parent = [];
                parentFigure = [];
                Settings.Size = "Medium";
                Settings.RegisterPlotter = true;
            end

            try
                %Create a new parent figure for the plotter to go in if we
                %didn't specify a parent
                if isempty(parent)
                    parent = uifigure();
                end

                %Work out which root uifigure to register context menu to
                if isempty(parentFigure)
                    cmParent = this.UIFigureHandle;
                else
                    cmParent = parentFigure;
                end

                %Get the Plotting Controller to actually construct the
                %plotter, add it to whatever parent we sent in. All of this
                %is View-agnostic, and doesn't need one at all.
                pltr = this.PlottingController.CreateNewPlotter(parent, Settings.Size);
                pltr.AttachContextMenu(cmParent);

                %Subscribe to events
                if Settings.RegisterPlotter
                    Palladium.Core.ErrorGuard.AddListener(pltr, 'AxesSelectionChange', @(src,evnt)this.PlotterAxesSelectionChange(src), Controller = this);
                end

                Palladium.Core.ErrorGuard.AddListener(pltr, 'SavePlot', @(src,evnt)this.SavePlot(evnt), Controller = this);

            catch err
                this.HandleError("Error adding new plotter", err);
                return;
            end

            %Register the plotter so it gets updated
            if Settings.RegisterPlotter
                try
                    this.PlottingController.RegisterPlotterObject(pltr, this.Headers);
                catch err
                    this.HandleError("Error registering plotter object", err);
                end
            end
        end

        function pltr = AddNewSimplePlotter(this, parent, size)
            %Create a SimplePlotter, which only plots what its owner sends it, in a GUI container.
            %A SimplePlotter is a barebones Plotter with no axis dropdowns,
            %and is never updated with the data rows. Used by the GUI and by
            %Instrument Controls that draw their own plots. On error, shows
            %the error dialogue
            %
            %Inputs:
            %   parent - container to put the plotter in, e.g. a grid layout
            %   size   - "Medium" (the default), or another size the Plotter supports
            %
            %Outputs:
            %   pltr - the new SimplePlotter
            arguments
                this;
                parent;
                size = "Medium";
            end

            try
                %Pass through to View to handle GUI stuff
                pltr = this.PlottingController.CreateNewSimplePlotter(parent, size);
                pltr.AttachContextMenu(this.UIFigureHandle);

                %Subscribe to events
                Palladium.Core.ErrorGuard.AddListener(pltr, 'SavePlot', @(src,evnt)this.SavePlot(evnt), Controller = this);

                %Simple plotters do not get registered for auto-updates.
                %Whatever made them has to push data to them itself.
            catch err
                this.HandleError("Error adding new simple plotter", err);
            end
        end

        function AttachView(this, view)
            %Give a View (GUI) the Controller and sub-controllers, so it can subscribe to their events.
            %Called by `Palladium.m` before `Initialise`. Calls the View's
            %`AssignControllersAndHookUpEvents`

            view.AssignControllersAndHookUpEvents(this, this.TimingLoopController, this.InstrumentController);
        end

        function CacheInstrumentCommand(this, instrument, command, controlName, Settings)
            %Queue a command for an instrument (or one of its controls), to run at the start of the next tick.
            %Passes through to the CommandController. Used by
            %`Palladium.CacheInstrumentCommand` and the Sequence Editor
            %
            %Inputs:
            %   instrument  - the instrument to run the command on
            %   command     - method call as text, e.g. "SetSourceLevel(2, false)"
            %   controlName - name of the instrument's Instrument Control to run it on instead. Empty (the default) for the instrument itself
            %   FunctionOnComplete - (name-value) function to call once the command has run. Default []
            arguments
                this;
                instrument (1,1) Palladium.Core.Instrument;
                command {mustBeTextScalar};
                controlName = string.empty;
                Settings.FunctionOnComplete = [];
            end

            this.CommandController.CacheInstrumentCommand(instrument, command, controlName, FunctionOnComplete = Settings.FunctionOnComplete);
        end

        function canStart = CanStart(this)
            %Check the data file's folder and name are valid, so measurements can start.
            %Called by `TimingLoopController.Start`. If not, shows the error
            %dialogue and returns false

            canStart = false;
            try
                %Verify directory and path valid
                if(~Palladium.Utilities.PathUtils.IsDirectoryValid(this.FileWriteDetails.Directory))
                    error("CanStartError:InvalidDirectory", "%s", ['Error - directory not valid: ' this.FileWriteDetails.Directory]);
                end
                if(~Palladium.Utilities.PathUtils.IsFileNameValid(this.FileWriteDetails.FileName))
                    error("CanStartError:InvalidFileName", "%s", ['Error - file name not valid: ' this.FileWriteDetails.FileName]);
                end
            catch err
                this.HandleError('Invalid file path. Cannot start measurements', err);
                return;
            end

            canStart = true;
        end

        function CloseProgress(this)
            %Close the progress bar, by raising StoppedShowingProgress.

            notify(this, "StoppedShowingProgress");
        end

        function classNames = GetAllInstrumentClassNames(this)
            %Names of all the instrument classes that can be added, MATLAB and Python.

            classNames = this.InstrumentController.ListOfAvailableInstrumentClassNameStrings;
        end

        function instRef = GetInstrumentFromName(this, instName)
            %Find an added instrument by its Name, via the InstrumentController.
            arguments
                this;
                instName {mustBeTextScalar};
            end

            %Pass through to InstrumentController
            instRef = this.InstrumentController.GetInstrumentFromName(instName);
        end

        function HaltMeasurementsOnInstrumentError(this, instr, e)
            %Show the error dialogue for an instrument's measurement error, and stop if the user asks.
            %Called by the InstrumentController when an instrument's
            %measurement fails and LogSettings.ErrorOnAllInstrumentErrors is
            %on (otherwise it only logs a warning)
            %
            %Inputs:
            %   instr - the instrument that failed
            %   e     - the error it threw

            %Show error message and ask if we want to stop measurements
            halt = this.HandleError("Error in main measurement loop - Collect Data from " + instr.FullName, e);
            if(halt)
                Palladium.Logging.Logger.Log("Info", "Measurements aborted by User from Error Dialogue");

                %Wind the loop down now (stop the timer, close the
                %instruments, raise Stopped) - unless it already has been,
                %as in HandleCallbackError
                if this.TimingLoopController.State ~= "Ready"
                    this.TimingLoopController.OnStopped();
                end
            end
        end

        function tf = IsClosing(this)
            %True once the GUI window has been closed (see OnFigureClosed).

            tf = this.Closing;
        end

        function HandleCallbackError(this, context, err, Settings)
            %Handle an error caught in a GUI callback, an event listener or the measurement loop.
            %The single entry point for these errors (see ErrorGuard for why
            %callbacks need this). Logs the error, shows the error dialogue,
            %and stops the measurement loop if the user chooses to. A
            %Standalone error, from a window that does not interact with the
            %measurement loop (e.g. the Data Viewer), gets a dialogue without
            %the stop option, and never touches the loop. Once the GUI is
            %closing, other errors just close the loop's timer
            %
            %Inputs:
            %   context    - what was happening, shown before the error message
            %   err        - the MException caught
            %   Standalone - (name-value) true for an error from a window that does not interact with the loop. Default false
            %   Figure     - (name-value) window to show the dialogue in (see HandleError). Default [], the main window
            arguments
                this;
                context;
                err;
                Settings.Standalone (1,1) logical = false;
                Settings.Figure = [];
            end

            if this.Closing && ~Settings.Standalone
                %Just break out of the loop if we've closed the window - it
                %can trigger silly errors about event listeners still being
                %subscribed which we don't care about
                this.TimingLoopController.CloseTimer();
                return;
            end

            halt = this.HandleError(context, err, Standalone = Settings.Standalone, Figure = Settings.Figure);
            if halt
                Palladium.Logging.Logger.Log("Info", "Measurements aborted by User from Error Dialogue");

                %Only wind the loop down if it is actually running - a
                %callback error while idle should not re-close instruments
                if this.TimingLoopController.State ~= "Ready"
                    this.TimingLoopController.OnStopped();
                end
            end
        end

        function Halt = HandleError(this, message, error, Settings)
            %Log an error and show the error dialogue, returning whether the user chose to stop.
            %Also shows the error on the main window's status light. An error
            %the user has suppressed is ignored; one arriving while a
            %dialogue is already open is only logged. With Standalone = true
            %the error is from a window that does not interact with the loop,
            %so the dialogue has no stop option, Halt is false, and the main
            %window's status light is left alone.
            %
            %Inputs:
            %   message    - what was happening, shown before the error message
            %   error      - the MException caught
            %   Standalone - (name-value) true for an error from a window that does not interact with the loop. Default false
            %   Figure     - (name-value) window to show the dialogue in. Default [], the main window
            %
            %Outputs:
            %   Halt - true if the user chose to stop the measurements
            arguments
                this;
                message;
                error;
                Settings.Standalone (1,1) logical = false;
                Settings.Figure = [];    %Window to show the dialogue in (figure, or a component in one). Empty, or no longer valid, means the main window
            end

            %Assemble a full message from the message sent into the logger,
            %and the actual error details
            msg = string(message) + ": " + string(error.message);

            %If we have previously suppressed this error, no need to do
            %anything, just return (and do not halt)
            if any(strcmp(this.SuppressedErrorMessages, msg))
                Halt = false;
                return;
            end

            %The timer keeps ticking underneath a modal error dialogue, so
            %more errors can arrive while one is being handled. Log those, but
            %don't stack up more dialogues
            if this.ErrorDialogOpen
                Halt = false;
                try
                    Palladium.Logging.Logger.LogError(error, message, SkipGUI = Settings.Standalone);
                catch
                    %Nothing more we can do
                end
                return;
            end

            %Held for the whole of error handling, not just the dialogue:
            %ShowStatus below fires events whose listeners could themselves
            %throw, which would otherwise loop back in here
            this.ErrorDialogOpen = true;
            resetFlag = onCleanup(@() this.ClearErrorDialogOpen());

            %Message about the error - Try to display a red light error status in the programme, and Log, but
            %don't fuss if that fails, just ignore the exception and throw
            %a warning
            try
                if ~Settings.Standalone
                    this.ShowStatus("Red", "Error: " + msg);
                    drawnow();
                end
                Palladium.Logging.Logger.Log("Error", msg, "FullMessage", msg + " : " + string(getReport(error, "extended", "hyperlinks", "on")), "SkipGUI", Settings.Standalone);
            catch e
                warning("HandleErrorWarning:HandlingFailed", "%s", "An error was thrown while.. trying to handle an error.. :" + string(e.message));
            end

            %TODO - use the DebugMode property to show simple stack trace
            %in the error. Right now it does nothing but it USED to

            %Pass on the error to the Error Handler to show a dialogue box
            %- user can choose whether to stop the measurement loop, and
            %separately whether to suppress this error going forward
            %Dialogue goes in the requested window if there is a live one,
            %else on the main window if there is a live one, else it is a
            %free-floating box (e.g. the main window has been closed)
            figureHandle = this.ResolveDialogueFigure(Settings.Figure);
            [Halt, suppressError] = Palladium.Logging.Logger.HandleError(message, error, figureHandle, Standalone = Settings.Standalone);

            %User could have chosen to Suppress this error message in the
            %dialogue box, so it will not be shown in the future - handle
            %that case. List of suppressed errors will (for now at least)
            %be a property of Controller, so will only be reset by
            %restarting the programme. Could reset it on measurement start
            %later if that turns out to be clearer for the user
            if(suppressError)
                %Log the fact that we are suppressing an error
                Palladium.Logging.Logger.Log("Info", "Error Suppressed by User: " + msg);

                %Add this error to the list
                this.SuppressedErrorMessages = [this.SuppressedErrorMessages, msg];
            end
        end

        function HandleWarning(this, msg, title)
            %Show a warning: a warning box in the main window, or a MATLAB warning if there is no GUI.
            %
            %Inputs:
            %   msg   - the warning, as plain text (newlines are kept, and backslashes are not escapes)
            %   title - title of the warning box

            try
                uifg = this.UIFigureHandle;
                if matlab.ui.internal.isUIFigure(uifg)
                    %Our view is a UI Figure, show a modal warning box based on
                    %its handle. The message is plain text - not passed
                    %through sprintf, which would treat the backslashes in
                    %Windows paths as escapes (cutting the message short, and
                    %printing a MATLAB warning, which the standalone app
                    %shows as a Windows error box)
                    uialert(uifg, Palladium.Utilities.GUIUtils.MessageToHTML(msg), title, "Icon", "warning", "Interpreter", "HTML");
                else
                    %Our view is not a ui figure - just show a warning in the
                    %console
                    warning("HandleWarningWarning:Message", "%s", msg);
                end
            catch
                warning("HandleWarningWarning:Message", "%s", msg);
            end
        end

        function tf = HasGUIWindow(this)
            %True if a GUI window is open to show messages and dialog boxes in

            tf = matlab.ui.internal.isUIFigure(this.UIFigureHandle) && isvalid(this.UIFigureHandle);
        end

        function Initialise(this, versionString, Settings)
            %Load the settings, start the Logger, set up the user files folder and load the instruments.
            %Called by `Palladium.m` after `AttachView`. In order:
            %
            %* loads the config file and starts the Logger - an error here
            %  is thrown, as the error dialogue is not set up yet;
            %* sets the default data file settings (FileWriteDetails);
            %* creates the user files folder and its subfolders, and copies
            %  starter files into them if they are not there yet;
            %* finds the GUI windows' icon, and raises SettingsApplied;
            %* sets up Python and loads the Python instrument classes - if
            %  Python can't be used, carries on without them (OnLoaded warns);
            %* loads the MATLAB instrument classes, initialises the
            %  TimingLoopController, and sets up the Sequence Editor.
            %
            %Inputs:
            %   versionString  - Palladium DAQ's version, for the start-up message
            %   ConfigFilePath - (name-value) config file to load instead of the default one. Default []
            arguments
                this;
                versionString {mustBeTextScalar};
                Settings.ConfigFilePath = [];                  % Default is blank ([]) - enter a filepath instead to override default Config json file loading and pass in the path for another settings file to be loaded from
            end

            %Initialise the Controller, loading and applying settings etc
            try
                %Load settings from .json config files in the Settings directory
                [logSettings, this.PathSettings, this.WindowSettings, this.PlottingController.PlotterSettings, this.PythonSettings, this.WarningSettings] = this.LoadSettings(ConfigFilePath=Settings.ConfigFilePath);
            catch e
                %Note that we don't pass this in to any nice error handling
                %because we haven't set that up yet
                error("InitialiseError:LoadSettingsFailed", "%s", "Error in loading settings in Controller.Initialise: " + string(e.message));
            end

            %Now we know the settings to pass to it, create a Logger. Don't
            %need to keep a reference to it, as it has a pseudo-static
            %singleton model where it can then be accessed with static
            %calls while remembering these settings
            Palladium.Logging.Logger(this,...
                logSettings.LogFileDirectory, logSettings.LogFileFileName,...
                "CommandWindowMessageLevel", logSettings.CommandWindowMessageLevel,...
                "GUIMessageLevel", logSettings.GUIMessageLevel,...
                "LogFileMessageLevel", logSettings.LogFileMessageLevel,...
                "PrintStackTraceInCommandWindow", logSettings.PrintStackTraceInCommandWindow);

            try
                %Set logging/error setting parameters in Controller
                this.InstrumentController.ErrorOnAllInstrumentErrors = logSettings.ErrorOnAllInstrumentErrors;

                %Show startup message now we have the Logger
                this.Log("Debug", "Initialising " + string(versionString), "Yellow", "Initialising " + string(versionString));

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
                this.DefaultDataDir = Palladium.Utilities.PathUtils.CleanPath(this.PathSettings.DefaultDirectory);

                %Set the User Files path, and create the directory if it
                %doesn't exist
                this.UserFilesDir = Palladium.Utilities.PathUtils.CleanPath(this.PathSettings.UserFilesDirectory);


                %Now make sure that folder exists and create it if not
                this.EnsureUserFilesDirExists(this.UserFilesDir);

                %Copy starter files into the user files folders, if they
                %aren't there yet. In the installed standalone application
                %these are installed next to the executable, in the
                %application folder (see deployTask in buildfile.m)

                %The template for new instrument drivers - not in the
                %standalone application, which can't load MATLAB drivers
                %written after it is built
                if ~isdeployed
                    this.CopyStarterFile("TemplateInstrumentClass.m", fullfile(this.ApplicationDir, "ExamplesAndTemplates", "Instruments"), this.UserInstrumentsDir);
                end

                %The template for new Python instruments - Python
                %instruments work in the standalone application too
                this.CopyStarterFile("TemplatePythonInstrument.py", fullfile(this.ApplicationDir, "ExamplesAndTemplates", "PythonInstruments"),...
                    fullfile(this.UserPythonInstrumentsDir, this.PythonInstrumentNamespace));

                %The example Preset
                this.CopyStarterFile("Example.json", fullfile(this.ApplicationDir, "ExamplesAndTemplates", "Presets"), this.UserPresetsDir);

                %The QDInterface dll for the PPMS, which needs to sit in a
                %folder alongside the QDInstrument dll file that the user
                %will have to install themselves
                this.CopyStarterFile("QDInterface.dll", fullfile(this.ApplicationDir, "Instrument Drivers", "Quantum Design", "PPMS Communication"),...
                    fullfile(this.UserInstrumentDriversDir, "Quantum Design", "PPMS Communication"));

                %Icon for the GUI's windows - in the Graphics folder of the
                %installed application, or in the source
                if isdeployed
                    iconPath = fullfile(this.ApplicationDir, "Graphics", "PalladiumDAQIcon.png");
                else
                    iconPath = fullfile(this.ApplicationDir, "+Palladium", "+Components", "Graphics", "PalladiumDAQIcon.png");
                end
                if isfile(iconPath)
                    this.WindowSettings.PalladiumIconPath = iconPath;
                else
                    this.WindowSettings.PalladiumIconPath = [];
                end

                %Send settings to the GUI
                args = Palladium.Events.SettingsChangedEventData(this.PathSettings, this.WindowSettings);
                notify(this, "SettingsApplied", args);

                %Set up Python Instrument loading. Python is optional: if it
                %can't be used, carry on without Python instruments, and warn
                %the user once Palladium DAQ has loaded (see OnLoaded)
                this.Log("Debug", "Initialising Python Instrument Classes", "Yellow", "Initialising Instruments...");
                this.PythonSetupStatus = this.SetUpPython();
                if ismember(this.PythonSetupStatus.Status, ["OK", "PackagesMissing"])
                    this.InstrumentController.PythonInstrumentController = Palladium.PythonInstruments.PythonInstrumentController(this.PythonInstrumentNamespace, this.ApplicationDir);
                    this.InstrumentController.PythonInstrumentController.LoadInstrumentClasses(this.UserPythonInstrumentsDir);
                    this.Log("Debug", "Python Instrument Classes initialised (Python " + this.PythonSetupStatus.Version + ", " + this.PythonSetupStatus.Executable + ")", "Green", "Instruments intialised");
                end
                if this.PythonSetupStatus.Status ~= "OK"
                    [title, ~] = Palladium.Utilities.PythonUtils.SetupHelpMessage(this.PythonSetupStatus);
                    logText = title + " (" + this.PythonSetupStatus.Status + "). Python: " + this.PythonSetupStatus.Executable;
                    if ~isempty(this.PythonSetupStatus.MissingPackages)
                        logText = logText + ". Missing packages: " + join(this.PythonSetupStatus.MissingPackages, ", ");
                    end
                    if this.PythonSetupStatus.ErrorMessage ~= ""
                        logText = logText + ". " + this.PythonSetupStatus.ErrorMessage;
                    end
                    this.Log("Warning", logText, "Yellow", title);
                end

                %Load standard Instrument Classes (do this after Python
                %ones, as it grabs those internally and adds them to the
                %list)
                this.Log("Debug", "Initialising Instrument Classes", "Yellow", "Initialising Instruments...");
                this.InstrumentController.LoadInstrumentClasses();
                this.Log("Debug", "Instrument Classes initialised", "Green", "Instruments intialised");

                %Initialise TimingLoopController
                this.TimingLoopController.Initialise();

                %Send paths and settings to the Sequence Controller - first
                %make sure the sequence directory exists.
                if ~exist(this.PathSettings.DefaultSequenceDirectory, "dir")
                    mkdir(this.PathSettings.DefaultSequenceDirectory);
                end
                this.SequenceEditorController.Initialise(...
                    "DefaultDataDirectory", this.PathSettings.DefaultDirectory,...
                    "DefaultSequenceDirectory", this.PathSettings.DefaultSequenceDirectory,...
                    "DefaultDataFileName", this.PathSettings.DefaultFileName,...
                    "SequenceFileExtension", this.PathSettings.SequenceFileExtension);

                %Display a status message in the logger
                this.Log("Info", "Ready", "Green", "Ready");
            catch err
                this.HandleError('Initialisation error in applying loaded Settings (Controller.Initialise)', err);
            end
        end

        function InitialiseDataWriting(this)
            %Make a new DataWriter for the current file settings, and settle the file name.
            %Called by `TimingLoopController.Start` and when a sequence
            %switches data file. The DataWriter applies the write mode to the
            %file name (e.g. incrementing its number, see
            %`DataWriter.ValidateFilePath`), and the result is sent to the
            %View with FileWriteOptionsChanged. Also removes
            %deleted plotters from the PlottingController

            %Create a DataWriter object to log all data
            this.DataWriter = Palladium.DataWriting.DataWriter(this.FileWriteDetails);
            this.FileWriteDetails.FileName = this.DataWriter.ValidateFilePath();

            %Update the View to display the file write settings
            args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
            notify(this, "FileWriteOptionsChanged", args);

            %Clean up Plotters list, remove any that have been deleted
            this.PlottingController.CleanUpPlotters();
        end

        function [success, msg, title] = InitialiseMeasurements(this)
            %Connect the instruments and prepare the data, plots and data file to start measuring.
            %Called by `TimingLoopController.Start` (but not by Resume, which
            %just restarts the loop). Shows a progress bar meanwhile. Clears
            %DataTable, connects and initialises the instruments, sets
            %Headers and Units, resets the plots, and writes the column
            %headers and instruments' metadata lines to the data file. If
            %setting up errors, shows the error dialogue and fails; if
            %collecting the metadata errors, it fails only if the user
            %chooses to stop there, and otherwise starts without the metadata
            %
            %Outputs:
            %   success - true if measurements are ready to start
            %   msg     - if an instrument failed to connect, the details. ""
            %             otherwise - including when the user has already seen
            %             an error dialogue
            %   title   - if an instrument failed to connect, a short title for the warning, else ""

            success = false; msg = ""; title = "";

            %Display a status message in the logger
            this.Log("Info", "Initialising measurements", "Yellow", "Initialising measurements");

            %Display a model progress bar so we can't go clicking things
            %while intialisation is underway - and also get clued in that a
            %slow operation is in fact running and we shouldn't click Start
            %100 times like my dad
            this.ShowProgress("Initialising measurements", "Initialising..");

            try

                %Initialise the (:, n) double array that will hold the
                %data
                this.DataTable = [];

                %Initialise all instruments
                [success, msg, title] = this.InstrumentController.InitialiseInstruments();

                %Error out here and break if any instrument failed to
                %connect
                if ~success
                    Palladium.Logging.Logger.Log("Error", title, "FullMessage", msg, "LogFileMessageLevel", "Error", "CommandWindowMessageLevel", "Error", "GUIMessageLevel", "Error");
                    return;
                end

                %Generate column headers and validate
                [this.Headers, headersString, this.Units] = this.InstrumentController.InitialiseHeaders();
                this.HeadersString = headersString;     %Kept for files started mid-run (SetFilePathWhileRunning)

                %Initialise all graphs
                this.PlottingController.UpdatePlotVariableNames(this.Headers);
                this.PlottingController.ClearPlots();

                %Refresh the Sequence Controller, as instrument names etc
                %may have changed
                this.SequenceEditorController.RefreshInstrumentNames();

                %Display a status message in the logger
                this.Log("Info", "Measurements initialised", "Green", "Measurements initialised");
            catch e
                this.CloseProgress();
                this.HandleError("Error initialising measurements", e);
                return;
            end

            %Add a metadata/settings line to the top of the datafile (in
            %the header) for each instrument that defines one
            metadataLines = [];     %No metadata lines if collecting them fails
            try
                %Update the progress bar
                this.UpdateProgress(1, "Writing metadata and headers");

                %Get the string to write from Instruments
                metadataLines = this.InstrumentController.GetMetadataLines();

                %Succesful end - close the progress bar
                this.CloseProgress();
            catch e
                this.CloseProgress();
                halt = this.HandleError("Error collecting instrument metadata", e);
                if halt
                    %The user chose to stop in the error dialogue - don't start.
                    %No message, as they have already seen the error (see
                    %TimingLoopController.AbortStart)
                    this.Log("Info", "Start cancelled from the error dialogue", "Yellow", "Start cancelled");
                    success = false; msg = ""; title = "";
                    return;
                end
                %Otherwise carry on, without the metadata lines
            end

            %Write the headers to file
            this.DataWriter.WriteHeaders(headersString, "MetadataLines", metadataLines);

            success = true;
        end

        function InstrumentPropertyChanged(this, instr)
            %Log an instrument's settings change and refresh the Sequence Editor's instrument names.
            %Called by the InstrumentController when an instrument raises
            %PropertyChanged

            %Display a status message in the logger
            this.Log("Info", instr.Name + " Property Changed", "Green", instr.Name + " Property Changed");

            %Run a refresh on the Sequence Editor, as instrument names may
            %have changed
            this.SequenceEditorController.RefreshInstrumentNames();
        end

        function Log(this, level, logText, colour, statusText)
            %Send a message to the Logger, and show a status message in the GUI's status strip.
            %
            %Inputs:
            %   level      - "Debug", "Info", "Warning" or "Error"
            %   logText    - message for the Logger
            %   colour     - status light colour: "Green", "Yellow" or "Red"
            %   statusText - shorter message for the status strip
            arguments
                this;
                level       {mustBeText, mustBeMember(level, ["Debug", "Info", "Warning", "Error"])};
                logText     (1,1) string;
                colour      {mustBeText, mustBeMember(colour, ["Green", "Yellow", "Red"])};
                statusText  (1,1) string;
            end

            %Pass through to the Logger and to the status strip in the
            %bottom of the GUI
            Palladium.Logging.Logger.Log(level, logText);
            this.ShowStatus(colour, statusText);
        end

        function Measure(this)
            %Run one tick of the measurement loop: commands, data collection, file, data table and plots.
            %Called by the TimingLoopController's timer every tick. In order:
            %runs queued commands (CommandController.Update), collects a data
            %row from the instruments, writes it to the data file, adds it
            %to DataTable, updates the plots and raises DataRowUpdated. Each
            %step catches its own errors (see HandleCallbackError), so the
            %rest still run if the user chooses to carry on; a failed data
            %collection gives a row of NaNs. If the user chooses to stop while
            %commands run, the rest of the tick is skipped; if they stop while
            %collecting, the row (padded with NaNs) is still written and plotted

            try
                this.CommandController.Update();
            catch e
                CatchMeasurementLoopError(this, e);
            end
            if this.TimingLoopController.State == "Ready"
                return;     %The user chose to stop measurements from an error dialogue - the instruments are closed now
            end

            try
                %Collect Data
                this.ShowStatus("Green", "Running");
                dataRow = this.InstrumentController.CollectMeasurement(this.Headers);
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
                %Update data plots & Update any Big Number Display windows
                this.PlottingController.PlotData(dataRow, this.DataTable);
                args = Palladium.Events.DataRowAddedEventData(dataRow, this.Headers);
                notify(this, "DataRowUpdated", args);
            catch e
                CatchMeasurementLoopError(this, e);
            end

            %Want to catch the error pretty locally, so the rest of the
            %stuff in the Update Loop still happens in the expected order
            %if we choose to Ignore or Suppress. This is just a private
            %function here to avoid duplicating the code of handling an
            %error specifically in the Measurement Loop
            function CatchMeasurementLoopError(this, e)
                %Show error message and ask if we want to stop measurements
                this.HandleCallbackError("Error in main measurement loop", e);
            end
        end

        function OnFigureClosed(this)
            %Shut down when the GUI window closes: stop the timer, close the instruments and the Sequence Editor.
            %Called by `Palladium.m`. Data Viewer windows are left open, by
            %design

            this.Log("Debug", "Palladium DAQ closed", "Yellow", "Closing");
            this.Closing = true;
            this.TimingLoopController.CloseTimer();
            this.InstrumentController.CloseAll();

            %Do cleanup events including e.g. shutting any
            %Sequence Editor windows (not DataViewer ones though, by
            %design)
            this.SequenceEditorController.Close();
        end

        function OnLoaded(this)
            %Finish start-up: raise Loaded so the GUI accepts input, then warn of any Python setup problem.
            %Called by `Palladium.m` once everything is set up, including any
            %Preset

            %Display a status message in the logger
            this.Log("Info", "Palladium loaded", "Green", "Ready");

            try
                %Let the user interact with the GUI now it is loaded and ready
                notify(this, "Loaded");
            catch err
                this.HandleError("Error unlocking input in Controller.OnLoaded", err);
            end

            %Now the main window is showing, warn about any problem setting
            %up Python
            this.ShowPythonSetupWarning();
        end

        function OnMeasurementsStopped(this)
            %Close all the instruments, once the measurement loop has stopped.
            %Called by `TimingLoopController.OnStopped`

            this.InstrumentController.CloseAll();
        end

        function OpenDataViewer(this)
            %Open a Data Viewer window, in the default data folder.

            try
                defaultDataPath = this.DefaultDataDir;
                extensions = this.FileWriteDetails.FileExtension;
                DataViewer("DefaultDir", defaultDataPath, "FileExtensions", extensions);
            catch err
                this.HandleError("Error opening DataViewer", err);
            end
        end

        function OpenHelp(this)
            %Open the documentation's contents page in a web browser.
            %The system browser from the compiled app, MATLAB's web browser
            %otherwise

            try
                %Docs is next to Palladium.m in the toolbox, and next to
                %PalladiumDAQ.exe in an installed app (the installer puts it there)
                indexPath = fullfile(this.ApplicationDir, "Docs", "index.html");
                assert(isfile(indexPath), "Controller:DocsNotFound", "Documentation not found at %s", indexPath);
                urlPath = replace(indexPath, "\", "/");
                if ~startsWith(urlPath, "/")    %Windows C:/..., not Mac/Linux /...
                    urlPath = "/" + urlPath;
                end
                url = "file://" + replace(urlPath, " ", "%20");
                if isdeployed
                    status = web(url, "-browser"); %#ok<NASGU>
                else
                    status = web(url); %#ok<NASGU>
                end
            catch err
                this.HandleError("Error opening the documentation", err);
            end
        end

        function OpenSequenceEditor(this)
            %Open a Sequence Editor window.

            try
                %Add a View/GUI to the sequence editor (which is secretly
                %already there)
                this.SequenceEditorController.CreateView("SequenceEditor_DefaultGUI", this.ApplicationDir,...
                    "IconPath", this.WindowSettings.PalladiumIconPath);

            catch err
                this.HandleError("Error opening Sequence Viewer", err);
            end
        end

        function QueueSequence(this, args)
            %Queue a sequence of commands from the Sequence Editor in the CommandController.
            %
            %Inputs:
            %   args - event data whose Value is a cell array of the commands

            cellArrayOfCommands = args.Value;

            this.CommandController.CacheCommands(cellArrayOfCommands);

            %Verbose/debug message printing
            this.Log("Info", "Queued Sequence", "Green", "Queued Sequence");
        end

        function RegisterUIFigure(this, uiFigureHandle)
            %Register the main GUI window, where error dialogues and warnings are then shown.
            %Called by the View
            arguments
                this;
                uiFigureHandle (1,1) handle;
            end

            this.UIFigureHandle = uiFigureHandle;
        end

        function RemoveInstrument(this, instrRef)
            %Remove an instrument, via the InstrumentController.

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

        function RemoveInstrumentControl(this, instrRef, controlDetailsStruct)
            %Remove an Instrument Control from an instrument, via the InstrumentController.
            %
            %Inputs:
            %   instrRef             - the instrument
            %   controlDetailsStruct - the control's details struct, as from DefineInstrumentControl

            try
                %Pass on through to InstrumentController
                this.InstrumentController.RemoveInstrumentControl(instrRef, controlDetailsStruct);

                %Verbose/debug message printing
                this.Log("Info", "Removed Instrument Control: " + controlDetailsStruct.Name, "Green", "Removed Instrument Control");
            catch err
                this.HandleError("Error removing instrument control " + controlDetailsStruct.Name, err);
            end
        end

        function LoadPreset(this, view)
            %Ask the user for a Preset .json file and apply it.
            %Called from the GUI's Settings menu. The file dialogue opens in
            %the user files folder's Presets folder. See
            %`PluginLoading.ApplyPresetFromJson`
            %
            %Inputs:
            %   view - the View, which adds the Preset's GUI parts (plots, Instrument Controls)

            defaultFilePath = Palladium.Utilities.PathUtils.CleanPath(this.UserPresetsDir);

            % Open file dialog in defaultFilePath and filter to .json
            filter = {'*.json','JSON files'; '*.*','All Files'};
            [file, location] = uigetfile(filter, "Load Preset", fullfile(defaultFilePath, '*.json'));

            %Cancel if it was cancelled
            if file == 0
                return;
            end
            jsonFilePath = fullfile(location, file);

            %Load the present in and apply all the settings
            Palladium.Utilities.PluginLoading.ApplyPresetFromJson(this, view, jsonFilePath);
        end

        function SavePreset(this, view)
            %Ask the user for a file name, and save the current setup there as a Preset .json file.
            %Called from the GUI's Settings menu. The file dialogue opens in
            %the user files folder's Presets folder. See
            %`PluginLoading.SavePresetToJson`
            %
            %Inputs:
            %   view - the View, whose GUI parts (plots) are saved too

            defaultFilePath = fullfile(this.UserPresetsDir, "NewPreset.json");
            defaultFilePath = Palladium.Utilities.PathUtils.CleanPath(defaultFilePath);

            %Open a file browse dialog window
            [file, location] = uiputfile(defaultFilePath, "Save Preset");

            %Cancel if it was cancelled
            if file == 0
                return;
            end
            jsonFilePath = fullfile(location, file);

            Palladium.Utilities.PluginLoading.SavePresetToJson(this, this.InstrumentController, view, jsonFilePath);
        end

        function SetFilePathWhileRunning(this, filePath, saveFileBool)
            %Switch to a new data file, or switch saving on or off, while measurements run.
            %The entry point for a sequence's `[DATAFILE]` command, through the
            %CommandController's DataFileCommandRun event. It is not queued:
            %it runs from CommandController.Update, the first step of the
            %tick (see Measure). Makes a new DataWriter, and starts the new
            %file with its header, as Start does
            %
            %Inputs:
            %   filePath     - full path of the new data file, or empty to keep the current one
            %   saveFileBool - true to write the data to file
            arguments
                this;
                filePath string;    %New data file, or empty to keep the current one
                saveFileBool (1,1) logical;
            end

            try
                %A new file, if a path is given. With no path (as from
                %[DATAFILE] 0) keep the current file name and folder, and
                %just switch saving on or off
                if ~isempty(filePath) && strlength(filePath) > 0
                    %Pull apart the path into its components
                    [filepath, fileName, fileExtension] = fileparts(filePath);

                    %Assign the variables
                    this.FileWriteDetails.Directory = Palladium.Utilities.PathUtils.CleanPath(filepath);
                    if ~isempty(fileExtension)
                        if ~strcmp(string(fileExtension), "")
                            this.FileWriteDetails.FileExtension = fileExtension;
                        end
                    end

                    %Make sure the filename doesn't have an extra file extension
                    %included by user by mistake - we will add an extension on
                    fileNameNoExt = Palladium.Utilities.PathUtils.StripExtension(fileName);

                    %Helpfully replace <DATE> tag with today's actual date
                    this.FileWriteDetails.FileName = Palladium.Utilities.PathUtils.ReplaceDateTag(fileNameNoExt);
                end
                this.FileWriteDetails.SaveFile = saveFileBool;

                %Refresh the data writer. This will also Update the View
                this.InitialiseDataWriting();

                %Start the new file with its header, as Start does - with
                %the instruments' settings now. WriteHeaders does nothing
                %if saving is switched off, or if appending to a file that
                %already exists
                if this.HeadersString ~= ""
                    this.DataWriter.WriteHeaders(this.HeadersString, "MetadataLines", this.InstrumentController.GetMetadataLines());
                end
            catch err
                this.HandleError("Error switching data file", err);
            end
        end

        function SetFilePathsDirectory(this, directory)
            %Set the data file's folder, and tell the View (FileWriteOptionsChanged).

            try
                this.FileWriteDetails.Directory = Palladium.Utilities.PathUtils.CleanPath(directory);

                %Update the View
                args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
                notify(this, "FileWriteOptionsChanged", args);
            catch err
                this.HandleError("Error in SetFilePathsDirectory", err);
            end
        end

        function SetFilePathsFileExtension(this, fileExtension)
            %Set the data file's extension, e.g. ".dat", and tell the View (FileWriteOptionsChanged).

            try
                this.FileWriteDetails.FileExtension = fileExtension;

                %Pass through to View
                args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
                notify(this, "FileWriteOptionsChanged", args);
            catch err
                this.HandleError("Error in SetFilePathsFileExtension", err);
            end
        end

        function SetFilePathsDescription(this, descriptionText)
            %Set the data file's description text, and tell the View (FileWriteOptionsChanged).

            try
                this.FileWriteDetails.DescriptionText = descriptionText;

                %Pass through to View
                args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
                notify(this, "FileWriteOptionsChanged", args);
            catch err
                this.HandleError("Error in SetFilePathsDescription", err);
            end
        end

        function SetFilePathsFileName(this, fileName)
            %Set the data file's name, and tell the View (FileWriteOptionsChanged).
            %Any extension is removed, and a `<DATE>` tag is replaced with
            %today's date

            try
                %Make sure the filename doesn't have an extra file extension
                %included by user by mistake - we will add an extension on
                fileNameNoExt = Palladium.Utilities.PathUtils.StripExtension(fileName);

                %Helpfully replace <DATE> tag with today's actual date
                fileNameDateRp = Palladium.Utilities.PathUtils.ReplaceDateTag(fileNameNoExt);

                %Set the variable
                this.FileWriteDetails.FileName = fileNameDateRp;

                %Pass through to View
                args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
                notify(this, "FileWriteOptionsChanged", args);
            catch err
                this.HandleError("Error setting file name", err);
            end
        end

        function SetFilePathsSaveFileBool(this, saveFileBool)
            %Set whether to write the data to file, and tell the View (FileWriteOptionsChanged).

            try
                this.FileWriteDetails.SaveFile = saveFileBool;

                %Pass through to View
                args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
                notify(this, "FileWriteOptionsChanged", args);
            catch err
                this.HandleError("Error setting save file bool", err);
            end
        end

        function SetFilePathsWriteMode(this, writeMode)
            %Set the data file's write mode, and tell the View (FileWriteOptionsChanged).
            %The write mode says what to do if the file already exists:
            %"Increment File No.", "Overwrite File" or "Append To File"

            try
                this.FileWriteDetails.WriteMode = writeMode;

                %Pass through to View
                args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
                notify(this, "FileWriteOptionsChanged", args);
            catch err
                this.HandleError("Error setting write mode", err);
            end
        end

        function ShowMessageInGUI(this, colour, msg)
            %Show a message from the Logger in the GUI's status strip.
            %For now this just calls ShowStatus, but is kept separate as the
            %Logger's entry point, so its messages could later be shown in
            %other ways

            this.ShowStatus(colour, msg);
        end

        function ShowProgress(this, msg, title)
            %Show a progress bar, by raising StartedShowingProgress.
            %
            %Inputs:
            %   msg   - message shown in the progress bar
            %   title - its title

            args = Palladium.Events.MessageEventData(msg, title);
            notify(this, "StartedShowingProgress", args);
        end

        function ShowStatus(this, colour, msg)
            %Show a message in the GUI's status strip, by raising GreenStatus, YellowStatus or RedStatus.
            %
            %Inputs:
            %   colour - status light colour: "Green", "Yellow" or "Red"
            %   msg    - the message

            switch(colour)
                case('Green');      notify(this, "GreenStatus", Palladium.Events.MessageEventData(msg));
                case('Yellow');     notify(this, "YellowStatus", Palladium.Events.MessageEventData(msg));
                case('Red');        notify(this, "RedStatus", Palladium.Events.MessageEventData(msg));
                otherwise
                    error("ShowStatusError:UnsupportedColour", "Colour unsupported in ShowStatus");
            end
        end

        function UpdateProgress(this, progress, message)
            %Move the progress bar on, by raising UpdatedProgress.
            %
            %Inputs:
            %   progress - fraction done, from 0 to 1
            %   message  - message to show in the progress bar
            arguments
                this;
                progress (1,1) double;
                message {mustBeTextScalar}
            end

            args = Palladium.Events.ProgressUpdateEventData(progress, message);
            notify(this, "UpdatedProgress", args);
        end

    end

    %% Methods (Private)
    methods(Access=private)

        function AppendToDataTable(this, dataRow)
            %Add a data row to the bottom of DataTable.

            if isempty(this.DataTable)
                this.DataTable = dataRow;
            else
                this.DataTable = [this.DataTable; dataRow];
            end
        end

        function figureHandle = ResolveDialogueFigure(this, requested)
            %The uifigure to show an error dialogue in: the requested one if open, else the main window, else empty.

            figureHandle = [];
            if ~isempty(requested)
                try
                    candidate = ancestor(requested, "figure");
                    if ~isempty(candidate) && isvalid(candidate) && matlab.ui.internal.isUIFigure(candidate)
                        figureHandle = candidate;
                        return;
                    end
                catch
                    %Deleted or not a UI object - use the main window
                end
            end

            if this.HasGUIWindow()
                figureHandle = this.UIFigureHandle;
            end
        end

        function ClearErrorDialogOpen(this)
            %Reset ErrorDialogOpen - run by an onCleanup in HandleError, so it is reset even if the dialogue errors.

            if isvalid(this)
                this.ErrorDialogOpen = false;
            end
        end

        function CopyStarterFile(this, fileName, sourceDir, destDir)
            %Copy a starter file (an example or template) into a user files folder, unless it is already there.
            %If the source file is missing - e.g. an installation that
            %doesn't include it - or there is no destination folder, log a
            %warning and carry on

            if isempty(destDir) || strlength(string(destDir)) == 0
                this.Log("Warning", "Could not copy " + fileName + " to the user files folder: no destination folder", "Yellow", "Starter file not copied: " + fileName);
                return;
            end
            if ~isfile(fullfile(sourceDir, fileName))
                this.Log("Warning", "Could not copy " + fileName + " to the user files folder: not found in " + sourceDir, "Yellow", "Starter file not found: " + fileName);
                return;
            end
            Palladium.Utilities.PathUtils.EnsureDirectoryExists(destDir);
            Palladium.Utilities.PathUtils.CopyFiles(fileName, sourceDir, destDir, Overwrite=false);
        end

        function EnsureUserFilesDirExists(this, pathToDir)
            %Create the user files folder and its subfolders if they don't exist, and add them to the path.
            %Sets the User...Dir properties. The subfolders are Presets,
            %Instrument Drivers (with Quantum Design/PPMS Communication), the
            %PythonInstruments namespace folder and, except in the installed
            %app, +Palladium/+Instruments for MATLAB instrument drivers.
            %Except in the installed app, the user files folder and Instrument
            %Drivers (with its subfolders) are added to the MATLAB path
            %
            %Inputs:
            %   pathToDir - the folder to make the user files folder in (UserFilesDir)

            %Build the path to the 'Palladium DAQ - User Files' directory
            userDirPath = fullfile(pathToDir, this.UserFolderName);

            %Create the directory if it doesn't exist
            newDirCreated = Palladium.Utilities.PathUtils.EnsureDirectoryExists(userDirPath);
            if newDirCreated
                this.Log("Info", "User directory at " + string(userDirPath) + " not found - creating new empty directory", "Green", "Creating User Directories");
            end


            %Set up the User Instrument Directory - .m instrument drivers
            %only make sense if not deployed as an exe, which can't load
            %MATLAB code written after it is built
            if ~isdeployed
                this.UserInstrumentsDir = fullfile(pathToDir, this.UserFolderName, this.UserInstrumentFolderName);
                newDirCreated = Palladium.Utilities.PathUtils.EnsureDirectoryExists(this.UserInstrumentsDir);
                if newDirCreated
                    this.Log("Info", "User directory at " + string(this.UserInstrumentsDir) + " not found - creating new empty directory", "Green", "Creating User Directories");
                end
            end

            %Set up the Presets Directory - Presets are .json files, so work
            %in the deployed exe too
            this.UserPresetsDir = fullfile(pathToDir, this.UserFolderName, this.UserPresetFolderName);
            newDirCreated = Palladium.Utilities.PathUtils.EnsureDirectoryExists(this.UserPresetsDir);
            if newDirCreated
                this.Log("Info", "User directory at " + string(this.UserPresetsDir) + " not found - creating new empty directory", "Green", "Creating User Directories");
            end

            %Set up the Instrument Drivers directory
            this.UserInstrumentDriversDir = fullfile(pathToDir, this.UserFolderName, this.UserInstrumentDriversFolderName);
            newDirCreated = Palladium.Utilities.PathUtils.EnsureDirectoryExists(this.UserInstrumentDriversDir);
            if newDirCreated
                this.Log("Info", "User directory at " + string(this.UserInstrumentDriversDir) + " not found - creating new empty directory", "Green", "Creating User Directories");
            end
            %And set up a Quantum Design/PPMS Communication folder inside
            %there, which will get the provided QDInterface.dll copied into
            %it
            Palladium.Utilities.PathUtils.EnsureDirectoryExists(fullfile(this.UserInstrumentDriversDir, "Quantum Design", "PPMS Communication"));

            % Ensure the user Python Instruments directory exists
            this.UserPythonInstrumentsDir = string(fullfile(this.UserFilesDir, this.UserFolderName));
            newDirCreated = Palladium.Utilities.PathUtils.EnsureDirectoryExists(fullfile(this.UserPythonInstrumentsDir, this.PythonInstrumentNamespace));
            if newDirCreated
                this.Log("Info", "User directory at " + string(fullfile(this.UserPythonInstrumentsDir, this.PythonInstrumentNamespace)) + " not found - creating new empty directory", "Green", "Creating User Directories");
            end

            %Add the User Dir to the MATLAB path
            if ~isdeployed
                addpath(userDirPath);
                addpath(genpath(this.UserInstrumentDriversDir));    %Includes subfolders
            end
        end

        function [logSettings, pathSettings, windowSettings, plotterSettings, pythonSettings, warningSettings] = LoadSettings(this, Settings)
            %Load the config file and return its sections, with the paths tidied and made absolute.
            %Remembers the config file's path in ConfigFilePath. Fixes a user
            %files path that ends in the user files folder itself (writing
            %the fix back to the config), makes relative paths absolute
            %(relative to ApplicationDir), and creates the default data
            %folder if needed - falling back to the user's Documents folder
            %(PathUtils.GetDocumentsDirectory), with a warning, if it can't be made
            %
            %Inputs:
            %   ConfigFilePath - (name-value) config file to load instead of the default one. Default []
            %
            %Outputs:
            %   logSettings, pathSettings, windowSettings, plotterSettings,
            %   pythonSettings, warningSettings - the config's sections, as structs
            arguments
                this;
                Settings.ConfigFilePath = [];                  % Default is blank ([]) - enter a filepath instead to override default Config json file loading and pass in the path for another settings file to be loaded from
            end

            %Load the settings file into struct
            configIO = Palladium.Utilities.ConfigIO();
            settingsStruct = configIO.LoadConfig(ApplicationDir=this.ApplicationDir, ConfigFilePath=Settings.ConfigFilePath);

            %Remember which config file is in use, to save settings to it later
            if isempty(Settings.ConfigFilePath)
                this.ConfigFilePath = configIO.GetConfigPath(ApplicationDir=this.ApplicationDir);
            else
                this.ConfigFilePath = string(Settings.ConfigFilePath);
            end

            %Parse the entries neatly into the PathSettings struct property
            logSettings = settingsStruct.LogSettings;
            pathSettings = settingsStruct.PathSettings;
            windowSettings = settingsStruct.WindowSettings;
            plotterSettings = settingsStruct.PlotterSettings;
            pythonSettings = settingsStruct.PythonSettings;
            warningSettings = settingsStruct.WarningSettings;

            %Handle the case of the user directory being inadvertently
            %in there twice - Physics\Matlab\Palladium DAQ - User Files\Palladium DAQ - User Files
            %which creates a confusing mess of folders. If the last
            %piece of the filepath is the name of the user dir (which
            %hasn't yet been added here), amend it
            [pth, dr, ~] = fileparts(pathSettings.UserFilesDirectory);
            if strcmp(string(dr), this.UserFolderName)
                %Strip off the trailing (duplicate) directory
                pathSettings.UserFilesDirectory = pth;

                %Write the tidied up path back to file
                configIO.SetConfigValue("PathSettings", "UserFilesDirectory", pth, ConfigFilePath=this.ConfigFilePath);
            end


            %Folders stored as relative paths are relative to ApplicationDir
            %(the folder Palladium.m is in) - make them absolute. In an
            %installed copy that is the installation folder, so warn
            isInstalled = ~configIO.IsSourceCheckout(this.ApplicationDir);
            pathSettings.DefaultDirectory = this.MakeAbsoluteFromApplicationDir(pathSettings.DefaultDirectory, this.ApplicationDir, isInstalled);
            logSettings.LogFileDirectory = this.MakeAbsoluteFromApplicationDir(logSettings.LogFileDirectory, this.ApplicationDir, isInstalled);
            pathSettings.DefaultSequenceDirectory = this.MakeAbsoluteFromApplicationDir(pathSettings.DefaultSequenceDirectory, this.ApplicationDir, isInstalled);
            pathSettings.UserFilesDirectory = this.MakeAbsoluteFromApplicationDir(pathSettings.UserFilesDirectory, this.ApplicationDir, isInstalled);

            %Clean the paths up, removing extra \\..\\.. loops etc
            pathSettings.DefaultDirectory = Palladium.Utilities.PathUtils.CleanPath(pathSettings.DefaultDirectory);
            logSettings.LogFileDirectory = Palladium.Utilities.PathUtils.CleanPath(logSettings.LogFileDirectory);
            pathSettings.DefaultSequenceDirectory = Palladium.Utilities.PathUtils.CleanPath(pathSettings.DefaultSequenceDirectory);
            pathSettings.UserFilesDirectory = Palladium.Utilities.PathUtils.CleanPath(pathSettings.UserFilesDirectory);

            %Verify that the DefaultDirectory exists - if it doesn't, try to make that folder. If that fails, set to a fallback
            %and warn user.
            if(~isfolder(pathSettings.DefaultDirectory))
                %Show a warning in the command window
                disp("Could not find directory " + pathSettings.DefaultDirectory + " specified in the config file. Creating new directory.");

                try
                    %Create the folder
                    mkdir(pathSettings.DefaultDirectory);

                    %Assert the creation was successful
                    assert(isfolder(pathSettings.DefaultDirectory), "LoadSettingsError:FolderNotFound", "Folder not found at path");
                catch exception
                    %Fall back to the user's Documents folder (or their home
                    %folder if there is none), on Windows, Mac and Linux - it
                    %always exists, so nothing more has to be created
                    fallbackDir = Palladium.Utilities.PathUtils.GetDocumentsDirectory();

                    %Warn the user. A MATLAB warning, not the Logger, which is
                    %not set up yet - in the standalone app it shows as a dialogue
                    warning("LoadSettingsWarning:DefaultDirectoryCreationFailed", "%s", "Could not find directory " + pathSettings.DefaultDirectory + " specified in the config file, and hit an error while trying to create it. Saving data to " + fallbackDir + " instead. Error message: " + string(exception.message));

                    %Set the Default Dir
                    pathSettings.DefaultDirectory = fallbackDir;

                end
            end
        end

        function PlotterAxesSelectionChange(this, pltr)
            %Replot a plotter whose axes were changed while measurements are not running.
            %While the loop runs, a plotter whose axis selection changes
            %replots on its next update tick. With no ticks that never
            %happens, so this listens to the plotter's AxesSelectionChange
            %event and replots it with the whole DataTable (if there is any
            %data)

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

        function PythonSetupWarningClosed(this, evt)
            %Remember in the config file if the user chose not to see the Python setup warning again.

            if evt.SelectedOption ~= "Don't show this again"
                return
            end
            try
                this.WarningSettings.SuppressPythonSetupWarning = true;
                configIO = Palladium.Utilities.ConfigIO();
                configIO.SetConfigValue("WarningSettings", "SuppressPythonSetupWarning", true, ConfigFilePath=this.ConfigFilePath);
                this.Log("Info", "Python setup warning turned off (WarningSettings.SuppressPythonSetupWarning in " + this.ConfigFilePath + ")", "Green", "Python setup warning turned off");
            catch err
                this.HandleError("Error saving the Python setup warning setting", err);
            end
        end

        function SavePlot(this, eventData)
            %Save a plotter's figure, as a .fig and a .png, next to the data file, when its SavePlot event fires.

            try
                %Save the figure and a png to file using the existing
                %DataWriter
                this.DataWriter.SaveFigure(eventData.Figure, eventData.Axes, this.FileWriteDetails.Directory, this.FileWriteDetails.FileName);

                %Display a status message in the logger
                this.Log("Info", "Plot saved", "Green", "Plot saved");
            catch err
                this.HandleError("Error saving figure", err);
            end
        end

        function status = SetUpPython(this)
            %Choose the Python to use, and check it can be used for Python instruments.
            %In order of preference: PythonSettings.PythonExecutable from the
            %config, the Python bundled with the standalone application
            %(installed in its application folder), or the one MATLAB finds
            %itself (see pyenv)
            %
            %Outputs:
            %   status - setup status struct (see PythonUtils.CheckPythonSetup)

            executable = string(this.PythonSettings.PythonExecutable);
            if isempty(executable) || executable == ""
                bundledPython = fullfile(this.ApplicationDir, "Python", "python.exe");
                if isdeployed && isfile(bundledPython)
                    executable = bundledPython;
                else
                    executable = "";
                end
            end

            if executable ~= ""
                [success, message] = Palladium.Utilities.PythonUtils.UsePythonExecutable(executable);
                if ~success
                    status = Palladium.Utilities.PythonUtils.MakeSetupStatus("LoadFailed", Executable=executable, ErrorMessage=message);
                    return
                end
            end

            status = Palladium.Utilities.PythonUtils.CheckPythonSetup();
        end

        function ShowPythonSetupWarning(this)
            %Show a dialog explaining any problem setting up Python, and how to fix it.
            %Not shown if Python is fine, the user has turned this warning
            %off, or there is no GUI to show it in. Doesn't wait for the
            %dialog to close

            if isempty(this.PythonSetupStatus) || this.PythonSetupStatus.Status == "OK" || this.WarningSettings.SuppressPythonSetupWarning
                return
            end

            try
                uifg = this.UIFigureHandle;
                if ~matlab.ui.internal.isUIFigure(uifg)
                    return
                end
                [title, msg] = Palladium.Utilities.PythonUtils.SetupHelpMessage(this.PythonSetupStatus, ConfigFilePath=this.ConfigFilePath);
                uiconfirm(uifg, msg, title, "Options", ["OK", "Don't show this again"], "DefaultOption", 1, "CancelOption", 1, ...
                    "Icon", "warning", "Interpreter", "html", "CloseFcn", @(~, evt) this.PythonSetupWarningClosed(evt));
            catch err
                this.HandleError("Error showing the Python setup warning", err);
            end
        end

    end

    %% Methods (Static, Private)
    methods(Static, Access = {?Palladium.Core.Controller, ?matlab.unittest.TestCase})    %Permission is Private, but also allow unit tests to see it

        function path = MakeAbsoluteFromApplicationDir(path, applicationDir, isInstalled)
            %Make a config folder path absolute, taking a relative one as relative to applicationDir.
            %An absolute path (PathUtils.IsAbsolutePath) is returned as it
            %is. In an installed copy (toolbox or compiled application),
            %applicationDir is the installation folder - which may not be
            %writable, and is replaced by each update - so a relative path
            %gives a warning. The Logger is not set up yet when the config
            %is loaded, so this is a MATLAB warning
            %
            %Inputs:
            %   path           - a config folder path, e.g. "Data" or "C:\Data"
            %   applicationDir - the folder Palladium.m is in
            %   isInstalled    - true if this is not a source checkout (ConfigIO.IsSourceCheckout)
            %
            %Outputs:
            %   path - the absolute path

            if Palladium.Utilities.PathUtils.IsAbsolutePath(path)
                return
            end

            relativePath = path;
            path = fullfile(applicationDir, path);
            if isInstalled
                warning("LoadSettingsWarning:RelativePathInInstalledCopy", "%s", "The folder """ + relativePath + """ in the config file is a relative path, so it is inside Palladium DAQ's installation folder (" + ...
                    Palladium.Utilities.PathUtils.CleanPath(path) + "). That folder may not be writable, and is replaced when Palladium DAQ is updated - set a full path for it in the config file instead.");
            end
        end

    end

end
