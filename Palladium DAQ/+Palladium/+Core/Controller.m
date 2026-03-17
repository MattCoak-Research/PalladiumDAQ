classdef Controller < handle
    %CONTROLLER Logic and measurement loop for Palladium DAQ Programme. 

    properties       
        %Paths and Directories
        ApplicationPath;    %These will be set in StartUp Fcn of the UiFigure
        ApplicationDir;     %These will be set in StartUp Fcn of the 
    end

    properties(GetAccess = public, SetAccess = private)
        %Settings structs
        WindowSettings;
        PathSettings;
        FileWriteDetails;

        %Data array
        DataTable;
        Headers = {};
        Units = {};

        %Sub-controllers
        TimingLoopController;
        InstrumentController;
        DataWriter;
    end

    properties(Access = private)
        PlottingController;
        SequenceEditorController;

        DefaultDataDir;

        Closing = false;    %Will get set by an attached GUI if it is in the process of being closed, to tell us to stop sending events to a now-invalid GUI

        SuppressedErrorMessages = {};
        UIFigureHandle = []; %Needed for error handling - need to know if we are throwing a modal dialogue box in an attached UIFigure, or a free floating normal one if there is no listening View
    end

    properties(Constant)
        PresetsDirectory = filesep + "+PalladiumPresets";
    end

    events
        DataRowUpdated;
        FileWriteOptionsChanged;
        FinalisePreset;
        GreenStatus;
        Loaded;
        RedStatus
        SettingsApplied;
        StartedShowingProgress;
        StoppedShowingProgress;
        UpdatedProgress;
        YellowStatus;
    end

    methods
        %% Constructor
        function this = Controller(Settings)
            arguments
                Settings.ApplicationDir {mustBeTextScalar};
                Settings.ApplicationPath {mustBeTextScalar};
            end

            this.ApplicationDir = Settings.ApplicationDir;
            this.ApplicationPath = Settings.ApplicationPath;

            %Create a helper class for managing Instruments
            this.InstrumentController = Palladium.Core.InstrumentController(this);
           
            %Create a helper class for controlling the main
            %measurement/timing loop, Start/Pause/Resume etc
            this.TimingLoopController = Palladium.Core.TimingLoopController(this);
           
            %And one for handling all things Plotting
            this.PlottingController = Palladium.Core.PlottingController();
        end

        %% AttachView
        function AttachView(this, view)
            %Assign controllers into the View and have it subscribe to
            %their events
            view.AssignControllersAndHookUpEvents(this, this.TimingLoopController, this.InstrumentController);
        end            
        
        %% AddNewPlotter
        function pltr = AddNewPlotter(this, parent, Settings)
            %This is used by things like Instrument Control creating GUIs
            %and placing Plotters in existing Gridlayouts
            arguments
                this;
                parent = [];
                Settings.Size = "Medium";
                Settings.RegisterPlotter = true;
            end

            try
                %Create a new parent figure for the plotter to go in if we
                %didn't specify a parent
                if isempty(parent)
                    parent = uifigure();
                end

                %Get the Plotting Controller to actually construct the
                %plotter, add it to whatever parent we sent in. All of this
                %is View-agnostic, and doesn't need one at all.
                pltr = this.PlottingController.CreateNewPlotter(parent, Settings.Size);
           
                %Subscribe to events
                if Settings.RegisterPlotter
                    addlistener(pltr, 'AxesSelectionChange', @(src,evnt)this.PlotterAxesSelectionChange(src));
                end

                addlistener(pltr, 'SavePlot', @(src,evnt)this.SavePlot(evnt));

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
                pltr = this.PlottingController.CreateNewSimplePlotter(parent, size);
                
                %Subscribe to events
                addlistener(pltr, 'SavePlot', @(src,evnt)this.SavePlot(evnt));

                %Simple plotters do not get registered for auto-updates.
                %Whatever made them has to push data to them itself.
            catch err
                this.HandleError("Error adding new simple plotter", err);
            end
        end
        
        %% CanStart
        function canStart = CanStart(this)
            canStart = false;
            try
                %Verify directory and path valid
                if(~Palladium.Utilities.PathUtils.IsDirectoryValid(this.FileWriteDetails.Directory))
                    error(['Error - directory not valid: ' strrep(this.FileWriteDetails.Directory, '\', '\\')]);
                end
                if(~Palladium.Utilities.PathUtils.IsFileNameValid(this.FileWriteDetails.FileName))
                    error(['Error - file name not valid: ' strrep(this.FileWriteDetails.FileName, '\', '\\')]);
                end
            catch err
                this.Controller.HandleError('Invalid file path. Cannot start measurements', err);
                return;
            end

            canStart = true;
        end      

        %% CloseProgress
        function CloseProgress(this)
            notify(this, "StoppedShowingProgress");
        end

        %% GetAllInstrumentClassNames
        function classNames = GetAllInstrumentClassNames(this)
            classNames = this.InstrumentController.ListOfAvailableInstrumentClassNameStrings;
        end

        %% HaltMeasurementsOnInstrumentError
        function HaltMeasurementsOnInstrumentError(this, instr, e)
            %Show error message and ask if we want to stop measurements
            halt = this.HandleError("Error in main measurement loop - Collect Data from " + instr.FullName, e);
            if(halt)
                Palladium.Logging.Logger.Log("Info", "Measurements aborted by User from Error Dialogue");
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
                Palladium.Logging.Logger.Log("Error", msg, "FullMessage", msg + " : " + string(getReport(error, "extended", "hyperlinks", "on")));
            catch e
                warning("An error was thrown while.. trying to handle an error.. : " + string(e.message));
            end

            %Pass on the error to the Error Handler to show a dialogue box
            %- user can choose whether to stop the measurement loop, and
            %separately whether to suppress this error going forward
            [Halt, suppressError] = Palladium.Logging.Logger.HandleError(message, error, this.UIFigureHandle);

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

        %% HandleWarning
        function HandleWarning(this, msg, title)
            try
                uifg = this.UIFigureHandle;
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
                [logSettings, this.PathSettings, this.WindowSettings, this.PlottingController.PlotterSettings] = this.LoadSettings();
            catch e
                %Note that we don't pass this in to any nice error handling
                %because we haven't set that up yet
                error("Error in loading settings in Controller.Initialise: " + string(e.message));
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

                %Retrieve iconPath to pass to a GUI
                this.WindowSettings.PalladiumIconPath = this.ApplicationDir + "\+Palladium\+Components\Graphics\PalladiumDAQIcon.png";

                %Send settings to the GUI
                args = Palladium.Events.SettingsChangedEventData(this.PathSettings, this.WindowSettings);
                notify(this, "SettingsApplied", args);

                %Load plugins
                this.Log("Debug", "Initialising plugins", "Yellow", "Initialising plugins...");
                this.InstrumentController.LoadInstrumentClasses(this.ApplicationDir + "\+Palladium\+Instruments");
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
            this.DataWriter = Palladium.DataWriting.DataWriter(this.FileWriteDetails);
            this.FileWriteDetails.FileName = this.DataWriter.ValidateFilePath();

            %Update the View to display the file write settings
            args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
            notify(this, "FileWriteOptionsChanged", args);

            %Clean up Plotters list, remove any that have been deleted
            this.PlottingController.CleanUpPlotters();
        end

        %% InitialiseMeasurements
        function [success, msg, title] = InitialiseMeasurements(this)
            %Reset and prepare all GUI and instruments ready to then run
            %the main update loop - note that Resume doesn't call this,
            %just gets the loop running again without it
            success = false; msg = ""; title = "";

            %Display a status message in the logger
            this.Log("Info", "Initialising measurements", "Yellow", "Initialising measurements");

            %Display a model progress bar so we can't go clicking things
            %while intialisation is underway - and also get clued in that a
            %slow operation is in fact running and we shouldn't click Start
            %100 times like my dad
            this.ShowProgress("Initialising measurements", "Initialising..");

            try
                %Generate column headers and validate
                [this.Headers, headersString, this.Units] = this.InstrumentController.InitialiseHeaders();

                %Initialise the (:, n) double array that will hold the
                %data
                this.DataTable = [];

                %Initialise all instruments
                [success, msg, title] = this.InstrumentController.InitialiseInstruments();

                if ~success
                    return;
                end

                %Initialise all graphs
                this.PlottingController.UpdatePlotVariableNames(this.Headers);
                this.PlottingController.ClearPlots();

                %Display a status message in the logger
                this.Log("Info", "Measurements initialised", "Green", "Measurements initialised");
            catch e
                this.CloseProgress();
                this.HandleError("Error initialising measurements", e);
                return;
            end

            %Add a metadata/settings line to the top of the datafile (in
            %the header) for each instrument that defines one
            try
                %Update the progress bar
                this.UpdateProgress(1, "Writing metadata and headers");

                %Get the string to write from Instruments
                metadataLines = this.InstrumentController.GetMetadataLines();

                %Succesful end - close the progress bar
                this.CloseProgress();
            catch e
                this.CloseProgress();
                this.HandleError("Error collecting instrument metadata", e);
            end

            %Write the headers to file
            this.DataWriter.WriteHeaders(headersString, "MetadataLines", metadataLines);

            success = true;            
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
            Palladium.Logging.Logger.Log(level, logText);
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
                dataRow = this.InstrumentController.CollectMeasurement(this.Headers);
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
                if(this.Closing)
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
                        Palladium.Logging.Logger.Log("Info", "Measurements aborted by User from Error Dialogue");
                        this.TimingLoopController.OnStopped();
                    end
                end
            end
        end       

        %% OnFigureClosed
        function OnFigureClosed(this)
            this.Log("Debug", "Palladium DAQ closed", "Yellow", "Closing");
            this.Closing = true;
            this.TimingLoopController.CloseTimer();
            this.InstrumentController.CloseAll();
        end

        %% OnLoaded
        function OnLoaded(this)
            %Display a status message in the logger
            this.Log("Info", "Palladium loaded", "Green", "Ready");

            try
                %Let the user interact with the GUI now it is loaded and ready
                notify(this, "Loaded");
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
                this.SequenceEditorController = Palladium.Sequence.SequenceEditorController(...
                    this,...
                    "DefaultSequenceDirectory", this.PathSettings.DefaultSequenceDirectory,...
                    "SequenceFileExtension", this.PathSettings.SequenceFileExtension);

                %Add a View/GUI to that
                this.SequenceEditorController.CreateView("SequenceEditor_DefaultGUI", this.ApplicationDir);

            catch err
                this.HandleError("Error opening Sequence Viewer", err);
            end
        end           

        %% RegisterUIFigure
        function RegisterUIFigure(this, uiFigureHandle)
            arguments
                this;
                uiFigureHandle (1,1) handle;
            end

            this.UIFigureHandle = uiFigureHandle;
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
                %Pass on through to InstrumentController
                this.InstrumentController.RemoveInstrumentControl(instrRef, controlDetailsStruct);
              
                %Verbose/debug message printing
                this.Log("Info", "Removed Instrument Control: " + controlDetailsStruct.Name, "Green", "Removed Instrument Control");
            catch err
                this.HandleError("Error removing instrument control " + controlDetailsStruct.Name, err);
            end
        end

        %% SetFilePathsDirectory
        function SetFilePathsDirectory(this, directory)
            try
                this.FileWriteDetails.Directory = Palladium.Utilities.PathUtils.CleanPath(directory);

                %Update the View
                args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
                notify(this, "FileWriteOptionsChanged", args);
            catch err
                this.HandleError("Error in SetFilePathsDirectory", err);
            end
        end

        %% SetFilePathsFileExtension
        function SetFilePathsFileExtension(this, fileExtension)
            try
                this.FileWriteDetails.FileExtension = fileExtension;

                %Pass through to View
                args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
                notify(this, "FileWriteOptionsChanged", args);
            catch err
                this.HandleError("Error in SetFilePathsFileExtension", err);
            end
        end

        %% SetFilePathsDescription
        function SetFilePathsDescription(this, descriptionText)
            try
                this.FileWriteDetails.DescriptionText = descriptionText;

                %Pass through to View
                args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
                notify(this, "FileWriteOptionsChanged", args);
            catch err
                this.HandleError("Error in SetFilePathsDescription", err);
            end
        end

        %% SetFilePathsFileName
        function SetFilePathsFileName(this, fileName)
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

        %% SetFilePathsSaveFileBool
        function SetFilePathsSaveFileBool(this, saveFileBool)
            try
                this.FileWriteDetails.SaveFile = saveFileBool;

                %Pass through to View
                args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
                notify(this, "FileWriteOptionsChanged", args);
            catch err
                this.HandleError("Error setting save file bool", err);
            end
        end

        %% SetFilePathsWriteMode
        function SetFilePathsWriteMode(this, writeMode)
            try
                this.FileWriteDetails.WriteMode = writeMode;

                %Pass through to View
                args = Palladium.Events.ValueChangedEventData(this.FileWriteDetails);
                notify(this, "FileWriteOptionsChanged", args);
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

        %% ShowProgress
        function ShowProgress(this, msg, title)
          args = Palladium.Events.MessageEventData(msg, title);
          notify(this, "StartedShowingProgress", args);
        end

        %% ShowStatus
        function ShowStatus(this, colour, msg)
            switch(colour)
                case('Green')
                    notify(this, "GreenStatus", Palladium.Events.MessageEventData(msg));
                case('Yellow')
                    notify(this, "YellowStatus", Palladium.Events.MessageEventData(msg));
                case('Red')
                    notify(this, "RedStatus", Palladium.Events.MessageEventData(msg));
                otherwise
                    error('Colour unsupported in ShowStatus');
            end
        end

        %% UpdateProgress
        function UpdateProgress(this, progress, message)
            %Tell the Controller that a slow event has made progress. Will
            %trigger updates on GUI Progress Bars on an attached View
            arguments
                this;
                progress (1,1) double;
                message {mustBeTextScalar}
            end

            args = Palladium.Events.ProgressUpdateEventData(progress, message);
            notify(this, "UpdatedProgress", args);
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

        %% LoadSettings
        function [logSettings, pathSettings, windowSettings, plotterSettings] = LoadSettings(this)
            %Load the settings file into struct
            configIO = Palladium.Utilities.ConfigIO();
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
            pathSettings.DefaultDirectory = Palladium.Utilities.PathUtils.CleanPath(pathSettings.DefaultDirectory);
            logSettings.LogFileDirectory = Palladium.Utilities.PathUtils.CleanPath(logSettings.LogFileDirectory);
            pathSettings.DefaultSequenceDirectory = Palladium.Utilities.PathUtils.CleanPath(pathSettings.DefaultSequenceDirectory);

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

        %% SavePlot
        function SavePlot(this, eventData)
            try
                %Save the figure and a png to file using the existing
                %DataWriter
                this.DataWriter.SaveFigure(eventData.Figure, this.FileWriteDetails.Directory, this.FileWriteDetails.FileName);

                %Display a status message in the logger
                this.Log("Info", "Plot saved", "Green", "Plot saved");
            catch err
                this.HandleError("Error saving figure", err);
            end
        end
    end

end

