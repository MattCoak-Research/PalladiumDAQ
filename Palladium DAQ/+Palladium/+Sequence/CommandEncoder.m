classdef CommandEncoder < handle
    %COMMANDENCODER
    %Handles parsing sequence text into Command objects, and creating those
    %strings
    %
    %Sequence text looks like:
    %[WAIT] 2.5 Sec

    %% Properties (Constant, Public)
    properties(Constant, Access=public)
        Enc_DataFile = "DATAFILE";
        Enc_Instr = "INSTR";
        Enc_RunSequence = "RUN";
        Enc_Wait = "WAIT";
    end

    %% Properties (Public)
    properties

    end

    %% Properties (Private)
    properties(Access=private)

    end

    %% Constructor
    methods

        function this = CommandEncoder()
        end

    end

    %% Methods (Public)
    methods(Access=public)

        function com = BuildCommandFromEventDetails(this, details)
            switch details.Type
                case this.Enc_DataFile
                    writeToFile = details.WriteToFile;
                    if writeToFile
                        %No file name: no path, so writing resumes with the
                        %current file name (the folder alone is not a file)
                        if strlength(strtrim(string(details.FileName))) == 0
                            filePath = "";
                        else
                            filePath = fullfile(details.Directory, details.FileName);
                        end
                        com = Palladium.Sequence.Commands.DataFileCommand(true, "DataFilePath", filePath);
                    else
                        com = Palladium.Sequence.Commands.DataFileCommand(false);
                    end

                case this.Enc_Instr
                    instr = details.Instrument;
                    com = Palladium.Sequence.Commands.InstrumentCommand(instr, details.CommandString, details.ControlName);

                case this.Enc_RunSequence
                    com = Palladium.Sequence.Commands.RunSequenceCommand(details.SequenceFilePath);

                case this.Enc_Wait
                    %Fetch and convert the wait value (get it into seconds,
                    %which the command expects, regardless of the display
                    %unit)
                    waitValue = details.WaitValue;
                    switch(details.WaitUnits)
                        case("sec")
                            waitVal_Sec = waitValue;
                        case("min")
                            waitVal_Sec = waitValue * 60;
                        case("hr")
                            waitVal_Sec = waitValue * 3600;
                        otherwise
                            error("BuildCommandFromEventDetailsError:UnrecognisedWaitUnit", "%s", "Unrecognised wait unit: " + string(details.WaitUnits));
                    end

                    com = Palladium.Sequence.Commands.WaitCommand(waitVal_Sec, "WaitDisplayUnits", details.WaitUnits);

                otherwise
                    error("BuildCommandFromEventDetailsError:UnrecognisedCommandType", "%s", "Unrecognised command type string: " + string(details.Type));
            end
        end

        function str = CommandToString(this, com)
            classType = extractAfter(class(com), 'Commands.');

            switch(classType)
                case("DataFileCommand")
                    str = this.BuildDataFileCommand(FilePath=com.DataFilePath, WriteToFile=com.WriteToFile);

                case("InstrumentCommand")
                    str = this.BuildInstrumentCommand(Instrument=com.Instrument, CommandString=com.CommandString, ControlName=com.ControlName);
                
                case("RunSequenceCommand")
                    str = this.BuildRunSequenceCommand(FilePath=com.SequencePath);

                case("WaitCommand")
                    waitVal = com.Wait_seconds;
                    waitDisplayUnit = com.WaitDisplayUnit;
                    str = this.BuildWaitCommand(WaitValue=waitVal, WaitUnit=waitDisplayUnit);

                otherwise
                    error("CommandToStringError:UnrecognisedCommandClass", "%s", "Unrecognised command class type in CommandEncoder: " + string(classType));
            end

        end

        function result = ParseSequenceText(this, strArrayOfSequenceLines, instrumentsList)
            arguments
                this;
                strArrayOfSequenceLines (:,1) string;
                instrumentsList = [];
            end

            %Remove empty and comment lines
            lns = strArrayOfSequenceLines(~strcmp(strArrayOfSequenceLines(:,1),""), :);
            lns = lns(~startsWith(lns, '%'));

            if isempty(lns)
                result = [];
            end

            for i = 1 : length(lns)
                result{i} = this.StringToCommand(lns(i), instrumentsList);
            end

        end

        function com = StringToCommand(this, str, instrumentsList)
            arguments
                this;
                str {mustBeTextScalar};
                instrumentsList = [];
            end

            typeStr = extractBetween(str, '[', ']');
            assert(~isempty(typeStr), "StringToCommandError:TypeStringNotFound", "Type String not found");

            commandStr = extractAfter(str, ']');
            commandStr = strtrim(commandStr);

            % Parse the command string based on the provided type
            switch typeStr{1}
                case this.Enc_DataFile
                    [writeToFile, filePath] = this.ParseDataFileCommand(commandStr);
                    com = Palladium.Sequence.Commands.DataFileCommand(writeToFile, "DataFilePath", filePath);

                case this.Enc_Instr
                    [instrumentName, command, controlName] = this.ParseInstrumentCommand(commandStr);
                    instrument = this.GetInstrumentFromName(instrumentName, instrumentsList);
                    com = Palladium.Sequence.Commands.InstrumentCommand(instrument, command, controlName);

                case this.Enc_RunSequence
                    seqFilePath = this.ParseRunSequenceCommand(commandStr);
                    com = Palladium.Sequence.Commands.RunSequenceCommand(seqFilePath);

                case this.Enc_Wait
                    [waitVal_Sec, waitUnits] = this.ParseWaitCommand(commandStr);
                    com = Palladium.Sequence.Commands.WaitCommand(waitVal_Sec, "WaitDisplayUnits", waitUnits);

                otherwise
                    error("StringToCommandError:UnrecognisedCommandType", "%s", "Unrecognised command type string: " + string(typeStr{1}));
            end

        end

    end

    %% Methods (Private)
    methods(Access=private)

        function str = BuildDataFileCommand(this, Settings)
            arguments
                this;
                Settings.FilePath {mustBeTextScalar} = "";
                Settings.WriteToFile (1,1) logical;
            end

            %Build the command
            str = "[" + Palladium.Sequence.CommandEncoder.Enc_DataFile + "]" + " " + num2str(Settings.WriteToFile);
            
            %Add the path, if there is one (with none, [DATAFILE] 1 switches
            %writing back on with the current file name)
            if Settings.WriteToFile && strlength(string(Settings.FilePath)) > 0
                str = str + " : " + string(Settings.FilePath);
            end
        end

        function str = BuildInstrumentCommand(this, Settings)
            arguments
                this;
                Settings.Instrument (1,1) Palladium.Core.Instrument;
                Settings.ControlName {mustBeTextScalar} = string.empty;
                Settings.CommandString {mustBeTextScalar};
            end

            name = string(Settings.Instrument.Name);
            if ~isempty(Settings.ControlName)
                name = name + "." + string(Settings.ControlName);
            end

            %Build the command
            %[INSTR] Keithley2410_1.SweepControl : PrintIdentifier(foo)
            str = "[" + Palladium.Sequence.CommandEncoder.Enc_Instr + "]" + " " + name + " : " + Settings.CommandString;
        end

        function str = BuildRunSequenceCommand(this, Settings)
            arguments
                this;
                Settings.FilePath {mustBeTextScalar};
            end

            %Build the command
            str = "[" + Palladium.Sequence.CommandEncoder.Enc_RunSequence + "]" + " " + string(Settings.FilePath);
        end

        function str = BuildWaitCommand(this, Settings)
            arguments
                this;
                Settings.WaitValue (1,1) double;
                Settings.WaitUnit {mustBeTextScalar} = "sec";
            end

            %Convert to lower case so we don't have to worry about Sec not
            %being recognised as sec
            waitUnit = lower(Settings.WaitUnit);

            switch(waitUnit)
                case("sec")
                    val = Settings.WaitValue;
                case("min")
                    val = Settings.WaitValue / 60;
                case("hr")
                    val = Settings.WaitValue / 3600;
                otherwise
                    error("BuildWaitCommandError:UnrecognisedWaitUnit", "%s", "Unrecognised wait unit: " + Settings.WaitUnit);
            end

            %Round to 3dp, stop it getting silly
            val = round(val, 3);

            %Build the command
            str = "[" + Palladium.Sequence.CommandEncoder.Enc_Wait + "]" + " " + num2str(val) + " " + Settings.WaitUnit;
        end

        function instRef = GetInstrumentFromName(~, instName, instrumentsList)
            instRef = []; %#ok<NASGU>

            for i = 1 : length(instrumentsList)
                if instrumentsList{i}.Name == instName
                    instRef = instrumentsList{i};
                    return;
                end
            end

            %If we got here, none of the instruments matched
            instStringNameList = "";
            for i = 1 : length(instrumentsList)
                instStringNameList = instStringNameList + instrumentsList{i}.Name;
                if i ~= length(instrumentsList)
                    instStringNameList = instStringNameList + ", ";
                end
            end
            if instStringNameList == ""
                instStringNameList = "-NONE-";
            end

            error("GetInstrumentFromNameError:NotFound", "%s", "Could not find instrument of Name " + instName + ". Added Instruments: " + instStringNameList);
        end

        function [writeFile, path] = ParseDataFileCommand(~, str)
            %Parse the text after [DATAFILE]: a flag, 1 (write) or 0
            %(stop writing), then optionally " : " and a file path, e.g.
            %"1 : C:\Data\Run2.dat", or just "0". Split at the first : only,
            %as Windows paths have another one after the drive letter. With
            %0, or with 1 and no path, the path is empty: keep the current
            %file name, and just switch writing on or off
            str = string(str);
            if contains(str, ":")
                flag = strtrim(extractBefore(str, ":"));
                path = strtrim(extractAfter(str, ":"));
            else
                flag = strtrim(str);
                path = "";
            end

            switch lower(flag)
                case {"1", "true"};     writeFile = true;
                case {"0", "false"};    writeFile = false;
                otherwise
                    error("ParseDataFileCommandError:InvalidFlag", "%s", "Data File command must start with 1 (write to file) or 0 (stop writing), but was given: " + str);
            end

            %A path means nothing when writing is switched off
            if ~writeFile
                path = "";
            end
        end

        function [instrumentName, command, controlName] = ParseInstrumentCommand(this, str)

            %[INSTR] Keithley2410_1.SweepControl : PrintIdentifier(foo)
            %[INSTR] and whitespace stripped by the time it gets here, will
            %look like:
            %Keithley2410_1.SweepControl : PrintIdentifier(foo)
            %or
            %Keithley2410_1 : PrintIdentifier(foo)

            %Split at the first : to separate target (first) and command
            %(second). Only the first - the command's arguments may contain
            %colons, e.g. a path like C:\Data
            str = string(str);
            assert(contains(str, ":"), "ParseInstrumentCommandError:MissingDelimiter", "%s", "Instrument command must be <Instrument Name> : <Method(arguments)>, but was given: " + str);
            targ = extractBefore(str, ":");
            command = strtrim(extractAfter(str, ":"));

            ss2 = strsplit(targ, ".");

            %First element is instrument name
            instrumentName = string(strtrim(ss2{1}));

            if length(ss2) > 1
                %We have a control name after the period
                controlName = string(strtrim(ss2{2}));
            else
                controlName = string.empty;
            end

        end

        function [seqFilePath] = ParseRunSequenceCommand(this, str)

           seqFilePath = str;
        end

        function [waitVal_Sec, waitUnit] = ParseWaitCommand(~, str)
            %Parse the text after [WAIT]: a number and a unit, sec, min or
            %hr (in any case), separated by any amount of space, e.g.
            %"30 sec". Returns the wait in seconds, and the unit in lower case
            parts = split(strtrim(string(str)));
            assert(numel(parts) == 2, "ParseWaitCommandError:InvalidFormat", "%s", "Wait command must be a number and a unit (sec, min or hr), e.g. 30 sec, but was given: " + string(str));

            val = str2double(parts(1));
            assert(~isnan(val), "ParseWaitCommandError:InvalidNumber", "%s", "Wait time is not a number: " + parts(1));

            waitUnit = lower(parts(2));
            switch waitUnit
                case "sec";     waitVal_Sec = val;
                case "min";     waitVal_Sec = val * 60;
                case "hr";      waitVal_Sec = val * 3600;
                otherwise
                    error("ParseWaitCommandError:UnrecognisedWaitUnit", "%s", "Unrecognised wait unit: " + parts(2) + " (use sec, min or hr)");
            end
        end

    end

end