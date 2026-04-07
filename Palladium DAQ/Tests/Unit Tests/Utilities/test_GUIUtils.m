classdef test_GUIUtils < matlab.unittest.TestCase
    % TEST_GUIUTILS Tests for Palladium utilities functions - GUIUtils
    % static class

    %% Properties
    properties
         TestingDir = fullfile("..", "data", "GUIUtils Testing");
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)

        function PathSetup(testCase)% Shared setup for the entire test class
            % Set up shared state for all tests.
            % Add PluginLoading Testing folder to the Path temporarily
            %Because we're using this fixture tooling, it will get
            %automatically removed on test completion
            import matlab.unittest.fixtures.PathFixture
            import matlab.unittest.constraints.ContainsSubstring
            f = testCase.applyFixture(PathFixture(testCase.TestingDir, IncludeSubfolders=true));
            testCase.verifyThat(path,ContainsSubstring(f.Folders(1)));
        end

    end

    %% Tests
    methods (Test)

        %% ComputePropertyList
        function test_ComputePropertyList_WithEmptyInstrument(testCase)
            instrument = [];
            exposeSubClassProperties = true;
            expectedPropertyList = [];

            actualPropertyList = Palladium.Utilities.GUIUtils.ComputePropertyList(instrument, exposeSubClassProperties);

            testCase.verifyEqual(actualPropertyList, expectedPropertyList);
        end

        function test_ComputePropertyList_WithInstrument(testCase)
            instrument = GUIUtilsTestingInstruments.TestInstrument();
            exposeSubClassProperties = true;
            expectedPropertyList = [...
                "Name";...
                "Connection_Type";...
                "TestProperty"];

            actualPropertyList = Palladium.Utilities.GUIUtils.ComputePropertyList(instrument, exposeSubClassProperties);

            testCase.verifyEqual(actualPropertyList, expectedPropertyList);
        end

        %% IsPropertyValidToUse
        function test_IsPropertyValidToUse_WithValidName(testCase)
            propName = 'validPropertyName';
            expectedResult = true;

            actualResult = Palladium.Utilities.GUIUtils.IsPropertyValidToUse(propName);

            testCase.verifyEqual(actualResult, expectedResult);
        end

        function testIsPropertyValidToUse_WithInvalidName(testCase)
            propName = '1invalidPropertyName';
            expectedResult = false;

            actualResult = Palladium.Utilities.GUIUtils.IsPropertyValidToUse(propName);

            testCase.verifyEqual(actualResult, expectedResult);
        end

        %% ToDoubleArrayFromScalarString
        function test_ToDoubleArrayFromScalarString_WithValidInput(testCase)
            str = "200 300 400";
            expectedArray = [200, 300, 400];
            expectedSuccess = true;

            [actualArray, actualSuccess] = Palladium.Utilities.GUIUtils.ToDoubleArrayFromScalarString(str);

            testCase.verifyEqual(actualArray, expectedArray);
            testCase.verifyEqual(actualSuccess, expectedSuccess);
        end

        function test_ToDoubleArrayFromScalarString_WithInvalidInput(testCase)
            str = '200 300 invalid';
            expectedArray = str;
            expectedSuccess = false;

            [actualArray, actualSuccess] = Palladium.Utilities.GUIUtils.ToDoubleArrayFromScalarString(str);

            testCase.verifyEqual(actualArray, expectedArray);
            testCase.verifyEqual(actualSuccess, expectedSuccess);
        end

        %% ToScalarString
        function test_ToScalarString_WithNumericVector(testCase)
            value = [1, 2, 3];
            expectedString = "1 2 3";

            actualString = Palladium.Utilities.GUIUtils.ToScalarString(value);

            testCase.verifyEqual(actualString, expectedString);
        end

        function test_ToScalarString_WithScalarValue(testCase)
            value = 42;
            expectedString = "42";

            actualString = Palladium.Utilities.GUIUtils.ToScalarString(value);

            testCase.verifyEqual(actualString, expectedString);
        end

        function test_ToScalarString_WithInvalidInput(testCase)
            value = rand(2, 2); % High-dimensional array
            testCase.verifyError(@() Palladium.Utilities.GUIUtils.ToScalarString(value), "ToScalarStringError:HighDimensionalArray");
        end

    end

end