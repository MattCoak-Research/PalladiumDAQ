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
            expectedWarningID = "MathsUtilsWarning:InvalidExponent";
            %Note this actually stops the warning being printed in the console, which
            %is nice - it means when we see a warning while testing it is unexpected
            testCase.verifyWarning(@() testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-10), ''), expectedWarningID);
        end

    end

end