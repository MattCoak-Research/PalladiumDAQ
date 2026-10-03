classdef test_DataWriteAndRead < matlab.unittest.TestCase
    % TEST_DATAWRITEANDREAD Round-trip tests: write data files with
    % Palladium.DataWriting.DataWriter exactly as the programme does
    % (ValidateFilePath, WriteHeaders, WriteLine/WriteData, then often
    % InsertMetadataLines), read them back with DataReader, and check
    % nothing was changed along the way.
    %
    % Numbers are written to 15 significant digits (writematrix's
    % default), so a double is not always recovered bit-for-bit. Data are
    % compared to a relative tolerance of 1e-14, and exactly where the
    % value is exactly representable in 15 digits (integers, 0.5, ...).

    %% Properties
    properties
        TempDir;
        DataTolerance = 1e-14;
    end

    %% Properties (TestParameter)
    properties (TestParameter)
        FileExtension = {".dat", ".txt", ".csv"};
        Shape = struct( ...
            "OneByOne", [1 1], ...
            "SingleRow", [1 6], ...
            "SingleColumn", [6 1], ...
            "TwoByTwo", [2 2], ...
            "Square", [8 8], ...
            "Wide", [3 120], ...
            "Long", [10000 4]);
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)

        function HelpersPathSetup(testCase)
            %Test helpers, which keep everything the tests write inside Testing Data Files
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "..", "Helpers")));
        end

        function SeedRandomNumberGenerator(testCase)
            testCase.addTeardown(@rng, rng);
            rng(1);
        end

    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)

        function CreateTemporaryFolder(testCase)
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            testCase.TempDir = string(fixture.Folder);
        end

    end

    %% Tests
    methods (Test)

        %% Data values
        function test_RoundTrip_IntegersAreExactTest(testCase)
            data = [0 1 -1 42; 1000000 -987654321 7 0];

            readBack = testCase.roundTrip(data);

            testCase.verifyEqual(readBack.Data, data);
        end

        function test_RoundTrip_ExactlyRepresentableFractionsAreExactTest(testCase)
            data = [0.5 0.25 0.125 -0.75; 1/1024 3/8 -1/16 100.5];

            readBack = testCase.roundTrip(data);

            testCase.verifyEqual(readBack.Data, data);
        end

        function test_RoundTrip_RandomDataSurvivesToFifteenSignificantDigitsTest(testCase)
            data = rand(200, 5) .* 10 .^ randi([-12 12], 200, 5) .* sign(randn(200, 5));

            readBack = testCase.roundTrip(data);

            testCase.verifyEqual(readBack.Data, data, "RelTol", testCase.DataTolerance);
        end

        function test_RoundTrip_FullRangeOfMagnitudesAndSignsTest(testCase)
            exponents = [-300 -100 -15 -3 0 3 15 100 300];
            data = [10 .^ exponents; -(10 .^ exponents); 1.2345678901234 * 10 .^ exponents];

            readBack = testCase.roundTrip(data);

            testCase.verifyEqual(readBack.Data, data, "RelTol", testCase.DataTolerance);
            testCase.verifyEqual(sign(readBack.Data), sign(data), "Signs must be preserved");
        end

        function test_RoundTrip_TimestampsAreNotAffectedByLargeMagnitudeTest(testCase)
            %Time columns in the example files are ~3e7 with sub-second
            %resolution, so ~15 digits are needed to keep them
            data = [29545432.2083213 100.814723686393; 29545432.2142851 100.913375856139];

            readBack = testCase.roundTrip(data);

            testCase.verifyEqual(readBack.Data, data, "RelTol", testCase.DataTolerance);
        end

        function test_RoundTrip_NaNAndInfinitiesKeepTheirPositionsTest(testCase)
            data = [NaN Inf -Inf 1; 2 NaN 3 Inf; -Inf 4 NaN 5; 6 7 8 NaN];

            readBack = testCase.roundTrip(data);

            testCase.verifyEqual(readBack.Data, data);
        end

        function test_RoundTrip_FirstRowOfNaNAndInfTest(testCase)
            %Regression: this used to read back as a column of NaN
            data = [NaN Inf -Inf; 1 2 3];

            readBack = testCase.roundTrip(data);

            testCase.verifyEqual(readBack.Data, data);
        end

        function test_RoundTrip_ColumnAndRowsOfOnlyNaNTest(testCase)
            data = [NaN 1 2; NaN 3 4; NaN 5 6; NaN NaN NaN];

            readBack = testCase.roundTrip(data);

            testCase.verifyEqual(readBack.Data, data);
        end

        function test_RoundTrip_DataOfAnyShapeTest(testCase, Shape)
            data = reshape(1 : prod(Shape), fliplr(Shape))' * 1.5;

            %WriteLine reopens the file for every row (~4 ms each), so
            %write the long file in one go
            readBack = testCase.roundTrip(data, UseWriteData=Shape(1) > 100);

            testCase.verifyEqual(readBack.Data, data);
        end

        function test_RoundTrip_HeaderOnlyFileHasNoDataTest(testCase)
            readBack = testCase.roundTrip(zeros(0, 3), Headers=["a" "b" "c"]);

            testCase.verifyEqual(readBack.Headers, ["a" "b" "c"]);
            testCase.verifyEmpty(readBack.Data);
        end

        function test_RoundTrip_WriteLineAndWriteDataGiveSameResultTest(testCase)
            data = rand(50, 3) * 100 - 50;

            byLine = testCase.roundTrip(data, UseWriteData=false);
            byMatrix = testCase.roundTrip(data, UseWriteData=true);

            testCase.verifyEqual(byMatrix.Data, byLine.Data);
        end

        function test_RoundTrip_MixingWriteDataAndWriteLineKeepsRowOrderTest(testCase)
            writer = testCase.newWriter("mixed");
            writer.WriteHeaders(sprintf("a\tb"));
            writer.WriteLine([1 2]);
            writer.WriteData([3 4; 5 6]);
            writer.WriteLine([7 8]);
            writer.WriteData([9 10]);

            readBack = testCase.read(writer);

            testCase.verifyEqual(readBack.Data, [1 2; 3 4; 5 6; 7 8; 9 10]);
        end

        %% Headers
        function test_RoundTrip_HeadersWithSpacesUnitsAndSymbolsTest(testCase)
            headers = ["Time (mins)", "Resistance (Ohms)", "dV/dI [a.u.]", "T_sample_1", "50% load", "B || H", "x = 1"];

            readBack = testCase.roundTrip(rand(2, numel(headers)), Headers=headers);

            testCase.verifyEqual(readBack.Headers, headers);
        end

        function test_RoundTrip_TrailingTabAfterLastHeaderIsDroppedTest(testCase)
            %Sweep files write a tab after every header, including the last
            readBack = testCase.roundTrip([1 2; 3 4], Headers=["a" "b"], TrailingTab=true);

            testCase.verifyEqual(readBack.Headers, ["a" "b"]);
            testCase.verifyEqual(readBack.Data, [1 2; 3 4]);
        end

        function test_RoundTrip_LongHeaderTest(testCase)
            longHeader = string(repmat('x', 1, 500));

            readBack = testCase.roundTrip([1 2], Headers=[longHeader, "b"]);

            testCase.verifyEqual(readBack.Headers, [longHeader, "b"]);
        end

        function test_RoundTrip_UnicodeHeadersAndMetadataTest(testCase)
            testCase.assumeEqual(string(feature("DefaultCharacterSet")), "UTF-8", ...
                "Non-ASCII text is written in MATLAB's default encoding, which is not UTF-8 here");
            headers = ["T (°C)", "R (Ω)", "μ_eff", "Δφ"];
            metadata = ["Sample: Ångström film", "ρ = 10 μΩ·cm"];

            readBack = testCase.roundTrip(rand(2, 4), Headers=headers, Metadata=metadata);

            testCase.verifyEqual(readBack.Headers, headers);
            testCase.verifyEqual(readBack.Metadata(5:6), metadata);
        end

        %% Metadata and description
        function test_RoundTrip_StandardMetadataLinesAreWrittenFirstTest(testCase)
            readBack = testCase.roundTrip([1 2], Description="My run");

            testCase.verifyEqual(readBack.Metadata, ["<<< Palladium DAQ data file 3.0 >>>", "My run", "", "<Instrument Settings and Metadata>"]);
        end

        function test_RoundTrip_MetadataLinesAreUnchangedTest(testCase)
            metadata = ["Keithley 2000 Settings: Mode = Resistance || Range = 100", "Sweep: Start = 0 || Stop = 10", "plain text"];

            readBack = testCase.roundTrip([1 2], Metadata=metadata);

            testCase.verifyEqual(readBack.Metadata(5:end), metadata);
            testCase.verifyLength(readBack.Metadata, 4 + numel(metadata));
        end

        function test_RoundTrip_BlankAndMissingMetadataLinesBecomeEmptyStringsTest(testCase)
            readBack = testCase.roundTrip([1 2], Metadata=["first", missing, "", "last"]);

            testCase.verifyEqual(readBack.Metadata(5:end), ["first", "", "", "last"]);
        end

        function test_RoundTrip_ManyMetadataLinesTest(testCase)
            metadata = "line " + (1 : 500);

            readBack = testCase.roundTrip(rand(3, 2), Metadata=metadata);

            testCase.verifyEqual(readBack.Metadata(5:end), metadata);
        end

        function test_RoundTrip_VeryLongMetadataLineTest(testCase)
            metadata = string(repmat('abcdefghij', 1, 2000));

            readBack = testCase.roundTrip(rand(2, 2), Metadata=metadata);

            testCase.verifyEqual(readBack.Metadata(5), metadata);
        end

        function test_RoundTrip_FormatCharactersAndPathsInTextAreNotInterpretedTest(testCase)
            tricky = "50% done C:\new\table %s %d \n \t";

            readBack = testCase.roundTrip([1 2], Description=tricky, Metadata=tricky);

            testCase.verifyEqual(readBack.Metadata(2), tricky);
            testCase.verifyEqual(readBack.Metadata(5), tricky);
        end

        function test_RoundTrip_TabsInsideMetadataAreKeptTest(testCase)
            metadata = "before" + char(9) + "after";

            readBack = testCase.roundTrip([1 2], Metadata=metadata);

            testCase.verifyEqual(readBack.Metadata(5), metadata);
        end

        function test_RoundTrip_EmptyDescriptionTest(testCase)
            readBack = testCase.roundTrip([1 2], Description="");

            testCase.verifyEqual(readBack.Metadata(2), "");
            testCase.verifyEqual(readBack.Data, [1 2]);
        end

        function test_RoundTrip_MetadataBuiltFromStructAndHeaderValuePairTest(testCase)
            fromStruct = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("Settings: ", struct("Mode", "AC", "Range", [1 2 3], "Gain", 10));
            fromPairs = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("Start: ", ["T (K)", "B (T)"], [4.2 0.5]);

            readBack = testCase.roundTrip([1 2], Metadata=[fromStruct, fromPairs]);

            testCase.verifyEqual(readBack.Metadata(5:6), [fromStruct, fromPairs]);
        end

        function test_RoundTrip_NumbersInMetadataSurviveExactlyTest(testCase)
            %Unlike the data columns, numbers in metadata lines are written
            %with as many digits as needed to read back as the same double
            values = [pi, 1/3, 29545432.2083213, 1e-300, -2/7, 0.1, 123456789012, NaN, Inf];
            headers = "v" + (1 : numel(values));
            fromStruct = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("S: ", struct("Values", values));
            fromPairs = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("P: ", headers, values);

            readBack = testCase.roundTrip([1 2], Metadata=[fromStruct, fromPairs]);

            structValues = str2double(split(extractAfter(readBack.Metadata(5), "Values = ")));
            testCase.verifyEqual(structValues', values, "Values in a struct line");
            pairValues = str2double(extractAfter(split(extractAfter(readBack.Metadata(6), "P: "), " || "), " = "));
            testCase.verifyEqual(pairValues', values, "Values in a header/value pair line");
        end

        %% File names and locations
        function test_RoundTrip_AnyFileExtensionTest(testCase, FileExtension)
            data = rand(4, 3);

            readBack = testCase.roundTrip(data, Extension=FileExtension);

            testCase.verifyEqual(readBack.Data, data, "RelTol", testCase.DataTolerance);
        end

        function test_RoundTrip_FolderWithSpacesAndNonAsciiCharactersTest(testCase)
            testCase.assumeEqual(string(feature("DefaultCharacterSet")), "UTF-8");
            folder = fullfile(testCase.TempDir, "sp ace & Ω folder");
            mkdir(folder);
            writer = testCase.newWriter("acq", Directory=folder);
            writer.WriteHeaders(sprintf("a\tb"));
            writer.WriteLine([1 2]);

            readBack = testCase.read(writer);

            testCase.verifyEqual(readBack.Data, [1 2]);
        end

        %% InsertMetadataLines (used at the end of sweeps)
        function test_InsertMetadataLines_DoesNotChangeDataOrHeadersTest(testCase)
            data = rand(25, 3) * 1e3;
            writer = testCase.writeFile("sweep", data, Headers=["a" "b" "c"], Metadata="start metadata");
            before = testCase.read(writer);

            writer.InsertMetadataLines("Sweep Data at end: T = 4.2");
            after = testCase.read(writer);

            testCase.verifyEqual(after.Data, before.Data, "Data must be bit-for-bit what was read before");
            testCase.verifyEqual(after.Headers, before.Headers);
        end

        function test_InsertMetadataLines_AddsLinesAfterExistingMetadataTest(testCase)
            writer = testCase.writeFile("sweep", [1 2; 3 4], Metadata=["m1", "m2"]);

            writer.InsertMetadataLines(["end line 1", "end line 2"]);

            metadata = testCase.read(writer).Metadata;
            testCase.verifyEqual(metadata(5:end), ["m1", "m2", "end line 1", "end line 2"]);
            testCase.verifyEqual(metadata(1:4), ["<<< Palladium DAQ data file 3.0 >>>", "A description", "", "<Instrument Settings and Metadata>"]);
        end

        function test_InsertMetadataLines_RepeatedlyKeepsDataIntactTest(testCase)
            data = [1 2 3; NaN Inf -Inf; 4 5 6];
            writer = testCase.writeFile("sweep", data);

            for i = 1 : 5
                writer.InsertMetadataLines("insert " + i);
            end

            readBack = testCase.read(writer);
            testCase.verifyEqual(readBack.Data, data);
            testCase.verifyEqual(readBack.Metadata(5:end), "insert " + (1 : 5));
        end

        function test_InsertMetadataLines_WorksOnFileWithNoDataRowsTest(testCase)
            %A sweep that was aborted before taking any data
            writer = testCase.writeFile("aborted", zeros(0, 2), Headers=["a" "b"]);

            writer.InsertMetadataLines("Sweep aborted by user after 1.5 s - no data.");

            readBack = testCase.read(writer);
            testCase.verifyEqual(readBack.Metadata(5), "Sweep aborted by user after 1.5 s - no data.");
            testCase.verifyEmpty(readBack.Data);
            testCase.verifyEqual(readBack.Headers, ["a" "b"]);
        end

        function test_InsertMetadataLines_FormatCharactersAreNotInterpretedTest(testCase)
            writer = testCase.writeFile("sweep", [1 2]);
            tricky = "50% done C:\new\table %s %d";

            writer.InsertMetadataLines(tricky);

            testCase.verifyEqual(testCase.read(writer).Metadata(5), tricky);
        end

        function test_InsertMetadataLines_DataWrittenAfterwardsIsStillReadTest(testCase)
            writer = testCase.writeFile("sweep", [1 2; 3 4]);
            writer.InsertMetadataLines("inserted mid-run");

            writer.WriteLine([5 6]);

            testCase.verifyEqual(testCase.read(writer).Data, [1 2; 3 4; 5 6]);
        end

        %% Write modes
        function test_AppendMode_SecondSessionAddsRowsWithoutRepeatingHeadersTest(testCase)
            first = testCase.writeFile("acq", [1 2; 3 4], WriteMode="Append To File", Metadata="first session");
            second = testCase.writeFile("acq", [5 6; 7 8], WriteMode="Append To File", Metadata="second session");

            readBack = testCase.read(second);

            testCase.verifyEqual(second.FileWriteDetails.FilePath, first.FileWriteDetails.FilePath);
            testCase.verifyEqual(readBack.Data, [1 2; 3 4; 5 6; 7 8]);
            testCase.verifyEqual(readBack.Metadata(5:end), "first session", "Second session's headers and metadata are not written");
            testCase.verifyEqual(readBack.Headers, ["a" "b"]);
        end

        function test_IncrementMode_EachRunGetsItsOwnNumberedFileTest(testCase)
            runs = {[1 2; 3 4], [5 6; 7 8; 9 10], [11 12]};
            writers = cell(1, 3);
            for i = 1 : 3
                writers{i} = testCase.writeFile("acq", runs{i}, WriteMode="Increment File No.");
            end

            for i = 1 : 3
                expectedName = "acq-" + compose("%05d", i) + ".dat";
                testCase.verifyEqual(string(writers{i}.FileWriteDetails.FilePath), fullfile(testCase.TempDir, expectedName));
                testCase.verifyEqual(testCase.read(writers{i}).Data, runs{i}, "Run " + i);
            end
        end

        function test_OverwriteMode_SecondRunReplacesFirstCompletelyTest(testCase)
            testCase.writeFile("acq", rand(20, 3), WriteMode="Overwrite File", Metadata=["old 1", "old 2"], Headers=["x" "y" "z"]);

            second = testCase.writeFile("acq", [1 2; 3 4], WriteMode="Overwrite File", Metadata="new", Headers=["a" "b"]);

            readBack = testCase.read(second);
            testCase.verifyEqual(readBack.Data, [1 2; 3 4]);
            testCase.verifyEqual(readBack.Headers, ["a" "b"]);
            testCase.verifyEqual(readBack.Metadata(5:end), "new");
        end

        %% Reading does not modify the file
        function test_ReadFile_DoesNotModifyTheFileTest(testCase)
            writer = testCase.writeFile("acq", rand(10, 3), Metadata="metadata");
            before = fileread(writer.FileWriteDetails.FilePath);
            beforeInfo = dir(writer.FileWriteDetails.FilePath);

            testCase.read(writer);
            testCase.read(writer);

            testCase.verifyEqual(fileread(writer.FileWriteDetails.FilePath), before);
            testCase.verifyEqual(dir(writer.FileWriteDetails.FilePath).datenum, beforeInfo.datenum);
        end

        function test_ReadFile_LeavesFileFreeToDeleteTest(testCase)
            writer = testCase.writeFile("acq", [1 2; 3 4]);
            testCase.read(writer);

            delete(writer.FileWriteDetails.FilePath);

            testCase.verifyFalse(isfile(writer.FileWriteDetails.FilePath));
        end

        %% Read -> write -> read again
        function test_ReadThenRewriteGivesIdenticalFileContentsTest(testCase)
            %Once a value has been through the 15 digit text format, writing
            %it again must not change it any further
            original = rand(30, 4) .* 10 .^ randi([-6 6], 30, 4);
            first = testCase.writeFile("acq_first", original, Headers=["a" "b" "c" "d"], Metadata=["m1", "m2"], Description="copy test");
            firstRead = testCase.read(first);

            second = testCase.writeFile("acq_second", firstRead.Data, Headers=firstRead.Headers, Metadata=firstRead.Metadata(5:end), Description=firstRead.Metadata(2));
            secondRead = testCase.read(second);

            testCase.verifyEqual(secondRead.Metadata, firstRead.Metadata);
            testCase.verifyEqual(secondRead.Headers, firstRead.Headers);
            testCase.verifyEqual(secondRead.Data, firstRead.Data, "Second generation must match exactly");
            testCase.verifyEqual(testCase.normalisedFileText(second), testCase.normalisedFileText(first), "Files should be identical");
        end

        %% A complete sweep, as run by the programme
        function test_CompleteSweepFileLifecycleTest(testCase)
            %Start a file with instrument and sweep metadata, write one
            %row per step, then add the end-of-sweep data row, as
            %SweepController_Stepped does
            headers = ["Sweep Value (V)", "Keithley - Resistance_Ohms", "Keithley - Current_A", "Sample Temperature (K)"];
            instrumentSettings = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("Keithley Settings: ", struct("MeasMode", "Resistance", "SourceMode", "Current", "Range", 100));
            sweepSettings = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", struct("MinVal", -1, "MaxVal", 1, "TargetNumSteps", 21, "SettleTime", 0.5));
            startRow = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("", headers, [0 1000 1e-5 4.2]);
            endRow = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("", headers, [1 1010.5 1.1e-5 4.3]);
            sweepValues = linspace(-1, 1, 21)';
            data = [sweepValues, 1000 + 10 * sweepValues + 0.01 * randn(21, 1), 1e-5 * (1 + 0.1 * sweepValues), 4.2 + 0.005 * (1 : 21)'];

            details = testCase.makeDetails("sweep", WriteMode="Increment File No.");
            writer = Palladium.DataWriting.DataWriter(details);
            writer.ValidateFilePath();
            writer.WriteHeaders(join(headers, char(9)) + char(9), MetadataLines=["Keithley Scan - Measurement data at Scan Start:", startRow, instrumentSettings, "Sweep Parameters:", sweepSettings]);
            for i = 1 : size(data, 1)
                writer.WriteLine(data(i, :));
            end
            writer.InsertMetadataLines(["Keithley Scan - Measurement data at Scan End:", endRow]);

            readBack = testCase.read(writer);

            testCase.verifyEqual(string(writer.FileWriteDetails.FilePath), fullfile(testCase.TempDir, "sweep-00001.dat"));
            testCase.verifyEqual(readBack.Headers, headers);
            testCase.verifyEqual(readBack.Data, data, "RelTol", testCase.DataTolerance);
            testCase.verifyEqual(readBack.Metadata(5:end), ["Keithley Scan - Measurement data at Scan Start:", startRow, instrumentSettings, "Sweep Parameters:", sweepSettings, "Keithley Scan - Measurement data at Scan End:", endRow]);
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
                "SaveFile", true);
        end

        function writer = newWriter(testCase, fileName, Settings)
            arguments
                testCase;
                fileName (1,1) string;
                Settings.Directory (1,1) string = "";
                Settings.Extension (1,1) string = ".dat";
                Settings.Description (1,1) string = "A description";
                Settings.WriteMode (1,1) string = "Overwrite File";
            end

            details = testCase.makeDetails(fileName, Directory=Settings.Directory, Extension=Settings.Extension, ...
                Description=Settings.Description, WriteMode=Settings.WriteMode);
            writer = Palladium.DataWriting.DataWriter(details);
        end

        function writer = writeFile(testCase, fileName, data, Settings)
            %Write a complete data file the way Controller does:
            %ValidateFilePath, WriteHeaders, then the rows
            arguments
                testCase;
                fileName (1,1) string;
                data double;
                Settings.Headers (1,:) string = strings(1, 0);
                Settings.Metadata = [];
                Settings.Description (1,1) string = "A description";
                Settings.WriteMode (1,1) string = "Overwrite File";
                Settings.Extension (1,1) string = ".dat";
                Settings.UseWriteData (1,1) logical = false;
                Settings.TrailingTab (1,1) logical = false;
            end

            headers = Settings.Headers;
            if isempty(headers)
                headers = "col" + (1 : size(data, 2));
                if size(data, 2) == 2
                    headers = ["a" "b"];
                end
            end
            headersLine = join(headers, char(9));
            if Settings.TrailingTab
                headersLine = headersLine + char(9);
            end

            writer = testCase.newWriter(fileName, Extension=Settings.Extension, Description=Settings.Description, WriteMode=Settings.WriteMode);
            writer.ValidateFilePath();
            writer.WriteHeaders(headersLine, MetadataLines=Settings.Metadata);

            if Settings.UseWriteData
                if ~isempty(data)
                    writer.WriteData(data);
                end
            else
                for i = 1 : size(data, 1)
                    writer.WriteLine(data(i, :));
                end
            end
        end

        function readBack = roundTrip(testCase, data, Settings)
            %Write data to a new file and read it straight back
            arguments
                testCase;
                data double;
                Settings.Headers (1,:) string = strings(1, 0);
                Settings.Metadata = [];
                Settings.Description (1,1) string = "A description";
                Settings.Extension (1,1) string = ".dat";
                Settings.UseWriteData (1,1) logical = false;
                Settings.TrailingTab (1,1) logical = false;
            end

            writer = testCase.writeFile("roundtrip" + string(randi(1e9)), data, Headers=Settings.Headers, Metadata=Settings.Metadata, ...
                Description=Settings.Description, Extension=Settings.Extension, UseWriteData=Settings.UseWriteData, TrailingTab=Settings.TrailingTab);
            readBack = testCase.read(writer);
        end

        function readBack = read(~, writer)
            reader = Palladium.DataWriting.DataReader();
            [readBack.Metadata, readBack.Headers, readBack.Data] = reader.ReadFile(writer.FileWriteDetails.FilePath);
        end

        function text = normalisedFileText(~, writer)
            %File contents with line endings normalised, so files written
            %and then edited (which changes CR LF to LF) compare equal
            text = strrep(fileread(writer.FileWriteDetails.FilePath), [char(13) newline], newline);
        end

    end

end
