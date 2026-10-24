classdef test_InstrumentOptionsPanel < matlab.unittest.TestCase
    %TEST_INSTRUMENTOPTIONSPANEL Tests the panel's area for an instrument's own setup controls: there only when the instrument adds some, and the settings shrink to make room
    %The panel's own components are private, so they are reached through the
    %panel the instrument is handed (SetupControlsInstrument keeps it)

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function NoSetupControlsLeavesNoAreaTest(testCase)
            panel = testCase.makePanel();
            instr = InstrumentTestingInstruments.SetupControlsInstrument();
            instr.SetupHeight = 0;

            panel.OpenInstrument(instr);

            testCase.verifyFalse(isvalid(instr.SetupParent), "No area is left behind");
            testCase.verifyNumElements(instr.SetupGrid.RowHeight, 4, "The designed layout, without the area's row");
        end

        function SetupControlsGetAnAreaTest(testCase)
            panel = testCase.makePanel();
            instr = InstrumentTestingInstruments.SetupControlsInstrument();

            panel.OpenInstrument(instr);

            testCase.verifyNumElements(instr.SetupGrid.RowHeight, 5, "A row for the area");
            testCase.verifyEqual(testCase.areaHeight(instr), 70, "Room made");
            testCase.verifySize(instr.SetupParent.Children, [1 1]);
            first = instr.SetupParent;

            %Drawn again (e.g. a setting changed): rebuilt, not added to
            panel.OpenInstrument(instr);
            testCase.verifyFalse(isvalid(first), "The old area is replaced");
            testCase.verifySize(instr.SetupParent.Children, [1 1]);
            grid = instr.SetupGrid;

            %Another instrument with none: the area goes again
            panel.OpenInstrument(Palladium.Instruments.Keithley2000());
            testCase.verifyFalse(isvalid(instr.SetupParent));
            testCase.verifyNumElements(grid.RowHeight, 4);
        end

        function LockingDisablesTheSetupControlsTest(testCase)
            panel = testCase.makePanel();
            instr = InstrumentTestingInstruments.SetupControlsInstrument();
            panel.OpenInstrument(instr);

            panel.LockInput();
            testCase.verifyEqual(instr.SetupParent.Enable, matlab.lang.OnOffSwitchState.off);

            panel.UnlockInput();
            testCase.verifyEqual(instr.SetupParent.Enable, matlab.lang.OnOffSwitchState.on);
        end

        function UnusableHeightLeavesNoAreaTest(testCase)
            %A height of zero or less means no area
            panel = testCase.makePanel();
            instr = InstrumentTestingInstruments.SetupControlsInstrument();
            instr.SetupHeight = -1;     %Not an error itself - an unusable height means no area
            panel.OpenInstrument(instr);
            testCase.verifyFalse(isvalid(instr.SetupParent));
            testCase.verifyNumElements(instr.SetupGrid.RowHeight, 4);
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function panel = makePanel(testCase)
            fig = uifigure("Visible", "off");
            testCase.addTeardown(@() delete(fig));
            panel = Palladium.Components.InstrumentOptionsPanel(fig);
            panel.UnlockInput();
        end

        function height = areaHeight(~, instr)
            %The height of the setup controls area's row in the panel's layout
            area = instr.SetupParent;
            height = area.Parent.RowHeight{area.Layout.Row};
        end
    end
end
