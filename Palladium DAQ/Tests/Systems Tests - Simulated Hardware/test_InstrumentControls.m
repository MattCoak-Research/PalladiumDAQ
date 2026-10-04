classdef test_InstrumentControls < matlab.unittest.TestCase
    %TEST_INSTRUMENTCONTROLS Tests adding and removing an Instrument Control with Palladium's scripting methods (AddInstrumentControl, RemoveInstrumentControl)

    %% Properties
    properties
        ConfigPath;     %Test config, relative to the Palladium.m folder
        Programme;      %The Palladium instance under test, with its GUI
        Instrument;     %A simulated Keithley 2410, which offers a "Sweep Control"
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
            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            testCase.Programme = pd;
            testCase.Instrument = pd.AddInstrument("Keithley2410", ConnectionType="Debug");
        end
    end

    %% Methods (Test)
    methods (Test)
        function AddThenRemoveByName(testCase)
            %RemoveInstrumentControl removes the control and its tab (it
            %used to call itself with the wrong arguments, and always error)
            pd = testCase.Programme;
            instr = testCase.Instrument;
            tabTitle = instr.Name + " - Sweep Control";

            pd.AddInstrumentControl(instr, "Sweep Control");
            testCase.verifyNotEmpty(instr.GetRegisteredControlObjectsFromName("Sweep Control"));
            testCase.verifyTrue(testCase.hasTab(tabTitle));

            pd.RemoveInstrumentControl(instr, "Sweep Control");
            testCase.verifyEmpty(instr.GetRegisteredControlObjectsFromName("Sweep Control"));
            testCase.verifyFalse(testCase.hasTab(tabTitle));
        end

        function AddAgainAfterRemoving(testCase)
            %After removing it, the same control can be added again
            pd = testCase.Programme;
            instr = testCase.Instrument;

            pd.AddInstrumentControl(instr, "Sweep Control");
            pd.RemoveInstrumentControl(instr, "Sweep Control");
            pd.AddInstrumentControl(instr, "Sweep Control");

            testCase.verifyNumElements(instr.GetRegisteredControlObjectsFromName("Sweep Control"), 1);
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function tf = hasTab(testCase, title)
            %True if the main window has a tab with this title
            fig = testCase.Programme.View.GetUIFigureHandle();
            tabs = findall(fig, "Type", "uitab");
            tf = any(string({tabs.Title}) == title);
        end
    end
end
