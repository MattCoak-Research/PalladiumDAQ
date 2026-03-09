classdef testDataReader < matlab.unittest.TestCase
    properties
        reader;
        FileName = fullfile('data', 'DataReaderTest.dat');
        expectedMetadata = ["<<< CoakView data file 3.0 >>>", "", "" "<Instrument Settings and Metadata>"];
        expectedColNames = ["Time (mins)"	"Channel A Temperature (K)"	"Channel B Temperature (K)"	"Ls331_1 Heater Power (W)"];
        expectedDataArray = [29545432.2083213	100.814723686393	100.905791937076	0.452857203366604;
                             29545432.2142851	100.913375856139	100.632359246225	0.452194659112487;
                             29545432.2159398	100.278498218867	100.546881519205	0.471543903797272;
                             29545432.2225682	100.964888535199	100.157613081678	0.471838337589614;
                             29545432.2236807	100.957166948243	100.485375648723	0.468006310549998];
    end

    methods (TestClassSetup)
        
    end

    methods (TestMethodSetup)
        % Setup for each test
        function SetupDataReader(testCase)
            testCase.reader = CoakView.DataWriting.DataReader();
        end
    end

    methods (Test)
        function testReadFile(testCase)
            % reader = CoakView.DataWriting.DataReader();
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
    end

end