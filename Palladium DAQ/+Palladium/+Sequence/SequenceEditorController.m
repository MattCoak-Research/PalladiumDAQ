classdef SequenceEditorController < handle
    %SEQUENCEEDITORCONTROLLER - logic class that acts as the Model for the
    %Sequence Editor application

    %% Properties (Private)
    properties (Access = private)
        SelectedDir;
        View;
        Controller;
        DataReader;
        DataWriter;
        Instruments = {};
    end

    %% Constructor
    methods
        function this = SequenceEditorController(controller)
            arguments
                controller (1,1) Palladium.Core.Controller;
            end

            this.Controller = controller;
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function CreateView(this, viewFileName, applicationDir, Settings)
            %Instantiate an instance of the View/GUI class from file, just
            %from the desired filename
            arguments
                this;
                viewFileName{mustBeTextScalar} = "SequenceEditor_DefaultGUI";
                applicationDir {mustBeTextScalar} = "";
                Settings.IconPath;
            end

            %If it exists already, just bring it to the fron
            if this.ViewExists
                this.View.SeizeFocus();
                this.View.RefreshInstrumentNames(this.Instruments);
                return;
            end

            %Construct the needed paths
            viewDir = fullfile(applicationDir,"+Palladium","+Sequence","+Views");
            fullViewCodeFilePath = fullfile(viewDir,viewFileName);
            namespaceClassPath = "Palladium.Sequence.Views." + viewFileName;

            %Check that this file exists in the expected folder
            assert(exist(fullViewCodeFilePath + ".m", "file") || exist(fullViewCodeFilePath + ".mlapp", "file"), "View file " + fullViewCodeFilePath + " not found");

            %Create an instance of the required class (empty constructor)
            fnHandle = str2func(namespaceClassPath);
            this.View = fnHandle();
            this.View.SetIcon(Settings.IconPath);

            %Subscribe to events
            addlistener(this.View, "DirectorySelect", @(src, event)this.DirectorySelected(src, event));
            addlistener(this.View, "FileSelect", @(src, event)this.FileSelected(src, event));
            addlistener(this.View, "SingleCommandQueued", @(src, event)this.SingleCommandQueued(src, event));

            %Set default dir and Start in the default directory
            this.View.DefaultDir = this.SelectedDir;
            this.View.FileExtension = this.DataWriter.FileWriteDetails.FileExtension;
            this.View.DirectorySelected(this.SelectedDir);

            %Update the newly minted View
            this.View.RefreshInstrumentNames(this.Instruments);
        end

        function DirectorySelected(this, ~, eventArgs)
            eventArgs
            disp('dir select');
            this.View.OnDirectorySelected();
        end

        function FileSelected(this, ~, eventArgs)
            eventArgs
            disp('file select');

            this.View.OnFileSelected();
        end

        function Initialise(this, Settings)
            arguments
                this;
                Settings.DefaultSequenceDirectory {mustBeText};
                Settings.SequenceFileExtension {mustBeText};
            end


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

        function InstrumentsChanged(this, eventArgs)
            %Called by events when the list of Instruments in
            %InstrumentController changes (Instrument Added or Removed)

            this.Instruments = eventArgs.Instruments;
            this.RefreshInstrumentNames();        
        end

        function RefreshInstrumentNames(this)
            if this.ViewExists
                this.View.RefreshInstrumentNames(this.Instruments);
            end
        end

        function SingleCommandQueued(this, ~, args)
            this.Controller.CacheCommand(args.InstrumentRef, string(args.CommandString));
        end
    end

    %% Methods (Private)
    methods(Access=private)

        function tf = ViewExists(this)
            tf = ~isempty(this.View) && isvalid(this.View);
        end
    end
end

