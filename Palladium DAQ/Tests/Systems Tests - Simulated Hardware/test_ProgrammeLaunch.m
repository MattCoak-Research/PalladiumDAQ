classdef test_ProgrammeLaunch < matlab.unittest.TestCase
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
            % Warning doesn't seem to generate identifier so can't test for
            % that
            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
            pd.Close();
        end

        function LaunchEmptyNoView(testCase)
            % Warning doesn't seem to generate identifier so can't test for
            % that
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            pd.Close();
        end

        function TestMeasurementLoop(testCase)
            % Warning doesn't seem to generate identifier so can't test for
            % that
            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
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