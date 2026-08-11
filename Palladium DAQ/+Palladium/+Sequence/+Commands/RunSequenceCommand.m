classdef RunSequenceCommand < Palladium.Sequence.Commands.Command
    %WAITCOMMAND 

    %% Properties (Public)
    properties(Access = public)
        SequencePath;
    end

    %% Properties (Private)
    properties (Access = private)
    end    

    %% Constructor
    methods
        function this = RunSequenceCommand(sequencePath, Settings)
            arguments
                sequencePath string;
                Settings.FunctionOnComplete = [];
            end
            
            this.FunctionOnComplete = Settings.FunctionOnComplete;

            this.SequencePath = sequencePath;
        end
    end

    %% Methods (Public)
    methods(Access = public)

    end
end