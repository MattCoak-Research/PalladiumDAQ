classdef test_SimplePlotterPanel < matlab.unittest.TestCase
    %TEST_SIMPLEPLOTTERPANEL Tests the plotter's kinds of plot: the usual scatter of y against x, and a Smith chart - switching between them
    %The panel's own axes are private, so these check what can be reached:
    %the plot kind, and whether plotting and appending behave

    %% Methods (Test)
    methods (Test)
        function StartsAsAScatterPlotTest(testCase)
            plotter = testCase.makePlotter();

            testCase.verifyEqual(plotter.PlotKind, "Scatter");
        end

        function SmithKindPlotsRealAgainstImaginaryTest(testCase)
            testCase.assumeTrue(Palladium.Utilities.GUIUtils.IsSmithPlotAvailable(), "Needs RF Toolbox");
            plotter = testCase.makePlotter();
            gamma = 0.8 * exp(-1i * linspace(0, 6, 50))';

            plotter.SetPlotKind("Smith");
            plotter.PlotData(real(gamma), imag(gamma));

            testCase.verifyEqual(plotter.PlotKind, "Smith");
            testCase.verifyFalse(plotter.TryAppendData(0.1, 0.1), "A Smith plot is always plotted afresh");
        end

        function CanSwitchBackAndForthTest(testCase)
            testCase.assumeTrue(Palladium.Utilities.GUIUtils.IsSmithPlotAvailable(), "Needs RF Toolbox");
            plotter = testCase.makePlotter();
            x = linspace(1, 10, 20)';

            plotter.PlotData(x, [x, 2 * x]);
            plotter.SetPlotKind("Smith");
            plotter.PlotData(0.5 * cos(x), 0.5 * sin(x));
            plotter.SetPlotKind("Scatter");
            plotter.PlotData(x, x);

            testCase.verifyEqual(plotter.PlotKind, "Scatter");
            testCase.verifyTrue(plotter.TryAppendData(11, 11), "Appending works again for a scatter plot");
        end

        function CopyPlotCopiesTheSmithTraceTest(testCase)
            %The copy was an empty chart: it tested the smithplot with isgraphics, which is false for it
            testCase.assumeTrue(Palladium.Utilities.GUIUtils.IsSmithPlotAvailable(), "Needs RF Toolbox");
            plotter = testCase.makePlotter();
            gamma = 0.8 * exp(-1i * linspace(0, 6, 50))';
            plotter.SetPlotKind("Smith");
            plotter.PlotData(real(gamma), imag(gamma));
            warning("off", "MATLAB:structOnObject");
            testCase.addTeardown(@() warning("on", "MATLAB:structOnObject"));
            before = findall(groot, "Type", "figure");

            button = struct(plotter).CopyPlotButton;      %The button's callback is private
            button.ButtonPushedFcn(button, []);

            copies = setdiff(findall(groot, "Type", "figure"), before);
            testCase.addTeardown(@() delete(copies(isvalid(copies))));
            testCase.assertNumElements(copies, 1);
            lines = findobj(copies, "Type", "line");
            trace = lines(arrayfun(@(l) numel(l.XData) == 50, lines));
            testCase.assertNotEmpty(trace, "The 50-point trace is in the copy");
            testCase.verifyEqual([trace(1).XData(1), trace(1).YData(1)], [0.8, 0], AbsTol = 1e-12);
        end

        function SmithKindWithoutRFToolboxIsRefusedTest(testCase)
            %Palladium works without RF Toolbox: asking its plotter for a Smith chart errors, and it stays a scatter plot
            testCase.assumeTrue(Palladium.Utilities.GUIUtils.IsSmithPlotAvailable(), "Needs RF Toolbox, to take away");
            plotter = testCase.makePlotter();
            testCase.hideRFToolbox();

            testCase.verifyError(@() plotter.SetPlotKind("Smith"), "SimplePlotterPanel:SmithPlotUnavailable");
            testCase.verifyEqual(plotter.PlotKind, "Scatter");
        end

        function UnknownKindIsRefusedTest(testCase)
            plotter = testCase.makePlotter();

            testCase.verifyError(@() plotter.SetPlotKind("Pie"), "MATLAB:validators:mustBeMember");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function hideRFToolbox(testCase)
            %Take the toolbox off the path for the test, so smithplot isn't found - as on a computer without it
            folder = fileparts(which("smithplot"));
            rmpath(folder);
            testCase.addTeardown(@() addpath(folder));
        end

        function plotter = makePlotter(testCase)
            fig = uifigure("Visible", "off");
            testCase.addTeardown(@() delete(fig));
            plotter = Palladium.Components.SimplePlotterPanel(fig);
            settings = struct("Size", "Large", "Colours", reshape([1 0 0; 0 0 1; 0 0.6 0; 1 0 1]', 1, []), "FontSize", 12, ...
                "LineStyles", ["None"; "None"; "None"; "None"], "LineWidth", 1, "MarkerSize", 6, "Markers", ["o"; "o"; "+"; "*"], "ShowLegends", false);
            plotter.ApplySettings(settings);
        end
    end
end
