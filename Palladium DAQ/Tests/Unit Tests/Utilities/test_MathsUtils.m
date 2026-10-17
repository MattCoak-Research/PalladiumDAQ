classdef test_MathsUtils < matlab.unittest.TestCase
    % TEST_MATHSUTILS Tests for Palladium utilities functions - MathsUtils
    % static class

    %% Tests
    methods (Test)

        %% ConvertExponentToSIPrefix
        function test_ConvertExponentToSIPrefix_CorrectOutputTest(testCase)
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-30), 'q');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-27), 'r');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-24), 'y');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-21), 'z');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-18), 'a');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-15), 'f');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-12), 'p');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-9), 'n');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-6), '$\mu$');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-3), 'm');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(0), '');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(3), 'k');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(6), 'M');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(9), 'G');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(12), 'T');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(15), 'P');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(18), 'E');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(21), 'Z');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(24), 'Y');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(27), 'R');
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(30), 'Q');
        end

        function test_ConvertExponentToSIPrefix_InvalidPrefixTest(testCase)
            %Gives '' and a logged warning - not a MATLAB warning, which the
            %standalone app shows as an error box
            testCase.logWarningsToCommandWindow();
            prefix = [];
            output = "";
            testCase.verifyWarningFree(@() convert());
            testCase.verifyEqual(prefix, '');
            testCase.verifySubstring(output, "Cannot convert value to SI prefix");

            function convert()
                output = evalc("prefix = Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-10)");
            end
        end

    end

    %% Methods (Private)
    methods (Access = private)
        function logWarningsToCommandWindow(testCase)
            %Set the (shared, persistent) Logger to print warnings to the
            %Command Window, where evalc can see them, and nowhere else -
            %other tests may have turned it off
            Palladium.Logging.Logger.Log("Debug", "Logging to the Command Window for test", "Controller", true, ...
                "LogFileDirectory", "", "LogFileFileName", "", ...
                "CommandWindowMessageLevel", "Warning", "GUIMessageLevel", "Off", "LogFileMessageLevel", "Off");
            testCase.addTeardown(@() Palladium.Logging.Logger.Log("Debug", "Logging stopped", "Controller", true, ...
                "LogFileDirectory", "", "LogFileFileName", "", ...
                "CommandWindowMessageLevel", "Off", "GUIMessageLevel", "Off", "LogFileMessageLevel", "Off"));
        end
    end

end