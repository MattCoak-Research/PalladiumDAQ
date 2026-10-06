classdef MockErrorController < handle
    %MOCKERRORCONTROLLER - Stand-in for Palladium.Core.Controller in
    %ErrorGuard tests. Just records what HandleCallbackError was called with.

    properties
        Contexts = strings(0,1);
        Errors = {};
        Standalone = false(0,1);
        Figures = {};
    end

    methods
        function HandleCallbackError(this, context, err, Settings)
            arguments
                this;
                context;
                err;
                Settings.Standalone (1,1) logical = false;
                Settings.Figure = [];
            end
            this.Contexts(end+1,1) = string(context);
            this.Standalone(end+1,1) = Settings.Standalone;
            this.Figures{end+1} = Settings.Figure;
            this.Errors{end+1} = err;
        end
    end
end
