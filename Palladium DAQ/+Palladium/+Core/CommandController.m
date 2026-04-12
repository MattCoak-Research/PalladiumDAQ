classdef CommandController < handle
    %CommandController - caches custom commands to send to instruments each
    %tick, prior to measure. part of Sequence control/architecture.
    %Also has tools to turn a Command struct of an instrument ref and a
    %string expected to represent a function call into a function handle
    %and then exceute it on that Instrument. Only logical, double and
    %string arguments are currently supported.
    %
    %Example command structs that would work in ExecuteCommand:
    %cmd3.Instrument = k; cmd3.Command = "Close";   (k a reference to a
    %Keithley2000 Instrument object already created elsewhere)
    %cmd.Instrument = k; cmd.Command = "SetSourceLevel(2.1,true)";

    %% Properties (Constant, Private)
    properties(Constant, Access = private)
        ArgumentNames = ["a", "b", "c", "d", "e", "f", "g", "h,", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"];
        InstName = "inst";
    end

    %% Properties (Public)
    properties
        %Will print verbose messages if this is set to true
        DebugMode = false;
    end

    %% Properties (Private)
    properties(Access = private)
        CachedCommands = [];
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

        function CacheCommand(this, instrument, command)
             arguments
                this;
                instrument (1,1) Palladium.Core.Instrument;
                command {mustBeTextScalar};
             end

             newCommand.Instrument = instrument;
             newCommand.Command = command;

            this.CachedCommands = [this.CachedCommands, newCommand];
        end

        function ExecuteCommand(this, commandStruct)

            %Get the function and a packaged struct of its arguments
            [fnHandle, args] = this.AssembleFunctionHandle(commandStruct.Command);

            %Execute the function on the Instrument stored in the command
            %struct
            if isempty(args)
                fnHandle(commandStruct.Instrument);
            else
                fnHandle(commandStruct.Instrument, args);
            end
        end

        function command = PullCachedCommand(this)
            %Return a list of commands to be executed this tick, and clear
            %them from the heap

            if isempty(this.CachedCommands)
                command = [];
                return;
            end

           command = this.CachedCommands(1);

           %Delete from heap - first in first out
           this.CachedCommands(1) = [];
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function [fnHandle, args] = AssembleFunctionHandle(this, commandStr)

            %Remove any semicolon that might be on there
            cmd = erase(commandStr, ";");

            %Remove any whitespace
            cmd = erase(cmd, " ");

            %If string does not end in (), maybe it was something like
            %Instrument.Connect - which doesn't technically need them.
            %Check for a missing ) at the end, and if not found assume this
            %is the case. Add a () on - we will need it in the next step
            if ~endsWith(cmd, ")")
                cmd = cmd + "()";
            end

            %Get array of string of the argument names (they will have been
            %passed in as (2, 4.5, "Holly"), we just want to count them and
            %replace with (a,b,c) to construct our function call
            [argumentNames, args] = this.GetListOfArgumentNamesFromFunctionString(cmd);

            inputArgsStr = this.ConstructInputArgumentsString(argumentNames);
            if isempty(args)%Case for functions with no arguments, like Connect();
                inputValuesStr = this.InstName;
            else
                inputValuesStr = this.InstName + "," + "args";
            end
            cmd = this.InsertArgumentsStr(cmd, inputArgsStr);

            str = "@" + "(" + inputValuesStr + ")" + cmd;

            if this.DebugMode
                disp("Function to Execute:");
                disp(str);
                disp(" ");
                disp("With arguments:");
                disp(args);
                disp(" ");
            end
            fnHandle = str2func(str);
        end

        function str = ConstructInputArgumentsString(this, arrayOfArgNames)
            str = this.InstName;

            for i = 1 : length(arrayOfArgNames)
                str = str + "," + "args." + arrayOfArgNames(i);
            end
        end

        function outVal = ConvertArgumentType(this, arg)
            if arg == "true"
                outVal = true;
                return;
            end
            if arg == "false"
                outVal = false;
                return;
            end
            if ~isnan(double(arg))
                outVal = double(arg);
                return;
            end

            %We got to here, guess we're sticking with a string
            outVal = arg;
        end

        function [argumentFieldNames, argsStruct] = GetListOfArgumentNamesFromFunctionString(this, commandStr)
            argStr = extractBetween(commandStr, '(', ')');
            argumentFieldNames = strings(0);
            argsStruct = [];

            if argStr == ""
                return;
            end

            givenArguments = strsplit(argStr, ',');

            argumentFieldNames = strings(length(givenArguments), 1); % Initialize with correct dimensions

            for i = 1 : length(givenArguments)
                argumentFieldNames(i) = this.ArgumentNames(i); % Assign argument names (just use a,b,c..)
                argsStruct.(this.ArgumentNames(i)) = this.ConvertArgumentType(givenArguments(i));
            end
        end

        function str = InsertArgumentsStr(~, commandStr, argStr)
            deletedArgStr = eraseBetween(commandStr, '(', ')');
            str = replaceBetween(deletedArgStr, '(', ')', argStr);
        end

    end

end