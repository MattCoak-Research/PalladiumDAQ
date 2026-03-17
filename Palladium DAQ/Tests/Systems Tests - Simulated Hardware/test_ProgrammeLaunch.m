classdef test_ProgrammeLaunch < matlab.unittest.TestCase
% TEST_PROGRAMMELAUNCH Tests for Palladium 
%
% 

    methods (TestClassSetup)
        % Shared setup for the entire test class
    end

    methods (TestMethodSetup)
        % Setup for each test
    end

    methods (Test)
        % Test methods
       
        function LaunchEmpty(testCase)
            % Warning doesn't seem to generate identifier so can't test for
            % that
            pd = Palladium();
            pd.Close();
        end
        
        function LaunchEmptyNoView(testCase)
            % Warning doesn't seem to generate identifier so can't test for
            % that
            pd = Palladium(View=[]);
            pd.Close();      
        end

        function TestMeasurementLoop(testCase)
            % Warning doesn't seem to generate identifier so can't test for
            % that
            pd = Palladium();
            pd.Start();
            pause(0.2);
            pd.Pause();
            pause(0.2);
            pd.Resume();
            pause(0.2);
            pd.Stop();
            pd.Close();
        end
    end

end