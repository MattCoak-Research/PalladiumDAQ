classdef CoakView < handle
    %COAKVIEW Overall container class of a CoakView instance - adds a
    %Controller and a View (usually the CoakView_DefaultGUI GUI, but can be
    %a command-line-only implementation or any other user-defined one if
    %desired)

    properties (Access = public)

    end

    properties (Access = private)
        Controller;
    end

    methods
        %% Constructor
        function this = CoakView(Settings)
            arguments
                Settings.View {mustBeTextScalar} = "CoakView_DefaultGUI";
                Settings.Preset = [];
            end

            %Set application paths for loading of child classes later - make
            %all paths relative to this, the filepath of the CoakView.m file
            %- if we don't do this they will be relative to the user's
            %current matlab open folder, which is a recipe for disaster
            applicationPath = mfilename('fullpath');
            [applicationDir, ~, ~] = fileparts(applicationPath);

            %Create the view/frontend/implementation/GUI
            view = this.CreateView(Settings.View, applicationDir);

            %Create a Controller class that will handle all the backend
            %logic
            this.Controller = CoakView.Core.Controller( ...
                "ApplicationDir", applicationDir,...
                "ApplicationPath", applicationPath, ...
                "View", view...
                );

            %Initialise the Controller
            this.Controller.Initialise();

            %Apply a preset, if specified in the optional arguments
            if ~isempty(Settings.Preset)
                presetFn = this.Controller.LoadPreset(Settings.Preset);
                this.Controller.ApplyPreset(presetFn);
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
            end

            %Pass through to Controller
            instRef = this.Controller.AddInstrument(instrumentClassName, settings.Name);
        end

        %% AddInstrumentControl
        function cont = AddInstrumentControl(this, instrRef, controlDetailsStruct)
            cont = this.Controller.AddInstrumentControl(instrRef, controlDetailsStruct);
        end

        %% Pause
        function Pause(this)
            this.Controller.Pause();
        end

        %% RemoveInstrument
        function RemoveInstrument(this, instRef)
            this.Controller.RemoveInstrument(instRef);
        end

        %% RemoveInstrumentControl
        function RemoveInstrumentControl(this, instrRef, controlDetailsStruct)
            this.Controller.RemoveInstrumentControl(instrRef, controlDetailsStruct);
        end

        %% Resume
        function Resume(this)
            this.Controller.Resume();
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

        %% Start
        function Start(this)
            this.Controller.Start();
        end

        %% Stop
        function Stop(this)
            this.Controller.Stop();
        end
    end

    methods (Access = private)

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

    end
end

