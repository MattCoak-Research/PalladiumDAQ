classdef Palladium < handle
    % PALLADIUM Entry point and overall container class of a Palladium DAQ instance - adds a
    % Controller and a View (usually the Palladium_DefaultGUI GUI, but can be
    % a command-line-only implementation or any other user-defined one if
    % desired)
    %
    % To run, just type Palladium; into the Command Window. Not in a
    % namespace, so nothing else needed. This will launch with the default
    % GUI as the View.
    %
    % To launch with no View, pass the View optional command as empty, ie
    % Palladium(View=[]);
    %
    % To launch with a Preset, enter the name of a file in the Presets
    % folder as the Preset argument, ie Palladium(Preset="Example");

    %% Properties(Constant, Private)
    properties (Constant, Access = private)
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Palladium Version Information
        % Will be read by the ver() function and therefore by the buildfile to define the Toolbox version numbers
        % Update these to define the Palladium Version Number

        %Major version number - semantic versioning used of form
        %major.minor.build, each of these are integers.
        MajorVersionNo = 3;

        %Minor version number - semantic versioning used of form
        %major.minor.build, each of these are integers.
        MinorVersionNo = 1;

        %Build version number - semantic versioning used of form
        %major.minor.build, each of these are integers.
        BuildVersionNo = 1;

        %Author information
        AuthorString = "M.J. Coak, University of Birmingham";
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        %Path to directory of built-in Preset files
        PresetsDirectory = filesep + "+PalladiumPresets";    
    end

    %% Properties (Private)
    properties (Access = {?Palladium, ?matlab.unittest.TestCase})
        Controller; %The reference to the Controller.m logic class that centrally coordinates everything in Palladium
        View = [];  %An optional GUI attached to the Palladium instance, with buttons and graphs etc. Not actually required to run the Programme
    end

    %% Methods (Static, Public)
    methods (Access = public, Static, Sealed)

        function verStruct = ver()
            % VER - Return Palladium version information struct, from private
            % const properties in the Palladium class definition. Those
            % properties are the single definition of what version the
            % current build is - toolbox, help etc versions will draw from
            % these.
            % Static method - evoke with Palladium.ver from any context.
            %
            % Output arguments:
            % verStruct - struct with fields: VersionString (string), FullversionString (string), Major (integer),
            %             Minor (integer), Build (integer), and AuthorString (string) fields
            verStruct.VersionString = sprintf('%d.%d.%d', Palladium.MajorVersionNo, Palladium.MinorVersionNo, Palladium.BuildVersionNo);
            verStruct.FullVersionString = sprintf('Palladium DAQ Version %d.%d.%d', Palladium.MajorVersionNo, Palladium.MinorVersionNo, Palladium.BuildVersionNo);
            verStruct.Major = Palladium.MajorVersionNo;
            verStruct.Minor = Palladium.MinorVersionNo;
            verStruct.Build = Palladium.BuildVersionNo;
            verStruct.AuthorString = Palladium.AuthorString;
        end

    end


    %% Constructor
    methods
        function this = Palladium(Settings)
            % PALLADIUM - Construct Palladium application object
            %
            % Example call: Palladium(Preset="Example", ConfigFilePath="ExampleFolder/Config.json");
            % View and ConfigFilePath arguments have built-in defaults, will
            % not normally need to be overridden.
            %
            % Preset is an optional functionality - entering the name of a file in the Presets
            % directory will apply that Preset after programme
            % initialisation. This means executing the code in that Preset
            % (basically a script) file to eg set a data directory, add a 2nd
            % plotting Window, add an Instrument and configure it. The idea
            % is that a Preset corresponds to a physical setup in the lab
            % that would be tedious to have to input and configure every time
            % the programme is launched - and thse are intended to be created and edited
            % by the User. See help on Presets and the Example.m file in the Presets folder
            % for help on creating Presets.
            %
            % Input arguments (optional, see arguments block):
            %  - ConfigFilePath (string or empty/null []. Default is []) - Default is blank ([]) - enter a filepath instead to override default Config json file loading and pass in the path for another settings file to be loaded from
            %  - DebugMode (logical. Default is false) - set to true to
            %  throw full errors on all Instrument error messages. This is
            %  for use when debugging issues or testing in development.
            %  - Preset (string or []. Default is []) - Optionally, enter the name of a Preset script in the +PalladiumPresets folder, like "Example"
            %  - View (string or []. Default is "PalladiumDAQ_DefaultGUI") -
            %  Enter blank ([]) to run a 'headless' Palladium with no GUI
            %  attached. Give the name of a .mlapp file in the +Views folder
            %  to use that GUI/View instead of the default.
            arguments
                Settings.ConfigFilePath = [];
                Settings.DebugMode (1,1) logical = false;
                Settings.Preset = [];
                Settings.View = "PalladiumDAQ_DefaultGUI";
            end

            %Check that new enough Matlab version is installed, toolboxes
            %are there.. etc etc. Will throw error if not
            Palladium.Utilities.Verification.ValidateInstall(MatlabVersion="R2025b", ToolboxNames = {"Instrument Control Toolbox"});

            %Set application paths for loading of child classes later - make
            %all paths relative to this, the filepath of the Palladium.m file
            %- if we don't do this they will be relative to the user's
            %current matlab open folder, which is a recipe for disaster
            applicationPath = mfilename('fullpath');
            [applicationDir, ~, ~] = fileparts(applicationPath);

            %Grab the version numbers, to e.g. send to a created View
            versionInfo = Palladium.ver();

            %Create the view/frontend/implementation/GUI
            if ~isempty(Settings.View)
                view = this.CreateView(Settings.View, applicationDir);
                view.SetVersionInformation(versionInfo.FullVersionString, versionInfo.Major, versionInfo.Minor, versionInfo.Build, versionInfo.AuthorString);
                this.View = view;
            else
                view = [];
            end

            %Create a Controller class that will handle all the backend logic
            this.Controller = Palladium.Core.Controller( ...
                "ApplicationDir", applicationDir,...
                "ApplicationPath", applicationPath,...
                "DebugMode", Settings.DebugMode...
                );

            %Register the view with the Controller
            if ~isempty(Settings.View)
                this.Controller.AttachView(view);
            end

            %If an override config path has been given, check that it has
            %the full path, including .json, and that the file exists
            if ~isempty(Settings.ConfigFilePath)
                %Check the file extension, add if missing
                Settings.ConfigFilePath = Palladium.Utilities.PathUtils.EnsureExtension(Settings.ConfigFilePath, ".json");
                %Check the file exists
                assert(isfile(Settings.ConfigFilePath), "Could not find override Config file at " + string(Settings.ConfigFilePath));
            end

            %Initialise the Controller
            this.Controller.Initialise(versionInfo.FullVersionString, ConfigFilePath=Settings.ConfigFilePath);

            %Apply a preset, if specified in the optional arguments
            if ~isempty(Settings.Preset)
                presetFn = this.LoadPreset(Settings.Preset);
                if ~isempty(presetFn)   %ie did it load succesfully
                    this.ApplyPreset(presetFn, view);
                end
            end

            %Tell the controller we have finished loading everything and
            %are ready to go
            this.Controller.OnLoaded();
        end
    end

    %% Methods (Public)
    methods

        function instRef = AddInstrument(this, instrumentClassName, settings)
            % ADDINSTRUMENT - Add or an Instrument instance to Palladium,
            % with optional settings.
            %
            % Usage: pd = Palladium(); to make a Palladium instance and
            % store the reference to it, then
            % pd.AddInstrument("Keithley2000");
            % or with optional arguments;
            % pd.AddInstrument("Keithley2000", ConnectionType="GPIB");
            %
            % To store the reference to that new instrument, assign the
            % output of this function:
            % keithleyInstrument = pd.AddInstrument("Keithley2000");
            % then one can do things like keithleyInstrument.Name =
            % "NewName"; or call functions on that Instrument.
            %
            % Input arguments:
            % this                - parent/manager object
            % instrumentClassName - instrument class name (text scalar)
            % settings            - struct with Name and ConnectionType (text scalars)
            %
            % Output arguments:
            % instRef             - reference/handle to the created or existing instrument
            arguments
                this;
                instrumentClassName {mustBeTextScalar};
                settings.Name {mustBeTextScalar} = "Auto";
                settings.ConnectionType {mustBeTextScalar} = "Auto";
            end

            %Pass through to Controller
            instRef = this.Controller.InstrumentController.AddInstrument(string(instrumentClassName), Name=string(settings.Name), ConnectionType=settings.ConnectionType);
        end

        function cont = AddInstrumentControl(this, instrRef, controlName, Settings)
            % ADDINSTRUMENTCONTROL - Order the GUI View to create and add a
            % Control for an existing Instrument. For example, add a 'Sweep
            % Control' Instrument Control object to a Keithley2000 that was
            % already added to Palladium.
            %
            % Input arguments:
            % - instrRef - Palladium.Core.Instrument reference - the instrument to add the control to (required)
            % - controlName - name of the control (text scalar) - must  match one of the Names defined in that Instrument's constructor, e.g. this.DefineInstrumentControl(Name = "Sweep Control", ClassName = "SweepController_Stepped", TabName = "Sweep Control", EnabledByDefault = false);
            %
            % Optional Name-Value pair arguments:
            % (Blank by default, override with string values to redefine the default values for this control)
            % - ControlName
            % - TabName
            arguments
                this;
                instrRef (1,1) Palladium.Core.Instrument;
                controlName (1,1) {mustBeTextScalar};
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
            cont = this.AddInstrumentControlFromStruct(instrRef, controlDetailsStruct);
        end

        function cont = AddInstrumentControlFromStruct(this, instrRef, controlDetailsStruct)
            % ADDINSTRUMENTCONTROLFROMSTRUCT - Create control from struct and
            % attach to instrument. This is a more advanced version for
            % scripting - easier to use ADDINSTRUMENTCONTROL which just needs
            % the name of the Control.
            %
            % Input arguments:
            % - this - container/manager object
            % - instrRef - Palladium.Core.Instrument instance to attach control to
            % - controlDetailsStruct - struct describing control parameters. Easiest way to get this is to call controlDetailsStruct = instrRef.GetControlOption(controlName) on an existing Instrument reference
            arguments
                this;
                instrRef (1,1) Palladium.Core.Instrument;
                controlDetailsStruct (1,1) struct;
            end

            %Pass on to the View
            cont = this.View.AddInstrumentControl(instrRef, controlDetailsStruct);
        end

        function Close(this)
            % CLOSE - Close the programme. Deletes View and Controller.

            if ~isempty(this.View)
                this.View.Close();
            else
                % Notify controller when there is no view to close
                this.Controller.OnFigureClosed();
            end
            delete(this.View);
            delete(this.Controller);
            this.View = [];
            this.Controller = [];
        end

        function classNames = GetAllInstrumentClassNames(this)
            %GETALLINSTRUMENTCLASSNAMES - Return a list (array of strings)
            %of all available Instrument class names - all the files in the
            %built-in and user Instrument folders.
            classNames = this.Controller.GetAllInstrumentClassNames();
        end

        function Pause(this)
            %PAUSE - Pause the Measurement Loop
            this.Controller.TimingLoopController.Pause();
        end

        function RemoveInstrument(this, instrRef)
            % REMOVEINSTRUMENT - Remove an instrument
            %
            % Input arguments:
            % instrRef - reference to the Palladium.Core.Instrument to remove
            arguments
                this;
                instrRef (1,1) Palladium.Core.Instrument;
            end

            this.Controller.InstrumentController.RemoveInstrument(instrRef);
        end

        function RemoveInstrumentControl(this, instrRef, controlName)
            % REMOVEINSTRUMENTCONTROL - Remove a named Instrument Control
            % from an instrument. This will error if a Control of this name
            % has not previously been added to that Instrument
            %
            % Input arguments:
            % instrRef    - Palladium.Core.Instrument reference to modify
            % controlName - name of control to remove (text scalar)
            arguments
                this;
                instrRef (1,1) Palladium.Core.Instrument;
                controlName {mustBeTextScalar};
            end

            %Get the struct with the control's details from the Instrument
            controlDetailsStruct = instrRef.GetControlOption(controlName);

            %Pass through to function below - this one is basically a nice
            %wrapper for it
            this.RemoveInstrumentControl(instrRef, controlDetailsStruct);
        end

        function RemoveInstrumentControlFromStruct(this, instrRef, controlDetailsStruct)
            % REMOVEINSTRUMENTCONTROLFROMSTRUCT - Remove a Control tied to an
            % instrument (e.g. a SweepController). This function is an
            % advanced utility function for scripting. Easier to use
            % REMOVEINSTRUMENTCONTROL, which just needs the name of the
            % Control's class.
            %
            % Input arguments:t
            % instrRef - Palladium.Core.Instrument instance reference
            % controlDetailsStruct - struct describing the control to remove
            arguments
                this;
                instrRef (1,1) Palladium.Core.Instrument;
                controlDetailsStruct (1,1) struct;
            end
            this.View.RemoveInstrumentControl(instrRef, controlDetailsStruct);
        end

        function Resume(this)
            %RESUME - Resume the (previously paused) Measurement Loop
            this.Controller.TimingLoopController.Resume();
        end

        function SetDescription(this, descriptionText)
            % SETDESCRIPTION - Set textual description for the current data
            % file. Will be written into the top-of-file metadata on
            % measurement Start
            %
            % Input arguments:
            % descriptionText - text or string describing the object
            arguments
                this;
                descriptionText {mustBeText};
            end

            %Pass through to Controller
            this.Controller.SetFilePathsDescription(descriptionText);
        end

        function SetDirectory(this, directory)
            % SETDIRECTORY - Set Palladium's working directory, where data
            % files will be saved
            %
            % Input arguments:
            % directory - target directory as text scalar
            arguments
                this;
                directory {mustBeTextScalar};
            end

            %Pass through to Controller
            this.Controller.SetFilePathsDirectory(directory);
        end

        function SetFileExtension(this, fileExtension)
            % SETFILEEXTENSION - Set the file extension that will be used for
            % data files Palladium writes
            %
            % Input arguments:
            % fileExtension - text scalar specifying the new file extension
            arguments
                this;
                fileExtension {mustBeTextScalar};
            end

            %Pass through to Controller
            this.Controller.SetFilePathsFileExtension(fileExtension);
        end

        function SetFileName(this, fileName)
            % SETFILENAME - Set the filename for this object
            %
            % Input arguments:
            % fileName - text scalar specifying the new filename
            arguments
                this;
                fileName {mustBeTextScalar};
            end

            %Pass through to Controller
            this.Controller.SetFilePathsFileName(fileName);
        end

        function SetSaveFileBool(this, saveFileBool)
            % SETSAVEFILEBOOL - Set flag controlling whether to save to file.
            % If this is false, no data file will be written to disk. By
            % default this is true
            %
            % Input arguments:
            % saveFileBool - logical scalar, true to enable saving
            arguments
                this;
                saveFileBool (1,1) logical;
            end

            %Pass through to Controller
            this.Controller.SetFilePathsSaveFileBool(saveFileBool);
        end

        function SetUpdateTime(this, time_s)
            % SETUPDATETIME - Set target update interval for the measurement loop, in seconds
            %
            % Input arguments:
            % time_s - update interval in seconds (positive scalar)
            arguments
                this;
                time_s (1,1) double {mustBePositive};
            end

            %Pass through to Controller
            this.Controller.TimingLoopController.SetUpdateTime(time_s);
        end

        function SetWriteMode(this, writeMode)
            % SETWRITEMODE - Set the object's write mode
            %
            % Input arguments:
            % writeMode - text scalar specifying write mode ("Append To File", )
            arguments
                this;
                writeMode {mustBeTextScalar, mustBeMember(writeMode, {"Increment File No.", "Overwrite File", "Append To File"})};
            end

            %Pass through to Controller
            this.Controller.SetFilePathsWriteMode(writeMode);
        end

        function Start(this)
            %START - Start the Measurement Loop; start measurements,
            %connecting to and initialising all Instruments, then looping
            %through in ticks to collect data from each, send commands,
            %update plots, save data to file
            this.Controller.TimingLoopController.Start();
        end

        function Stop(this)
            %STOP - Stop the Measurement Loop
            this.Controller.TimingLoopController.Stop();
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function ApplyPreset(this, presetFn, view)
            try
                %Display a status message in the logger
                this.Controller.ShowStatus('Yellow', 'Applying Preset');

                %Execute the Preset script file
                presetFn(this, view);

                %Display a status message in the logger
                this.Controller.ShowStatus('Yellow', 'Finalising Preset');

                %Finalise the preset - basically, update the GUI to reflect
                %changes
                notify(this.Controller, "FinalisePreset");
            catch err

                if strcmp(err.message, "Dot indexing is not supported for variables of this type.") && isempty(view)    %Add additional helpder text to the error if it's likely we are trying to call functions on an empty GUI. Note we're avoiding isempty checks or architectural complexity in the PReset functions to keep them easy to edit and understand, which means the user can do silly things like this
                    try
                        error("Assignment error in a Preset with no attached view. The 'gui' argument is null, are you trying to call functions like AddPlottingWindow on it? Error message: " + string(err.message));
                    catch exception
                        this.Controller.HandleError("Error applying Preset", exception);
                    end
                else
                    this.Controller.HandleError("Error applying Preset", err);
                end
            end
        end

        function view = CreateView(~, viewFileName, applicationDir)
            %Instantiate an instance of the View/GUI class from file, just
            %from the desired filename

            %Construct the needed paths
            viewDir = fullfile(applicationDir,"+Palladium","+Views");
            fullViewCodeFilePath = fullfile(viewDir,viewFileName);
            namespaceClassPath = "Palladium.Views." + viewFileName;

            %Check that this file exists in the expected folder
            assert(exist(fullViewCodeFilePath + ".m", "file") || exist(fullViewCodeFilePath + ".mlapp", "file"), "View file " + fullViewCodeFilePath + " not found");

            %Create an instance of the required class (empty constructor)
            fnHandle = str2func(namespaceClassPath);
            view = fnHandle();
        end

        function dirPath = GetPresetsDir(this)
            dirPath = fullfile(this.Controller.ApplicationDir,  this.PresetsDirectory);
        end

        function presetFn = LoadPreset(this, presetName)
            presetFn = [];
            %Display a status message in the logger
            this.Controller.ShowStatus('Yellow', 'Loading Preset');

            try
                %Fetch paths
                presetsDir = this.GetPresetsDir();
                presetPath = fullfile(presetsDir, presetName) + ".m";

                %Error checking
                assert(exist(presetsDir,"dir") == 7, "Presets directory " + string(presetsDir) + " not found");
                assert(exist(presetPath,"file") == 2, "Preset file " + string(presetPath) + " not found");

                %Load the present in as a function handle
                presetFn = Palladium.Utilities.PluginLoading.InstantiatePreset("PalladiumPresets", presetName);
            catch err
                this.Controller.HandleError("Error loading Preset", err);
            end
        end

    end
end

