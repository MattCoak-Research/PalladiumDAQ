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

                case this.Enc_Instr
                    instr = details.Instrument;
                    com = Palladium.Sequence.Commands.InstrumentCommand(instr, details.CommandString, details.ControlName);
                case this.Enc_RunSequence

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
                            error("Unrecognised wait unit: " + string(details.WaitUnits));
                    end

                    com = Palladium.Sequence.Commands.WaitCommand(waitVal_Sec, "WaitDisplayUnits", details.WaitUnits);

                otherwise
                    error("Unrecognised command type string: " + string(details.Type));
            end
        end

        function str = CommandToString(this, com)
            classType = extractAfter(class(com), 'Commands.');

            switch(classType)
                case("DataFileCommand")

                case("InstrumentCommand")
                    str = this.BuildInstrumentCommand(Instrument=com.Instrument, CommandString=com.CommandString, ControlName=com.ControlName);
                case("RunSequenceCommand")

                case("WaitCommand")
                    waitVal = com.Wait_seconds;
                    waitDisplayUnit = com.WaitDisplayUnit;
                    str = this.BuildWaitCommand(WaitValue=waitVal, WaitUnit=waitDisplayUnit);
                otherwise
                    error("Unrecognised command class type in CommandEncoder: " + string(classType));
            end

        end

        function result = ParseSequenceText(this, cellArrayOfSequenceLines, instrumentsList)
            arguments
                this;
                cellArrayOfSequenceLines (:,1) cell;
                instrumentsList = [];
            end

            %Remove empty and comment lines
            lns = cellArrayOfSequenceLines(~cellfun('isempty', cellArrayOfSequenceLines));
            lns = lns(~startsWith(lns, '%'));

            for i = 1 : length(lns)
                result{i} = this.StringToCommand(string(lns{i}), instrumentsList);
            end

        end

        function com = StringToCommand(this, str, instrumentsList)
            arguments
                this;
                str {mustBeTextScalar};
                instrumentsList = [];
            end

            typeStr = extractBetween(str, '[', ']');
            assert(~isempty(typeStr), "Type String not found");

            commandStr = extractAfter(str, ']');
            commandStr = strtrim(commandStr);

            % Parse the command string based on the provided type
            switch typeStr{1}
                case this.Enc_DataFile

                case this.Enc_Instr
                    [instrumentName, command, controlName] = this.ParseInstrumentCommand(commandStr);
                    instrument = this.GetInstrumentFromName(instrumentName, instrumentsList);
                    com = Palladium.Sequence.Commands.InstrumentCommand(instrument, command, controlName);
                case this.Enc_RunSequence

                case this.Enc_Wait
                    [waitVal_Sec, waitUnits] = this.ParseWaitCommand(commandStr);
                    com = Palladium.Sequence.Commands.WaitCommand(waitVal_Sec, "WaitDisplayUnits", waitUnits);
                otherwise
                    error("Unrecognised command type string: " + string(typeStr{1}));
            end

        end

    end

    %% Methods (Private)
    methods(Access=private)

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
                    error("Unrecognised wait unit: " + Settings.WaitUnit);
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
                instStringNameList = instStringNameList + instrumentsList.Name;
                if i ~= length(instrumentsList)
                    instStringNameList = instStringNameList + ", ";
                end
            end
            if instStringNameList == ""
                instStringNameList = "-NONE-";
            end

            error("GetInstrumentFromNameError:NotFound", "Could not find instrument of Name " + instName + ". Added Instruments: " + instStringNameList);
        end

        function [instrumentName, command, controlName] = ParseInstrumentCommand(this, str)

            %[INSTR] Keithley2410_1.SweepControl : PrintIdentifier(foo)
            %[INSTR] and whitespace stripped by the time it gets here, will
            %look like:
            %Keithley2410_1.SweepControl : PrintIdentifier(foo)
            %or
            %Keithley2410_1 : PrintIdentifier(foo)

            %Split on the : to seperate target (first) and command (second)
            ss = strsplit(str, ":");
            targ = string(ss{1});
            command = string(strtrim(ss{2}));

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

        function [waitVal_Sec, waitUnit] = ParseWaitCommand(this, str)

            ss = strsplit(str, " ");
            val = str2double(ss{1});
            waitUnit = ss{2};

            switch(waitUnit)
                case("sec")
                    waitVal_Sec = val;
                case("min")
                    waitVal_Sec = val * 60;
                case("hr")
                    waitVal_Sec = val * 3600;
                otherwise
                    error("Unrecognised wait unit: " + Settings.WaitUnit);
            end

        end

    end

end