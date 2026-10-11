classdef test_MetadataErrorOnStart < matlab.unittest.TestCase
    %TEST_METADATAERRORONSTART - What happens when collecting an instrument's metadata fails as measurements start.
    %The error dialogue offers Stop Measurements or Ignore. Stop used to be
    %ignored (measurements started anyway); now it cancels the start, with
    %no second dialogue. Ignore starts without the metadata lines. Uses the
    %test-only MetadataErrorInstrument (in data/MetadataError), and answers
    %the modal dialogue with Logger.TestDialogResponse

    %% Properties
    properties
        ConfigPath;     %Test config, relative to the Palladium.m folder
        Programme;      %The Palladium instance under test, without a GUI
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function fixturesSetup(testCase)
            testFolder = fileparts(mfilename('fullpath'));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testFolder, "..", "Helpers")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testFolder, "data", "MetadataError")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
            testCase.ConfigPath = fullfile("Tests", "TestingConfig.json");
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function setup(testCase)
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            testCase.addTeardown(@() Palladium.Logging.Logger.TestDialogResponse("set", ""));
            testCase.Programme = pd;
        end
    end

    %% Methods (Test)
    methods (Test)
        function StopInErrorDialogueCancelsStart(testCase)
            %Measurements don't start, the instrument is disconnected again,
            %and the error dialogue is the only one shown (no empty
            %"Initialisation has been aborted" warning after it)
            pd = testCase.Programme;
            instr = pd.AddInstrument("MetadataErrorInstrument", ConnectionType="Debug");
            pd.SetUpdateTime(0.1);
            Palladium.Logging.Logger.TestDialogResponse("set", "Stop Measurements");
            rows = testCase.countRows(pd);

            testCase.verifyWarningFree(@() pd.Start(), "There should be no second (warning) dialogue");
            pause(0.5);

            testCase.verifyEqual(Palladium.Logging.Logger.TestDialogResponse("count"), 1, "There should be one error dialogue");
            testCase.verifyEqual(string(pd.Controller.TimingLoopController.State), "Ready", "Measurements should not have started");
            testCase.verifyFalse(instr.IsConnected, "The instrument should be disconnected again");
            testCase.verifyEqual(rows(), 0, "No data should be taken");
        end

        function IgnoreInErrorDialogueStartsWithoutMetadata(testCase)
            %Measurements start, and the data file has its headers but no
            %metadata line for the instrument
            pd = testCase.Programme;
            instr = pd.AddInstrument("MetadataErrorInstrument", ConnectionType="Debug");
            pd.SetUpdateTime(0.1);
            Palladium.Logging.Logger.TestDialogResponse("set", "Ignore");
            rows = testCase.countRows(pd);

            pd.Start();
            pause(0.5);

            testCase.verifyEqual(string(pd.Controller.TimingLoopController.State), "Running");
            testCase.verifyGreaterThan(rows(), 0, "Data should be taken");
            lines = readlines(pd.Controller.DataWriter.FileWriteDetails.FilePath);
            testCase.verifyTrue(any(contains(lines, instr.Name + " - Value")), "The column headers should be written");
            testCase.verifyFalse(any(contains(lines, instr.Name + " Settings")), "There should be no metadata line for the instrument");

            pd.Stop();
            pause(0.5);
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function rows = countRows(testCase, pd)
            %Count the data rows written, returning a function that gives the count so far
            counter = containers.Map({'rows'}, {0});
            lst = addlistener(pd.Controller, "DataRowUpdated", @(~, ~) increment());
            testCase.addTeardown(@() delete(lst));
            rows = @() counter('rows');

            function increment()
                counter('rows') = counter('rows') + 1;
            end
        end
    end
end
