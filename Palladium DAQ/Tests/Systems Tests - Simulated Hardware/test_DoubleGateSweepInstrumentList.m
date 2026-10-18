classdef test_DoubleGateSweepInstrumentList < matlab.unittest.TestCase
    %TEST_DOUBLEGATESWEEPINSTRUMENTLIST Tests the Double 2450 Gate Sweep control's Gate instrument drop-down, with simulated Keithley 2450s
    %The drop-down lists the Keithley 2450s other than the control's own
    %(the Main). It used to be filled only when the control was added -
    %erroring when there was no other 2450 - and never updated.

    %% Properties
    properties
        ConfigPath;     %Test config, relative to the Palladium.m folder
        Programme;      %The Palladium instance under test, with its GUI
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function fixturesSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "Helpers")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
            testCase.ConfigPath = fullfile("Tests", "TestingConfig.json");
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function setup(testCase)
            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            testCase.Programme = pd;

            %Errors are answered, and counted - none are expected
            Palladium.Logging.Logger.TestDialogResponse("set", "Ignore");
            testCase.addTeardown(@() Palladium.Logging.Logger.TestDialogResponse("set", ""));
            testCase.addTeardown(@() testCase.verifyEqual(Palladium.Logging.Logger.TestDialogResponse("count"), 0, "No error dialogues"));
        end
    end

    %% Methods (Test)
    methods (Test)
        function OnlyOneKeithley2450Test(testCase)
            %Adding the control with no other 2450 to be the Gate used to
            %error ("'Items' must be a 1-by-N cell array...")
            pd = testCase.Programme;
            main = pd.AddInstrument("Keithley2450", ConnectionType="Debug");

            cont = pd.AddInstrumentControl(main, "Double 2450 Gate Sweep");

            testCase.verifyNotEmpty(cont, "The control was added");
            testCase.verifyEmpty(testCase.gateDropDown(cont).Items);
        end

        function RunWithoutAGateTest(testCase)
            %A Gate is only needed to Run: pressing Run without one says so
            %(a warning in the window) and starts nothing, leaving the GUI
            %ready to Run again
            pd = testCase.Programme;
            main = pd.AddInstrument("Keithley2450", ConnectionType="Debug");
            cont = pd.AddInstrumentControl(main, "Double 2450 Gate Sweep");
            warning("off", "MATLAB:structOnObject");
            testCase.addTeardown(@() warning("on", "MATLAB:structOnObject"));
            gui = struct(cont).GUIView;

            gui.RunSweep();

            control = struct(cont);
            testCase.verifyFalse(control.PendingRun, "Not queued");
            testCase.verifyEmpty(control.PendingRunTimer, "Not started");
            testCase.verifyEqual(string(testCase.gateDropDown(cont).Enable), "on", "Ready to Run again");
        end

        function GateAddedAndRemovedLaterTest(testCase)
            %A 2450 added after the control appears in the list, and goes
            %again when removed. Other instruments are never listed
            pd = testCase.Programme;
            main = pd.AddInstrument("Keithley2450", ConnectionType="Debug");
            cont = pd.AddInstrumentControl(main, "Double 2450 Gate Sweep");
            dropDown = testCase.gateDropDown(cont);

            gate = pd.AddInstrument("Keithley2450", ConnectionType="Debug");
            pd.AddInstrument("Keithley2410", ConnectionType="Debug");
            testCase.verifyEqual(string(dropDown.Items), string(gate.Name), "Only the other 2450 - not the Main or the 2410");

            pd.RemoveInstrument(gate);
            testCase.verifyEmpty(dropDown.Items);
        end

        function ChosenGateIsKeptTest(testCase)
            %Changing the instruments doesn't change the Gate chosen, while
            %it is still there
            pd = testCase.Programme;
            main = pd.AddInstrument("Keithley2450", ConnectionType="Debug");
            first = pd.AddInstrument("Keithley2450", ConnectionType="Debug");
            second = pd.AddInstrument("Keithley2450", ConnectionType="Debug");
            cont = pd.AddInstrumentControl(main, "Double 2450 Gate Sweep");
            dropDown = testCase.gateDropDown(cont);
            testCase.verifyEqual(string(dropDown.Items), string([first.Name, second.Name]));

            dropDown.Value = second;
            pd.AddInstrument("Keithley2410", ConnectionType="Debug");
            testCase.verifyEqual(dropDown.Value, second, "Kept when an instrument is added");

            pd.RemoveInstrument(first);
            testCase.verifyEqual(dropDown.Value, second, "Kept when another instrument is removed");
        end

        function RemovedControlStopsListeningTest(testCase)
            %Once the control is removed, adding instruments doesn't reach it
            pd = testCase.Programme;
            main = pd.AddInstrument("Keithley2450", ConnectionType="Debug");
            pd.AddInstrumentControl(main, "Double 2450 Gate Sweep");
            pd.RemoveInstrumentControl(main, "Double 2450 Gate Sweep");

            %No error dialogues (checked after every test)
            pd.AddInstrument("Keithley2450", ConnectionType="Debug");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function dropDown = gateDropDown(testCase, cont)
            %The control's Gate instrument drop-down. Both it and the GUI
            %are private, and findall can't see inside an App Designer
            %component, so they are read with struct
            warning("off", "MATLAB:structOnObject");
            testCase.addTeardown(@() warning("on", "MATLAB:structOnObject"));
            dropDown = struct(struct(cont).GUIView).InstrDropDown;
            testCase.assertClass(dropDown, "matlab.ui.control.DropDown");
        end
    end
end
