classdef test_BigNumberDisplay < matlab.unittest.TestCase
    %TEST_BIGNUMBERDISPLAY Tests the Big Number Display window: what it shows, that its text always fits, and that it goes when its window closes
    %The windows are kept hidden.

    %% Properties
    properties
        Display;        %The display under test
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function createDisplay(testCase)
            testCase.Display = Palladium.Components.BigNumberDisplay("Sample Temperature (K)", "K", 2, Visible="off");
            testCase.addTeardown(@() delete(testCase.Display));
        end
    end

    %% Tests
    methods (Test)

        %% What it shows
        function ShowsItsColumnOfEachRowTest(testCase)
            %6 significant figures, trailing zeros kept - so the length
            %doesn't change when a reading ends in 0
            testCase.Display.UpdateValue([1 4.25 7]);
            testCase.verifyEqual(testCase.Display.DisplayedValue, "4.25000");
            testCase.verifyEqual(string(testCase.valueText().String), "4.25000");

            testCase.Display.UpdateValue([1 -0.003 7]);
            testCase.verifyEqual(testCase.Display.DisplayedValue, "-0.00300000");

            %No trailing decimal point
            testCase.Display.UpdateValue([1 123456.789 7]);
            testCase.verifyEqual(testCase.Display.DisplayedValue, "123457");
        end

        function NumberFormatTest(testCase)
            testCase.Display.NumberFormat = "%.2f";
            testCase.Display.UpdateValue([1 4.25678 7]);
            testCase.verifyEqual(testCase.Display.DisplayedValue, "4.26");
        end

        function NaNAndMissingColumnTest(testCase)
            testCase.Display.UpdateValue([1 NaN 7]);
            testCase.verifyEqual(testCase.Display.DisplayedValue, "NaN");

            %A row without this column - e.g. after instruments were removed
            testCase.verifyWarningFree(@() testCase.Display.UpdateValue(1));
            testCase.verifyEqual(testCase.Display.DisplayedValue, "-");
        end

        function TitleAndUnitsTest(testCase)
            testCase.verifyEqual(string(testCase.Display.Figure.Name), "Sample Temperature (K)");
            testCase.verifyEqual(string(testCase.unitsText().String), "K");

            testCase.Display.SetTitle("Field_1 (T)");
            testCase.Display.SetUnits("T");
            testCase.verifyEqual(string(testCase.Display.Figure.Name), "Field_1 (T)");
            testCase.verifyEqual(string(testCase.titleText().String), "Field_1 (T)", "Shown as typed - no TeX subscript");
            testCase.verifyEqual(string(testCase.unitsText().String), "T");
        end

        %% Fitting the window
        function TextFitsAtEverySizeTest(testCase)
            %Never cut off - at any window shape, with short and long values
            for size = [520 300; 200 120; 900 250; 250 700; 120 60]'
                testCase.resizeTo(size');
                for value = [4.2, 123456.789, -1.23456e-12]
                    testCase.Display.UpdateValue([0 value]);
                    testCase.verifyAllTextFits(sprintf("%dx%d, value %g", size(1), size(2), value));
                end
            end
        end

        function BiggerWindowGivesBiggerTextTest(testCase)
            testCase.Display.UpdateValue([0 4.2]);
            testCase.resizeTo([300 200]);
            small = testCase.valueText().FontSize;
            testCase.resizeTo([900 600]);
            testCase.verifyGreaterThan(testCase.valueText().FontSize, small);
        end

        function LongerValueGivesSmallerTextTest(testCase)
            %So it stays inside the window rather than running off the sides
            testCase.resizeTo([520 300]);
            testCase.Display.UpdateValue([0 4]);
            short = testCase.valueText().FontSize;
            testCase.Display.UpdateValue([0 -1.23456e-12]);
            testCase.verifyLessThan(testCase.valueText().FontSize, short);
            testCase.verifyAllTextFits("long value");
        end

        function ShorterValueKeepsItsSizeAndPlaceTest(testCase)
            %A shorter value doesn't refit - that made the text jump about
            %from tick to tick - and, right-aligned, its digits stay put
            testCase.resizeTo([520 300]);
            testCase.Display.UpdateValue([0 -1.23456e-12]);
            longSize = testCase.valueText().FontSize;
            longRight = testCase.valueText().Position(1);

            testCase.Display.UpdateValue([0 4.2]);
            testCase.verifyEqual(testCase.valueText().FontSize, longSize);
            testCase.verifyEqual(testCase.valueText().Position(1), longRight);
            testCase.verifyAllTextFits("shorter value");
        end

        function ResizeRefitsToTheCurrentValueTest(testCase)
            %After a long value then a short one, resizing fits the short one
            testCase.resizeTo([520 300]);
            testCase.Display.UpdateValue([0 -1.23456e-12]);
            testCase.Display.UpdateValue([0 4.2]);
            longSize = testCase.valueText().FontSize;

            testCase.resizeTo([521 300]);
            testCase.verifyGreaterThan(testCase.valueText().FontSize, longSize);
            testCase.verifyAllTextFits("after resize");
        end

        %% Closing
        function ClosingTheWindowDeletesTheDisplayTest(testCase)
            close(testCase.Display.Figure);     %As the window's close button does
            testCase.verifyFalse(isvalid(testCase.Display));
        end

        function DeletingTheWindowDeletesTheDisplayTest(testCase)
            %As the main window does to its dependent windows when it closes -
            %which skips the close request. The display used to stay valid,
            %and then fail every tick on its deleted text
            delete(testCase.Display.Figure);
            testCase.verifyFalse(isvalid(testCase.Display));
        end

        function NoIconFileTest(testCase)
            d = Palladium.Components.BigNumberDisplay("T", "", 1, Icon="", Visible="off");
            testCase.addTeardown(@() delete(d));
            testCase.verifyTrue(isvalid(d));
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function resizeTo(testCase, widthHeight)
            %Resize the window and refit. A hidden window in a batch MATLAB
            %takes a moment to report its new size, so wait for it
            fig = testCase.Display.Figure;
            fig.Position(3:4) = widthHeight;
            timer = tic;
            while any(abs(fig.InnerPosition(3:4) - widthHeight) > 1) && toc(timer) < 5
                drawnow;
                pause(0.05);
            end
            testCase.Display.OnResize();
        end

        function verifyAllTextFits(testCase, label)
            %Every piece of text lies inside the window (the axes covers it exactly)
            ax = findobj(testCase.Display.Figure, "Type", "axes");
            W = ax.XLim(2);
            H = ax.YLim(2);
            texts = findobj(ax, "Type", "text", "Visible", "on");     %Not the hidden measuring text
            for k = 1 : numel(texts)
                e = texts(k).Extent;
                what = label + ": '" + string(texts(k).String) + "'";
                testCase.verifyGreaterThanOrEqual(e(1), -0.5, what + " runs off the left");
                testCase.verifyLessThanOrEqual(e(1) + e(3), W + 0.5, what + " runs off the right");
                testCase.verifyGreaterThanOrEqual(e(2), -0.5, what + " runs off the bottom");
                testCase.verifyLessThanOrEqual(e(2) + e(4), H + 0.5, what + " runs off the top");
            end
        end

        function t = valueText(testCase)
            t = testCase.textShowing(testCase.Display.DisplayedValue);
        end

        function t = unitsText(testCase)
            t = testCase.textShowing(testCase.Display.Units);
        end

        function t = titleText(testCase)
            t = testCase.textShowing(testCase.Display.Title);
        end

        function t = textShowing(testCase, str)
            texts = findobj(testCase.Display.Figure, "Type", "text", "Visible", "on");
            t = texts(string({texts.String}) == str);
            testCase.assertNumElements(t, 1, "One text showing '" + str + "'");
        end
    end
end
