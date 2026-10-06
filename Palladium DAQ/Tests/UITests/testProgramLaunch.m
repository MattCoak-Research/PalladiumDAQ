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
            %Palladium writes its data files, sequences and logs to the
            %Data, Sequences and Logs folders in Testing Data Files (see
            %TestingConfig.json). The fixture removes them again afterwards.
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "Helpers")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
            testCase.ConfigPath = fullfile("Tests", "TestingConfig.json");   %Relative to the Palladium.m folder
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
            verifyTrue(testCase, pd.Controller.HasGUIWindow());     %The standalone app then keeps logged errors off stderr (no Windows error box)
            pd.Close();
        end

        function LoggerReachesGUI(testCase)
            %The Logger is given the Controller, so its warnings and errors
            %show in the status bar, and it knows a window is open (so the
            %standalone app keeps them off stderr - no Windows error box).
            %It used to never get the Controller, and did neither
            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
            c = onCleanup(@() pd.Close());
            drawnow();
            verifyTrue(testCase, pd.Controller.HasGUIWindow());

            %Record the yellow status message sent to the GUI
            setappdata(groot, "LoggerReachesGUI", "");
            listener = event.listener(pd.Controller, "YellowStatus", @(~, e) setappdata(groot, "LoggerReachesGUI", string(e.Message)));
            Palladium.Logging.Logger.Log("Warning", "Logger test warning");
            delete(listener);
            verifyEqual(testCase, getappdata(groot, "LoggerReachesGUI"), "Logger test warning", "The Logger's warning did not reach the GUI");
            rmappdata(groot, "LoggerReachesGUI");
        end
        
        function LaunchEmptyNoView(testCase)
            % Check that no view has been created
            pd = Palladium(ConfigFilePath=testCase.ConfigPath, View=[]);
            verifyEmpty(testCase, pd.View);
            verifyNotEmpty(testCase, pd.Controller);
            verifyFalse(testCase, pd.Controller.HasGUIWindow());
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