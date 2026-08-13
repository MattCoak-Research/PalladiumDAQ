classdef WaitCommand < Palladium.Sequence.Commands.Command
    %WAITCOMMAND 

    %% Properties (Public)
    properties(Access = public)
        Wait_seconds;
        WaitDisplayUnit = "sec";
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
                Settings.WaitDisplayUnits;
            end
            
            this.FunctionOnComplete = Settings.FunctionOnComplete;

            this.Wait_seconds = wait_Seconds;
            this.WaitDisplayUnit = string(Settings.WaitDisplayUnits);

            this.IsCompleteFn = @this.CheckComplete;
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function isComplete = CheckComplete(this)
            if isempty(this.Timer)
                isComplete = false;
                return;
            end

            elapsed = toc(this.Timer);

            isComplete = elapsed >= this.Wait_seconds;
        end

        function str = GetDurationString(this)
            str = num2str(this.Wait_seconds) + " seconds";
        end

        function Start(this)
            this.Timer = tic;  
        end
    end
end