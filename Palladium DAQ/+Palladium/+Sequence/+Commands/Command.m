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

    end
end