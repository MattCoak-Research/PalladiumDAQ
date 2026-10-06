classdef MockErrorController < handle
    %MOCKERRORCONTROLLER - Stand-in for Palladium.Core.Controller in
    %ErrorGuard tests. Just records what HandleCallbackError was called with.

    properties
        Contexts = strings(0,1);
        Errors = {};
    end

    methods
        function HandleCallbackError(this, context, err)
            this.Contexts(end+1,1) = string(context);
            this.Errors{end+1} = err;
        end
    end
end
