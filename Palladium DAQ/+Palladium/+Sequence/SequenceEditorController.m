classdef SequenceEditorController < handle
    %SEQUENCEEDITORCONTROLLER - logic class that acts as the Model for the
    %Sequence Editor application
    
    properties
    end

    properties (Access = private)
        SelectedDir;
        View;
        Controller;
        DataReader;
        DataWriter;
    end
    
    methods
        function this = SequenceEditorController(controller, Settings)
            arguments
                controller (1,1) Palladium.Core.Controller;
                Settings.DefaultSequenceDirectory {mustBeText};
                Settings.SequenceFileExtension {mustBeText};
            end
            this.Controller = controller;

            this.SelectedDir = Settings.DefaultSequenceDirectory;

            %Construct a DataReader object to handle the nuts and bolts of
            %reading files (designed like this so we can easily extend to
            %different file encoding types later)
            this.DataReader = Palladium.DataWriting.DataReader();

            %Construct a DataWriter object - for saving figures
             %Assign into private property struct FileWriteDetails
            fileWriteDetails.Directory = Settings.DefaultSequenceDirectory;
            fileWriteDetails.FileName = "File Name";
            fileWriteDetails.DescriptionText = "Sequence Description";
            fileWriteDetails.FileExtension = Settings.SequenceFileExtension;
            fileWriteDetails.SaveFile = true;
            fileWriteDetails.WriteMode = "Overwrite File";
            this.DataWriter = Palladium.DataWriting.DataWriter(fileWriteDetails);
        end

        %% CreateView
        function CreateView(this, viewFileName, applicationDir)
            arguments
                this;
                viewFileName{mustBeTextScalar} = "SequenceEditor_DefaultGUI";
                applicationDir {mustBeTextScalar} = "";
            end

            %Instantiate an instance of the View/GUI class from file, just
            %from the desired filename

            %Construct the needed paths
            viewDir = fullfile(applicationDir,"+Palladium","+Sequence","+Views");
            fullViewCodeFilePath = fullfile(viewDir,viewFileName);
            namespaceClassPath = "Palladium.Sequence.Views." + viewFileName;

            %Check that this file exists in the expected folder
            assert(exist(fullViewCodeFilePath + ".m", "file") || exist(fullViewCodeFilePath + ".mlapp", "file"), "View file " + fullViewCodeFilePath + " not found");

            %Create an instance of the required class (empty constructor)
            fnHandle = str2func(namespaceClassPath);
            this.View = fnHandle();

            %Subscribe to events
            addlistener(this.View, "DirectorySelect", @(src, event)this.DirectorySelected(src, event));
            addlistener(this.View, "FileSelect", @(src, event)this.FileSelected(src, event));

            %Set default dir and Start in the default directory
            this.View.DefaultDir = this.SelectedDir;
            this.View.FileExtension = this.DataWriter.FileWriteDetails.FileExtension;
            this.View.DirectorySelected(this.SelectedDir);
        end

        %% DirectorySelected
        function DirectorySelected(this, sender, eventArgs)
            eventArgs
            disp('dir select');
            this.View.OnDirectorySelected();
        end

        %% FileSelected
        function FileSelected(this, ~, eventArgs)
            eventArgs
            disp('file select');

            this.View.OnFileSelected();
        end

    end
end

