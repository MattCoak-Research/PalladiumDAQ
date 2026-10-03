classdef test_InstrumentControlBase < matlab.unittest.TestCase
    % TEST_INSTRUMENTCONTROLBASE Tests for Palladium.Core.InstrumentControlBase.
    % It is Abstract, so InstrumentTestingInstruments.StubControl (in the
    % data folder) stands in, with test hooks onto its protected members.
    % So far this covers InitialiseDataWriter, which sets up the file a
    % sweep or scan writes its data to.

    %% Properties
    properties
        TestingDir = fullfile("..", "data", "Instrument Testing");
        TempDir;
        Instrument;
        Control;
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)

        function PathSetup(testCase)
            import matlab.unittest.fixtures.PathFixture
            %Test helpers, which keep everything the tests write inside Testing Data Files
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "..", "Helpers")));
            testCase.applyFixture(PathFixture(testCase.TestingDir, IncludeSubfolders=true));
        end

    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)

        function CreateInstrumentAndControl(testCase)
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            testCase.TempDir = string(fixture.Folder);

            %The Instrument holds the programme's overall file settings,
            %which a control builds its own file name from
            testCase.Instrument = InstrumentTestingInstruments.StubInstrument();
            testCase.Instrument.FileWriteDetails = struct( ...
                "Directory", testCase.TempDir, ...
                "FileName", "run", ...
                "FileExtension", ".dat", ...
                "DescriptionText", "A description", ...
                "WriteMode", "Overwrite File", ...
                "SaveFile", false);

            testCase.Control = InstrumentTestingInstruments.StubControl("Sweep");
            testCase.Control.SetInstrumentForTest(testCase.Instrument);
        end

    end

    %% Tests
    methods (Test)

        %% InitialiseDataWriter
        function test_InitialiseDataWriter_AppendsSuffixToOverallFileNameTest(testCase)
            writer = testCase.Control.InitialiseDataWriterForTest(" - Sweep File");

            testCase.verifyEqual(string(writer.FileWriteDetails.FileName), "run - Sweep File");
        end

        function test_InitialiseDataWriter_FileNameEndingInNumberIsNotChangedTest(testCase)
            %Regression: a "-" used to be added to any name ending in a
            %digit, to stop the old file numbering incrementing it
            testCase.Instrument.FileWriteDetails.FileName = "sample_T297";

            writer = testCase.Control.InitialiseDataWriterForTest(" - Sweep File");

            testCase.verifyEqual(string(writer.FileWriteDetails.FileName), "sample_T297 - Sweep File");
        end

        function test_InitialiseDataWriter_NumberedFileIsNamedAfterTheNumbersInTheNameTest(testCase)
            testCase.Instrument.FileWriteDetails.FileName = "sample_T297";
            writer = testCase.Control.InitialiseDataWriterForTest(" Sweep 2");

            newName = writer.ValidateFilePath();

            testCase.verifyEqual(newName, "sample_T297 Sweep 2-00001");
        end

        function test_InitialiseDataWriter_EmptyOverallFileNameDoesNotErrorTest(testCase)
            testCase.Instrument.FileWriteDetails.FileName = "";

            writer = testCase.Control.InitialiseDataWriterForTest(" - Sweep File");

            testCase.verifyEqual(string(writer.FileWriteDetails.FileName), " - Sweep File");
        end

        %% InitialiseDataWriter - empty sweep file name
        function test_InitialiseDataWriter_EmptySuffixErrorsTest(testCase)
            %An empty suffix would give the sweep file the same name as the
            %main data file, which is being written to at the same time
            for suffix = {"", '', [], string.empty, "   ", " ", sprintf("\t"), strings(1, 0)}
                testCase.verifyError(@() testCase.Control.InitialiseDataWriterForTest(suffix{1}), "InitialiseDataWriterError:EmptyFileNameSuffix");
            end
        end

        function test_InitialiseDataWriter_EmptySuffixErrorMessageExplainsTheProblemTest(testCase)
            try
                testCase.Control.InitialiseDataWriterForTest("");
            catch err
                testCase.verifySubstring(string(err.message), "same name as the main data file");
                return;
            end

            testCase.verifyFail("Expected an error for an empty suffix");
        end

        function test_InitialiseDataWriter_EmptySuffixIsAllowedWhenTheFileIsNotBeingSavedTest(testCase)
            %Nothing is written when saving is switched off, so there is no
            %clash with the main file
            writer = testCase.Control.InitialiseDataWriterForTest("", WriteToFile=false);

            testCase.verifyEqual(string(writer.FileWriteDetails.FileName), "run");
        end

        function test_InitialiseDataWriter_NonEmptySuffixIsFineWhetherOrNotSavingTest(testCase)
            testCase.verifyNotEmpty(testCase.Control.InitialiseDataWriterForTest(" x", WriteToFile=true));
            testCase.verifyNotEmpty(testCase.Control.InitialiseDataWriterForTest(" x", WriteToFile=false));
        end

        function test_InitialiseDataWriter_SuffixOfOnlyATagIsNotEmptyTest(testCase)
            testCase.Instrument.FullHeadersRow = "Temperature (K)";
            testCase.Instrument.LastFullDataRow = 4.2;

            writer = testCase.Control.InitialiseDataWriterForTest("[Temperature (K)]");

            testCase.verifyEqual(string(writer.FileWriteDetails.FileName), "run4p20");
        end

        function test_InitialiseDataWriter_EmptySuffixCannotTakeTheNextMainFileNumberTest(testCase)
            %When the overall name already ends in a counter ("run-00001"),
            %an empty suffix used to give a sweep file that claimed the next
            %counter, "run-00002", out from under the main file
            testCase.Instrument.FileWriteDetails.FileName = "run-00001";

            testCase.verifyError(@() testCase.Control.InitialiseDataWriterForTest(""), "InitialiseDataWriterError:EmptyFileNameSuffix");
        end

        function test_InitialiseDataWriter_FailedAttemptChangesNothingTest(testCase)
            before = testCase.Instrument.FileWriteDetails;

            try
                testCase.Control.InitialiseDataWriterForTest("");
            catch
            end

            testCase.verifyEqual(testCase.Instrument.FileWriteDetails, before);
            filesCreated = setdiff(string({dir(testCase.TempDir).name}), [".", ".."]);
            testCase.verifyEmpty(filesCreated, "No files should have been created");
        end

        function test_InitialiseDataWriter_AlwaysIncrementsFileNumberAndSavesTest(testCase)
            %Whatever the programme's own settings, a sweep file is a new
            %numbered file, and is saved
            writer = testCase.Control.InitialiseDataWriterForTest(" Sweep");

            testCase.verifyEqual(string(writer.FileWriteDetails.WriteMode), "Increment File No.");
            testCase.verifyTrue(writer.FileWriteDetails.SaveFile);
        end

        function test_InitialiseDataWriter_SuccessiveFilesGetSuccessiveNumbersTest(testCase)
            names = strings(1, 3);
            for i = 1 : 3
                writer = testCase.Control.InitialiseDataWriterForTest(" Sweep");
                names(i) = writer.ValidateFilePath();
                writer.WriteHeaders("a");
            end

            testCase.verifyEqual(names, ["run Sweep-00001" "run Sweep-00002" "run Sweep-00003"]);
        end

        function test_InitialiseDataWriter_LeavesTheInstrumentsOwnFileSettingsAloneTest(testCase)
            before = testCase.Instrument.FileWriteDetails;

            testCase.Control.InitialiseDataWriterForTest(" Sweep");

            testCase.verifyEqual(testCase.Instrument.FileWriteDetails, before);
        end

        function test_InitialiseDataWriter_ReplacesTaggedDataColumnsInFileNameTest(testCase)
            %Text in [] is replaced by that column's value from the last
            %measurement row, with the decimal point swapped for a "p"
            testCase.Instrument.FullHeadersRow = ["Time (s)", "Temperature (K)"];
            testCase.Instrument.LastFullDataRow = [10 4.2];
            testCase.Instrument.FileWriteDetails.FileName = "run";

            writer = testCase.Control.InitialiseDataWriterForTest(" at [Temperature (K)] K");

            testCase.verifyEqual(string(writer.FileWriteDetails.FileName), "run at 4p20 K");
        end

    end

end
