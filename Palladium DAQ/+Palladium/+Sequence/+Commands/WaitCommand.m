classdef WaitCommand < Palladium.Sequence.Commands.Command
    %WAITCOMMAND 

    %% Properties (Public)
    properties(Access = public)
        Wait_seconds;
    end

    %% Properties (Private)
    properties (Access = private)
        Timer;
    end    

    %% Constructor
    methods
        function this = WaitCommand(wait_Seconds, Settings)
            arguments
                wait_Seconds (1,1) double {mustBePositive};
                Settings.FunctionOnComplete = [];
            end
            
            this.FunctionOnComplete = Settings.FunctionOnComplete;

            this.Wait_seconds = wait_Seconds;

            this.IsCompleteFn = @this.CheckComplete;
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function isComplete = CheckComplete(this)
            elapsed = toc(this.Timer);

            isComplete = elapsed >= this.Wait_seconds;
        end

        function Start(this)
            this.Timer = tic;  
        end
    end
end