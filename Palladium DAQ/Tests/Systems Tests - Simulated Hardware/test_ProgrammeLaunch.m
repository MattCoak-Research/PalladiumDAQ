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

    methods (Test)
        function InstrumentsDisconnectedAfterStop(testCase)
            %Instruments are connected while measuring, and not once
            %stopped - simulated ones too
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            instr = pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            pd.SetUpdateTime(0.1);
            testCase.verifyFalse(instr.IsConnected);

            pd.Start();
            pause(0.5);
            testCase.verifyTrue(instr.IsConnected);

            pd.Stop();
            pause(0.5);
            testCase.verifyFalse(instr.IsConnected);
        end

        function StopFromInstrumentErrorDialogueStopsCleanly(testCase)
            %With ErrorOnAllInstrumentErrors, choosing Stop Measurements in
            %the error dialogue stops at once: one dialogue, Stopped raised
            %once, and every instrument disconnected. The tick's row is still
            %written and plotted, in full - NaNs for the failed instrument
            %and for those not measured. Used to carry on measuring the other
            %(now closed) instruments, each failing with its own dialogue
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            first = pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            second = pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            pd.SetUpdateTime(0.1);
            pd.Controller.InstrumentController.ErrorOnAllInstrumentErrors = true;

            %Answer the (modal) error dialogue with Stop Measurements
            Palladium.Logging.Logger.TestDialogResponse("set", "Stop Measurements");
            testCase.addTeardown(@() Palladium.Logging.Logger.TestDialogResponse("set", ""));

            %Count Stopped events, and data rows, noting how many rows there
            %were when measurements stopped
            setappdata(groot, "HaltTest", struct("Stopped", 0, "Rows", 0, "RowsAtStop", NaN, "LastRow", []));
            testCase.addTeardown(@() rmappdata(groot, "HaltTest"));
            l1 = addlistener(pd.Controller.TimingLoopController, "Stopped", @(~, ~) testCase.recordStop());
            l2 = addlistener(pd.Controller, "DataRowUpdated", @(~, e) testCase.recordRow(e.DataRow));
            testCase.addTeardown(@() delete([l1, l2]));

            pd.Start();
            pause(0.5);
            first.Disconnect();     %Its next reading fails, as a real instrument's would
            pause(1);

            counts = getappdata(groot, "HaltTest");
            testCase.verifyEqual(Palladium.Logging.Logger.TestDialogResponse("count"), 1, "There should be one error dialogue");
            testCase.verifyEqual(counts.Stopped, 1, "Stopped should be raised once");
            testCase.verifyEqual(string(pd.Controller.TimingLoopController.State), "Ready");
            testCase.verifyFalse(first.IsConnected);
            testCase.verifyFalse(second.IsConnected);
            testCase.verifyEqual(counts.Rows, counts.RowsAtStop + 1, "The stopped tick's row should still be written and plotted - once");
            testCase.verifyNumElements(counts.LastRow, numel(pd.Controller.Headers), "The row should have a value for every column");
            testCase.verifyFalse(isnan(counts.LastRow(1)), "The time column should be filled");
            testCase.verifyTrue(all(isnan(counts.LastRow(2:end))), "Both instruments' columns should be NaN: the first failed, the second was not measured");

            %...and it is the last line of the data file
            fileRows = readmatrix(pd.Controller.DataWriter.FileWriteDetails.FilePath, FileType="text", Delimiter="	");
            testCase.verifyEqual(size(fileRows, 2), numel(pd.Controller.Headers), "Every line of the data file should be full width");
            testCase.verifyTrue(all(isnan(fileRows(end, 2:end))), "The last line written should be the padded row");
        end
    end

    methods (Test)
        function ConnectionStateWarningsOnlyWhenSomethingWentWrong(testCase)
            %Connect and Disconnect warn if called in the wrong state - which
            %normal use never does: starting and stopping, a start that
            %fails on its second instrument (the first is disconnected, the
            %CloseAll after it skips both), and closing Palladium
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            closer = onCleanup(@() pd.Close());
            pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            pd.SetUpdateTime(0.1);

            setappdata(groot, "ConnectionWarnings", strings(0));
            testCase.addTeardown(@() rmappdata(groot, "ConnectionWarnings"));
            lst = addlistener(pd.Controller, "YellowStatus", @(~, e) testCase.recordConnectionWarning(e.Message));
            testCase.addTeardown(@() delete(lst));

            %Start and stop
            pd.Start();
            pause(0.5);
            pd.Stop();
            pause(0.5);

            %A start that fails: a GPIB instrument with no hardware attached
            failing = pd.AddInstrument("Keithley2000", ConnectionType="GPIB");
            evalc("pd.Start();");   %Hide the "could not connect" warning
            pause(0.5);
            testCase.verifyEqual(string(pd.Controller.TimingLoopController.State), "Ready");
            testCase.verifyFalse(failing.IsConnected);

            %Close Palladium
            clear closer
            testCase.verifyEmpty(getappdata(groot, "ConnectionWarnings"), "Normal use should not warn about the connection state");
        end
    end

    methods (Test)
        function InstrumentControlsWithoutGUIErrorClearly(testCase)
            %Instrument Controls need the GUI - without one, adding or
            %removing them gives a clear error (it used to be a raw
            %"Dot indexing is not supported" from the missing View)
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            instr = pd.AddInstrument("Keithley2410", ConnectionType="Debug");

            testCase.verifyError(@() pd.AddInstrumentControl(instr, "Sweep Control"), "Palladium:NoGUI");
            testCase.verifyError(@() pd.RemoveInstrumentControl(instr, "Sweep Control"), "Palladium:NoGUI");
        end

        function AddInstrumentNeedsTheWholeClassName(testCase)
            %Part of a class name is not enough; char is accepted, as the
            %arguments block allows (it used to be rejected as not a string)
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            ic = pd.Controller.InstrumentController;

            Palladium.Logging.Logger.TestDialogResponse("set", "Ignore");
            testCase.addTeardown(@() Palladium.Logging.Logger.TestDialogResponse("set", ""));
            testCase.verifyEmpty(ic.AddInstrument("Keithley"), "A partial class name should not add an instrument");
            testCase.verifyEqual(Palladium.Logging.Logger.TestDialogResponse("count"), 1, "It should be reported in the error dialogue");

            instr = ic.AddInstrument('Keithley2000');
            testCase.verifyClass(instr, "Palladium.Instruments.Keithley2000");
        end
    end

    methods (Test)
        function StateIsALoopStateThroughout(testCase)
            %TimingLoopController.State is a Palladium.Enums.LoopState before
            %starting and after every change (it used to start as a
            %categorical and become a string, so strcmp on it gave false
            %before the first start)
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            pd.SetUpdateTime(0.1);
            tlc = pd.Controller.TimingLoopController;

            testCase.verifyState(tlc, "Ready");
            pd.Start();
            pause(0.5);
            testCase.verifyState(tlc, "Running");
            pd.Pause();
            testCase.verifyState(tlc, "Pausing");
            pause(0.5);
            testCase.verifyState(tlc, "Paused");
            pd.Resume();
            pause(0.5);
            testCase.verifyState(tlc, "Running");
            pd.Stop();
            testCase.verifyState(tlc, "Stopping");
            pause(0.5);
            testCase.verifyState(tlc, "Ready");
        end
    end

    methods (Test)
        function UncreatableDataFolderFallsBackToDocuments(testCase)
            %If the config's data folder doesn't exist and can't be created,
            %Palladium warns and uses the user's Documents folder (it used
            %USERPROFILE, which is Windows-only - empty on Linux and Mac).
            %The data folder is "inside" a file, which no OS can create
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            root = string(fixture.Folder);
            writelines("Not a folder", fullfile(root, "blocker.txt"));
            appDir = string(fileparts(which("Palladium")));

            cfg = readstruct(fullfile(appDir, "Tests", "TestingConfig.json"));
            cfg.PathSettings.DefaultDirectory = fullfile(root, "blocker.txt", "Data");
            configPath = fullfile(root, "Config.json");
            writestruct(cfg, configPath, FileType="json");

            pd = testCase.verifyWarning(@() Palladium(View=[], ConfigFilePath=configPath), ...
                "LoadSettingsWarning:DefaultDirectoryCreationFailed");
            testCase.addTeardown(@() pd.Close());   %Runs before the fixture removes the folder

            documents = Palladium.Utilities.PathUtils.CleanPath(Palladium.Utilities.PathUtils.GetDocumentsDirectory());
            testCase.verifyEqual(Palladium.Utilities.PathUtils.CleanPath(pd.Controller.PathSettings.DefaultDirectory), documents);
            testCase.verifyTrue(isfolder(pd.Controller.PathSettings.DefaultDirectory), "The fallback folder should exist");
        end
    end

    methods (Access = private)
        function verifyState(testCase, tlc, expected)
            %Check the loop's state is the LoopState expected, and works with strcmp
            testCase.verifyClass(tlc.State, "Palladium.Enums.LoopState");
            testCase.verifyEqual(tlc.State, Palladium.Enums.LoopState(expected));
            testCase.verifyTrue(strcmp(tlc.State, expected), "strcmp should work on the state");
        end

        function recordConnectionWarning(~, message)
            %Record a status message about Connect or Disconnect being called in the wrong state
            if contains(message, ["Connect was called", "Disconnect was called"])
                setappdata(groot, "ConnectionWarnings", [getappdata(groot, "ConnectionWarnings"), string(message)]);
            end
        end

        function recordStop(~)
            %Count a Stopped event, noting the number of rows so far
            counts = getappdata(groot, "HaltTest");
            counts.Stopped = counts.Stopped + 1;
            counts.RowsAtStop = counts.Rows;
            setappdata(groot, "HaltTest", counts);
        end

        function recordRow(~, dataRow)
            %Count a data row written and plotted, keeping the last one
            counts = getappdata(groot, "HaltTest");
            counts.Rows = counts.Rows + 1;
            counts.LastRow = dataRow;
            setappdata(groot, "HaltTest", counts);
        end

        function last = lastOf(~, messages)
            %The last message recorded, or "" if there are none
            last = "";
            if ~isempty(messages)
                last = messages(end);
            end
        end
    end

end