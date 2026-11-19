classdef FakeProgressController < handle
    %FakeProgressController - Stand-in for the Controller's progress bar calls, recording them.

    %% Properties (Public)
    properties (Access = public)
        Shown = false;          %True while a bar is shown
        ShownCount = 0;         %How many times one was shown
        Message = "";           %The last message shown
        Title = "";             %The last title shown
        Closed = false;         %True once a bar has been closed
        LastProgress = [];      %The last UpdateProgress fraction
    end

    %% Methods (Public)
    methods (Access = public)
        function ShowProgress(this, message, title)
            this.Shown = true;
            this.ShownCount = this.ShownCount + 1;
            this.Message = message;
            this.Title = title;
        end

        function UpdateProgress(this, progress, message)
            this.LastProgress = progress;
            this.Message = message;
        end

        function CloseProgress(this)
            this.Shown = false;
            this.Closed = true;
        end
    end
end
