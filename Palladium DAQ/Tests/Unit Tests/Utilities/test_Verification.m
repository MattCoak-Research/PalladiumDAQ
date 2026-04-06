classdef test_Verification < matlab.unittest.TestCase
    % VERIFICATION Tests for Palladium utilities functions - Verification
    % static class

    %% TestClassSetup
    methods (TestClassSetup)
        % Shared setup for the entire test class
    end

    %% TestMethodSetup
    methods (TestMethodSetup)
        % Setup for each test
    end

    %% Tests
    methods (Test) % Test methods

        %% CheckForDuplicatesInCellArrayOfStrings
        function test_CheckForDuplicatesInCellArrayOfStrings(testCase)
            cellArray = {"apple", "banana", "apple", "orange", "banana"};
            expectedDuplicates = ["apple", "banana"];
            expectedCombinedString = "apple, banana";

            [actualDuplicates, actualCombinedString] = Palladium.Utilities.Verification.CheckForDuplicatesInCellArrayOfStrings(cellArray);

            testCase.verifyEqual(actualDuplicates, expectedDuplicates);
            testCase.verifyEqual(actualCombinedString, expectedCombinedString);
        end

        function test_CheckForDuplicatesInCellArrayOfStrings_CharInputs(testCase)
            cellArray = {'apple', 'banana', 'apple', 'orange', 'banana'};
            expectedDuplicates = ["apple", "banana"];
            expectedCombinedString = "apple, banana";

            [actualDuplicates, actualCombinedString] = Palladium.Utilities.Verification.CheckForDuplicatesInCellArrayOfStrings(cellArray);

            testCase.verifyEqual(actualDuplicates, expectedDuplicates);
            testCase.verifyEqual(actualCombinedString, expectedCombinedString);
        end

        function test_CheckForDuplicatesInCellArrayOfStrings_NoDuplicatesInInput(testCase)
            cellArray = {"apple", "banana", "orange", };
            expectedCombinedString = "";

            [actualDuplicates, actualCombinedString] = Palladium.Utilities.Verification.CheckForDuplicatesInCellArrayOfStrings(cellArray);

            testCase.verifyEmpty(actualDuplicates);
            testCase.verifyEqual(actualCombinedString, expectedCombinedString);
        end

        function test_CheckForDuplicatesInCellArrayOfStrings_EmptyInput(testCase)
            cellArray = {"apple", "banana", "orange", };
            expectedCombinedString = "";

            [actualDuplicates, actualCombinedString] = Palladium.Utilities.Verification.CheckForDuplicatesInCellArrayOfStrings(cellArray);

            testCase.verifyEmpty(actualDuplicates);
            testCase.verifyEqual(actualCombinedString, expectedCombinedString);
        end


        %% CheckForDuplicatesInHeadersArray
        function test_CheckForDuplicatesInHeadersArray(testCase)
            headers = {'Header1', 'Header2', 'Header1', 'Header3', 'Header2'};
            expectedDuplicates = {'Header1', 'Header2'};
            expectedCombinedString = "Header1, Header2";

            [actualDuplicates, actualCombinedString] = Palladium.Utilities.Verification.CheckForDuplicatesInHeadersArray(headers);

            testCase.verifyEqual(sort(actualDuplicates), sort(expectedDuplicates));
            testCase.verifyEqual(actualCombinedString, expectedCombinedString);
        end

        %% ValidateInstall
        function test_ValidateInstallWithValidSettings(testCase)
            matlabVersion = "R2025b";
            toolboxNames = {"Instrument Control Toolbox"};

            % Assuming the toolbox is installed and version is valid
            testCase.verifyWarningFree(@() Palladium.Utilities.Verification.ValidateInstall(MatlabVersion=matlabVersion, ToolboxNames=toolboxNames));
        end

        %% VerifyToolboxInstalled
        function test_VerifyToolboxInstalledNotFound(testCase)
            testCase.verifyError(@() Palladium.Utilities.Verification.VerifyToolboxInstalled("NonExistentToolbox"), "VerifyToolboxError:ToolboxNotInstalled");
        end
    end

end