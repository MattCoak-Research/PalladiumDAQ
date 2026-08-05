classdef SequenceEditorController < handle
    %SEQUENCEEDITORCONTROLLER - logic class that acts as the Model for the
    %Sequence Editor application

    %% Properties (Public)
    properties(Access=public)
        
    end

    %% Properties (Private)
    properties (Access = private)
        SelectedDir;
        View;
        CommandEncoder;
        DataReader;
        DataWriter;
        Instruments = {};
    end

    %% Events
    events
        SingleCommandQueue;
    end

    %% Constructor
    methods
        function this = SequenceEditorController()
            arguments
                
            end

            this.CommandEncoder = Palladium.Sequence.CommandEncoder();
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function Close(this)
            %Called by the Palladium main class, then Controller.Close.
            %Close any open Views
            if ~isempty(this.View)
                this.View.Close();
            end
        end

        function CommandInserted(this, details)
            cmd = this.CommandEncoder.BuildCommandFromEventDetails(details);            
            str = this.CommandEncoder.CommandToString(cmd);
            
            this.InsertSequenceLine(str);
        end

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
            addlistener(this.View, "CommandInsert", @(src, event)this.CommandInserted(event.Details));
            addlistener(this.View, "DirectorySelect", @(src, event)this.DirectorySelected(src, event));
            addlistener(this.View, "FileSelect", @(src, event)this.FileSelected(src, event));
            addlistener(this.View, "SaveButtonPressed", @(src, event)this.SaveSequenceButtonPushed(event.Value));
            addlistener(this.View, "SingleCommandQueued", @(src, event)this.SingleCommandQueued(src, event));
            addlistener(this.View, "SequenceRun", @(src, event)this.RunSequence(event));

            %Set default dir and Start in the default directory
            this.View.DefaultDir = this.SelectedDir;
            this.View.FileExtension = this.DataWriter.FileWriteDetails.FileExtension;
            this.View.DirectorySelected(this.SelectedDir);

            %Update the newly minted View
            this.View.RefreshInstrumentNames(this.Instruments);
        end

        function DirectorySelected(this, ~, eventArgs)           
            this.View.OnDirectorySelected();
        end

        function instRef = GetInstrumentFromName(this, instName)
            arguments
                this;
                instName {mustBeTextScalar};
            end

            instRef = []; %#ok<NASGU>

            for i = 1 : length(this.Instruments)
                if this.Instruments{i}.Name == instName
                    instRef = this.Instruments{i};
                    return;
                end
            end

            %If we got here, none of the instruments matched
            instStringNameList = "";
            for i = 1 : length(this.Instruments)
                instStringNameList = instStringNameList + this.Instruments{i}.Name;
                if i ~= length(this.Instruments)
                    instStringNameList = instStringNameList + ", ";
                end
            end
            if instStringNameList == ""
                instStringNameList = "-NONE-";
            end

            error("GetInstrumentFromNameError:NotFound", "Could not find instrument of Name " + instName + ". Added Instruments: " + instStringNameList);
        end

        function FileSelected(this, ~, eventArgs)
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

        function InsertSequenceLine(this, str)
            this.View.InsertSequenceLine(str);
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

        function RunSequence(this, evnt)
            seqTextCell = evnt.Value;
            result = this.CommandEncoder.ParseSequenceText(seqTextCell, this.Instruments);
            result
        end

        function SaveSequenceButtonPushed(this, details)
            [file,location] = uiputfile('*.m');
            if isequal(file,0) || isequal(location,0)
                disp('User clicked Cancel.')
            else
                disp(['User selected ',fullfile(location,file),...
                    ' and then clicked Save.'])
            end
        end

        function SingleCommandQueued(this, ~, args)
            %Pass on event - if a Controller made this as expected in a
            %normal programme running (not a unit test for example), it
            %will be listening and will call CacheInstrumentCommand
            notify(this, "SingleCommandQueue", args);

        %    this.Controller.CacheInstrumentCommand(args.InstrumentRef, string(args.CommandString), args.ControlName, FunctionOnComplete = args.FunctionToRunOnComplete);
        end
    end

    %% Methods (Private)
    methods(Access=private)       

        function tf = ViewExists(this)
            tf = ~isempty(this.View) && isvalid(this.View);
        end
    end
end

