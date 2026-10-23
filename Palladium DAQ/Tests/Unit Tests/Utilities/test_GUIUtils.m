classdef test_GUIUtils < matlab.unittest.TestCase
    % TEST_GUIUTILS Tests for Palladium utilities functions - GUIUtils
    % static class

    %% Properties
    properties
         TestingDir = fullfile("..", "data", "GUIUtils Testing");
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)

        function PathSetup(testCase)% Shared setup for the entire test class
            % Set up shared state for all tests.
            % Add PluginLoading Testing folder to the Path temporarily
            %Because we're using this fixture tooling, it will get
            %automatically removed on test completion
            import matlab.unittest.fixtures.PathFixture
            import matlab.unittest.constraints.ContainsSubstring
            f = testCase.applyFixture(PathFixture(testCase.TestingDir, IncludeSubfolders=true));
            testCase.verifyThat(path,ContainsSubstring(f.Folders(1)));
        end

    end

    %% Tests
    methods (Test)

        %% IsSmithPlotAvailable
        function test_IsSmithPlotAvailable_FollowsTheToolboxTest(testCase)
            testCase.assumeTrue(exist("smithplot", "file") > 0, "Needs RF Toolbox, to take away");
            testCase.verifyTrue(Palladium.Utilities.GUIUtils.IsSmithPlotAvailable());

            folder = fileparts(which("smithplot"));
            rmpath(folder);
            testCase.addTeardown(@() addpath(folder));

            testCase.verifyFalse(Palladium.Utilities.GUIUtils.IsSmithPlotAvailable());
        end

        %% ComputePropertyList
        function test_ComputePropertyList_WithEmptyInstrument(testCase)
            instrument = [];
            exposeSubClassProperties = true;
            expectedPropertyList = [];

            actualPropertyList = Palladium.Utilities.GUIUtils.ComputePropertyList(instrument, exposeSubClassProperties);

            testCase.verifyEqual(actualPropertyList, expectedPropertyList);
        end

        function test_ComputePropertyList_WithInstrument(testCase)
            instrument = GUIUtilsTestingInstruments.PropertyListTestInstrument();
            exposeSubClassProperties = true;
            expectedPropertyList = [...
                "Name";...
                "Connection_Type";...
                "TestProperty"];

            actualPropertyList = Palladium.Utilities.GUIUtils.ComputePropertyList(instrument, exposeSubClassProperties);

            testCase.verifyEqual(actualPropertyList, expectedPropertyList);
        end

        function test_ComputePropertyList_WithAccessListProperty(testCase)
            % Keithley2000.MeasMode has SetAccess given as a list of classes
            % (a cell array, not a char vector) - it must be left out of the
            % GUI rather than erroring, for either setting of exposeSubClassProperties
            instrument = Palladium.Instruments.Keithley2000();

            for exposeSubClassProperties = [true, false]
                actualPropertyList = Palladium.Utilities.GUIUtils.ComputePropertyList(instrument, exposeSubClassProperties);
                testCase.verifyFalse(any(actualPropertyList == "MeasMode"));
                testCase.verifyTrue(any(actualPropertyList == "Name"));
            end
        end

        %% IsPropertyValidToUse
        function test_IsPropertyValidToUse_WithValidName(testCase)
            propName = 'validPropertyName';
            expectedResult = true;

            actualResult = Palladium.Utilities.GUIUtils.IsPropertyValidToUse(propName);

            testCase.verifyEqual(actualResult, expectedResult);
        end

        function testIsPropertyValidToUse_WithInvalidName(testCase)
            propName = '1invalidPropertyName';
            expectedResult = false;

            actualResult = Palladium.Utilities.GUIUtils.IsPropertyValidToUse(propName);

            testCase.verifyEqual(actualResult, expectedResult);
        end

        %% ToDoubleArrayFromScalarString
        function test_ToDoubleArrayFromScalarString_WithValidInput(testCase)
            str = "200 300 400";
            expectedArray = [200, 300, 400];
            expectedSuccess = true;

            [actualArray, actualSuccess] = Palladium.Utilities.GUIUtils.ToDoubleArrayFromScalarString(str);

            testCase.verifyEqual(actualArray, expectedArray);
            testCase.verifyEqual(actualSuccess, expectedSuccess);
        end

        function test_ToDoubleArrayFromScalarString_WithInvalidInput(testCase)
            str = '200 300 invalid';
            expectedArray = str;
            expectedSuccess = false;

            [actualArray, actualSuccess] = Palladium.Utilities.GUIUtils.ToDoubleArrayFromScalarString(str);

            testCase.verifyEqual(actualArray, expectedArray);
            testCase.verifyEqual(actualSuccess, expectedSuccess);
        end

        %% ToScalarString
        function test_ToScalarString_WithNumericVector(testCase)
            value = [1, 2, 3];
            expectedString = "1 2 3";

            actualString = Palladium.Utilities.GUIUtils.ToScalarString(value);

            testCase.verifyEqual(actualString, expectedString);
        end

        function test_ToScalarString_WithScalarValue(testCase)
            value = 42;
            expectedString = "42";

            actualString = Palladium.Utilities.GUIUtils.ToScalarString(value);

            testCase.verifyEqual(actualString, expectedString);
        end

        function test_ToScalarString_WithInvalidInput(testCase)
            value = rand(2, 2); % High-dimensional array
            testCase.verifyError(@() Palladium.Utilities.GUIUtils.ToScalarString(value), "ToScalarStringError:HighDimensionalArray");
        end

        function test_MessageToHTML_KeepsWindowsPaths(testCase)
            %Backslashes stay as typed - this message used to be cut off
            %at the \U, with a MATLAB warning
            html = Palladium.Utilities.GUIUtils.MessageToHTML("Put it in:" + newline + "`C:\Users\Matt\Documents`");
            testCase.verifyEqual(html, "Put it in:<br><code>C:\Users\Matt\Documents</code>");
        end

        function test_MessageToHTML_EscapesHTMLCharacters(testCase)
            html = Palladium.Utilities.GUIUtils.MessageToHTML("value < 0 & x > 1");
            testCase.verifyEqual(html, "value &lt; 0 &amp; x &gt; 1");
        end

        function test_MessageToHTML_MakesLinks(testCase)
            %Trailing punctuation is not part of the link
            html = Palladium.Utilities.GUIUtils.MessageToHTML("See https://www.qdusa.com/pharos/.");
            testCase.verifyEqual(html, "See <a href=""https://www.qdusa.com/pharos/"">https://www.qdusa.com/pharos/</a>.");
        end

        %% GreekToLaTeX
        function test_GreekToLaTeX_Letters(testCase)
            toLaTeX = @Palladium.Utilities.GUIUtils.GreekToLaTeX;

            testCase.verifyEqual(toLaTeX("Resistance (Ω)"), "Resistance ($\Omega$)");
            testCase.verifyEqual(toLaTeX("Δθ (deg)"), "$\Delta\theta$ (deg)", "Neighbours share one math group");
            testCase.verifyEqual(toLaTeX("χ_ac"), "$\chi$_ac");
            testCase.verifyEqual(toLaTeX("Α" + "Β"), "AB", "Capitals that look like Latin letters");
            testCase.verifyEqual(toLaTeX(string(char([181, 8486]))), "$\mu\Omega$", "Micro and ohm signs");
            testCase.verifyEqual(toLaTeX(["Current (A)", "R (kΩ)"]), ["Current (A)", "R (k$\Omega$)"], "Arrays, and text unchanged");
        end

        function test_GreekToLaTeX_EveryLetterDrawsWithLaTeX(testCase)
            %Each converted letter must be one MATLAB's LaTeX interpreter can draw
            fig = uifigure("Visible", "off");
            testCase.addTeardown(@delete, fig);
            ax = uiaxes(fig);
            letters = string(num2cell(char([913:929, 931:937, 945:969, 977, 981, 982, 1009, 1013, 181, 8486])));
            for letter = letters
                testCase.verifyWarningFree(@() drawLabel(ax, letter), letter);
            end

            function drawLabel(ax, letter)
                xlabel(ax, Palladium.Utilities.GUIUtils.GreekToLaTeX("x " + letter), "Interpreter", "latex");
                drawnow;
            end
        end

        %% EscapeLaTeX
        function test_EscapeLaTeX_SpecialCharacters(testCase)
            escape = @Palladium.Utilities.GUIUtils.EscapeLaTeX;

            testCase.verifyEqual(escape("dV/dI_x (kΩ) 50%"), "dV/dI\_x (k$\Omega$) 50\%");
            testCase.verifyEqual(escape("a&b #1 $5 {x}"), "a{\&}b \#1 \$5 \{x\}");
            testCase.verifyEqual(escape("x^2 ~y C:\d"), "x$\hat{}$2 $\tilde{}$y C:$\backslash$d");
            testCase.verifyEqual(escape("Ω^"), "$\Omega\hat{}$", "One math group with a Greek neighbour");
            testCase.verifyEqual(escape(["Time (mins)", "B || H"]), ["Time (mins)", "B || H"], "Other text unchanged");
            testCase.verifyEqual(Palladium.Utilities.GUIUtils.GreekToLaTeX("R_Ω 50%"), "R_$\Omega$ 50%", "GreekToLaTeX escapes nothing else");
        end

        function test_EscapeLaTeX_EveryEscapeDrawsWithLaTeX(testCase)
            %Each escape must be one MATLAB's LaTeX interpreter can draw
            fig = uifigure("Visible", "off");
            testCase.addTeardown(@delete, fig);
            ax = uiaxes(fig);
            for ch = ["_", "%", "&", "#", "$", "{", "}", "^", "~", "\", "<", ">", "|", "Ω^~"]
                testCase.verifyWarningFree(@() drawLabel(ax, ch), ch);
            end

            function drawLabel(ax, ch)
                xlabel(ax, Palladium.Utilities.GUIUtils.EscapeLaTeX("a" + ch + "b"), "Interpreter", "latex");
                drawnow;
            end
        end

        %% ShowWarning
        function test_ShowWarning_WithNoWindowIsLogged(testCase)
            %Without a window (e.g. no GUI) the warning is logged - no dialogue, no error
            figuresBefore = numel(findall(groot, "Type", "figure"));
            testCase.verifyWarningFree(@() evalc("Palladium.Utilities.GUIUtils.ShowWarning([], ""Test warning"")"));
            testCase.verifyNumElements(findall(groot, "Type", "figure"), figuresBefore);
        end

        function test_ShowWarning_InAHiddenWindowIsLogged(testCase)
            %A hidden window can't show the warning box (uialert errors) - logged instead
            fig = uifigure("Visible", "off");
            testCase.addTeardown(@() delete(fig));
            label = uilabel(uigridlayout(fig, [1 1]));
            testCase.verifyWarningFree(@() Palladium.Utilities.GUIUtils.ShowWarning(label, "Test warning", "Test"));
        end

    end

end