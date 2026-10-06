classdef ErrorGuard
    %ErrorGuard - Static utility for catching errors thrown in event listeners and GUI callbacks.
    %MATLAB converts any error that escapes an event listener or UI
    %callback into an orange warning, and never rethrows it to the code that
    %fired the event. So a try-catch around `notify()` or `drawnow()` cannot
    %see it, and (when fired during the measurement loop) it bypasses all of
    %the programme's error handling. The only fix is a try-catch inside the
    %callback itself, which is what this class adds.
    %
    %Caught errors are routed to `Controller.HandleCallbackError`: logged,
    %shown in the normal error dialogue, and the measurement loop is stopped
    %if the user chooses to.
    %
    %Three ways to use it:
    %
    %* `AddListener` - drop-in replacement for `addlistener`, for any listener.
    %* `Wrap` - guard a function handle, e.g. one assigned to a UI component's callback property.
    %* `HandleError` - one-line hook for the `catch` block of an App Designer callback.

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function ltr = AddListener(src, eventName, callback, Settings)
            %Add an event listener whose errors are caught and handled, as a drop-in for `addlistener`.
            %Returns the listener handle exactly as `addlistener` does, so it
            %can be passed on to `RegisterEventListener` as usual.
            %
            %Inputs:
            %   src - the object that fires the event
            %   eventName - name of the event to listen for
            %   callback - function handle to call when the event fires
            %
            %Optional name-value arguments:
            %   Controller - the Controller to report errors to. Empty (the default) uses the one registered with `DefaultController`
            %   Context - text shown in the error log and dialogue. Defaults to naming the event
            %
            %Outputs:
            %   ltr - the listener handle
            arguments
                src;
                eventName {mustBeTextScalar};
                callback (1,1) function_handle;
                Settings.Controller = [];
                Settings.Context {mustBeTextScalar} = "";
            end

            context = string(Settings.Context);
            if strlength(context) == 0
                context = "Error in " + string(eventName) + " event handler";
            end

            guarded = Palladium.Core.ErrorGuard.Wrap(callback, Controller = Settings.Controller, Context = context);
            ltr = addlistener(src, eventName, guarded);
        end

        function controller = DefaultController(newController)
            %Get or set the Controller that errors are sent to when the caller has no reference to one.
            %Inside most of the `.mlapp` GUI components there is no
            %Controller handle, so errors go here. The Controller registers
            %itself on construction. With several Controllers alive (e.g. in
            %unit tests) the most recent one wins.
            %
            %Inputs:
            %   newController - (optional) the Controller to register. Leave out to just read the current one
            %
            %Outputs:
            %   controller - the currently registered Controller, or empty if there is none
            persistent registered;
            if nargin > 0
                registered = newController;
            end
            controller = registered;
        end

        function HandleError(context, err)
            %Report an error caught in a GUI callback, for use in its `catch` block.
            %Needs no Controller handle, so it reads the same in any
            %component:
            %
            %   catch err
            %       Palladium.Core.ErrorGuard.HandleError("Error in X", err);
            %   end
            %
            %The error goes to the default Controller's error handling (log
            %and error dialogue), or is just logged if there isn't one.
            %
            %Inputs:
            %   context - text describing where the error happened, shown in the log and dialogue
            %   err - the caught `MException`
            arguments
                context {mustBeTextScalar};
                err;
            end

            Palladium.Core.ErrorGuard.Report([], string(context), err);
        end

        function guarded = Wrap(callback, Settings)
            %Wrap a function handle so that any error it throws is caught and handled.
            %The returned handle calls `callback` with whatever arguments it
            %is given. If that throws, the error is reported to the
            %Controller instead of MATLAB turning it into a warning. The
            %guard itself never throws.
            %
            %Inputs:
            %   callback - function handle to guard
            %
            %Optional name-value arguments:
            %   Controller - the Controller to report errors to. Empty (the default) uses the one registered with `DefaultController`
            %   Context - text shown in the error log and dialogue
            %
            %Outputs:
            %   guarded - function handle accepting any arguments
            arguments
                callback (1,1) function_handle;
                Settings.Controller = [];
                Settings.Context {mustBeTextScalar} = "Error in callback";
            end

            controller = Settings.Controller;
            context = string(Settings.Context);
            guarded = @GuardedCallback;

            function GuardedCallback(varargin)
                try
                    callback(varargin{:});
                catch err
                    Palladium.Core.ErrorGuard.Report(controller, context, err);
                end
            end
        end

    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function Report(controller, context, err)
            %Hand an error to the Controller if there is a live one, otherwise log it. Never throws.
            %An empty `controller` means the default one registered with
            %`DefaultController`. If there is no live Controller at all,
            %the error is logged with the `Logger` instead.
            try
                if isempty(controller)
                    controller = Palladium.Core.ErrorGuard.DefaultController();
                end

                if ~isempty(controller) && isvalid(controller)
                    controller.HandleCallbackError(context, err);
                else
                    Palladium.Logging.Logger.LogError(err, context);
                end
            catch e
                warning("ErrorGuardWarning:ReportFailed", "%s", "Could not report an error from a callback (" + context + "): " + string(e.message) + ". Original error: " + string(err.message));
            end
        end

    end
end
