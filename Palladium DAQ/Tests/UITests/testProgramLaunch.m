classdef testProgramLaunch < matlab.uitest.TestCase
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
            % Test that view and controller have been created
            % Creates default view
            pd = Palladium();
            verifyNotEmpty(testCase, pd.View);
            verifyNotEmpty(testCase, pd.Controller);
            pd.Close();
        end
        
        function LaunchEmptyNoView(testCase)
            % Check that no view has been created
            pd = Palladium(View=[]);
            verifyEmpty(testCase, pd.View);
            verifyNotEmpty(testCase, pd.Controller);
            pd.Close();      
        end

        function TestMeasurementLoop(testCase)
            % Test that view and controller have been created
            pd = Palladium();
            verifyNotEmpty(testCase, pd.View);
            verifyNotEmpty(testCase, pd.Controller);

            %pd.Start();
            testCase.press(pd.View.StateControlPanel.StartButton);
            verifyEqual(testCase, pd.Controller.TimingLoopController.State, "Running");
            % pause(0.2);  % Calls from Matt's original code - trying to
                            % replace with uitest calls
            % pd.Pause();
            % pause(0.2);
            % pd.Resume();
            % pause(0.2);
            % pd.Stop();
            pd.Close();
        end
    end

end