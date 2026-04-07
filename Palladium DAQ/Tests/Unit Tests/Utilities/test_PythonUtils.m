classdef test_PythonUtils < matlab.unittest.TestCase
    % TEST_PythonUTILS Tests for Palladium utilities functions - PythonUtils
    % static class

    %% Properties
    properties
        TempDir = fullfile("..", "data", "Python Testing");
    end

    %% Tests
    methods (Test)

        %% AppendFolderToPythonPath
        function test_AppendFolderToPythonPath(testCase)
            % Test to verify that a directory is appended to the Python path

            % Call the method to append the directory to the Python path
            Palladium.Utilities.PythonUtils.AppendFolderToPythonPath(testCase.TempDir);

            % Verify that the directory is in the Python path by running
            % the little Python test function saved in there
            inputVal = 12;
            expectedVal = 120;
            val = py.pythontest.foo(inputVal);
            
            %Test code file just multiplies input by 10 - expect 120 as the output
            convertedVal = double(val);
            testCase.verifyEqual(convertedVal, expectedVal);
        end

    end

end