classdef test_ScanController < matlab.unittest.TestCase
    % TEST_SCANCONTROLLER Tests for starting a scan with
    % Palladium.Instruments.Controls.ScanController. It is attached to a
    % fake GUI (InstrumentTestingInstruments.FakeScanView) and a stub
    % Instrument rather than the real ones, so only what happens before the
    % scan reaches the hardware is covered here: checking the sweep file name.

    %% Properties
    properties
        TestingDir = fullfile("..", "..", "data", "Instrument Testing");
        TempDir;
        Controller;
        View;
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)

        function PathSetup(testCase)
            import matlab.unittest.fixtures.PathFixture
            %Test helpers, which keep everything the tests write inside Testing Data Files
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "..", "..", "Helpers")));
            testCase.applyFixture(PathFixture(testCase.TestingDir, IncludeSubfolders=true));
        end

    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)

        function CreateControllerWithFakeViewAndInstrument(testCase)
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            testCase.TempDir = string(fixture.Folder);

            instrument = InstrumentTestingInstruments.StubInstrument();
            instrument.FileWriteDetails = struct( ...
                "Directory", testCase.TempDir, ...
                "FileName", "run", ...
                "FileExtension", ".dat", ...
                "DescriptionText", "A description", ...
                "WriteMode", "Increment File No.", ...
                "SaveFile", true);

            testCase.View = InstrumentTestingInstruments.FakeScanView();
            testCase.Controller = InstrumentTestingInstruments.TestableScanController();
            testCase.Controller.AttachForTest(testCase.View, instrument);
        end

    end

    %% Tests
    methods (Test)

        %% Run pressed with no sweep file name
        function test_RunPushed_EmptyFileNameWhileSavingErrorsTest(testCase)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", "");

            testCase.verifyError(@() testCase.Controller.PressRunForTest(), "InitialiseDataWriterError:EmptyFileNameSuffix");
        end

        function test_RunPushed_EmptyFileNameLeavesTheScanNotRunningTest(testCase)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", "");

            try
                testCase.Controller.PressRunForTest();
            catch
            end

            testCase.verifyFalse(testCase.Controller.Running);
            testCase.verifyEqual(testCase.Controller.TimeElapsed_s, 0);
        end

        function test_RunPushed_EmptyFileNamePutsTheGUIBackToReadyTest(testCase)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", "");

            try
                testCase.Controller.PressRunForTest();
            catch
            end

            testCase.verifyFalse(testCase.View.Running, "Run button must be usable again");
            testCase.verifyEqual(testCase.View.ReadyCount, 1);
        end

        function test_RunPushed_EmptyFileNameWritesNoFileTest(testCase)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", "   ");

            try
                testCase.Controller.PressRunForTest();
            catch
            end

            filesCreated = setdiff(string({dir(testCase.TempDir).name}), [".", ".."]);
            testCase.verifyEmpty(filesCreated, "Nothing may be written, least of all to the main data file's name");
        end

        function test_RunPushed_CanBeRunAgainAfterAnEmptyFileNameWasRejectedTest(testCase)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", "");
            try
                testCase.Controller.PressRunForTest();
            catch
            end

            %Second attempt with a name set again gets as far as the same
            %check, and passes it (it then stops at the stub Instrument,
            %which has no scan to run)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", " - Sweep File");

            err = testCase.errorFrom(@() testCase.Controller.PressRunForTest());

            testCase.verifyNotEqual(string(err.identifier), "InitialiseDataWriterError:EmptyFileNameSuffix");
        end


        %% Run and Abort, for sequences and scripts
        function test_Run_GoesThroughThePanelLikeTheRunButtonTest(testCase)
            testCase.verifyError(@() testCase.Controller.Run(), "ScanController:ScanNotStarted");

            testCase.verifyEqual(testCase.View.RunCount, 1, "The panel's own Run was used, with its checks");
        end

        function test_Run_ErrorsWhenThePanelDoesNotStartAScanTest(testCase)
            %E.g. the panel refused an empty sweep name: a sequence must not carry on as if a scan had been made
            testCase.View.RunAction = [];

            err = testCase.errorFrom(@() testCase.Controller.Run());

            testCase.verifyEqual(string(err.identifier), "ScanController:ScanNotStarted");
            testCase.verifyFalse(testCase.Controller.Running);
        end

        function test_Abort_WithNoScanRunningDoesNothingTest(testCase)
            testCase.Controller.Abort();

            testCase.verifyEqual(testCase.View.AbortCount, 0);
        end

        function test_SettersGoThroughThePanelTest(testCase)
            testCase.Controller.SetSweepName("T_300K");
            testCase.Controller.SetSaveSweepFile(false);
            testCase.Controller.SetContinuous(true);

            testCase.verifyEqual(testCase.View.SweepName, "T_300K");
            testCase.verifyFalse(testCase.View.SaveToFile);
            testCase.verifyTrue(testCase.View.Continuous);
        end

        function test_RunIsACommandThatWaitsForTheScanTest(testCase)
            %A sequence calls Run and waits until the scan has been saved or aborted
            testCase.verifyNotEmpty(testCase.Controller.GetCommandCompleteFn("Run()"));
            testCase.verifyEmpty(testCase.Controller.GetCommandCompleteFn("ScanRun"), "The event handler is not a command any more");
            testCase.verifyEmpty(testCase.Controller.GetCommandCompleteFn("Abort()"));
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function err = errorFrom(~, fcn)
            err = MException("test:NoError", "No error was thrown");
            try
                fcn();
            catch caught
                err = caught;
            end
        end

    end

end
