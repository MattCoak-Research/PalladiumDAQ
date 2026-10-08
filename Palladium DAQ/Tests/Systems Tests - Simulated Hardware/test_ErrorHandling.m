classdef test_ErrorHandling < matlab.unittest.TestCase
    % TEST_ERRORHANDLING Tests that errors reach the status light only when they should.
    % An error in a window that does not interact with the measurement loop
    % (a Standalone error, e.g. in the Data Viewer) is logged, but must not
    % turn the main window's status light red.
    %
    % The error dialogues themselves are modal and are not tested here.

    properties
        ConfigPath;
    end

    methods (TestClassSetup)
        function configPathSetup(testCase)
            %Palladium.m is two folders up. The project puts it on the path
            %for tests registered in it, but not for a newly added test
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "..")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "Helpers")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
            testCase.ConfigPath = fullfile("Tests", "TestingConfig.json");   %Relative to the Palladium.m folder
        end
    end

    methods (Test)

        function LoggedErrorTurnsStatusLightRed(testCase)
            [pd, redCount] = testCase.launchCountingRedStatus();
            testCase.addTeardown(@() pd.Close());

            Palladium.Logging.Logger.LogError(MException("Test:Boom", "boom"), "Normal error");

            testCase.verifyEqual(redCount(), 1);
        end

        function StandaloneLoggedErrorLeavesStatusLightAlone(testCase)
            [pd, redCount] = testCase.launchCountingRedStatus();
            testCase.addTeardown(@() pd.Close());

            Palladium.Logging.Logger.LogError(MException("Test:Boom", "boom"), "Standalone error", SkipGUI = true);

            testCase.verifyEqual(redCount(), 0);
        end

    end

    methods (Access = private)

        function [pd, redCount] = launchCountingRedStatus(testCase)
            %Launch Palladium with no view, and return a function that gives
            %how many times the Controller has fired its RedStatus event
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            %A containers.Map is a handle, so the listener and the returned
            %function share one counter (a plain variable would be copied
            %into the function handle at the moment it is created)
            counter = containers.Map({'red'}, {0});
            ltr = addlistener(pd.Controller, "RedStatus", @(~,~) increment());
            testCase.addTeardown(@() delete(ltr));
            redCount = @() counter('red');

            function increment()
                counter('red') = counter('red') + 1;
            end
        end

    end
end
