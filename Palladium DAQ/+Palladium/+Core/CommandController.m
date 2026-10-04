classdef CommandController < handle
    %CommandController - caches custom commands to send to instruments each
    %tick, prior to measure. part of Sequence control/architecture.
    %Also has tools to turn a Command struct of an instrument ref and a
    %string expected to represent a function call into a function handle
    %and then exceute it on that Instrument. Only logical, double and
    %string arguments are supported: true/false, numbers, and text - in
    %quotes ("..." or '...') if it contains spaces, commas or colons, or
    %should not be read as a number.
    %
    %Example command structs that would work in ExecuteCommand:
    %cmd3.Instrument = k; cmd3.Command = "Close";   (k a reference to a
    %Keithley2000 Instrument object already created elsewhere)
    %cmd.Instrument = k; cmd.Command = "SetSourceLevel(2.1,true)";

    %% Properties (Public)
    properties
        %Will print verbose messages if this is set to true
        DebugMode = false;
    end

    %% Properties (Dependent, Public)
    properties (Dependent)
        Busy;
    end

    %% Properties (Private)
    properties(Access = private)
        CachedCommands = [];
        CommandCurrentlyExecuting = [];
        SequenceRunning = false;
    end

    %% Events
    events
        CommandsFinished;
        DataFileCommandRun;
    end

    %% Get and Set Accessors
    methods
        function val = get.Busy(this)
            val = ~isempty(this.CommandCurrentlyExecuting);
        end
    end

    %% Constructor
    methods
        function this = CommandController(Settings)
            arguments
                Settings.DebugMode (1,1) logical = false;
            end

            this.DebugMode = Settings.DebugMode;
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function AbortSequence(this)
            %Clears all cached commands, sequence and single alike            
            this.CachedCommands = [];
            this.SequenceRunning = false;

            if ~isempty(this.CommandCurrentlyExecuting)
                this.CommandCurrentlyExecuting.Abort();
                this.CommandCurrentlyExecuting = [];
            end
        end

        function CacheCommands(this, cellArrayOfCommands)           
            this.CachedCommands = [this.CachedCommands, cellArrayOfCommands];
            this.SequenceRunning = true;
        end

        function CacheInstrumentCommand(this, instrument, command, controlName, Settings)
            arguments
                this;
                instrument (1,1) Palladium.Core.Instrument;
                command {mustBeTextScalar};
                controlName = string.empty;
                Settings.FunctionOnComplete = [];
            end

            newCommand = Palladium.Sequence.Commands.InstrumentCommand(instrument, command, controlName, FunctionOnComplete = Settings.FunctionOnComplete);

            if isempty(this.CachedCommands)
                this.CachedCommands = {newCommand};
            else
                this.CachedCommands{end+1} = newCommand;
            end
        end

        function ExecuteCommand(this, command)
            cmdType = class(command);

            switch(cmdType)
                case("Palladium.Sequence.Commands.InstrumentCommand")
                    this.ExecuteInstrumentCommand(command);
                case("Palladium.Sequence.Commands.WaitCommand")
                    this.ExecuteWaitCommand(command);
                case("Palladium.Sequence.Commands.DataFileCommand")
                    this.ExecuteDataFileCommand(command);
                otherwise
                    error("ExecuteCommandError:UnsupportedCommandType", "%s", "Unsupported command type " + string(cmdType))
            end
        end

        function command = PullCachedCommand(this)
            %Return a list of commands to be executed this tick, and clear
            %them from the heap

            if isempty(this.CachedCommands)
                command = [];
                return;
            end

           command = this.CachedCommands{1};

           %Delete from heap - first in first out
           this.CachedCommands(1) = [];
        end

        function Update(this)
            if isempty(this.CommandCurrentlyExecuting)
                %Execute any sequence/instrument commands
                command = this.PullCachedCommand();
                if ~isempty(command)
                    this.ExecuteCommand(command);

                    %Check if command finished right away and handle
                    if isempty(command.IsCompleteFn)    %If left blank, command will be assumed to have completed instantly. Overide to make the controller check each tick instead
                        %Function completed
                        if ~isempty(command.FunctionOnComplete)
                            command.FunctionOnComplete();
                        end
                    else
                        %Function needs some time to complete. Set it as
                        %CommandCurrentlyExecuting, blocking execution of future
                        %ones until it is complete
                        this.CommandCurrentlyExecuting = command;
                    end
                else
                    if this.SequenceRunning
                        this.AllCommandsFinished();
                    end
                end
            else
                %Check to see if the running command is now finished
                if this.CommandCurrentlyExecuting.IsCompleteFn()
                    %Function completed
                    if ~isempty(this.CommandCurrentlyExecuting.FunctionOnComplete)
                        this.CommandCurrentlyExecuting.FunctionOnComplete();
                    end

                    %Clear the property to let the next command queue up
                    %next tick
                    this.CommandCurrentlyExecuting = [];
                end
            end
        end
    end

    %% Methods (Private)
    methods(Access = private)

        function AllCommandsFinished(this)
            this.SequenceRunning = false;
            this.Log("All commands finished, Sequence complete");
            notify(this, "CommandsFinished");
        end

        function [fnHandle, args] = AssembleFunctionHandle(this, commandStr)
            %Turn a command such as SetTemperature(10, "Sample A") into a
            %function that calls that method on a target (an instrument or
            %one of its controls), and a cell array of the arguments to
            %pass it: fnHandle(target, args)
            [methodName, args] = this.ParseCommandString(commandStr);
            fnHandle = @(target, args) target.(methodName)(args{:});

            if this.DebugMode
                this.Log(" ");
                this.Log("Method to execute: " + methodName + ", with " + numel(args) + " argument(s)");
                this.Log(" ");
            end
        end

        function outVal = ConvertArgumentType(~, arg)
            %An unquoted argument: true or false, a number, or else text
            switch lower(arg)
                case "true";    outVal = true;
                case "false";   outVal = false;
                otherwise
                    outVal = str2double(arg);
                    if isnan(outVal)
                        outVal = arg;   %Not a number - keep it as text
                    end
            end
        end

        function [methodName, args] = ParseCommandString(this, commandStr)
            %Split a command such as SetTemperature(10, "Sample A") into the
            %method name and a cell array of its arguments. The brackets
            %are optional with no arguments (e.g. Connect)
            cmd = strtrim(string(commandStr));
            if endsWith(cmd, ";")
                cmd = strtrim(extractBefore(cmd, strlength(cmd)));
            end

            if contains(cmd, "(")
                methodName = strtrim(extractBefore(cmd, "("));
                assert(endsWith(cmd, ")"), "ParseCommandStringError:MissingBracket", "%s", "Command must end with ): " + cmd);
                openIdx = strfind(cmd, "(");
                argStr = extractBetween(cmd, openIdx(1) + 1, strlength(cmd) - 1);   %Between the first ( and the last )
            else
                methodName = cmd;
                argStr = "";
            end

            assert(isvarname(methodName), "ParseCommandStringError:InvalidMethodName", "%s", "Not a valid method name: '" + methodName + "', in command: " + cmd);
            args = this.SplitArguments(argStr);
        end

        function args = SplitArguments(this, argStr)
            %Split a comma-separated list of arguments into a cell array.
            %Commas inside quotes ("..." or '...') don't split; quoted text
            %is kept exactly, without its quotes, and is never converted to
            %a number or true/false. Unquoted arguments are trimmed and
            %converted with ConvertArgumentType
            args = {};
            argStr = char(argStr);
            if isempty(strtrim(argStr))
                return;
            end

            quoteChars = ['"', ''''];
            pieces = {};
            quoteChar = '';
            startIdx = 1;
            for k = 1 : length(argStr)
                c = argStr(k);
                if isempty(quoteChar) && any(c == quoteChars)
                    quoteChar = c;
                elseif ~isempty(quoteChar) && c == quoteChar
                    quoteChar = '';
                elseif isempty(quoteChar) && c == ','
                    pieces{end + 1} = argStr(startIdx : k - 1); %#ok<AGROW>
                    startIdx = k + 1;
                end
            end
            assert(isempty(quoteChar), "SplitArgumentsError:UnclosedQuote", "%s", "Unclosed quote in arguments: " + string(argStr));
            pieces{end + 1} = argStr(startIdx : end);

            args = cell(1, numel(pieces));
            for k = 1 : numel(pieces)
                piece = strtrim(pieces{k});
                assert(~isempty(piece), "SplitArgumentsError:EmptyArgument", "%s", "Empty argument in: " + string(argStr));
                if length(piece) >= 2 && any(piece(1) == quoteChars) && piece(end) == piece(1)
                    args{k} = string(piece(2 : end - 1));
                else
                    args{k} = this.ConvertArgumentType(string(piece));
                end
            end
        end

        function ExecuteDataFileCommand(this, command)
            this.Log("Data File Command: " + command.GetDescription());

            fileWriteDetails.FullPath = command.DataFilePath;
            fileWriteDetails.SaveFile = command.WriteToFile;

            args = Palladium.Events.DataFileEventData(fileWriteDetails);
            notify(this, "DataFileCommandRun", args);
        end

        function ExecuteInstrumentCommand(this, command)

            %Get the function and a packaged struct of its arguments
            [fnHandle, args] = this.AssembleFunctionHandle(command.CommandString);

            %Retrieve the thing to call the function on - could be the
            %instrument reference itself, if no control name given, or one
            %of it's controls
            if isempty(command.ControlName)
                target = command.Instrument;
            else
                targets = command.Instrument.GetRegisteredControlObjectsFromName(command.ControlName);
                assert(isscalar(targets), "ExecuteInstrumentCommandError:ControlNotUnique", "%s", "Found multiple Controls or no Control of this name: " + string(command.ControlName));
                target = targets(1);
            end

            %Execute the function on the Instrument stored in the command
            %struct
            fnHandle(target, args);

        end

        function ExecuteWaitCommand(this, command)
            this.Log("Starting wait, " + command.GetDurationString());
            command.Start();
        end

        function Log(this, str)
            if isempty(str) || strcmp(str, " ")
                disp(" ");
            else
                disp("Seq:: " + string(strrep(str, '\', '\\')));    %Properly escape filepath separators so the string of a path renders properly
            end
        end
    end

end