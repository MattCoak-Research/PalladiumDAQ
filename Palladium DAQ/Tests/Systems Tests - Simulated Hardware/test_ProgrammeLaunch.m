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

        function PauseThenResume(testCase)
            %Pause stops the timer and raises Paused; Resume restarts it
            %and raises Resumed, once each. Resume used to start the
            %timer twice ("already running" error) and never raise Resumed
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            pd.SetUpdateTime(0.1);
            tlc = pd.Controller.TimingLoopController;

            %Count the events
            setappdata(groot, "PauseThenResume", [0 0]);
            testCase.addTeardown(@() rmappdata(groot, "PauseThenResume"));
            count = @(i) setappdata(groot, "PauseThenResume", getappdata(groot, "PauseThenResume") + (1:2 == i));
            l1 = addlistener(tlc, "Paused", @(~, ~) count(1));
            l2 = addlistener(tlc, "Resumed", @(~, ~) count(2));
            testCase.addTeardown(@() delete([l1, l2]));

            pd.Start();
            pause(0.5);
            pd.Pause();
            pause(0.5);
            testCase.verifyEqual(string(tlc.State), "Paused");

            testCase.verifyWarningFree(@() pd.Resume());
            pause(0.5);
            testCase.verifyEqual(string(tlc.State), "Running");
            testCase.verifyEqual(getappdata(groot, "PauseThenResume"), [1 1], "Paused and Resumed should each be raised once");

            pd.Stop();
            pause(0.5);
        end

        function StateChangesThatDontApplyWarn(testCase)
            %Start, Pause, Resume and Stop warn and do nothing when they
            %don't apply in the current state - e.g. Start while running
            %used to reconnect everything and start a new data file
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            pd.SetUpdateTime(0.1);
            tlc = pd.Controller.TimingLoopController;

            %Record the status strip's yellow (warning) messages
            setappdata(groot, "StateChangeWarnings", strings(0));
            testCase.addTeardown(@() rmappdata(groot, "StateChangeWarnings"));
            lst = addlistener(pd.Controller, "YellowStatus", @(~, e) setappdata(groot, "StateChangeWarnings", [getappdata(groot, "StateChangeWarnings"), string(e.Message)]));
            testCase.addTeardown(@() delete(lst));
            lastWarning = @() testCase.lastOf(getappdata(groot, "StateChangeWarnings"));

            %Ready: Pause, Resume and Stop don't apply
            pd.Pause();
            testCase.verifyEqual(lastWarning(), "Cannot pause - measurements are not running");
            pd.Resume();
            testCase.verifyEqual(lastWarning(), "Cannot resume - measurements have not been started - use Start");
            pd.Stop();
            testCase.verifyEqual(lastWarning(), "Cannot stop - measurements are already stopped");
            testCase.verifyEqual(string(tlc.State), "Ready");

            %Running: Start and Resume don't apply
            pd.Start();
            pause(0.5);
            pd.Start();
            testCase.verifyEqual(lastWarning(), "Cannot start - measurements are already running");
            pd.Resume();
            testCase.verifyEqual(lastWarning(), "Cannot resume - measurements are already running");
            testCase.verifyEqual(string(tlc.State), "Running");

            %Paused: Pause and Start don't apply
            pd.Pause();
            pause(0.5);
            pd.Pause();
            testCase.verifyEqual(lastWarning(), "Cannot pause - measurements are already paused");
            pd.Start();
            testCase.verifyEqual(lastWarning(), "Cannot start - measurements are paused - use Resume, or Stop first");
            testCase.verifyEqual(string(tlc.State), "Paused");

            %...and the valid calls still work
            pd.Resume();
            pause(0.5);
            testCase.verifyEqual(string(tlc.State), "Running");
            pd.Stop();
            pause(0.5);
            testCase.verifyEqual(string(tlc.State), "Ready");
        end

        function ResumeWhilePausingCancelsThePause(testCase)
            %Resume before a pause has taken effect (the tick in progress
            %not finished yet) keeps the loop running, with no Paused event
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            pd.SetUpdateTime(2);    %Long ticks, so the pause is still pending
            tlc = pd.Controller.TimingLoopController;

            setappdata(groot, "PausedRaised", false);
            testCase.addTeardown(@() rmappdata(groot, "PausedRaised"));
            lst = addlistener(tlc, "Paused", @(~, ~) setappdata(groot, "PausedRaised", true));
            testCase.addTeardown(@() delete(lst));

            pd.Start();
            pause(0.5);
            pd.Pause();
            testCase.verifyEqual(string(tlc.State), "Pausing");
            pd.Resume();
            testCase.verifyEqual(string(tlc.State), "Running");
            pause(2.5);     %Past the next tick
            testCase.verifyEqual(string(tlc.State), "Running");
            testCase.verifyFalse(getappdata(groot, "PausedRaised"), "The cancelled pause should not take effect");
            pd.Stop();
            pause(2.5);
        end
    end

    methods (Access = private)
        function last = lastOf(~, messages)
            %The last message recorded, or "" if there are none
            last = "";
            if ~isempty(messages)
                last = messages(end);
            end
        end
    end

end