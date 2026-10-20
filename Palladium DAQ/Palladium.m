classdef Palladium < handle
    %Palladium - The Palladium DAQ program: create one to launch it, then control it from scripts.
    %Typing `Palladium` in the Command Window starts Palladium DAQ with its
    %GUI. `pd = Palladium(...)` does the same and returns the object, whose
    %public methods do from a script what the GUI's buttons do: add
    %instruments and Instrument Controls, set up the data file, and start,
    %pause and stop measurements. The class is not in a namespace, so no
    %`import` is needed.
    %
    %Name-value options when constructing (all optional):
    %
    %* `Preset` - name of a Preset in the user files folder's `Presets`
    %  folder, without `.json`, to apply on launch, e.g. `Preset="Example"`.
    %* `View` - the GUI to use, from the `Palladium.Views` namespace.
    %  `View=[]` runs with no GUI.
    %* `ConfigFilePath` - a Config.json to use instead of the usual one: a
    %  full path, or one relative to the folder `Palladium.m` is in.
    %* `DebugMode` - `true` to make instrument errors stop with a full stack
    %  trace, instead of being caught and logged. For developing drivers.
    %
    %A typical script:
    %
    %```matlab
    %pd = Palladium(View=[]);
    %k = pd.AddInstrument("Keithley2000", ConnectionType="Debug");
    %pd.SetDirectory("C:\Data");
    %pd.SetFileName("<DATE>_FirstTest");
    %pd.SetUpdateTime(0.5);
    %pd.Start();     % measurements then run in the background, on a timer
    %pd.Stop();
    %pd.Close();
    %```
    %
    %Internally, Palladium creates the `Palladium.Core.Controller`, which
    %coordinates everything, and the View, and attaches the View to the
    %Controller's events. Almost every method passes straight through to the
    %Controller or its `InstrumentController` and `TimingLoopController`.
    %`Palladium.ver()` returns the version, which is defined here. See
    %"Getting started" and "Presets and Config.json" in the documentation.

    %% Properties (Constant, Private)
    % The version of Palladium DAQ, read by ver() - and so by the buildfile,
    % for the toolbox version. Update these to set the version number
    properties (Constant, Access = private)
        MajorVersionNo = 3;     %Major version number (semantic versioning, major.minor.build)
        MinorVersionNo = 8;     %Minor version number (semantic versioning, major.minor.build)
        BuildVersionNo = 1;     %Build version number (semantic versioning, major.minor.build)
        AuthorString = "M.J. Coak, University of Birmingham";  %Author, returned by ver() and passed to the GUI with the version
    end

    %% Properties (Private)
    properties (Access = {?Palladium, ?matlab.unittest.TestCase})
        Controller; %The Palladium.Core.Controller that centrally coordinates everything in Palladium DAQ
        View = [];  %The GUI attached to this instance, or [] when running with no GUI
    end


    %% Constructor
    methods
        function this = Palladium(Settings)
            %Launch Palladium DAQ, optionally with a Preset, another Config file or no GUI.
            %Checks the MATLAB version and toolboxes, creates the View and the
            %Controller, loads Config.json, applies the Preset if one is given,
            %and then tells the Controller that loading is finished.
            %
            %A Preset is a .json file describing a setup to apply once
            %Palladium DAQ has started: the instruments to add, with their
            %settings and Instrument Controls, the update time, and plotting
            %tabs and windows with their default axes. Save one from the GUI
            %(Save Preset, under Settings), or edit a .json file by hand. See
            %"Presets and Config.json" in the documentation.
            %
            %Inputs (all optional name-value arguments):
            %   ConfigFilePath - path of a Config .json file to use instead of
            %                    the usual Config.json: a full path, or one relative
            %                    to the folder Palladium.m is in. ".json" is added if missing;
            %                    errors if the file is not found. Default []
            %   DebugMode      - true to throw full errors on all instrument
            %                    errors, for debugging and development. Default false
            %   Preset         - name of a .json Preset in the user files
            %                    folder's Presets folder, without the .json,
            %                    e.g. "Example". Default [], no Preset
            %   View           - class name of the GUI to use, in the
            %                    Palladium.Views namespace, or [] to run with no
            %                    GUI. Default "PalladiumDAQ_DefaultGUI"
            %
            %Outputs:
            %   this - the Palladium object, for scripting
            arguments
                Settings.ConfigFilePath = [];
                Settings.DebugMode (1,1) logical = false;
                Settings.Preset = [];
                Settings.View = "PalladiumDAQ_DefaultGUI";
            end

            %Compiler hint to tell MATLAB to include the default GUI in its
            %dependency analysis search when compiling (or it doesn't get
            %bundled in to the standalone exe)
            %#function Palladium.Views.PalladiumDAQ_DefaultGUI
            %#function Palladium.Instruments.Keithley2000
            %#function Palladium.Instruments.Keithley2410

            %Check that new enough Matlab version is installed, toolboxes
            %are there.. etc etc. Will throw error if not
            Palladium.Utilities.Verification.ValidateInstall(MatlabVersion="R2026b", ToolboxNames = {"Instrument Control Toolbox"});

            %Set application paths for loading of child classes later - make
            %all paths relative to this, the filepath of the Palladium.m file
            %- if we don't do this they will be relative to the user's
            %current matlab open folder, which is a recipe for disaster
            if isdeployed % Stand-alone mode: the installation folder, next to the executable
                try
                    applicationDir = char(Palladium.Utilities.PathUtils.GetDeployedApplicationDirectory());
                catch err
                    %No GUI or Logger yet - show the error in a dialogue, as
                    %a compiled application has no Command Window
                    uiwait(errordlg(err.message, "Palladium DAQ installation folder not found"));
                    rethrow(err);
                end
            else
                applicationPath = mfilename('fullpath');
                [applicationDir, ~, ~] = fileparts(applicationPath);
            end

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

                %Use an absolute path as it is; take a relative one as relative
                %to the folder this file is in
                if ~Palladium.Utilities.PathUtils.IsAbsolutePath(Settings.ConfigFilePath)
                    Settings.ConfigFilePath = fullfile(applicationDir, Settings.ConfigFilePath);
                end
                Settings.ConfigFilePath = Palladium.Utilities.PathUtils.CleanPath(Settings.ConfigFilePath);

                %Check the file exists
                assert(isfile(Settings.ConfigFilePath), "PalladiumError:ConfigFileNotFound", "%s", "Could not find override Config file at " + string(Settings.ConfigFilePath));
            end

            %Initialise the Controller
            this.Controller.Initialise(versionInfo.FullVersionString, ConfigFilePath=Settings.ConfigFilePath);

            %Apply a preset, if specified in the optional arguments
            if ~isempty(Settings.Preset)
                this.LoadPreset(Settings.Preset);
            end

            %Tell the controller we have finished loading everything and
            %are ready to go
            this.Controller.OnLoaded();
        end
    end

    %% Methods (Public)
    methods

        function instRef = AddInstrument(this, instrumentClassName, settings)
            %Add an instrument, by the name of its driver class, and return it.
            %Any of its Instrument Controls that are enabled by default are
            %added too. Keep the returned instrument to change its settings or
            %call its methods, e.g.
            %`k = pd.AddInstrument("Keithley2000", ConnectionType="Debug");`
            %then `k.Name = "DMM";`. If the instrument can't be created, the
            %error is reported and [] is returned.
            %
            %Inputs:
            %   instrumentClassName - the driver's class name, as in the GUI's
            %                         Instruments list, e.g. "Keithley2000"
            %   Name                - the instrument's name, used in its data
            %                         column headers. Default "Auto", the class's
            %                         default name with a number added, e.g.
            %                         "K2000_1". A number is also added if the
            %                         name is already taken
            %   ConnectionType      - the connection type, as text, e.g. "GPIB"
            %                         or "Debug" (simulated, no hardware).
            %                         Default "Auto", the driver's default
            %
            %Outputs:
            %   instRef - the new Palladium.Core.Instrument, or [] on failure
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
            %Add one of an instrument's Instrument Controls, such as a Sweep Control, to the GUI.
            %The instrument must already have been added, and Palladium must
            %have a GUI.
            %
            %Inputs:
            %   instrRef    - the Palladium.Core.Instrument to add the control to
            %   controlName - the control's Name, as given to
            %                 DefineInstrumentControl in the instrument's
            %                 constructor, e.g. "Sweep Control"
            %   ControlName - optional new name for this control, e.g.
            %                 "IV Sweep". Default [], keep the defined name
            %   TabName     - optional name of the GUI tab it is shown in.
            %                 Default [], keep the defined tab name
            %
            %Outputs:
            %   cont - the Instrument Control created
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
            %Add an Instrument Control to the GUI from its full definition struct.
            %A lower-level version of `AddInstrumentControl`, which is easier
            %to use as it needs only the control's name. Needs a GUI: errors (Palladium:NoGUI) without one.
            %
            %Inputs:
            %   instrRef             - the Palladium.Core.Instrument to add the control to
            %   controlDetailsStruct - the control's definition, as returned by
            %                          `instrRef.GetControlOption(controlName)`,
            %                          optionally edited
            %
            %Outputs:
            %   cont - the Instrument Control created
            arguments
                this;
                instrRef (1,1) Palladium.Core.Instrument;
                controlDetailsStruct (1,1) struct;
            end

            this.AssertHasGUI("add an Instrument Control");

            %Pass on to the View
            cont = this.View.AddInstrumentControl(instrRef, controlDetailsStruct);
        end

        function CacheInstrumentCommand(this, instrument, command, controlName)
            %Queue a command to run on an instrument, or one of its controls, on the next measurement tick.
            %Commands are not run straight away, because the measurement loop
            %may be talking to the hardware at that moment. Queued commands
            %run one per tick, in order, so measurements must be running for
            %them to happen. For example
            %`pd.CacheInstrumentCommand(k, "SetSourceLevel(0.001,true)");`
            %where k is a Keithley2410.
            %
            %Inputs:
            %   instrument  - the Palladium.Core.Instrument to run it on
            %   command     - the method call to run, as text, e.g.
            %                 "SetSourceLevel(0.001,true)"
            %   controlName - optional name of one of the instrument's
            %                 Instrument Controls to run it on instead, e.g.
            %                 "Sweep Control". Default empty, run it on the
            %                 instrument

            arguments
                this;
                instrument (1,1) Palladium.Core.Instrument;
                command {mustBeTextScalar};
                controlName = string.empty;
            end

            this.Controller.CacheInstrumentCommand(instrument, command, controlName);
        end

        function Close(this)
            %Shut down Palladium DAQ, deleting its View and Controller.
            %Closes the GUI, or with no GUI, stops the measurement timer and
            %closes the instruments' connections. The object can't be used
            %afterwards. Closing again does nothing.

            %Already closed - nothing left to shut down (this used to error)
            if isempty(this.Controller)
                return;
            end

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
            %List the class names of all available instrument drivers.
            %These are the built-in drivers and those in the user files
            %folder, MATLAB and Python - the names AddInstrument accepts.
            %
            %Outputs:
            %   classNames - string array of driver class names

            classNames = this.Controller.GetAllInstrumentClassNames();
        end

        function instRef = GetInstrumentFromName(this, instName)
            %Find an added instrument by its Name, e.g. "K2000_1".
            %Errors, listing the names of the added instruments, if none has
            %that name.
            %
            %Inputs:
            %   instName - the instrument's Name
            %
            %Outputs:
            %   instRef - the Palladium.Core.Instrument with that name
            arguments
                this;
                instName {mustBeTextScalar};
            end

            %Pass through to InstrumentController
            instRef = this.Controller.GetInstrumentFromName(instName);
        end

        function display = OpenBigNumberDisplay(this, column, Settings)
            %Open a Big Number Display window, showing a data column's latest value in large type.
            %Updated each measurement tick, and closed with Palladium DAQ.
            %Measurements must have started, so the data columns are known.
            %Without a column, a window asks for it, and how to show the
            %value; scripts can give them.
            %
            %Inputs:
            %   column             - (optional) the column's number, or its exact header,
            %                        e.g. "K2000_1 - Voltage (V)"
            %   SignificantFigures - (name-value) significant figures to show. Default 6
            %   NumberFormat       - (name-value) sprintf format for the value, e.g. "%.3f",
            %                        used instead of SignificantFigures. Default "" (automatic)
            %
            %Outputs:
            %   display - the Palladium.Components.BigNumberDisplay, or [] if none was opened

            arguments
                this;
                column = [];
                Settings.SignificantFigures = Palladium.Components.BigNumberDisplay.DefaultSignificantFigures;
                Settings.NumberFormat = "";
            end

            display = this.Controller.OpenBigNumberDisplay(column, SignificantFigures=Settings.SignificantFigures, ...
                NumberFormat=Settings.NumberFormat);
        end

        function Pause(this)
            %Hold the measurement loop until Resume is called, as the GUI's Pause button does.

            this.Controller.TimingLoopController.Pause();
        end

        function RemoveInstrument(this, instrRef)
            %Remove an added instrument and delete it.
            %
            %Inputs:
            %   instrRef - the Palladium.Core.Instrument to remove
            arguments
                this;
                instrRef (1,1) Palladium.Core.Instrument;
            end

            this.Controller.InstrumentController.RemoveInstrument(instrRef);
        end

        function RemoveInstrumentControl(this, instrRef, controlName)
            %Remove an Instrument Control, by name, from an instrument and the GUI.
            %Errors if the instrument does not offer a control of that name, or
            %it has not been added. Needs a GUI: errors (Palladium:NoGUI) without one.
            %
            %Inputs:
            %   instrRef    - the Palladium.Core.Instrument the control belongs to
            %   controlName - the control's Name, e.g. "Sweep Control"
            arguments
                this;
                instrRef (1,1) Palladium.Core.Instrument;
                controlName {mustBeTextScalar};
            end

            %Get the struct with the control's details from the Instrument
            controlDetailsStruct = instrRef.GetControlOption(controlName);

            %Pass through to function below - this one is basically a nice
            %wrapper for it
            this.RemoveInstrumentControlFromStruct(instrRef, controlDetailsStruct);
        end

        function RemoveInstrumentControlFromStruct(this, instrRef, controlDetailsStruct)
            %Remove an Instrument Control from an instrument and the GUI, given its definition struct.
            %A lower-level version of `RemoveInstrumentControl`, which is
            %easier to use as it needs only the control's name. Needs a GUI: errors (Palladium:NoGUI) without one.
            %
            %Inputs:
            %   instrRef             - the Palladium.Core.Instrument the control belongs to
            %   controlDetailsStruct - the control's definition, as returned by
            %                          `instrRef.GetControlOption(controlName)`
            arguments
                this;
                instrRef (1,1) Palladium.Core.Instrument;
                controlDetailsStruct (1,1) struct;
            end

            this.AssertHasGUI("remove an Instrument Control");
            this.View.RemoveInstrumentControl(instrRef, controlDetailsStruct);
        end

        function Resume(this)
            %Restart the measurement loop after Pause, as the GUI's Resume button does.

            this.Controller.TimingLoopController.Resume();
        end

        function SetDescription(this, descriptionText)
            %Set the description written into the data file's header when measurements start.
            %
            %Inputs:
            %   descriptionText - the description, as text
            arguments
                this;
                descriptionText {mustBeText};
            end

            %Pass through to Controller
            this.Controller.SetFilePathsDescription(descriptionText);
        end

        function SetDirectory(this, directory)
            %Set the folder that data files are saved in.
            %
            %Inputs:
            %   directory - the folder's path
            arguments
                this;
                directory {mustBeTextScalar};
            end

            %Pass through to Controller
            this.Controller.SetFilePathsDirectory(directory);
        end

        function SetFileExtension(this, fileExtension)
            %Set the file extension of the data files, normally ".dat".
            %
            %Inputs:
            %   fileExtension - the extension, e.g. ".dat"
            arguments
                this;
                fileExtension {mustBeTextScalar};
            end

            %Pass through to Controller
            this.Controller.SetFilePathsFileExtension(fileExtension);
        end

        function SetFileName(this, fileName)
            %Set the data file's name, without folder or extension.
            %Any extension given is removed, and `<DATE>` is replaced with
            %today's date, e.g. "<DATE>_FirstTest".
            %
            %Inputs:
            %   fileName - the file name
            arguments
                this;
                fileName {mustBeTextScalar};
            end

            %Pass through to Controller
            this.Controller.SetFilePathsFileName(fileName);
        end

        function SetSaveFileBool(this, saveFileBool)
            %Set whether a data file is written, as the GUI's Write to File option does.
            %
            %Inputs:
            %   saveFileBool - true to write a data file (the default), false
            %                  to measure without saving
            arguments
                this;
                saveFileBool (1,1) logical;
            end

            %Pass through to Controller
            this.Controller.SetFilePathsSaveFileBool(saveFileBool);
        end

        function SetUpdateTime(this, time_s)
            %Set the target update time of the measurement loop - the time between readings.
            %
            %Inputs:
            %   time_s - the update time, in seconds
            arguments
                this;
                time_s (1,1) double {mustBePositive};
            end

            %Pass through to Controller
            this.Controller.TimingLoopController.SetUpdateTime(time_s);
        end

        function SetWriteMode(this, writeMode)
            %Set what happens when the data file already exists.
            %
            %Inputs:
            %   writeMode - "Increment File No." (start a new numbered file),
            %               "Overwrite File" or "Append To File"
            arguments
                this;
                writeMode {mustBeTextScalar, mustBeMember(writeMode, {"Increment File No.", "Overwrite File", "Append To File"})};
            end

            %Pass through to Controller
            this.Controller.SetFilePathsWriteMode(writeMode);
        end

        function Start(this)
            %Begin measuring, as the GUI's Start button does.
            %Checks the data file path, connects to and initialises all the
            %instruments, writes the data file's header, and then starts the
            %measurement loop, which runs on a timer: each tick reads every
            %instrument, runs any queued commands, updates the plots and
            %writes a line to the data file. Returns once the loop has
            %started. If an instrument fails to connect, starting is aborted
            %with a warning.

            this.Controller.TimingLoopController.Start();
        end

        function Stop(this)
            %End measurements, as the GUI's Stop button does.
            %The current tick finishes, and then the instruments are closed.

            this.Controller.TimingLoopController.Stop();
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function AssertHasGUI(this, action)
            %Error clearly if there is no GUI, for methods that need one.
            %Instrument Controls live in tabs of the GUI, so they can't be
            %added or removed when Palladium was started with View=[]
            %
            %Inputs:
            %   action - what was being attempted, e.g. "add an Instrument Control"

            assert(~isempty(this.View), "Palladium:NoGUI", "%s", "Cannot " + action + ": Palladium was started without a GUI (View=[]). Instrument Controls are part of the GUI, so they need it.");
        end

        function view = CreateView(~, viewFileName, applicationDir)
            %Create the View (GUI) from its class name in the Palladium.Views namespace.

            %Construct the needed paths
            viewDir = fullfile(applicationDir,"+Palladium","+Views");
            fullViewCodeFilePath = fullfile(viewDir,viewFileName);
            namespaceClassPath = "Palladium.Views." + viewFileName;

            %Check that this file exists in the expected folder - only if
            %not in a compiled exe version, where paths are not the same
            %deal
            if ~isdeployed
                assert(exist(fullViewCodeFilePath + ".m", "file") || exist(fullViewCodeFilePath + ".mlapp", "file"), "CreateViewError:ViewFileNotFound", "%s", "View file " + fullViewCodeFilePath + " not found");
            end

            %Create an instance of the required class (empty constructor)
            fnHandle = str2func(namespaceClassPath);
            view = fnHandle();
        end

        function LoadPreset(this, presetName)
            %Load a .json Preset, by name, from the user Presets folder and apply it.
            %Presets list instruments to add (with their properties to set)
            %and programme-level settings, as well as GUI preferences like
            %graph windows to show. Errors are reported, not thrown

            %Display a status message in the logger
            this.Controller.ShowStatus('Yellow', 'Loading Preset');

            try
                %Fetch paths
                presetsDir = this.Controller.UserPresetsDir;
                presetPath = fullfile(presetsDir, presetName) + ".json";

                %Error checking
                assert(exist(presetsDir,"dir") == 7, "LoadPresetError:PresetsDirNotFound", "%s", "Presets directory " + string(presetsDir) + " not found");
                assert(exist(presetPath,"file") == 2, "LoadPresetError:PresetFileNotFound", "%s", "Preset file " + string(presetPath) + " not found");

                %Load the present in and apply all the settings
                Palladium.Utilities.PluginLoading.ApplyPresetFromJson(this.Controller, this.View, presetPath);

                %Display a status message in the logger
                this.Controller.ShowStatus('Yellow', 'Finalising Preset');

                %Finalize the preset - basically, update the GUI to reflect
                %changes
                notify(this.Controller, "FinalisePreset");
            catch err
                this.Controller.HandleError("Error loading Preset", err);
            end
        end

    end

    %% Methods (Static, Public, Sealed)
    methods (Access = public, Static, Sealed)

        function verStruct = ver()
            %Return the version of Palladium DAQ, e.g. as `Palladium.ver().VersionString`.
            %The constant properties of this class are the single definition
            %of the version: the toolbox, documentation and GUI all take it
            %from here.
            %
            %Outputs:
            %   verStruct - struct with fields VersionString (e.g. "3.7.0"),
            %               FullVersionString ("Palladium DAQ Version 3.7.0"),
            %               Major, Minor and Build (numbers) and AuthorString

            verStruct.VersionString = sprintf('%d.%d.%d', Palladium.MajorVersionNo, Palladium.MinorVersionNo, Palladium.BuildVersionNo);
            verStruct.FullVersionString = sprintf('Palladium DAQ Version %d.%d.%d', Palladium.MajorVersionNo, Palladium.MinorVersionNo, Palladium.BuildVersionNo);
            verStruct.Major = Palladium.MajorVersionNo;
            verStruct.Minor = Palladium.MinorVersionNo;
            verStruct.Build = Palladium.BuildVersionNo;
            verStruct.AuthorString = Palladium.AuthorString;
        end

    end
end

