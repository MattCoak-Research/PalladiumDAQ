classdef test_DataWriter < matlab.unittest.TestCase
    % TEST_DATAWRITER Tests for Palladium.DataWriting.DataWriter. These
    % check the contents of the files it writes directly. Writing then
    % reading back through DataReader is covered in test_DataWriteAndRead.
    %
    % Not covered: DataWriter's retry loop succeeding on a later attempt
    % (needs a file that is locked and then released mid-write).

    %% Properties
    properties
        TempDir;    %Fresh empty folder for each test, removed afterwards
        LogDir;
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)

        function HelpersPathSetup(testCase)
            %Test helpers, which keep everything the tests write inside Testing Data Files
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "..", "Helpers")));
        end

    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)

        function CreateTemporaryFolder(testCase)
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            testCase.TempDir = string(fixture.Folder);
            testCase.LogDir = fullfile(testCase.TempDir, "logs");
        end

    end

    %% Tests
    methods (Test)

        %% Constructor and ConstructPath
        function test_Constructor_StoresDetailsAndBuildsFilePathTest(testCase)
            details = testCase.makeDetails("acq");

            writer = Palladium.DataWriting.DataWriter(details);

            testCase.verifyEqual(writer.FileWriteDetails.FilePath, fullfile(testCase.TempDir, "acq.dat"));
            testCase.verifyEqual(writer.FileWriteDetails.FileName, "acq");
            testCase.verifyEqual(writer.FileWriteDetails.DescriptionText, "A description");
        end

        function test_Constructor_AcceptsCharacterInputsTest(testCase)
            details = testCase.makeDetails("acq");
            details.Directory = char(details.Directory);
            details.FileName = 'acq';
            details.FileExtension = '.txt';

            writer = Palladium.DataWriting.DataWriter(details);

            testCase.verifyEqual(string(writer.FileWriteDetails.FilePath), fullfile(testCase.TempDir, "acq.txt"));
        end

        function test_ConstructPath_UpdatesWhenFileNameChangesTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            writer.FileWriteDetails.FileName = "other";
            writer.ConstructPath();

            testCase.verifyEqual(writer.FileWriteDetails.FilePath, fullfile(testCase.TempDir, "other.dat"));
        end

        function test_Defaults_FileInfoAndEndMarkerTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            testCase.verifyEqual(writer.FileInfo, "<<< Palladium DAQ data file 3.0 >>>");
            testCase.verifyEqual(Palladium.DataWriting.DataWriter.END_METADATA_LINES_STRING, "<<< END METADATA LINES >>>");
        end

        %% WriteHeaders
        function test_WriteHeaders_WritesExpectedLayoutTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            writer.WriteHeaders(sprintf("Time (s)\tTemp (K)"), MetadataLines=["first line", "second line"]);

            expected = [ ...
                "<<< Palladium DAQ data file 3.0 >>>"
                "A description"
                ""
                "<Instrument Settings and Metadata>"
                "first line"
                "second line"
                "<<< END METADATA LINES >>>"
                ""
                sprintf("Time (s)\tTemp (K)")];
            testCase.verifyEqual(testCase.fileLines(writer), expected);
        end

        function test_WriteHeaders_WithoutMetadataLinesTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            writer.WriteHeaders("a");

            expected = [ ...
                "<<< Palladium DAQ data file 3.0 >>>"
                "A description"
                ""
                "<Instrument Settings and Metadata>"
                "<<< END METADATA LINES >>>"
                ""
                "a"];
            testCase.verifyEqual(testCase.fileLines(writer), expected);
        end

        function test_WriteHeaders_MissingAndEmptyMetadataLinesBecomeBlankLinesTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            writer.WriteHeaders("a", MetadataLines=["first", missing, ""]);

            lines = testCase.fileLines(writer);
            testCase.verifyEqual(lines(5:7), ["first"; ""; ""]);
            testCase.verifyEqual(lines(8), "<<< END METADATA LINES >>>");
        end

        function test_WriteHeaders_EmptyDescriptionGivesBlankLineTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", Description=""));

            writer.WriteHeaders("a");

            lines = testCase.fileLines(writer);
            testCase.verifyEqual(lines(1:4), ["<<< Palladium DAQ data file 3.0 >>>"; ""; ""; "<Instrument Settings and Metadata>"]);
        end

        function test_WriteHeaders_UsesWindowsLineEndingsTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            writer.WriteHeaders("a", MetadataLines="m");

            text = fileread(writer.FileWriteDetails.FilePath);
            testCase.verifyEqual(count(text, string([char(13) newline])), 8, "Every header line should end in CR LF");
            testCase.verifyEqual(count(text, newline), 8, "No bare LF line endings in the header");
        end

        function test_WriteHeaders_OverwritesExistingFileTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));
            writer.WriteHeaders("old header", MetadataLines="old metadata");
            writer.WriteLine([1 2 3]);

            writer.WriteHeaders("new header");

            lines = testCase.fileLines(writer);
            testCase.verifyEqual(lines(end), "new header");
            testCase.verifyFalse(any(contains(lines, "old")), "Nothing of the old file should be left");
        end

        function test_WriteHeaders_AppendModeLeavesExistingFileUntouchedTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Append To File"));
            writer.WriteHeaders("original", MetadataLines="original metadata");
            writer.WriteLine([1 2]);
            before = fileread(writer.FileWriteDetails.FilePath);

            laterWriter = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Append To File"));
            laterWriter.WriteHeaders("ignored", MetadataLines="ignored metadata");

            testCase.verifyEqual(fileread(writer.FileWriteDetails.FilePath), before);
        end

        function test_WriteHeaders_AppendModeWritesHeadersWhenFileMissingTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Append To File"));

            writer.WriteHeaders("a");

            testCase.verifyTrue(isfile(writer.FileWriteDetails.FilePath));
            testCase.verifyEqual(testCase.fileLines(writer, "last"), "a");
        end

        function test_WriteHeaders_KeepsFormatCharactersLiteralTest(testCase)
            %Description and metadata text can contain % and backslashes
            %(Windows paths): they must be written exactly as given
            tricky = "50% done C:\new\table %s %d";
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", Description=tricky));

            writer.WriteHeaders("a", MetadataLines=tricky);

            lines = testCase.fileLines(writer);
            testCase.verifyEqual(lines(2), tricky);
            testCase.verifyEqual(lines(5), tricky);
        end

        %% WriteLine and WriteData
        function test_WriteLine_AppendsTabDelimitedRowsTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));
            writer.WriteHeaders("a");

            writer.WriteLine([1 2.5 -3]);
            writer.WriteLine([4 5 6]);

            lines = testCase.fileLines(writer);
            testCase.verifyEqual(lines(end-1:end), [sprintf("1\t2.5\t-3"); sprintf("4\t5\t6")]);
        end

        function test_WriteLine_LeavesHeadersAlreadyWrittenAloneTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));
            writer.WriteHeaders("a", MetadataLines="m");
            headerLines = testCase.fileLines(writer);

            writer.WriteLine([1 2]);

            lines = testCase.fileLines(writer);
            testCase.verifyEqual(lines(1:numel(headerLines)), headerLines);
            testCase.verifyLength(lines, numel(headerLines) + 1);
        end

        function test_WriteLine_WritesNaNAndInfAsTextTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));
            writer.WriteHeaders("a");

            writer.WriteLine([NaN Inf -Inf]);

            testCase.verifyEqual(testCase.fileLines(writer, "last"), sprintf("NaN\tInf\t-Inf"));
        end

        function test_WriteLine_WritesFifteenSignificantDigitsTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));
            writer.WriteHeaders("a");

            writer.WriteLine([pi 1/3 1e-300]);

            testCase.verifyEqual(testCase.fileLines(writer, "last"), sprintf("3.14159265358979\t0.333333333333333\t1e-300"));
        end

        function test_WriteLine_CreatesFileIfHeadersWereNeverWrittenTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            writer.WriteLine([1 2]);

            testCase.verifyEqual(testCase.fileLines(writer), sprintf("1\t2"));
        end

        function test_WriteData_AppendsEveryRowOfMatrixTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));
            writer.WriteHeaders("a");

            writer.WriteData([1 2; 3 4; 5 6]);

            lines = testCase.fileLines(writer);
            testCase.verifyEqual(lines(end-2:end), [sprintf("1\t2"); sprintf("3\t4"); sprintf("5\t6")]);
        end

        function test_WriteData_ProducesSameFileAsRepeatedWriteLineTest(testCase)
            data = [1.5 2; -3 4e-9; NaN 6; 7 Inf];
            lineWriter = Palladium.DataWriting.DataWriter(testCase.makeDetails("byline"));
            dataWriter = Palladium.DataWriting.DataWriter(testCase.makeDetails("bydata"));
            lineWriter.WriteHeaders("a");
            dataWriter.WriteHeaders("a");

            for i = 1 : size(data, 1)
                lineWriter.WriteLine(data(i, :));
            end
            dataWriter.WriteData(data);

            testCase.verifyEqual(testCase.fileLines(dataWriter), testCase.fileLines(lineWriter));
        end

        function test_WriteLine_UnwritablePathWarnsAndLogsDataLossWithoutThrowingTest(testCase)
            logPath = testCase.initialiseLogger();
            details = testCase.makeDetails("acq", Directory=fullfile(testCase.TempDir, "no", "such", "folder"));
            writer = Palladium.DataWriting.DataWriter(details);

            testCase.verifyWarning(@() testCase.runQuietly(@() writer.WriteLine([1 2 3])), "WriteLineWarning:WriteFailed");

            logText = fileread(logPath);
            testCase.verifySubstring(logText, "failed after 3 attempts. Data have been lost.");
        end

        function test_WriteData_UnwritablePathWarnsAndLogsDataLossWithoutThrowingTest(testCase)
            logPath = testCase.initialiseLogger();
            details = testCase.makeDetails("acq", Directory=fullfile(testCase.TempDir, "no", "such", "folder"));
            writer = Palladium.DataWriting.DataWriter(details);

            testCase.verifyWarning(@() testCase.runQuietly(@() writer.WriteData([1 2; 3 4])), "WriteDataWarning:WriteFailed");

            testCase.verifySubstring(fileread(logPath), "failed after 3 attempts. Data have been lost.");
        end

        %% InsertMetadataLines
        function test_InsertMetadataLines_InsertsSingleLineBeforeEndMarkerTest(testCase)
            writer = testCase.writerWithData("acq", MetadataLines=["m1", "m2"]);

            writer.InsertMetadataLines("inserted");

            lines = testCase.fileLines(writer);
            testCase.verifyEqual(lines(5:8), ["m1"; "m2"; "inserted"; "<<< END METADATA LINES >>>"]);
        end

        function test_InsertMetadataLines_InsertsStringArrayInOrderTest(testCase)
            writer = testCase.writerWithData("acq");

            writer.InsertMetadataLines(["a", "b", "c"]);

            lines = testCase.fileLines(writer);
            testCase.verifyEqual(lines(5:8), ["a"; "b"; "c"; "<<< END METADATA LINES >>>"]);
        end

        function test_InsertMetadataLines_RepeatedInsertsAccumulateInOrderTest(testCase)
            writer = testCase.writerWithData("acq", MetadataLines="m1");

            writer.InsertMetadataLines("first insert");
            writer.InsertMetadataLines("second insert");

            lines = testCase.fileLines(writer);
            testCase.verifyEqual(lines(5:8), ["m1"; "first insert"; "second insert"; "<<< END METADATA LINES >>>"]);
        end

        function test_InsertMetadataLines_LeavesEverythingElseUnchangedTest(testCase)
            writer = testCase.writerWithData("acq", MetadataLines=["m1", "m2"]);
            before = testCase.fileLines(writer);
            endIdx = find(before == "<<< END METADATA LINES >>>");

            writer.InsertMetadataLines("inserted");

            after = testCase.fileLines(writer);
            testCase.verifyEqual(after(1:endIdx-1), before(1:endIdx-1), "Lines before the insertion point");
            testCase.verifyEqual(after(endIdx+1:end), before(endIdx:end), "End marker, blank line, headers and data");
        end

        function test_InsertMetadataLines_KeepsFormatCharactersLiteralTest(testCase)
            writer = testCase.writerWithData("acq");
            tricky = "50% done C:\new\table %s %d";

            writer.InsertMetadataLines(tricky);

            testCase.verifyEqual(testCase.fileLines(writer, 5), tricky);
        end

        function test_InsertMetadataLines_NoEndMarkerWarnsAndLeavesFileUnchangedTest(testCase)
            logPath = testCase.initialiseLogger(); %#ok<NASGU>
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("plain"));
            fid = fopen(writer.FileWriteDetails.FilePath, "w");
            fprintf(fid, "line one\nline two\n");
            fclose(fid);
            before = fileread(writer.FileWriteDetails.FilePath);

            testCase.verifyWarning(@() testCase.runQuietly(@() writer.InsertMetadataLines("x")), "InsertMetadataLinesWarning:MetadataMarkerNotFound");

            testCase.verifyEqual(fileread(writer.FileWriteDetails.FilePath), before);
        end

        function test_InsertMetadataLines_MissingFileWarnsInsteadOfThrowingTest(testCase)
            testCase.initialiseLogger();
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("never_written"));

            testCase.verifyWarning(@() testCase.runQuietly(@() writer.InsertMetadataLines("x")), "InsertMetadataLinesWarning:WriteFailed");
            testCase.verifyFalse(isfile(writer.FileWriteDetails.FilePath), "Must not create the file");
        end

        function test_InsertMetadataLines_RejectsNonTextTest(testCase)
            writer = testCase.writerWithData("acq");

            testCase.verifyError(@() writer.InsertMetadataLines(5), "MATLAB:validators:mustBeText");
        end

        %% ValidateFilePath
        function test_ValidateFilePath_IncrementModeAddsNumberToNewNameTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Increment File No."));

            newName = writer.ValidateFilePath();

            testCase.verifyEqual(newName, "acq-00001");
            testCase.verifyEqual(writer.FileWriteDetails.FileName, "acq-00001");
            testCase.verifyEqual(writer.FileWriteDetails.FilePath, fullfile(testCase.TempDir, "acq-00001.dat"));
        end

        function test_ValidateFilePath_IncrementModeSkipsExistingFilesTest(testCase)
            testCase.touch("acq-00001.dat");
            testCase.touch("acq-00002.dat");
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Increment File No."));

            newName = writer.ValidateFilePath();

            testCase.verifyEqual(newName, "acq-00003");
            testCase.verifyEqual(writer.FileWriteDetails.FilePath, fullfile(testCase.TempDir, "acq-00003.dat"));
        end

        function test_ValidateFilePath_IncrementModeKeepsFreeNumberedNameTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq-00005", WriteMode="Increment File No."));

            testCase.verifyEqual(writer.ValidateFilePath(), "acq-00005");
        end

        function test_ValidateFilePath_IncrementModeIncrementsExistingNumberedNameTest(testCase)
            testCase.touch("acq-00005.dat");
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq-00005", WriteMode="Increment File No."));

            testCase.verifyEqual(writer.ValidateFilePath(), "acq-00006");
        end

        function test_ValidateFilePath_IncrementModeShortNamesTest(testCase)
            %Regression: names under 3 characters used to error, which also
            %meant typing one into the file name box in the GUI errored
            for name = ["a", "ab", "7"]
                writer = Palladium.DataWriting.DataWriter(testCase.makeDetails(name, WriteMode="Increment File No."));

                testCase.verifyEqual(writer.ValidateFilePath(), name + "-00001", name);
            end
        end

        function test_ValidateFilePath_IncrementModeNameEndingInNumbersIsNotIncrementedTest(testCase)
            testCase.touch("acq_T297.dat");
            testCase.touch("sample 02-Aug-2026.dat");

            first = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq_T297", WriteMode="Increment File No."));
            second = Palladium.DataWriting.DataWriter(testCase.makeDetails("sample 02-Aug-2026", WriteMode="Increment File No."));

            testCase.verifyEqual(first.ValidateFilePath(), "acq_T297-00001");
            testCase.verifyEqual(second.ValidateFilePath(), "sample 02-Aug-2026-00001");
        end

        function test_ValidateFilePath_IncrementModeFeedingTheNameBackGivesTheNextFileTest(testCase)
            %Controller stores the name ValidateFilePath returns, so the
            %next Start validates that name
            details = testCase.makeDetails("acq", WriteMode="Increment File No.");
            names = strings(1, 3);
            for i = 1 : 3
                writer = Palladium.DataWriting.DataWriter(details);
                details.FileName = writer.ValidateFilePath();
                writer.WriteHeaders("a");
                names(i) = details.FileName;
            end

            testCase.verifyEqual(names, ["acq-00001" "acq-00002" "acq-00003"]);
        end

        function test_ValidateFilePath_IncrementModeOnlyConsidersMatchingExtensionTest(testCase)
            testCase.touch("acq-00001.csv");
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Increment File No.", Extension=".dat"));

            testCase.verifyEqual(writer.ValidateFilePath(), "acq-00001");
        end

        function test_ValidateFilePath_IncrementedFileIsWrittenToTheNewNameTest(testCase)
            testCase.touch("acq-00001.dat");
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Increment File No."));
            writer.ValidateFilePath();

            writer.WriteHeaders("a");

            testCase.verifyTrue(isfile(fullfile(testCase.TempDir, "acq-00002.dat")));
            testCase.verifyEqual(dir(fullfile(testCase.TempDir, "acq-00001.dat")).bytes, 0, "Existing file must be left alone");
        end

        function test_ValidateFilePath_OverwriteModeKeepsNameTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Overwrite File"));

            newName = writer.ValidateFilePath();

            testCase.verifyEqual(newName, "acq");
            testCase.verifyEqual(writer.FileWriteDetails.FilePath, fullfile(testCase.TempDir, "acq.dat"));
        end

        function test_ValidateFilePath_OverwriteModeReplacesOldContentOnceHeadersWrittenTest(testCase)
            old = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Overwrite File"));
            old.WriteHeaders("old header", MetadataLines="old metadata");
            old.WriteLine([1 2 3]);

            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Overwrite File"));
            writer.ValidateFilePath();
            writer.WriteHeaders("new header");
            writer.WriteLine([9 9 9]);

            lines = testCase.fileLines(writer);
            testCase.verifyEqual(lines(end-1:end), ["new header"; sprintf("9\t9\t9")]);
            testCase.verifyFalse(any(contains(lines, "old")));
        end

        function test_ValidateFilePath_OverwriteModeLeavesExistingFileUntouchedTest(testCase)
            %ValidateFilePath also runs whenever the file settings are
            %edited in the GUI, and before the instruments connect, so it
            %must never destroy the existing file - that only happens once
            %WriteHeaders writes the new one
            existing = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Overwrite File"));
            existing.WriteHeaders("header", MetadataLines="precious metadata");
            existing.WriteLine([1 2 3]);
            before = fileread(existing.FileWriteDetails.FilePath);

            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Overwrite File"));
            writer.ValidateFilePath();
            writer.ValidateFilePath();

            testCase.verifyEqual(fileread(writer.FileWriteDetails.FilePath), before);
        end

        function test_ValidateFilePath_OverwriteModeIgnoresMatlabFunctionsWithTheSameNameTest(testCase)
            %Regression: the file name alone was looked up on MATLAB's
            %search path, so a name like "run" matched run.m and
            %triggered a delete (and a warning)
            for name = ["run", "mean", "plot"]
                testCase.assumeNotEqual(exist(name, "file") + exist(name, "builtin"), 0, name + " should exist as a MATLAB function");
                writer = Palladium.DataWriting.DataWriter(testCase.makeDetails(name, WriteMode="Overwrite File"));

                testCase.verifyWarningFree(@() writer.ValidateFilePath(), name);
                testCase.verifyEqual(writer.FileWriteDetails.FilePath, fullfile(testCase.TempDir, name + ".dat"));
            end
        end

        function test_ValidateFilePath_OverwriteModeNeverDeletesFilesInTheCurrentFolderTest(testCase)
            %Regression: a file in the current folder with the same name as
            %the data file (and no extension) used to be deleted
            workingFolder = fullfile(testCase.TempDir, "working");
            mkdir(workingFolder);
            unrelated = fullfile(workingFolder, "notes");
            fid = fopen(unrelated, "w");
            fprintf(fid, "something unrelated\n");
            fclose(fid);
            testCase.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(workingFolder));
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("notes", WriteMode="Overwrite File"));

            writer.ValidateFilePath();

            testCase.verifyTrue(isfile(unrelated));
        end

        function test_ValidateFilePath_AppendModeKeepsNameAndExistingFileTest(testCase)
            testCase.touch("acq.dat");
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Append To File"));

            newName = writer.ValidateFilePath();

            testCase.verifyEqual(newName, "acq");
            testCase.verifyTrue(isfile(fullfile(testCase.TempDir, "acq.dat")));
        end

        function test_ValidateFilePath_AcceptsCharacterWriteModeTest(testCase)
            details = testCase.makeDetails("acq");
            details.WriteMode = 'Increment File No.';
            writer = Palladium.DataWriting.DataWriter(details);

            testCase.verifyEqual(writer.ValidateFilePath(), "acq-00001");
        end

        function test_ValidateFilePath_SaveFileOffLeavesNameAloneEvenIfFileExistsTest(testCase)
            testCase.touch("acq.dat");
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Increment File No.", SaveFile=false));

            newName = writer.ValidateFilePath();

            testCase.verifyEqual(newName, "acq");
            testCase.verifyEqual(writer.FileWriteDetails.FilePath, fullfile(testCase.TempDir, "acq.dat"));
        end

        function test_ValidateFilePath_UnsupportedWriteModeErrorsTest(testCase)
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq", WriteMode="Delete Everything"));

            testCase.verifyError(@() writer.ValidateFilePath(), "ValidateFilePathError:UnsupportedWriteMode");
        end

        %% SaveFigure
        function test_SaveFigure_SavesFigAndPngTest(testCase)
            [fig, ax] = testCase.makeFigure();
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            writer.SaveFigure(fig, ax, testCase.TempDir, "myplot");

            figFile = fullfile(testCase.TempDir, "myplot-Fig-00001.fig");
            pngFile = fullfile(testCase.TempDir, "myplot-Fig-00001.png");
            testCase.verifyTrue(isfile(figFile));
            testCase.verifyTrue(isfile(pngFile));
            testCase.verifyGreaterThan(dir(figFile).bytes, 0);
            testCase.verifyGreaterThan(dir(pngFile).bytes, 0);
        end

        function test_SaveFigure_NumbersRepeatedSavesTest(testCase)
            [fig, ax] = testCase.makeFigure();
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            writer.SaveFigure(fig, ax, testCase.TempDir, "myplot");
            writer.SaveFigure(fig, ax, testCase.TempDir, "myplot");

            for n = ["00001", "00002"]
                testCase.verifyTrue(isfile(fullfile(testCase.TempDir, "myplot-Fig-" + n + ".fig")), n);
                testCase.verifyTrue(isfile(fullfile(testCase.TempDir, "myplot-Fig-" + n + ".png")), n);
            end
        end

        function test_SaveFigure_UsesAxesTitleForFileNameTest(testCase)
            [fig, ax] = testCase.makeFigure();
            title(ax, "My Plot Title");
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            writer.SaveFigure(fig, ax, testCase.TempDir, "ignored_name");

            testCase.verifyTrue(isfile(fullfile(testCase.TempDir, "My Plot Title-Fig-00001.png")));
            testCase.verifyFalse(isfile(fullfile(testCase.TempDir, "ignored_name-Fig-00001.png")));
        end

        function test_SaveFigure_UsesFirstLineOfMultilineTitleForFileNameTest(testCase)
            [fig, ax] = testCase.makeFigure();
            title(ax, {"First line of title", "second line"});
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            writer.SaveFigure(fig, ax, testCase.TempDir, "ignored_name");

            testCase.verifyTrue(isfile(fullfile(testCase.TempDir, "First line of title-Fig-00001.png")));
        end

        function test_SaveFigure_TitlesUntitledAxesFromFileNameTest(testCase)
            [fig, ax] = testCase.makeFigure();
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            writer.SaveFigure(fig, ax, testCase.TempDir, "my_run_name");

            testCase.verifyEqual(string(ax.Title.String), "my run name");
        end

        function test_SaveFigure_MissingDirectoryErrorsTest(testCase)
            [fig, ax] = testCase.makeFigure();
            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails("acq"));

            testCase.verifyError(@() writer.SaveFigure(fig, ax, fullfile(testCase.TempDir, "nope"), "myplot"), "SaveFigureError:SaveFailed");
        end

        %% BuildMetadataLineStringFromStruct
        function test_BuildMetadataLineFromStruct_FormatsFieldsInOrderTest(testCase)
            s = struct("Frequency", 100, "Mode", "AC", "Enabled", true);

            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("Settings: ", s);

            testCase.verifyEqual(line, "Settings: Frequency = 100 || Mode = AC || Enabled = true");
        end

        function test_BuildMetadataLineFromStruct_JoinsArrayValuesWithSpacesTest(testCase)
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", struct("Range", [1 2 3], "Names", ["a" "b"]));

            testCase.verifyEqual(line, "Range = 1 2 3 || Names = a b");
        end

        function test_BuildMetadataLineFromStruct_EmptyValueShownAsBracketsTest(testCase)
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", struct("Nothing", []));

            testCase.verifyEqual(line, "Nothing = []");
        end

        function test_BuildMetadataLineFromStruct_SingleFieldHasNoSeparatorTest(testCase)
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("P: ", struct("A", 1));

            testCase.verifyEqual(line, "P: A = 1");
        end

        function test_BuildMetadataLineFromStruct_EmptyStructGivesJustThePrefixTest(testCase)
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("Prefix: ", struct());

            testCase.verifyEqual(line, "Prefix: ");
        end

        function test_BuildMetadataLineFromStruct_NumbersKeepFullPrecisionTest(testCase)
            s = struct("Pi", pi, "Third", 1/3, "Small", 1e-7, "Long", 0.123456789, "Tenth", 0.1, "Big", 123456789012);

            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", s);

            testCase.verifyEqual(line, "Pi = 3.141592653589793 || Third = 0.3333333333333333 || Small = 1e-07 || Long = 0.123456789 || Tenth = 0.1 || Big = 123456789012");
        end

        function test_BuildMetadataLineFromStruct_NumbersReadBackExactlyTest(testCase)
            values = [rand(1, 100) .* 10 .^ randi([-30 30], 1, 100), -rand(1, 20), 1e308, 5e-324, realmax, realmin, 0, -0.5, 2^53 + 2];

            for value = values
                line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", struct("v", value));

                testCase.verifyEqual(str2double(extractAfter(line, "v = ")), value, "Value written as " + line);
            end
        end

        function test_BuildMetadataLineFromStruct_ArraysKeepFullPrecisionTest(testCase)
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", struct("Values", [pi 1/3 100]));

            testCase.verifyEqual(line, "Values = 3.141592653589793 0.3333333333333333 100");
        end

        function test_BuildMetadataLineFromStruct_NaNAndInfinityAreWrittenAsTextTest(testCase)
            %string(NaN) is a missing string, which used to blank the whole line
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("S: ", struct("A", NaN, "B", Inf, "C", -Inf, "D", [1 NaN]));

            testCase.verifyEqual(line, "S: A = NaN || B = Inf || C = -Inf || D = 1 NaN");
            testCase.verifyFalse(ismissing(line));
        end

        function test_BuildMetadataLineFromStruct_SinglePrecisionIsWrittenWithoutExtraDigitsTest(testCase)
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", struct("Tenth", single(0.1), "Pi", single(pi), "Whole", single(7)));

            testCase.verifyEqual(line, "Tenth = 0.1 || Pi = 3.1415927 || Whole = 7");
            testCase.verifyEqual(single(str2double("3.1415927")), single(pi), "Must read back as the same single");
        end

        function test_BuildMetadataLineFromStruct_OtherTypesAreConvertedAsBeforeTest(testCase)
            s = struct("Int", int32(42), "Unsigned", uint8([1 2 3]), "Flag", false, "Text", "abc", "Char", 'xyz', "Category", categorical("Resistance"));

            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", s);

            testCase.verifyEqual(line, "Int = 42 || Unsigned = 1 2 3 || Flag = false || Text = abc || Char = xyz || Category = Resistance");
        end

        %% BuildMetadataLineStringFromHeaderValuePair
        function test_BuildMetadataLineFromHeaderValuePair_FormatsPairsTest(testCase)
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("Start: ", ["T (K)", "B (T)"], [4.2 0.5]);

            testCase.verifyEqual(line, "Start: T (K) = 4.2 || B (T) = 0.5");
        end

        function test_BuildMetadataLineFromHeaderValuePair_ValuesKeepFullPrecisionTest(testCase)
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("", ["Time (s)", "R (Ohm)", "I (A)"], [29545432.2083213, 1/3, 1.234567890123e-9]);

            testCase.verifyEqual(line, "Time (s) = 29545432.2083213 || R (Ohm) = 0.3333333333333333 || I (A) = 1.234567890123e-09");
        end

        function test_BuildMetadataLineFromHeaderValuePair_NaNAndInfinityAreWrittenAsTextTest(testCase)
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("", ["a", "b", "c"], [NaN Inf -Inf]);

            testCase.verifyEqual(line, "a = NaN || b = Inf || c = -Inf");
        end

        function test_BuildMetadataLineFromHeaderValuePair_AcceptsCellArrayOfHeadersTest(testCase)
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("", {'a', 'b'}, [1 2]);

            testCase.verifyEqual(line, "a = 1 || b = 2");
        end

        function test_BuildMetadataLineFromHeaderValuePair_SinglePairHasNoSeparatorTest(testCase)
            line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("", "a", 7);

            testCase.verifyEqual(line, "a = 7");
        end

        function test_BuildMetadataLineFromHeaderValuePair_LengthMismatchErrorsTest(testCase)
            testCase.verifyError(@() Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("", ["a", "b"], [1 2 3]), ...
                "BuildMetadataLineStringFromHeaderValuePairError:LengthMismatch");
        end

        function test_BuildMetadataLineFromHeaderValuePair_EmptyDataRowWarnsAndReturnsPrefixTest(testCase)
            line = [];
            testCase.verifyWarning(@() assignOutput(), "BuildMetadataLineStringFromHeaderValuePairWarning:EmptyDataRow");
            testCase.verifyEqual(line, "Prefix: ");

            function assignOutput()
                line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("Prefix: ", ["a", "b"], []);
            end
        end

        function test_BuildMetadataLineFromHeaderValuePair_EmptyHeaderRowWarnsAndReturnsPrefixTest(testCase)
            line = [];
            testCase.verifyWarning(@() assignOutput(), "BuildMetadataLineStringFromHeaderValuePairWarning:EmptyDataRow");
            testCase.verifyEqual(line, "Prefix: ");

            function assignOutput()
                line = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("Prefix: ", [], [1 2]);
            end
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function details = makeDetails(testCase, fileName, Settings)
            %A FileWriteDetails struct like the one Controller builds
            arguments
                testCase;
                fileName (1,1) string;
                Settings.Directory (1,1) string = "";
                Settings.Extension (1,1) string = ".dat";
                Settings.Description (1,1) string = "A description";
                Settings.WriteMode (1,1) string = "Overwrite File";
                Settings.SaveFile (1,1) logical = true;
            end

            if Settings.Directory == ""
                Settings.Directory = testCase.TempDir;
            end

            details = struct( ...
                "Directory", Settings.Directory, ...
                "FileName", fileName, ...
                "FileExtension", Settings.Extension, ...
                "DescriptionText", Settings.Description, ...
                "WriteMode", Settings.WriteMode, ...
                "SaveFile", Settings.SaveFile);
        end

        function writer = writerWithData(testCase, fileName, Settings)
            %A writer whose file already has headers and a few data rows,
            %like a sweep file at the point metadata is added to it
            arguments
                testCase;
                fileName (1,1) string;
                Settings.MetadataLines = [];
            end

            writer = Palladium.DataWriting.DataWriter(testCase.makeDetails(fileName));
            writer.WriteHeaders(sprintf("a\tb"), MetadataLines=Settings.MetadataLines);
            writer.WriteLine([1 2]);
            writer.WriteLine([3 4]);
        end

        function lines = fileLines(~, writer, which)
            %The lines of the writer's file as a string column, with CR LF
            %endings normalised and the final line ending removed. which can
            %be "last" or a line number to return just that line
            arguments
                ~;
                writer;
                which = "all";
            end

            text = fileread(writer.FileWriteDetails.FilePath);
            text = strrep(text, [char(13) newline], newline);
            lines = splitlines(string(text));
            if lines(end) == ""
                lines(end) = [];
            end

            if isequal(which, "last")
                lines = lines(end);
            elseif isnumeric(which)
                lines = lines(which);
            end
        end

        function touch(testCase, fileName)
            %Create an empty file in the temporary folder
            fclose(fopen(fullfile(testCase.TempDir, fileName), "w"));
        end

        function [fig, ax] = makeFigure(testCase)
            fig = figure(Visible="off");
            testCase.addTeardown(@() close(fig, "force"));
            ax = axes(fig);
            plot(ax, 1:3);
        end

        function logPath = initialiseLogger(testCase)
            %Palladium's Logger keeps its settings in persistent state set
            %up by Controller. DataWriter logs when a write fails, so point
            %the logger at a file in the temporary folder (and nowhere else)
            %for the test, then switch everything off afterwards.
            logPath = fullfile(testCase.LogDir, "unit.log");
            Palladium.Logging.Logger.Log("Debug", "Logging started for test", "Controller", true, ...
                "LogFileDirectory", testCase.LogDir, "LogFileFileName", "unit.log", ...
                "CommandWindowMessageLevel", "Off", "GUIMessageLevel", "Off", "LogFileMessageLevel", "Debug");
            testCase.addTeardown(@() Palladium.Logging.Logger.Log("Debug", "Logging stopped", "Controller", true, ...
                "LogFileDirectory", testCase.LogDir, "LogFileFileName", "unit.log", ...
                "CommandWindowMessageLevel", "Off", "GUIMessageLevel", "Off", "LogFileMessageLevel", "Off"));
        end

        function runQuietly(~, fcn) %#ok<INUSD>
            %Run fcn with anything it prints to the command window captured
            %and discarded (warnings are still raised for verifyWarning)
            evalc("fcn()");
        end

    end

end
