classdef test_PresetSaveLoad < matlab.unittest.TestCase
    %TEST_PRESETSAVELOAD Tests saving the plotting tabs and windows to a preset (Save Preset), and loading them back

    %% Properties
    properties
        ConfigPath;     %Test config, relative to the Palladium.m folder
        Folder;         %Fresh folder in Testing Data Files for each test's preset files
        Programme;      %The Palladium instance under test, with its GUI
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
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            testCase.Folder = string(fixture.Folder);
            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            testCase.Programme = pd;
        end
    end

    %% Methods (Test)
    methods (Test)
        function SavesGridSizeAndEveryPlotter(testCase)
            %A 2x2 tab: saved as Row and Col, with each plotter's axes in
            %grid order (along each row in turn)
            testCase.addTab(2, 2);

            tab = testCase.savedSpecs(testCase.save("Saved.json"), "PlottingTabs");

            testCase.verifyEqual([tab.Row, tab.Col], [2, 2]);
            testCase.verifyFalse(isfield(tab, "Column"));
            testCase.verifyEqual(string(tab.DefaultXAxis)', ["X1", "X2", "X3", "X4"]);
            for k = 1 : 4
                ya = string(tab.DefaultYAxes{k})';
                testCase.verifyEqual(ya(1:2), ["Y" + k + "a", "Y" + k + "b"], "Plotter " + k);
            end
        end

        function TabRoundTrip(testCase)
            %Loading a saved preset gives a tab like the original: saving
            %again, the loaded tab's settings match the original's
            testCase.addTab(2, 2);
            path = testCase.save("First.json");

            Palladium.Utilities.PluginLoading.ApplyPresetFromJson(testCase.Programme.Controller, testCase.Programme.View, path);

            tabs = testCase.savedSpecs(testCase.save("Second.json"), "PlottingTabs");
            testCase.verifyNumElements(tabs, 2);
            testCase.verifyEqual(tabs(2), tabs(1));
        end

        function WindowRoundTrip(testCase)
            %The same for a separate plotting window, with a 1x2 grid
            plotters = testCase.Programme.View.AddNewPlottingWindow(1, 2);
            testCase.setAxes(plotters);
            path = testCase.save("First.json");

            Palladium.Utilities.PluginLoading.ApplyPresetFromJson(testCase.Programme.Controller, testCase.Programme.View, path);

            windows = testCase.savedSpecs(testCase.save("Second.json"), "PlottingWindows");
            testCase.verifyNumElements(windows, 2);
            testCase.verifyEqual([windows(1).Row, windows(1).Col], [1, 2]);
            testCase.verifyEqual(string(windows(1).DefaultXAxis)', ["X1", "X2"]);
            testCase.verifyEqual(windows(2), windows(1));
        end

        function GapInYAxesKeepsPositions(testCase)
            %A plotter with only its second y axis set: it stays the second
            %after saving and loading. And a plotter with no x axis doesn't
            %move the next plotter's x axis
            plotters = testCase.Programme.View.AddNewPlottingTab(1, 2);
            plotters(1).SetDefaultYAxes([], "OnlyY2", [], []);
            plotters(2).SetDefaultXAxis("X2");
            path = testCase.save("First.json");

            tab = testCase.savedSpecs(path, "PlottingTabs");
            testCase.verifyEqual(string(tab.DefaultXAxis)', ["", "X2"]);
            testCase.verifyEqual(string(tab.DefaultYAxes{1})', ["", "OnlyY2", "", ""]);

            Palladium.Utilities.PluginLoading.ApplyPresetFromJson(testCase.Programme.Controller, testCase.Programme.View, path);
            tabs = testCase.savedSpecs(testCase.save("Second.json"), "PlottingTabs");
            testCase.verifyEqual(tabs(2), tabs(1));
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function addTab(testCase, rows, cols)
            %A plotting tab whose plotters each have their own default axes
            plotters = testCase.Programme.View.AddNewPlottingTab(rows, cols);
            testCase.setAxes(plotters);
        end

        function setAxes(~, plotters)
            %Plotter k gets x axis Xk, and y axes Yka and Ykb
            for k = 1 : numel(plotters)
                plotters(k).SetDefaultXAxis("X" + k);
                plotters(k).SetDefaultYAxes("Y" + k + "a", "Y" + k + "b", [], []);
            end
        end

        function path = save(testCase, fileName)
            %Save a preset, as Save Preset does
            path = fullfile(testCase.Folder, fileName);
            ctrl = testCase.Programme.Controller;
            Palladium.Utilities.PluginLoading.SavePresetToJson(ctrl, ctrl.InstrumentController, testCase.Programme.View, path);
        end

        function specs = savedSpecs(~, path, section)
            %The PlottingTabs or PlottingWindows of a saved preset, as a
            %struct array
            data = jsondecode(fileread(path));
            specs = data.(section);
            if iscell(specs)
                specs = [specs{:}];
            end
        end
    end
end
