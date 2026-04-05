classdef testProgramLaunch < matlab.uitest.TestCase
% TEST_PROGRAMMELAUNCH Tests for Palladium 
%
% 
    properties
        ConfigPath;
    end
    
    methods (TestClassSetup)
        % Shared setup for the entire test class
        function configPathSetup(testCase)
            % Set up shared state for all tests.
            testCase.ConfigPath = fullfile("..","Palladium DAQ", "Tests", "TestingConfig.json");
            end
    end

    methods (TestClassTeardown)
        % Remove folder created during test
        function TeardownFiles(~)
            path = fullfile( '..','Palladium DAQ - Testing');
            rmdir(path, 's');
        end
    end

    methods (TestMethodSetup)
        % Setup for each test
    end

    methods (Test)
        % Test methods
       
        function LaunchEmpty(testCase)
            % Test that view and controller have been created
            % Creates default view
            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
            verifyNotEmpty(testCase, pd.View);
            verifyNotEmpty(testCase, pd.Controller);
            drawnow();
            pd.Close();
        end
        
        function LaunchEmptyNoView(testCase)
            % Check that no view has been created
            pd = Palladium(ConfigFilePath=testCase.ConfigPath, View=[]);
            verifyEmpty(testCase, pd.View);
            verifyNotEmpty(testCase, pd.Controller);
            pd.Close();      
        end

        function TestMeasurementLoop(testCase)
            % Test that view and controller have been created
            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
            verifyNotEmpty(testCase, pd.View);
            verifyNotEmpty(testCase, pd.Controller);
            drawnow();

            %pd.Start();
            % The following 2 lines are commented until find solution to UI
            % control access
           % testCase.press(pd.View.StateControlPanel.StartButton);
           % verifyEqual(testCase, pd.Controller.TimingLoopController.State, "Running");
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