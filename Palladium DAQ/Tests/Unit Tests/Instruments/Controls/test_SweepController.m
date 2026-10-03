classdef test_SweepController < matlab.unittest.TestCase
    % TEST_SWEEPCONTROLLER Tests for the logic in the SweepController base
    % class that doesn't need a GUI, using
    % InstrumentTestingInstruments.StubSweepController (in the data folder)
    % in place of a real sweep.

    %% Properties
    properties
        TestingDir = fullfile("..", "..", "data", "Instrument Testing");
        Controller;
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)

        function PathSetup(testCase)
            import matlab.unittest.fixtures.PathFixture
            testCase.applyFixture(PathFixture(testCase.TestingDir, IncludeSubfolders=true));
        end

    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)

        function CreateController(testCase)
            testCase.Controller = InstrumentTestingInstruments.StubSweepController();
        end

    end

    %% Tests
    methods (Test)

        %% SweepRun
        function test_SweepRun_StartsRunningTest(testCase)
            testCase.Controller.SweepRun();

            testCase.verifyTrue(testCase.Controller.Running);
            testCase.verifyEqual(testCase.Controller.SetupCount, 1);
            testCase.verifyEqual(testCase.Controller.AbortCount, 0);
        end

        function test_SweepRun_FailedSetupRethrowsTheOriginalErrorTest(testCase)
            testCase.Controller.ThrowOnSetup = true;

            testCase.verifyError(@() testCase.Controller.SweepRun(), "StubSweepController:SetupFailed");
        end

        function test_SweepRun_FailedSetupLeavesTheSweepNotRunningTest(testCase)
            %A sweep that couldn't be set up (eg no file to save to) must
            %not carry on stepping the instrument
            testCase.Controller.ThrowOnSetup = true;

            try
                testCase.Controller.SweepRun();
            catch
            end

            testCase.verifyFalse(testCase.Controller.Running);
            testCase.verifyTrue(testCase.Controller.IsComplete());
            testCase.verifyFalse(testCase.Controller.IsBusy());
            testCase.verifyEqual(testCase.Controller.TimeElapsed_s, 0);
        end

        function test_SweepRun_FailedSetupAbortsTheSweepOnceTest(testCase)
            %So the GUI is put back to ready
            testCase.Controller.ThrowOnSetup = true;

            try
                testCase.Controller.SweepRun();
            catch
            end

            testCase.verifyEqual(testCase.Controller.AbortCount, 1);
        end

        function test_SweepRun_FailedSetupWithFailingAbortStillReportsTheOriginalErrorTest(testCase)
            testCase.Controller.ThrowOnSetup = true;
            testCase.Controller.AbortThrows = true;

            testCase.verifyError(@() testCase.Controller.SweepRun(), "StubSweepController:SetupFailed");
            testCase.verifyFalse(testCase.Controller.Running, "Must not be left running even if the abort fails");
        end

        function test_SweepRun_CanBeRunAgainAfterAFailedSetupTest(testCase)
            testCase.Controller.ThrowOnSetup = true;
            try
                testCase.Controller.SweepRun();
            catch
            end

            testCase.Controller.ThrowOnSetup = false;
            testCase.Controller.SweepRun();

            testCase.verifyTrue(testCase.Controller.Running);
        end

        %% SweepAbort and SweepComplete
        function test_SweepAbort_StopsRunningTest(testCase)
            testCase.Controller.SweepRun();

            testCase.Controller.SweepAbort();

            testCase.verifyFalse(testCase.Controller.Running);
            testCase.verifyEqual(testCase.Controller.AbortCount, 1);
        end

        function test_IsBusyAndIsComplete_FollowRunningTest(testCase)
            testCase.verifyFalse(testCase.Controller.IsBusy());
            testCase.verifyTrue(testCase.Controller.IsComplete());

            testCase.Controller.SweepRun();

            testCase.verifyTrue(testCase.Controller.IsBusy());
            testCase.verifyFalse(testCase.Controller.IsComplete());
        end

        %% Static helpers
        function test_GenerateSweepPoints_ByStepTest(testCase)
            points = Palladium.Instruments.Controls.SweepController.GenerateSweepPoints(0, 1, 0.25, []);

            testCase.verifyEqual(points, [0 0.25 0.5 0.75 1]);
        end

        function test_GenerateSweepPoints_ByNumberOfStepsTest(testCase)
            points = Palladium.Instruments.Controls.SweepController.GenerateSweepPoints(1, 0, 0, 3);

            testCase.verifyEqual(points, [1 0.5 0]);
        end

        function test_CalculatePoints_JoinsSegmentsWithoutDuplicatingEndpointsTest(testCase)
            points = Palladium.Instruments.Controls.SweepController.CalculatePoints([0 1 0], 0.5);

            testCase.verifyEqual(points, [0 0.5 1 0.5 0]);
        end

        function test_TrimExtremalPoints_RemovesDuplicatesAndPointsOnTheWayTest(testCase)
            trimmed = Palladium.Instruments.Controls.SweepController.TrimExtremalPoints([0 0 1 2 1 0]);

            testCase.verifyEqual(trimmed, [0 2 0]);
        end

        function test_CalculateTotalMagnitude_SumsAbsoluteChangesTest(testCase)
            total = Palladium.Instruments.Controls.SweepController.CalculateTotalMagnitude([0 2 -1]);

            testCase.verifyEqual(total, 5);
        end

    end

end
