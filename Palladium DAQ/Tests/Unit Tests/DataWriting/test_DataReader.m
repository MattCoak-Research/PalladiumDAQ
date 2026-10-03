classdef test_DataReader < matlab.unittest.TestCase
    % TEST_DATAREADER Tests for Palladium.DataWriting.DataReader. The first
    % group read the saved example files in the data folder; the rest build
    % small files in a folder inside Testing Data Files, so each behaviour (line endings,
    % short files, NaN/Inf, odd headers..) is tested on exactly the file
    % that shows it. Writing then reading back is in test_DataWriteAndRead.
    properties
        reader;
        TempDir;
        FileName = fullfile('..', 'data', 'DataReaderTest.dat');
        NoMetaMarkerFile = fullfile('..', 'data', 'DataReaderNoMetaMarker.dat');
        NoHeaderStringFile = fullfile('..', 'data', 'DataReaderNoHeaderString.dat');
        HeaderStringSpaceFile = fullfile('..', 'data', 'DataReaderHeaderStringSpace.dat')
        expectedMetadata = ["<<< Palladium DAQ data file 3.0 >>>", "", "" "<Instrument Settings and Metadata>"];
        expectedColNames = ["Time (mins)"	"Channel A Temperature (K)"	"Channel B Temperature (K)"	"Ls331_1 Heater Power (W)"];
        expectedDataArray = [29545432.2083213	100.814723686393	100.905791937076	0.452857203366604;
                             29545432.2142851	100.913375856139	100.632359246225	0.452194659112487;
                             29545432.2159398	100.278498218867	100.546881519205	0.471543903797272;
                             29545432.2225682	100.964888535199	100.157613081678	0.471838337589614;
                             29545432.2236807	100.957166948243	100.485375648723	0.468006310549998];
    end

    methods (TestClassSetup)

        function HelpersPathSetup(testCase)
            %Test helpers, which keep everything the tests write inside Testing Data Files
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "..", "Helpers")));
        end

    end

    methods (TestMethodSetup)
        % Setup for each test
        function SetupDataReader(testCase)
            testCase.reader = Palladium.DataWriting.DataReader();
        end

        function CreateTemporaryFolder(testCase)
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            testCase.TempDir = string(fixture.Folder);
        end
    end

    methods (Test)
        function testReadFile(testCase)
            % reader = Palladium.DataWriting.DataReader();
            [headerMetadataLines, dataColNames, dataArray] = testCase.reader.ReadFile(testCase.FileName);

            % Verify metadata lines
            testCase.verifyEqual(headerMetadataLines, testCase.expectedMetadata);

            % Verify column names
            testCase.verifyEqual(dataColNames, testCase.expectedColNames);

            % Verify data array
            testCase.verifyEqual(dataArray, testCase.expectedDataArray);
        end

       function testInvalidFilename(testCase)
           verifyError(testCase, @() testCase.reader.ReadFile(''), 'DataReader:OpenFileFailure');
       end

       % Meta data marker <<< END METADATA LINES >>> is missing
       function testNoMetadataMarker(testCase)
           verifyError(testCase, @() testCase.reader.ReadFile(testCase.NoMetaMarkerFile), ...
               'DataReader:NoMetadataMarker');
       end

       % If no header string will read first row of data instead
       function testNoHeaderString(testCase)
           verifyError(testCase, @() testCase.reader.ReadFile(testCase.NoHeaderStringFile), ...
               'DataReader:NumericHeaderString');
       end

       % No header string but extra line space in file so reads empty row
       function testHeaderStringSpace(testCase)
           verifyError(testCase, @() testCase.reader.ReadFile(testCase.HeaderStringSpaceFile), ...
               'DataReader:NoHeaderString');
       end

       %% ReadFile - missing and malformed files
       function test_ReadFile_NonexistentFileErrorsTest(testCase)
           missingFile = fullfile(testCase.TempDir, "does_not_exist.dat");

           testCase.verifyError(@() testCase.reader.ReadFile(missingFile), "DataReader:OpenFileFailure");
       end

       function test_ReadFile_MarkerWithTrailingSpaceIsNotRecognisedTest(testCase)
           %The end-of-metadata line has to match exactly
           file = testCase.writeStandardFile("padded.dat", sprintf("a\tb"), "1" + char(9) + "2", EndMarker="<<< END METADATA LINES >>> ");

           testCase.verifyError(@() testCase.reader.ReadFile(file), "DataReader:NoMetadataMarker");
       end

       %% ReadFile - line endings
       function test_ReadFile_GivesSameResultForCRLFAndLFLineEndingsTest(testCase)
           rows = [sprintf("1\t2"); sprintf("3\t4")];
           crlf = testCase.writeStandardFile("crlf.dat", sprintf("a\tb"), rows, EndOfLine=string([char(13) newline]));
           lf = testCase.writeStandardFile("lf.dat", sprintf("a\tb"), rows, EndOfLine=newline);

           [mdCRLF, hCRLF, dCRLF] = testCase.reader.ReadFile(crlf);
           [mdLF, hLF, dLF] = testCase.reader.ReadFile(lf);

           testCase.verifyEqual(mdLF, mdCRLF);
           testCase.verifyEqual(hLF, hCRLF);
           testCase.verifyEqual(dLF, dCRLF);
           testCase.verifyEqual(dLF, [1 2; 3 4]);
       end

       function test_ReadFile_FileWithoutFinalLineEndingTest(testCase)
           file = testCase.writeStandardFile("noeol.dat", sprintf("a\tb"), [sprintf("1\t2"); sprintf("3\t4")], FinalEndOfLine=false);

           [~, ~, data] = testCase.reader.ReadFile(file);

           testCase.verifyEqual(data, [1 2; 3 4]);
       end

       %% ReadFile - shape of the data
       function test_ReadFile_ShortFilesAreReadCorrectlyTest(testCase)
           %Regression: with the delimiter left to be guessed, readmatrix
           %returned a column of NaN for files with only one or two rows
           for numRows = 1 : 3
               data = reshape(1 : 2 * numRows, 2, numRows)';
               rows = join(string(data), char(9), 2);
               file = testCase.writeStandardFile("short" + numRows + ".dat", sprintf("a\tb"), rows);

               [~, ~, readBack] = testCase.reader.ReadFile(file);

               testCase.verifyEqual(readBack, data, numRows + " row(s)");
           end
       end

       function test_ReadFile_NaNAndInfInFirstRowTest(testCase)
           %Regression: a first data row of NaN/Inf also broke the guessed
           %delimiter
           file = testCase.writeStandardFile("nan.dat", sprintf("a\tb\tc"), [sprintf("NaN\tInf\t-Inf"); sprintf("1\t2\t3")]);

           [~, ~, data] = testCase.reader.ReadFile(file);

           testCase.verifyEqual(data, [NaN Inf -Inf; 1 2 3]);
       end

       function test_ReadFile_NaNAndInfInLaterRowsTest(testCase)
           rows = [sprintf("1\t2\t3"); sprintf("NaN\t5\tInf"); sprintf("7\tNaN\t-Inf")];
           file = testCase.writeStandardFile("nan2.dat", sprintf("a\tb\tc"), rows);

           [~, ~, data] = testCase.reader.ReadFile(file);

           testCase.verifyEqual(data, [1 2 3; NaN 5 Inf; 7 NaN -Inf]);
       end

       function test_ReadFile_SingleColumnTest(testCase)
           file = testCase.writeStandardFile("column.dat", "only", ["5"; "6"; "7"]);

           [~, headers, data] = testCase.reader.ReadFile(file);

           testCase.verifyEqual(headers, "only");
           testCase.verifyEqual(data, [5; 6; 7]);
       end

       function test_ReadFile_HeaderOnlyFileGivesEmptyDataWithNoRowsTest(testCase)
           file = testCase.writeStandardFile("headeronly.dat", sprintf("a\tb"), strings(0, 1));

           [~, headers, data] = testCase.reader.ReadFile(file);

           testCase.verifyEqual(headers, ["a" "b"]);
           testCase.verifyEmpty(data);
       end

       function test_ReadFile_ParsesScientificNotationAndNegativeNumbersTest(testCase)
           rows = [sprintf("1.5e-3\t-2E+10"); sprintf("-0.25\t1e300")];
           file = testCase.writeStandardFile("sci.dat", sprintf("a\tb"), rows);

           [~, ~, data] = testCase.reader.ReadFile(file);

           testCase.verifyEqual(data, [1.5e-3 -2e10; -0.25 1e300]);
       end

       function test_ReadFile_WideFileTest(testCase)
           numCols = 60;
           headers = "col" + (1 : numCols);
           row = join(string(1 : numCols), char(9));
           file = testCase.writeStandardFile("wide.dat", join(headers, char(9)), [row; row]);

           [~, readHeaders, data] = testCase.reader.ReadFile(file);

           testCase.verifyEqual(readHeaders, headers);
           testCase.verifyEqual(data, repmat(1 : numCols, 2, 1));
       end

       function test_ReadFile_ManyRowsTest(testCase)
           numRows = 5000;
           values = (1 : numRows)' * [1 0.5];
           file = testCase.writeStandardFile("long.dat", sprintf("a\tb"), join(string(values), char(9), 2));

           [~, ~, data] = testCase.reader.ReadFile(file);

           testCase.verifyEqual(data, values);
       end

       %% ReadFile - metadata and headers
       function test_ReadFile_ReturnsAllMetadataLinesIncludingBlankOnesTest(testCase)
           file = testCase.writeStandardFile("meta.dat", "a", "1", Metadata=["first"; ""; "third || x = 1"; ""]);

           metadata = testCase.reader.ReadFile(file);

           testCase.verifyEqual(metadata, ["<<< Palladium DAQ data file 3.0 >>>", "A description", "", "<Instrument Settings and Metadata>", "first", "", "third || x = 1", ""]);
       end

       function test_ReadFile_DataIsCorrectWhateverTheNumberOfMetadataLinesTest(testCase)
           for numExtra = [0 1 7 200]
               metadata = "metadata line " + (1 : numExtra)';
               file = testCase.writeStandardFile("many" + numExtra + ".dat", sprintf("a\tb"), [sprintf("1\t2"); sprintf("3\t4")], Metadata=metadata);

               [readMetadata, ~, data] = testCase.reader.ReadFile(file);

               testCase.verifyEqual(data, [1 2; 3 4], numExtra + " extra metadata lines");
               testCase.verifyLength(readMetadata, 4 + numExtra);
           end
       end

       function test_ReadFile_MetadataKeepsTabsPercentSignsAndBackslashesTest(testCase)
           tricky = ["tab" + char(9) + "separated"; "50% done"; "C:\new\table %s %d"];
           file = testCase.writeStandardFile("tricky.dat", "a", "1", Metadata=tricky);

           metadata = testCase.reader.ReadFile(file);

           testCase.verifyEqual(metadata(5:7), tricky');
       end

       function test_ReadFile_HeadersKeepSpacesUnitsAndSymbolsTest(testCase)
           headers = ["Time (mins)", "Resistance (Ohms)", "dV/dI [a.u.]", "T_sample_1", "50% load"];
           file = testCase.writeStandardFile("hdr.dat", join(headers, char(9)), "1" + repmat(string(char(9)) + "1", 1, 4));

           [~, readHeaders] = testCase.reader.ReadFile(file);

           testCase.verifyEqual(readHeaders, headers);
       end

       function test_ReadFile_TrailingTabOnHeaderLineIsIgnoredTest(testCase)
           %Sweep files build their header line with a tab after every
           %header, including the last
           file = testCase.writeStandardFile("trailing.dat", sprintf("a\tb\t"), sprintf("1\t2"));

           [~, headers, data] = testCase.reader.ReadFile(file);

           testCase.verifyEqual(headers, ["a" "b"]);
           testCase.verifyEqual(data, [1 2]);
       end

       %% ReadHeadersFromFile
       function test_ReadHeadersFromFile_ReturnsHeadersMetadataAndLineCountTest(testCase)
           [headers, metadata, numHeaderLines] = testCase.reader.ReadHeadersFromFile(testCase.FileName);

           testCase.verifyEqual(headers, testCase.expectedColNames);
           testCase.verifyEqual(metadata, testCase.expectedMetadata);
           testCase.verifyEqual(numHeaderLines, 7, "4 metadata lines + end marker + blank line + headers line");
       end

       function test_ReadHeadersFromFile_LineCountGrowsWithMetadataLinesTest(testCase)
           for numExtra = [0 1 10]
               file = testCase.writeStandardFile("count" + numExtra + ".dat", "a", "1", Metadata="m" + (1 : numExtra)');

               [~, ~, numHeaderLines] = testCase.reader.ReadHeadersFromFile(file);

               testCase.verifyEqual(numHeaderLines, 7 + numExtra);
           end
       end

       function test_ReadHeadersFromFile_DoesNotNeedAnyDataTest(testCase)
           file = testCase.writeStandardFile("nodata.dat", sprintf("a\tb"), strings(0, 1));

           headers = testCase.reader.ReadHeadersFromFile(file);

           testCase.verifyEqual(headers, ["a" "b"]);
       end

       function test_ReadHeadersFromFile_MissingFileErrorsTest(testCase)
           testCase.verifyError(@() testCase.reader.ReadHeadersFromFile(fullfile(testCase.TempDir, "nope.dat")), "DataReader:OpenFileFailure");
       end

       function test_ReadHeadersFromFile_LeavesNoFileOpenTest(testCase)
           file = testCase.writeStandardFile("closed.dat", "a", "1");
           openBefore = testCase.openFileIds();

           testCase.reader.ReadHeadersFromFile(file);

           testCase.verifyEqual(testCase.openFileIds(), openBefore);
       end

       function test_ReadFile_ErrorsLeaveNoFileOpenTest(testCase)
           %A file that fails the checks must not stay open (it would be
           %locked on Windows, so it couldn't be moved or deleted)
           badFiles = {testCase.NoMetaMarkerFile, testCase.NoHeaderStringFile, testCase.HeaderStringSpaceFile};
           openBefore = testCase.openFileIds();

           for i = 1 : numel(badFiles)
               try
                   testCase.reader.ReadFile(badFiles{i});
               catch
               end
           end

           testCase.verifyEqual(testCase.openFileIds(), openBefore);
       end

       %% ReadHeadersLine (static)
       function test_ReadHeadersLine_SplitsOnTabsTest(testCase)
           fid = testCase.openTextFile(sprintf("Time (s)\tTemp (K)\tField"));

           headers = Palladium.DataWriting.DataReader.ReadHeadersLine(fid);

           testCase.verifyEqual(headers, ["Time (s)" "Temp (K)" "Field"]);
       end

       function test_ReadHeadersLine_SkipsEmptyFieldsTest(testCase)
           fid = testCase.openTextFile(sprintf("a\t\tb\t"));

           headers = Palladium.DataWriting.DataReader.ReadHeadersLine(fid);

           testCase.verifyEqual(headers, ["a" "b"]);
       end

       function test_ReadHeadersLine_NumericHeaderErrorsTest(testCase)
           fid = testCase.openTextFile(sprintf("a\t5\tb"));

           testCase.verifyError(@() Palladium.DataWriting.DataReader.ReadHeadersLine(fid), "DataReader:NumericHeaderString");
       end

       function test_ReadHeadersLine_EmptyLineErrorsTest(testCase)
           fid = testCase.openTextFile("");

           testCase.verifyError(@() Palladium.DataWriting.DataReader.ReadHeadersLine(fid), "DataReader:NoHeaderString");
       end

       function test_ReadHeadersLine_OnlyTabsErrorsTest(testCase)
           fid = testCase.openTextFile(sprintf("\t\t"));

           testCase.verifyError(@() Palladium.DataWriting.DataReader.ReadHeadersLine(fid), "DataReader:NoHeaderString");
       end

       function test_ReadHeadersLine_ReadsOnlyOneLineTest(testCase)
           fid = testCase.openTextFile(["first\tline"; "second line"]);

           Palladium.DataWriting.DataReader.ReadHeadersLine(fid);

           testCase.verifyEqual(string(fgetl(fid)), "second line");
       end

       %% ScanFileForMetadataRows (static)
       function test_ScanFileForMetadataRows_ReturnsLinesBeforeMarkerAndMarkerRowNumberTest(testCase)
           fid = testCase.openTextFile(["one"; "two"; "<<< END METADATA LINES >>>"; "after"]);

           [rowNo, metadata] = Palladium.DataWriting.DataReader.ScanFileForMetadataRows(fid, "<<< END METADATA LINES >>>");

           testCase.verifyEqual(metadata, ["one" "two"]);
           testCase.verifyEqual(rowNo, 3, "Row number of the end marker");
       end

       function test_ScanFileForMetadataRows_MarkerOnFirstLineGivesNoMetadataTest(testCase)
           fid = testCase.openTextFile(["<<< END METADATA LINES >>>"; "after"]);

           [rowNo, metadata] = Palladium.DataWriting.DataReader.ScanFileForMetadataRows(fid, "<<< END METADATA LINES >>>");

           testCase.verifyEmpty(metadata);
           testCase.verifyEqual(rowNo, 1);
       end

       function test_ScanFileForMetadataRows_StopsReadingAtMarkerTest(testCase)
           fid = testCase.openTextFile(["one"; "<<< END METADATA LINES >>>"; "after"]);

           Palladium.DataWriting.DataReader.ScanFileForMetadataRows(fid, "<<< END METADATA LINES >>>");

           testCase.verifyEqual(string(fgetl(fid)), "after");
       end

       function test_ScanFileForMetadataRows_NoMarkerErrorsTest(testCase)
           fid = testCase.openTextFile(["one"; "two"]);

           testCase.verifyError(@() Palladium.DataWriting.DataReader.ScanFileForMetadataRows(fid, "<<< END METADATA LINES >>>"), "DataReader:NoMetadataMarker");
       end

       function test_ScanFileForMetadataRows_EmptyFileErrorsTest(testCase)
           fid = testCase.openTextFile(strings(0, 1));

           testCase.verifyError(@() Palladium.DataWriting.DataReader.ScanFileForMetadataRows(fid, "<<< END METADATA LINES >>>"), "DataReader:NoMetadataMarker");
       end

       %% ReadDataArray (static)
       function test_ReadDataArray_SkipsGivenNumberOfHeaderLinesTest(testCase)
           file = testCase.writeRawFile("raw.dat", ["junk"; "more junk"; sprintf("1\t2"); sprintf("3\t4")]);

           data = Palladium.DataWriting.DataReader.ReadDataArray(file, 2);

           testCase.verifyEqual(data, [1 2; 3 4]);
       end

       function test_ReadDataArray_ReturnsDoubleTest(testCase)
           file = testCase.writeRawFile("int.dat", [sprintf("1\t2"); sprintf("3\t4")]);

           data = Palladium.DataWriting.DataReader.ReadDataArray(file, 0);

           testCase.verifyClass(data, "double");
       end

       function test_ReadDataArray_ReadsTabDelimitedDataWhateverItsShapeTest(testCase)
           %One and two row files, with and without NaN/Inf
           cases = {[1 2 3], [1 2; 3 4], [NaN Inf -Inf], [NaN Inf -Inf; 1 2 3], [5; 6]};
           for i = 1 : numel(cases)
               expected = cases{i};
               file = testCase.writeRawFile("shape" + i + ".dat", ["header"; join(compose("%g", expected), char(9), 2)]);

               data = Palladium.DataWriting.DataReader.ReadDataArray(file, 1);

               testCase.verifyEqual(data, expected, "case " + i);
           end
       end

       function test_ReadDataArray_NoRowsAfterHeaderGivesEmptyTest(testCase)
           file = testCase.writeRawFile("empty.dat", "header");

           data = Palladium.DataWriting.DataReader.ReadDataArray(file, 1);

           testCase.verifyEmpty(data);
       end

    end

    %% Methods (Private)
    methods (Access = private)

        function path = writeRawFile(testCase, fileName, lines, Settings)
            %Write lines to a file in the temporary folder, exactly as given
            arguments
                testCase;
                fileName (1,1) string;
                lines (:,1) string;
                Settings.EndOfLine (1,1) string = newline;
                Settings.FinalEndOfLine (1,1) logical = true;
            end

            path = fullfile(testCase.TempDir, fileName);
            text = strjoin(lines, Settings.EndOfLine);
            if Settings.FinalEndOfLine && ~isempty(lines)
                text = text + Settings.EndOfLine;
            end

            fid = fopen(path, "w");
            fwrite(fid, char(text), "char");
            fclose(fid);
        end

        function path = writeStandardFile(testCase, fileName, headersLine, dataLines, Settings)
            %Write a file laid out like a Palladium data file: file info,
            %description, blank line, "Instrument Settings" line, any extra
            %metadata, end marker, blank line, headers line, then the data
            arguments
                testCase;
                fileName (1,1) string;
                headersLine (1,1) string;
                dataLines (:,1) string;
                Settings.Metadata (:,1) string = strings(0, 1);
                Settings.EndMarker (1,1) string = "<<< END METADATA LINES >>>";
                Settings.EndOfLine (1,1) string = newline;
                Settings.FinalEndOfLine (1,1) logical = true;
            end

            lines = [ ...
                "<<< Palladium DAQ data file 3.0 >>>"
                "A description"
                ""
                "<Instrument Settings and Metadata>"
                Settings.Metadata
                Settings.EndMarker
                ""
                headersLine
                dataLines];

            path = testCase.writeRawFile(fileName, lines, EndOfLine=Settings.EndOfLine, FinalEndOfLine=Settings.FinalEndOfLine);
        end

        function ids = openFileIds(~)
            %Identifiers of all files currently open. openedFiles replaces
            %the deprecated fopen('all') in newer releases
            if ~isempty(which("openedFiles"))
                ids = openedFiles();
            else
                ids = fopen('all');
            end
        end

        function fid = openTextFile(testCase, lines)
            %Open a small text file for reading, closed again at the end of the test
            path = testCase.writeRawFile("scratch" + string(randi(1e9)) + ".txt", string(lines(:)));
            fid = fopen(path, "r");
            testCase.addTeardown(@() fclose(fid));
        end

    end

end
