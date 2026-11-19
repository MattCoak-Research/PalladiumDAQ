classdef DelayedProgress < handle
    %DelayedProgress - Palladium's progress bar, shown only if the work takes longer than a moment, and closed when this object is deleted.
    %For something that is usually quick but can be slow (e.g. setting up
    %an analyser): a bar that flashed up every time would be a nuisance.
    %Create it before the work, and delete it (or let it go out of scope, or
    %use an onCleanup) after:
    %
    %```matlab
    %progress = Palladium.Utilities.DelayedProgress(controller, "Setting up...");
    %cleanup = onCleanup(@() delete(progress));
    %```
    %
    %The bar is the Controller's (ShowProgress and CloseProgress), which is
    %modal, so it also stops clicks reaching the window behind while the
    %work goes on. It is shown by a timer, which runs while the work waits
    %(e.g. in a pause) - work that never lets MATLAB process events
    %won't show it. With no Controller (e.g. in tests), nothing is shown.

    %% Properties (Private)
    properties (Access = private)
        Controller = [];        %The Palladium.Core.Controller to show the bar with, or empty for none
        Timer = [];             %The timer that shows the bar after the delay
        Message = "";           %The bar's message
        Title = "";             %Its title
        Shown = false;          %True once the bar has been shown
    end

    %% Constructor
    methods
        function this = DelayedProgress(controller, message, Settings)
            %Start the clock: the bar is shown after Delay_s if this object has not been deleted by then.
            %
            %Inputs:
            %   controller - the Palladium.Core.Controller, or [] for none
            %   message    - the message in the bar
            %   Title      - (name-value) the bar's title. Default "Please wait"
            %   Delay_s    - (name-value) how long the work may take before the bar appears. Default 1

            arguments
                controller;
                message {mustBeTextScalar};
                Settings.Title {mustBeTextScalar} = "Please wait";
                Settings.Delay_s (1,1) double {mustBeNonnegative} = 1;
            end

            this.Message = string(message);
            this.Title = string(Settings.Title);
            if isempty(controller) || ~isvalid(controller)
                return;
            end

            this.Controller = controller;
            this.Timer = timer("StartDelay", Settings.Delay_s, "ExecutionMode", "singleShot", "TimerFcn", @(~, ~) this.Show());
            start(this.Timer);
        end

        function delete(this)
            %Stop the clock, and close the bar if it was shown.

            if ~isempty(this.Timer)
                try
                    stop(this.Timer);
                    delete(this.Timer);
                catch
                    %Nothing more can be done
                end
                this.Timer = [];
            end
            if this.Shown && ~isempty(this.Controller) && isvalid(this.Controller)
                try
                    this.Controller.CloseProgress();
                catch
                    %Nothing more can be done
                end
            end
            this.Shown = false;
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function Update(this, fraction, message)
            %Move the bar on, if it is being shown.
            %
            %Inputs:
            %   fraction - how much is done, 0 to 1
            %   message  - the message to show

            if this.Shown
                this.Controller.UpdateProgress(fraction, message);
            end
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function Show(this)
            %Show the bar - called by the timer when the delay is up.

            try
                if ~this.Shown && ~isempty(this.Controller) && isvalid(this.Controller)
                    this.Controller.ShowProgress(this.Message, this.Title);
                    this.Shown = true;
                end
            catch err
                Palladium.Logging.Logger.Log("Warning", "Could not show the progress bar: " + string(err.message));
            end
        end

    end
end
