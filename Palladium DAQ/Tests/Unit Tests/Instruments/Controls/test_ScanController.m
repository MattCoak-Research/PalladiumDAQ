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

        %% ScanRun with no sweep file name
        function test_ScanRun_EmptyFileNameWhileSavingErrorsTest(testCase)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", "");

            testCase.verifyError(@() testCase.Controller.ScanRun(), "InitialiseDataWriterError:EmptyFileNameSuffix");
        end

        function test_ScanRun_EmptyFileNameLeavesTheScanNotRunningTest(testCase)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", "");

            try
                testCase.Controller.ScanRun();
            catch
            end

            testCase.verifyFalse(testCase.Controller.Running);
            testCase.verifyEqual(testCase.Controller.TimeElapsed_s, 0);
        end

        function test_ScanRun_EmptyFileNamePutsTheGUIBackToReadyTest(testCase)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", "");

            try
                testCase.Controller.ScanRun();
            catch
            end

            testCase.verifyFalse(testCase.View.Running, "Run button must be usable again");
            testCase.verifyEqual(testCase.View.ReadyCount, 1);
        end

        function test_ScanRun_EmptyFileNameWritesNoFileTest(testCase)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", "   ");

            try
                testCase.Controller.ScanRun();
            catch
            end

            filesCreated = setdiff(string({dir(testCase.TempDir).name}), [".", ".."]);
            testCase.verifyEmpty(filesCreated, "Nothing may be written, least of all to the main data file's name");
        end

        function test_ScanRun_CanBeRunAgainAfterAnEmptyFileNameWasRejectedTest(testCase)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", "");
            try
                testCase.Controller.ScanRun();
            catch
            end

            %Second attempt with a name set again gets as far as the same
            %check, and passes it (it then stops at the stub Instrument,
            %which has no scan to run)
            testCase.View.ScanDetails = struct("SaveSweepFile", true, "FileName", " - Sweep File");

            err = testCase.errorFrom(@() testCase.Controller.ScanRun());

            testCase.verifyNotEqual(string(err.identifier), "InitialiseDataWriterError:EmptyFileNameSuffix");
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
