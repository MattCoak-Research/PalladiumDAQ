classdef testUtilities < matlab.unittest.TestCase
% TESTUTILITIES Tests for CoakView utilities functions
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
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(-30), 'q');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(-27), 'r');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(-24), 'y');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(-21), 'z');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(-18), 'a');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(-15), 'f');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(-12), 'p');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(-9), 'n');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(-6), '$\mu$');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(-3), 'm');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(0), '');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(3), 'k');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(6), 'M');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(9), 'G');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(12), 'T');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(15), 'P');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(18), 'E');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(21), 'Z');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(24), 'Y');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(27), 'R');
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(30), 'Q');
        end

        function MathsUtilsInvalidPrefixTest(testCase)
            % Warning doesn't seem to generate identifier so can't test for
            % that
            testCase.verifyEqual(CoakView.Utilities.Maths.MathsUtils.ConvertExponentToSIPrefix(-10), '');
        
        end
            
    end

end