classdef test_BigNumberDisplays < matlab.unittest.TestCase
    %TEST_BIGNUMBERDISPLAYS Tests Big Number Displays opened through the Controller (OpenBigNumberDisplay), with a simulated instrument measuring
    %The column is given, so no list dialogue opens. Error dialogues are
    %answered with Logger.TestDialogResponse.

    %% Properties
    properties
        ConfigPath;     %Test config, relative to the Palladium.m folder
        Programme;      %The Palladium instance under test (no GUI)
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function fixturesSetup(testCase)
            %Palladium writes its data files, sequences and logs to the
            %Data, Sequences and Logs folders in Testing Data Files (see
            %TestingConfig.json). The fixture removes them again afterwards.
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "Helpers")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
            testCase.ConfigPath = fullfile("Tests", "TestingConfig.json");
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function setup(testCase)
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() testCase.closeIfOpen(pd));
            testCase.Programme = pd;
            pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            pd.SetUpdateTime(0.1);
            testCase.addTeardown(@() Palladium.Logging.Logger.TestDialogResponse("set", ""));
        end
    end

    %% Methods (Test)
    methods (Test)

        function NothingToShowBeforeMeasurementsStartTest(testCase)
            %The data columns aren't known yet - nothing opens, without error
            display = [];
            testCase.verifyWarningFree(@() open());
            testCase.verifyEmpty(display);

            function open()
                evalc("display = testCase.Programme.Controller.OpenBigNumberDisplay(2)");
            end
        end

        function ShowsTheLatestValueOfItsColumnTest(testCase)
            controller = testCase.startMeasuring();
            header = string(controller.Headers(2));

            display = controller.OpenBigNumberDisplay(header);
            testCase.addTeardown(@() delete(display));
            pause(0.5);

            testCase.verifyEqual(display.Title, header);
            testCase.verifyEqual(display.Units, string(controller.Units(2)), "The column's units, not its header");
            testCase.verifyNotEqual(display.DisplayedValue, "-", "Updated each tick");
            testCase.verifyEqual(display.ColumnIndex, 2);
        end

        function ColumnByNumberTest(testCase)
            controller = testCase.startMeasuring();

            display = controller.OpenBigNumberDisplay(2);
            testCase.addTeardown(@() delete(display));

            testCase.verifyEqual(display.Title, string(controller.Headers(2)));
        end

        function NoSuchColumnShowsAnErrorTest(testCase)
            controller = testCase.startMeasuring();
            Palladium.Logging.Logger.TestDialogResponse("set", "Ignore");

            display = [];
            evalc("display = controller.OpenBigNumberDisplay(""No such column"")");

            testCase.verifyEmpty(display);
            testCase.verifyEqual(Palladium.Logging.Logger.TestDialogResponse("count"), 1, "One error dialogue");
        end

        function ClosedDisplayIsDroppedTest(testCase)
            %Measuring carries on without error after a display's window is closed
            controller = testCase.startMeasuring();
            display = controller.OpenBigNumberDisplay(2);
            Palladium.Logging.Logger.TestDialogResponse("set", "Ignore");

            close(display.Figure);
            pause(0.5);

            testCase.verifyEqual(Palladium.Logging.Logger.TestDialogResponse("count"), 0, "No errors from the closed display");
        end

        function ClosingPalladiumClosesTheDisplaysTest(testCase)
            controller = testCase.startMeasuring();
            display = controller.OpenBigNumberDisplay(2);

            testCase.Programme.Close();

            testCase.verifyFalse(isvalid(display));
        end

    end

    %% Methods (Private)
    methods (Access = private)
        function controller = startMeasuring(testCase)
            %Start measuring, and wait for a few ticks so the data columns are known
            testCase.Programme.Start();
            pause(0.5);
            controller = testCase.Programme.Controller;
        end

        function closeIfOpen(~, pd)
            %Close Palladium - closing again after a test already did is fine
            if isvalid(pd)
                pd.Close();
            end
        end
    end
end
