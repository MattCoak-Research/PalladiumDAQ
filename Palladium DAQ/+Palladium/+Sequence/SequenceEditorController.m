classdef SequenceEditorController < handle
    %SEQUENCEEDITORCONTROLLER - logic class that acts as the Model for the
    %Sequence Editor application

    %% Properties (Constant, private)
    properties(Constant, Access=private)
        SequenceFileHeader = "Palladium Sequence File, Version [1.0]";
    end

    %% Properties (Public)
    properties(Access=public)

    end

    %% Properties (Private)
    properties (Access = private)
        SelectedDir;
        DefaultDataFileName;
        DefaultDataDirectory;
        View;
        CommandEncoder;
        FileWriteDetails;
        Instruments = {};
    end

    %% Events
    events
        SequenceAbort;
        SequenceQueue;
        SingleCommandQueue;
    end

    %% Constructor
    methods
        function this = SequenceEditorController()
            this.CommandEncoder = Palladium.Sequence.CommandEncoder();
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function AbortSequence(this)
            %Pass on event - if a Controller made this as expected in a
            %normal programme running (not a unit test for example), it
            %will be listening 
            notify(this, "SequenceAbort");

             if ~isempty(this.View)
                this.View.OnSequenceAbort();
            end
        end

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

        function CommandsFinished(this)
            %This gets called via event thrown in CommandController, when a
            %sequence has completed all its Commands

             if ~isempty(this.View)
                this.View.SequenceComplete();
            end
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
            addlistener(this.View, "SequenceAbort", @(src, event)this.AbortSequence());

            %Update the newly minted View
            this.View.RefreshInstrumentNames(this.Instruments);


            %Set default dir and Start in the default directory
            this.View.SetDefaultPaths(this.SelectedDir, this.FileWriteDetails.FileExtension, this.DefaultDataDirectory, this.DefaultDataFileName);
        end

        function DirectorySelected(this, ~, ~)
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
            filePath = eventArgs.Value;

            seqLines = this.LoadSequenceFromFile(filePath);

            this.SetSequence(seqLines);
        end

        function Initialise(this, Settings)
            arguments
                this;
                Settings.DefaultDataDirectory {mustBeText};
                Settings.DefaultSequenceDirectory {mustBeText};
                Settings.DefaultDataFileName {mustBeText};
                Settings.SequenceFileExtension {mustBeText};
            end


            this.SelectedDir = Settings.DefaultSequenceDirectory;
            this.DefaultDataFileName = Settings.DefaultDataFileName;
            this.DefaultDataDirectory = Settings.DefaultDataDirectory;

            %Construct a DataWriter object - for saving figures
            %Assign into private property struct FileWriteDetails
            fileWriteDetails.Directory = Settings.DefaultSequenceDirectory;
            fileWriteDetails.FileName = "New Sequence";
            fileWriteDetails.DescriptionText = "Sequence Description";
            fileWriteDetails.FileExtension = Settings.SequenceFileExtension;
            fileWriteDetails.SaveFile = true;
            fileWriteDetails.WriteMode = "Overwrite File";

            this.FileWriteDetails = fileWriteDetails;
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
            seqTextStrArray = evnt.Value;

            %Make sure format is always the same - array of strings.
            %TextArea is inconsistent in testing, depending on if file is
            %loaded or edits are made manually.
            if iscell(seqTextStrArray)
                seqTextStrArray = convertCharsToStrings(seqTextStrArray);
            end

            %Parse the array of strings into a cell array of Command
            %classes
            result = this.CommandEncoder.ParseSequenceText(seqTextStrArray, this.Instruments);

            if isempty(result)
                warndlg("Empty sequence, cannot run");
                if ~isempty(this.View)
                    disp("Sequence Aborted");
                    this.View.OnSequenceAbort();
                end                
                return;
            end
          
            %Read any sequences called in RunSequence commands from disk,
            %parse them and insert the contents into the queue in the place
            %of that RunSequence line.
            %This runs recursively, as the loaded sequence could also have
            %another nested RunSequence command
            [tf, index] = ContainsRunSequenceCommand(result);
            while(tf)
                seqCom = result{index};

                %Remove the sequence command from the chain
                result(index) = [];

                %Load the sequence file and unpack it
                newSeqStrArray = this.LoadSequenceFromFile(seqCom.SequencePath);    %This will be a string array, as it's loaded 
                newSeq = this.CommandEncoder.ParseSequenceText(newSeqStrArray, this.Instruments);

                %Insert the new commands into the sequence at index 'index'
                edited = [result(1:index-1), newSeq, result(index:end)];
                result = edited;

                %Update, check again - do we need to loop round again, or
                %did we get all the nested sequences?
                [tf, index] = ContainsRunSequenceCommand(result);
            end

            %Pass on event - if a Controller made this as expected in a
            %normal programme running (not a unit test for example), it
            %will be listening and will call CacheInstrumentCommand etc
            args = Palladium.Events.SequenceEventData(result);
            notify(this, "SequenceQueue", args);

            function [tf, index] = ContainsRunSequenceCommand(cellArrayOfCommands)
                %Returns true and the index on first identified example, as
                %when we use this to decode the seq and insert new lines
                %for the nested sequence, the indices of any others further
                %down will change, so just keep iterating the first until
                %all are ticked off.
                tf = false;
                index = [];

                for i = 1 : length(cellArrayOfCommands)
                    if isa(cellArrayOfCommands{i}, 'Palladium.Sequence.Commands.RunSequenceCommand')
                        tf = true;
                        index = i;
                        return;
                    end
                end
            end
        end

        function SaveSequenceButtonPushed(this, sequenceLines)
            this.SelectedDir
            seqExt = "*" + string(this.FileWriteDetails.FileExtension);
            filter = {seqExt, "Palladium Sequence Files"};
            defaultpath = fullfile(this.SelectedDir, this.FileWriteDetails.FileName);
            title = "Save Sequence As..";

            %Open a save as file dialogue
            [file,location] = uiputfile(filter, title, defaultpath);
            if isequal(file,0) || isequal(location,0)
                return;
            end

            path = fullfile(location,file);

            this.SaveSequenceToFile(sequenceLines, path);

            %Refresh the GUI, as a new file may well have appeared in it
            this.View.RefreshDir();
        end

        function SetSequence(this, seqLines)
            this.View.SetSequence(seqLines);
        end

        function SingleCommandQueued(this, ~, args)
            %Pass on event - if a Controller made this as expected in a
            %normal programme running (not a unit test for example), it
            %will be listening and will call CacheInstrumentCommand
            notify(this, "SingleCommandQueue", args);
        end

    end

    %% Methods (Private)
    methods(Access=private)

        function sequenceLines = LoadSequenceFromFile(~, filePath)

            lnes = readlines(filePath);

            if isempty(lnes)
                warndlg("Empty or invalid sequence file");
                sequenceLines = [];
                return;
            end

            if length(lnes) < 2
                warndlg("Empty or invalid sequence file");
                sequenceLines = [];
                return;
            end

            %Trim off first two lines (header)
            sequenceLines = lnes(3:end);

            %Remove any trailing empty lines
            foundLine = true;
            while(foundLine)
                if isempty(sequenceLines(end)) || strcmp(sequenceLines(end), "")
                    sequenceLines(end) = [];
                    foundLine = true;
                else
                    foundLine = false;
                end
            end


        end

        function SaveSequenceToFile(~, sequenceLines, filePath)
            %Will overwrite
            fid = fopen(filePath, 'w');

            formatSpec = '%s\n';

            fprintf(fid, formatSpec, Palladium.Sequence.SequenceEditorController.SequenceFileHeader);
            fprintf(fid, formatSpec, "");

            %Remove any trailing empty lines
            foundLine = true;
            while(foundLine)
                if isempty(sequenceLines(end)) || strcmp(sequenceLines(end), "")
                    sequenceLines(end) = [];
                    foundLine = true;
                else
                    foundLine = false;
                end
            end

            for i = 1 : length(sequenceLines)
                fprintf(fid, formatSpec, sequenceLines{i});
            end

            fclose(fid);
        end

        function tf = ViewExists(this)
            tf = ~isempty(this.View) && isvalid(this.View);
        end
    end
end

