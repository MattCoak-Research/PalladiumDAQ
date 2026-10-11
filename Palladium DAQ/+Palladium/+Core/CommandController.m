classdef CommandController < handle
    %CommandController - Runs queued sequence and instrument commands, one at a time, at the start of each tick.
    %Created by the Controller, which holds it as `CommandController`. It
    %keeps one first-in, first-out queue of commands
    %(`Palladium.Sequence.Commands` objects), filled in two ways:
    %
    %* **Sequences**: the Sequence Editor's `SequenceQueue` event reaches
    %  `Controller.QueueSequence`, which calls `CacheCommands` with the
    %  whole sequence.
    %* **Single commands**: the Sequence Editor's `SingleCommandQueue`
    %  event, or `Palladium.CacheInstrumentCommand` from a script, reaches
    %  `Controller.CacheInstrumentCommand`, which calls
    %  `CacheInstrumentCommand`.
    %
    %Commands are never run straight away, because the instruments may be
    %in the middle of a reading. Instead `Controller.Measure` calls
    %`Update` at the start of every tick of the measurement loop (run by
    %the TimingLoopController), before the InstrumentController collects
    %the tick's data row. So commands run between readings, and only while
    %measurements are running.
    %
    %Each `Update` starts the next command if none is in progress. A
    %command with an `IsCompleteFn` (a `WaitCommand`, or an instrument
    %method registered with a completion check, such as ramping to a
    %temperature) holds up the queue, and is checked again each tick until
    %it is complete. When a command completes, its `FunctionOnComplete` is
    %called. When a sequence's commands have all run, `CommandsFinished`
    %is raised; a `DataFileCommand` raises `DataFileCommandRun`. The
    %Controller listens to both. `AbortSequence` empties the queue.
    %
    %An `InstrumentCommand`'s text is turned into a call of one method of
    %the instrument, or of one of its Instrument Controls. Only logical,
    %double and string arguments are supported: true/false, numbers, and
    %text - in quotes ("..." or '...') if it contains spaces, commas or
    %colons, or should not be read as a number. For example:
    %
    %* `ClearStatus` or `ClearStatus()` calls `instr.ClearStatus()`
    %* `SetSourceLevel(2.1, true)` calls `instr.SetSourceLevel(2.1, true)`
    %* `SetSample("Sample A, run 2")` calls `instr.SetSample("Sample A, run 2")`

    %% Properties (Public)
    properties
        DebugMode = false;  %True to print the method and number of arguments of each instrument command run
    end

    %% Properties (Dependent, Public)
    properties (Dependent)
        Busy;               %True while a command that takes several ticks is in progress
    end

    %% Properties (Private)
    properties(Access = private)
        CachedCommands = [];                %Cell array of the commands waiting to run, first in first out
        CommandCurrentlyExecuting = [];     %The command in progress, waiting for its IsCompleteFn to return true, or [] for none
        SequenceRunning = false;            %True from CacheCommands until the queue empties and CommandsFinished is raised
    end

    %% Events
    events
        CommandsFinished;       %Raised when the commands of a sequence have all run - the Controller tells the Sequence Editor
        DataFileCommandRun;     %Raised by a DataFileCommand, with a DataFileEventData - the Controller switches data file or saving on or off
    end

    %% Get and Set Accessors
    methods
        function val = get.Busy(this)
            %True while a command that takes several ticks is in progress.

            val = ~isempty(this.CommandCurrentlyExecuting);
        end
    end

    %% Constructor
    methods
        function this = CommandController(Settings)
            %Create the controller, with an empty queue.
            %
            %Inputs:
            %   DebugMode - true to print details of each instrument command
            %               run. Default false

            arguments
                Settings.DebugMode (1,1) logical = false;
            end

            this.DebugMode = Settings.DebugMode;
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function AbortSequence(this)
            %Clear all queued commands, sequence and single alike, and abort the one in progress.
            %Calls the in-progress command's Abort. Called by the Controller
            %when the Sequence Editor's abort button is pressed. Does not
            %raise CommandsFinished

            this.CachedCommands = [];
            this.SequenceRunning = false;

            if ~isempty(this.CommandCurrentlyExecuting)
                this.CommandCurrentlyExecuting.Abort();
                this.CommandCurrentlyExecuting = [];
            end
        end

        function CacheCommands(this, cellArrayOfCommands)
            %Add a sequence's commands to the end of the queue.
            %Called by `Controller.QueueSequence`. CommandsFinished is raised
            %once the queue has emptied
            %
            %Inputs:
            %   cellArrayOfCommands - cell array of Palladium.Sequence.Commands
            %                         objects, in the order to run them

            this.CachedCommands = [this.CachedCommands, cellArrayOfCommands];
            this.SequenceRunning = true;
        end

        function CacheInstrumentCommand(this, instrument, command, controlName, Settings)
            %Add a single instrument command to the end of the queue, to run on a coming tick.
            %Called by `Controller.CacheInstrumentCommand`. Unlike
            %CacheCommands, does not start a sequence, so CommandsFinished
            %is not raised for it
            %
            %Inputs:
            %   instrument         - the Palladium.Core.Instrument to run it on
            %   command            - the method call, e.g. "SetSourceLevel(2, false)"
            %   controlName        - name of one of the instrument's
            %                        Instrument Controls to run it on instead,
            %                        e.g. "Sweep Control". Default empty, the
            %                        instrument itself
            %   FunctionOnComplete - function to call when the command
            %                        completes. Default []

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
            %Run one command now, according to its type.
            %An InstrumentCommand calls the instrument (or control) method,
            %a WaitCommand starts its timer, and a DataFileCommand raises
            %DataFileCommandRun. Normally called by Update; errors for any
            %other command type
            %
            %Inputs:
            %   command - an InstrumentCommand, WaitCommand or DataFileCommand

            cmdType = class(command);

            switch(cmdType)
                case("Palladium.Sequence.Commands.InstrumentCommand");  this.ExecuteInstrumentCommand(command);
                case("Palladium.Sequence.Commands.WaitCommand");        this.ExecuteWaitCommand(command);
                case("Palladium.Sequence.Commands.DataFileCommand");    this.ExecuteDataFileCommand(command);
                otherwise
                    error("ExecuteCommandError:UnsupportedCommandType", "%s", "Unsupported command type " + string(cmdType))
            end
        end

        function command = PullCachedCommand(this)
            %Remove the next command from the front of the queue and return it.
            %
            %Outputs:
            %   command - the command, or [] if the queue is empty

            if isempty(this.CachedCommands)
                command = [];
                return;
            end

           command = this.CachedCommands{1};

           %Delete from heap - first in first out
           this.CachedCommands(1) = [];
        end

        function Update(this)
            %Run or check on the queued commands - called by the Controller at the start of each tick.
            %If a command is in progress, checks its IsCompleteFn and, once
            %it is complete, calls its FunctionOnComplete, so the next
            %command starts on the following tick. Otherwise starts the next
            %command: one with no IsCompleteFn completes at once (its
            %FunctionOnComplete is called straight away), and one with an
            %IsCompleteFn becomes the command in progress. If the queue is
            %empty at the end of a sequence, raises CommandsFinished

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
            %End the sequence, and raise CommandsFinished.

            this.SequenceRunning = false;
            this.Log("All commands finished, Sequence complete");
            notify(this, "CommandsFinished");
        end

        function [fnHandle, args] = AssembleFunctionHandle(this, commandStr)
            %Turn a command string into a function that calls the method on a target, and its arguments.
            %For example SetTemperature(10, "Sample A") gives a function
            %called as fnHandle(target, args), where target is an instrument
            %or one of its controls, and args is {10, "Sample A"}

            [methodName, args] = this.ParseCommandString(commandStr);
            fnHandle = @(target, args) target.(methodName)(args{:});

            if this.DebugMode
                this.Log(" ");
                this.Log("Method to execute: " + methodName + ", with " + numel(args) + " argument(s)");
                this.Log(" ");
            end
        end

        function outVal = ConvertArgumentType(~, arg)
            %Convert an unquoted argument to true or false, a number, or else keep it as text.

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
            %Split a command string into the method name and a cell array of its arguments.
            %For example SetTemperature(10, "Sample A"). The brackets are
            %optional with no arguments (e.g. ClearStatus), and a trailing ";"
            %is ignored. Errors if the method name isn't a valid name

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
            %Raise DataFileCommandRun with the command's data file path and whether to save.

            this.Log("Data File Command: " + command.GetDescription());

            fileWriteDetails.FullPath = command.DataFilePath;
            fileWriteDetails.SaveFile = command.WriteToFile;

            args = Palladium.Events.DataFileEventData(fileWriteDetails);
            notify(this, "DataFileCommandRun", args);
        end

        function ExecuteInstrumentCommand(this, command)
            %Call the command's method on its instrument, or on the named Instrument Control.

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
            %Start a WaitCommand's timer.

            this.Log("Starting wait, " + command.GetDurationString());
            command.Start();
        end

        function Log(this, str)
            %Print a message to the Command Window, prefixed "Seq:: ", or a blank line for empty or " ".

            if isempty(str) || strcmp(str, " ")
                disp(" ");
            else
                disp("Seq:: " + string(str));    %disp prints backslashes as they are - no escaping needed
            end
        end
    end

end
