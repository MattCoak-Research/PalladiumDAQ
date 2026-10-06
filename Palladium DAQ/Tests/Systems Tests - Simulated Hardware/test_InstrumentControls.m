classdef test_InstrumentControls < matlab.unittest.TestCase
    %TEST_INSTRUMENTCONTROLS Tests adding and removing an Instrument Control with Palladium's scripting methods (AddInstrumentControl, RemoveInstrumentControl)
    %For both kinds of Sweep Control: stepped (Keithley 2410) and ramped
    %(Mercury IPS).

    %% Properties
    properties
        ConfigPath;     %Test config, relative to the Palladium.m folder
        Programme;      %The Palladium instance under test, with its GUI
    end

    %% Properties (TestParameter)
    properties (TestParameter)
        InstrumentType = {"Keithley2410", "MercuryIPS"};     %Offer a "Sweep Control": SweepController_Stepped and SweepController_Ramp
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
        end
    end

    %% Methods (Test)
    methods (Test)
        function AddThenRemoveByName(testCase, InstrumentType)
            %RemoveInstrumentControl removes the control and its tab (it
            %used to call itself with the wrong arguments, and always error;
            %and the ramp control's RemoveControl set a property no
            %instrument has)
            pd = testCase.Programme;
            instr = pd.AddInstrument(InstrumentType, ConnectionType="Debug");
            tabTitle = instr.Name + " - Sweep Control";

            pd.AddInstrumentControl(instr, "Sweep Control");
            testCase.verifyNotEmpty(instr.GetRegisteredControlObjectsFromName("Sweep Control"));
            testCase.verifyTrue(testCase.hasTab(tabTitle));

            pd.RemoveInstrumentControl(instr, "Sweep Control");
            testCase.verifyEmpty(instr.GetRegisteredControlObjectsFromName("Sweep Control"));
            testCase.verifyFalse(testCase.hasTab(tabTitle));
        end

        function AddAgainAfterRemoving(testCase, InstrumentType)
            %After removing it, the same control can be added again
            pd = testCase.Programme;
            instr = pd.AddInstrument(InstrumentType, ConnectionType="Debug");

            pd.AddInstrumentControl(instr, "Sweep Control");
            pd.RemoveInstrumentControl(instr, "Sweep Control");
            pd.AddInstrumentControl(instr, "Sweep Control");

            testCase.verifyNumElements(instr.GetRegisteredControlObjectsFromName("Sweep Control"), 1);
        end

        function SteppedSweepDefaultsAndKeptValues(testCase)
            %The stepped Sweep Control's start/middle/end values default to
            %10% of the way from the middle of the limits to each limit (not
            %the limits themselves - up to 1100 V on a 2410). Values entered
            %are kept when an instrument setting changes, clamped to the
            %limits, and go back to the defaults when the units change
            pd = testCase.Programme;
            instr = pd.AddInstrument("Keithley2410", ConnectionType="Debug");
            cont = pd.AddInstrumentControl(instr, "Sweep Control");
            values = @() [cont.ControlDetailsStruct.SweepDetails.MinVal, cont.ControlDetailsStruct.SweepDetails.MidVal, cont.ControlDetailsStruct.SweepDetails.MaxVal];

            %Sourcing current (the default): the 2410 can source up to 1.05 A
            testCase.verifyEqual(values(), [-0.105, 0, 0.105], AbsTol=1e-12);

            %Values entered are kept when another setting changes
            warning("off", "MATLAB:structOnObject");
            testCase.addTeardown(@() warning("on", "MATLAB:structOnObject"));
            gui = struct(cont).GUIView;
            gui.SetStartingValues(-0.5, 0.1, 0.5);
            instr.Name = "Renamed";
            testCase.verifyEqual(values(), [-0.5, 0.1, 0.5], AbsTol=1e-12);

            %...and clamped to the limits
            gui.SetStartingValues(-5, 0, 5);
            testCase.verifyEqual(values(), [-1.05, 0, 1.05], AbsTol=1e-12);

            %Changing the units sets the defaults for the new units: sourcing
            %voltage, up to 1100 V when the protection limit can't be read
            instr.SourceMode = instr.SourceType("Voltage");
            testCase.verifyEqual(values(), [-110, 0, 110], AbsTol=1e-9);

            %The limits are read again once the instrument is connected, on
            %starting measurements - keeping the values entered
            gui.SetStartingValues(-20, 0, 20);
            pd.Start();
            pause(1);
            pd.Stop();
            testCase.verifyEqual(values(), [-20, 0, 20], AbsTol=1e-9);
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
