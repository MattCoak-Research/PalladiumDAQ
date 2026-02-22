classdef CoakView < handle
    %COAKVIEW Overall container class of a CoakView instance - adds a
    %Controller and a View (usually the CoakView_DefaultGUI GUI, but can be
    %a command-line-only implementation or any other user-defined one if
    %desired)

    properties (Access = public)

    end

    properties (Access = private)
        Controller;
        View = [];
    end

    methods
        %% Constructor
        function this = CoakView(Settings)
            arguments
                Settings.View = "CoakView_DefaultGUI";
                Settings.Preset = [];
            end

            %Check that new enough Matlab version is installed, toolboxes
            %are there.. etc etc. Will throw error if not
            CoakView.Utilities.ErrorChecking.Verification.ValidateInstall(MatlabVersion="R2025b", ToolboxNames = {"Instrument Control Toolbox"});
   
            %Set application paths for loading of child classes later - make
            %all paths relative to this, the filepath of the CoakView.m file
            %- if we don't do this they will be relative to the user's
            %current matlab open folder, which is a recipe for disaster
            applicationPath = mfilename('fullpath');
            [applicationDir, ~, ~] = fileparts(applicationPath);

            %Create the view/frontend/implementation/GUI
            if ~isempty(Settings.View)
                view = this.CreateView(Settings.View, applicationDir);
                this.View = view;
            else
                view = [];
            end

            %Create a Controller class that will handle all the backend
            %logic
            this.Controller = CoakView.Core.Controller( ...
                "ApplicationDir", applicationDir,...
                "ApplicationPath", applicationPath...
                );

            %Register the view with the Controller
            if ~isempty(Settings.View)
                this.Controller.AttachView(view);
            end

            %Initialise the Controller
            this.Controller.Initialise();

            %Apply a preset, if specified in the optional arguments
            if ~isempty(Settings.Preset)
                presetFn = this.LoadPreset(Settings.Preset);
                this.ApplyPreset(presetFn, view);
            end

            %Tell the controller we have finished loading everything and
            %are ready to go
            this.Controller.OnLoaded();
        end

        %% AddInstrument
        function instRef = AddInstrument(this, instrumentClassName, settings)
            arguments
                this;
                instrumentClassName {mustBeTextScalar};
                settings.Name {mustBeTextScalar} = "Auto";
                settings.ConnectionType {mustBeTextScalar} = "Auto";
            end

            %Pass through to Controller
            instRef = this.Controller.InstrumentController.AddInstrument(instrumentClassName, Name=settings.Name, ConnectionType=settings.ConnectionType);
        end

         %% AddInstrumentControl
        function cont = AddInstrumentControl(this, instrRef, controlDetailsStruct)
            %Pass on to the View
            cont = this.View.AddInstrumentControl(instrRef, controlDetailsStruct);
        end

        %% Pause
        function Pause(this)
            this.Controller.TimingLoopController.Pause();
        end

        %% RemoveInstrument
        function RemoveInstrument(this, instRef)
            this.Controller.InstrumentController.RemoveInstrument(instRef);
        end

        %% RemoveInstrumentControl
        function RemoveInstrumentControl(this, instRef, controlDetailsStruct)
            this.View.RemoveInstrumentControl(instRef, controlDetailsStruct);
        end

        %% Resume
        function Resume(this)
            this.Controller.TimingLoopController.Resume();
        end

        %% SetFilePathsDirectory
        function SetFilePathsDirectory(this, directory)
            this.Controller.SetFilePathsDirectory(directory);
        end

        %% SetFilePathsFileExtension
        function SetFilePathsFileExtension(this, fileExtension)
            this.Controller.SetFilePathsFileExtension(fileExtension);
        end

        %% SetFilePathsDescription
        function SetFilePathsDescription(this, descriptionText)
            this.Controller.SetFilePathsDescription(descriptionText);
        end

        %% SetFilePathsFileName
        function SetFilePathsFileName(this, fileName)
            this.Controller.SetFilePathsFileName(fileName);
        end

        %% SetFilePathsSaveFileBool
        function SetFilePathsSaveFileBool(this, saveFileBool)
            this.Controller.SetFilePathsSaveFileBool(saveFileBool);
        end

        %% SetFilePathsWriteMode
        function SetFilePathsWriteMode(this, writeMode)
            this.Controller.SetFilePathsWriteMode(writeMode);
        end

        %% SetUpdateTime
        function SetUpdateTime(this, time_s)
            this.Controller.TimingLoopController.SetUpdateTime(time_s);
        end

        %% Start
        function Start(this)
            this.Controller.TimingLoopController.Start();
        end

        %% Stop
        function Stop(this)
            this.Controller.TimingLoopController.Stop();
        end
    end

    methods (Access = private)

        %% ApplyPreset
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

        %% CreateView
        function view = CreateView(~, viewFileName, applicationDir)
            %Instantiate an instance of the View/GUI class from file, just
            %from the desired filename

            %Construct the needed paths
            viewDir = applicationDir + "\\+CoakViewViews\\";
            fullViewCodeFilePath = viewDir + viewFileName;
            namespaceClassPath = "CoakViewViews." + viewFileName;

            %Check that this file exists in the expected folder
            assert(exist(fullViewCodeFilePath + ".m", "file") || exist(fullViewCodeFilePath + ".mlapp", "file"), "View file " + fullViewCodeFilePath + " not found");

            %Create an instance of the required class (empty constructor)
            fnHandle = str2func(namespaceClassPath);
            view = fnHandle();
        end

        %% GetPresetsDir
        function dirPath = GetPresetsDir(this)
            dirPath = fullfile(this.Controller.ApplicationDir,  this.Controller.PresetsDirectory);
        end

        %% LoadPreset
        function presetFn = LoadPreset(this, presetName)
            %Display a status message in the logger
            this.Controller.ShowStatus('Yellow', 'Loading Preset');

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
                this.Controller.HandleError("Error loading Preset", err);
            end
        end

       

    end
end

