classdef Command < handle
    %COMMAND 

    %% Properties (Public)
    properties(Access = public)
        IsCompleteFn = [];  %If left blank, command will be assumed to have completed instantly. Overide to make the controller check each tick instead
        FunctionOnComplete = [];
    end

    %% Constructor
    methods
        function this = Command()
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function Abort(this)
            %Doesn't do anything, override for functionality.
            %Only a command currently being executed will get this called,
            %not every command queued up in a Sequence
        end

    end
end