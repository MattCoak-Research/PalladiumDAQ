classdef testUtilities < matlab.unittest.TestCase
% TESTUTILITIES Tests for Palladium utilities functions
%
% Currently tests only MathsUtils

    methods (TestClassSetup)
        % Shared setup for the entire test class
    end

    methods (TestMethodSetup)
        % Setup for each test
    end

    methods (Test)
        % Test methods

        function MathsUtilsCorrectOutputTest(testCase)
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

        function MathsUtilsInvalidPrefixTest(testCase)
            % Warning doesn't seem to generate identifier so can't test for
            % that
            testCase.verifyEqual(Palladium.Utilities.MathsUtils.ConvertExponentToSIPrefix(-10), '');
        
        end
            
    end

end