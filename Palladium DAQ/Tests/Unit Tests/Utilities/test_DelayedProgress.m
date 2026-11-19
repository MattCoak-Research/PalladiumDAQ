classdef test_DelayedProgress < matlab.unittest.TestCase
    %TEST_DELAYEDPROGRESS Tests the progress bar that only appears if the work takes a moment

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function QuickWorkShowsNothingTest(testCase)
            controller = InstrumentTestingInstruments.FakeProgressController();

            progress = Palladium.Utilities.DelayedProgress(controller, "Working", Delay_s = 5);
            delete(progress);
            pause(0.1);

            testCase.verifyEqual(controller.ShownCount, 0);
            testCase.verifyFalse(controller.Closed, "Nothing to close");
        end

        function SlowWorkShowsTheBarThenClosesItTest(testCase)
            controller = InstrumentTestingInstruments.FakeProgressController();

            progress = Palladium.Utilities.DelayedProgress(controller, "Working on it", Title = "Scan", Delay_s = 0.1);
            testCase.addTeardown(@() delete(progress(isvalid(progress))));
            testCase.verifyFalse(controller.Shown, "Not at once");
            pause(0.5);

            testCase.verifyTrue(controller.Shown, "Shown while the work goes on");
            testCase.verifyEqual(controller.Message, "Working on it");
            testCase.verifyEqual(controller.Title, "Scan");

            progress.Update(0.5, "Half way");
            testCase.verifyEqual(controller.LastProgress, 0.5);

            delete(progress);

            testCase.verifyFalse(controller.Shown);
            testCase.verifyTrue(controller.Closed);
        end

        function NoControllerDoesNothingTest(testCase)
            progress = Palladium.Utilities.DelayedProgress([], "Working", Delay_s = 0.05);
            pause(0.2);
            progress.Update(0.5, "x");
            testCase.verifyWarningFree(@() delete(progress));
        end
    end
end
