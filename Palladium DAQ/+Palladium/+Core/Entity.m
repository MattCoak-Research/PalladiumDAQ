classdef(Abstract) Entity < handle
    %Entity - Abstract base class shared by Instrument and InstrumentControlBase.
    %Every instrument driver and Instrument Control is therefore an Entity,
    %which lets them tell a sequence when a command has finished.
    %
    %A sequence's InstrumentCommand calls a method of an instrument or
    %control, e.g. `SetTemperature(300)`. By default the command counts as
    %done straight away. For commands that take time, such as a PPMS
    %reaching a temperature or a sweep finishing, the class calls
    %`RegisterCommandCompleteQuery` in its constructor with a function that
    %reports when it is done. The InstrumentCommand gets that function with
    %`GetCommandCompleteFn`, and the CommandController calls it each tick
    %until it returns true before running the next command.

    %% Properties (Private)
    properties(Access = private)
        RegisteredCommandCompleteQueryStructs = [];     %Struct array of the registered queries: CommandFunctionName and FnHandle
    end

    %% Methods (Public, Sealed)
    methods (Access = public, Sealed)

        function commandCompleteFn = GetCommandCompleteFn(this, commandStr)
            %Get the function that reports when a sequence command has finished, if one is registered.
            %Called by InstrumentCommand. Looks up the method name of
            %commandStr among those registered with
            %RegisterCommandCompleteQuery. The name is read exactly as when
            %the command is run (CommandController.ParseMethodName), so
            %"SweepRun", "SweepRun()" and "SetField (1, 100);" all match
            %
            %Inputs:
            %   commandStr - the command, e.g. "SetTemperature(300, 10)"
            %
            %Outputs:
            %   commandCompleteFn - its function handle, or [] if none is
            %                       registered, meaning the command
            %                       completes immediately

            commandCompleteFn = [];

            if isempty(this.RegisteredCommandCompleteQueryStructs)
                return;
            end

            %Just the method name, without the arguments
            methodName = Palladium.Core.CommandController.ParseMethodName(commandStr);

            for i = 1 : length(this.RegisteredCommandCompleteQueryStructs)
                s = this.RegisteredCommandCompleteQueryStructs(i);

                if strcmp(s.CommandFunctionName, methodName)
                    commandCompleteFn = s.FnHandle;
                    return;
                end
            end

        end

        function RegisterCommandCompleteQuery(this, commandFunctionName, fnHandle)
            %Register a function that tells a sequence when a command has finished - call in the constructor.
            %Without one, a sequence treats the command as done as soon as
            %it returns; with one, it waits, calling fnHandle each tick.
            %For example, PPMS registers IsTemperatureStable for
            %SetTemperature
            %
            %Inputs:
            %   commandFunctionName - name of the method the sequence calls,
            %                         e.g. "SetTemperature"
            %   fnHandle            - function handle taking no arguments and
            %                         returning true once the command has
            %                         finished, e.g. @this.IsTemperatureStable

            s.CommandFunctionName = commandFunctionName;
            s.FnHandle = fnHandle;

            if isempty(this.RegisteredCommandCompleteQueryStructs)
                this.RegisteredCommandCompleteQueryStructs = s;
            else
                this.RegisteredCommandCompleteQueryStructs = [this.RegisteredCommandCompleteQueryStructs, s];
            end
        end

    end
end
