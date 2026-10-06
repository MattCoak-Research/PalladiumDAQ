classdef test_ErrorGuard < matlab.unittest.TestCase
    % TEST_ERRORGUARD Tests for Palladium.Core.ErrorGuard - errors thrown in
    % event listeners must reach the Controller's error handling, rather
    % than MATLAB turning them into warnings.

    %% Methods (Private)
    methods (Access = private)
        function silenceWarnings(testCase)
            %The Logger warns about its own setup when used without a
            %Controller, which is not of interest to these tests
            state = warning("off", "all");
            testCase.addTeardown(@() warning(state));
        end
    end

    %% Tests
    methods (Test)

        function WrapPassesArgumentsThrough(testCase)
            ctrl = MockErrorController();
            received = {};
            guarded = Palladium.Core.ErrorGuard.Wrap(@(varargin) store(varargin{:}), Controller = ctrl);
            guarded(1, "two");

            testCase.verifyEqual(received, {1, "two"});
            testCase.verifyEmpty(ctrl.Contexts);

            function store(varargin)
                received = varargin;
            end
        end

        function WrapRoutesErrorToController(testCase)
            ctrl = MockErrorController();
            guarded = Palladium.Core.ErrorGuard.Wrap(@(~,~) error("Test:Boom", "boom"), Controller = ctrl, Context = "My context");

            testCase.verifyWarningFree(@() guarded(1, 2));
            testCase.verifyEqual(ctrl.Contexts, "My context");
            testCase.verifyEqual(string(ctrl.Errors{1}.identifier), "Test:Boom");
        end

        function ListenerErrorReachesControllerThroughNotify(testCase)
            ctrl = MockErrorController();
            src = ErrorGuardTestSource();
            ltr = Palladium.Core.ErrorGuard.AddListener(src, "Fired", @(~,~) error("Test:Boom", "boom"), Controller = ctrl, Context = "Listener failed");
            testCase.addTeardown(@() delete(ltr));

            testCase.verifyWarningFree(@() notify(src, "Fired"));
            testCase.verifyEqual(ctrl.Contexts, "Listener failed");
        end

        function HandleErrorUsesDefaultController(testCase)
            ctrl = MockErrorController();
            previous = Palladium.Core.ErrorGuard.DefaultController();
            Palladium.Core.ErrorGuard.DefaultController(ctrl);
            testCase.addTeardown(@() Palladium.Core.ErrorGuard.DefaultController(previous));

            Palladium.Core.ErrorGuard.HandleError("From a GUI callback", MException("Test:Boom", "boom"));

            testCase.verifyEqual(ctrl.Contexts, "From a GUI callback");
        end

        function WithoutControllerFallsBackToLogger(testCase)
            guarded = Palladium.Core.ErrorGuard.Wrap(@(~) error("Test:Boom", "boom"));

            %Must not throw, even with nowhere to report to
            testCase.silenceWarnings();
            guarded(1);   %Must not throw, even with nowhere to report to
            testCase.verifyTrue(true);
        end

        function DeletedControllerFallsBackToLogger(testCase)
            ctrl = MockErrorController();
            guarded = Palladium.Core.ErrorGuard.Wrap(@(~) error("Test:Boom", "boom"), Controller = ctrl);
            delete(ctrl);

            testCase.silenceWarnings();
            guarded(1);   %Must not throw, even with nowhere to report to
            testCase.verifyTrue(true);
        end

    end
end
