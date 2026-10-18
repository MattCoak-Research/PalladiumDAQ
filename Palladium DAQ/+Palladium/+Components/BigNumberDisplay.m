classdef BigNumberDisplay < handle
    %BigNumberDisplay - A window showing the latest value of one data column in large type, sized to fill the window.
    %Opened from the main window's **New Display** button, so a reading can
    %be seen across the lab. The Controller calls `UpdateValue` with each
    %new data row. The title (the column's header) runs across the top, and
    %the value, with its units in smaller type, fills the rest - never cut
    %off at the sides.
    %
    %Values are shown to SignificantFigures significant figures. Very large
    %or small values (those sprintf's "%g" would show as e.g. 1.23450e+07)
    %are shown in engineering notation instead - a power of ten that is a
    %multiple of 3, written as a superscript: 12.3450×10⁶. Set NumberFormat
    %to format values with sprintf instead.
    %
    %To keep the text steady from tick to tick, trailing zeros are kept,
    %the value is in a fixed-width font, and it is right-aligned against
    %the units. The text is sized to fit the widest value shown since the
    %window was last resized, so it only shrinks when a wider value
    %arrives, and is refitted to the current value when the window is
    %resized.
    %
    %Closing the window deletes the object, so `isvalid` shows whether it
    %is still open.
    %
    %The text is drawn in an invisible axes whose units are the window's
    %pixels, as an axes can measure text (a text object's Extent) and a GUI
    %label can't. Text width and height scale roughly in proportion to font
    %size, so each piece is measured at a reference size and scaled to fit,
    %then measured again at that size and shrunk until it really fits - at
    %small sizes text is relatively bigger (TeX superscripts keep a minimum
    %size, and fonts differ between systems). The measuring is done on a
    %hidden text object, so the visible text only ever changes to its final
    %size.

    %% Properties (Constant, Private)
    properties (Constant, Access = private)
        ReferenceFontSize = 100;    %Font size (pixels) text is measured at before scaling to fit
        Margin = 0.05;              %Space around the text, as a fraction of the window's smaller side
        TitleHeightFraction = 0.2;  %Most of the window's height the title can take
        UnitsSizeRatio = 0.5;       %Size of the units text, relative to the value's
        UnitsGap = 0.25;            %Space between the value and its units, as a fraction of the value's font size
        NoValueText = "-";          %Shown until the first value arrives
        ValueFont = "FixedWidth";   %Font of the value - fixed-width, so each character takes the same space
        MaxShrinkSteps = 20;        %Most times Layout shrinks text that doesn't fit at the size first worked out
    end

    %% Properties (Constant, Public)
    properties (Constant, Access = public)
        DefaultSignificantFigures = 6;  %Significant figures values are shown to, unless set otherwise
    end

    %% Properties (Public)
    properties (Access = public)
        ColumnIndex (1,1) double {mustBeInteger, mustBePositive} = 1;  %Which column of each data row to show
        SignificantFigures (1,1) double {mustBeInteger, mustBePositive} = Palladium.Components.BigNumberDisplay.DefaultSignificantFigures;  %Significant figures the value is shown to, trailing zeros included
        NumberFormat (1,1) string {Palladium.Components.BigNumberDisplay.mustBeNumberFormat} = "";  %sprintf format of the value, e.g. "%.3f", used instead of SignificantFigures and engineering notation. "" (the default) for those
    end

    %% Properties (Public, Private Set)
    properties (GetAccess = public, SetAccess = private)
        Figure;                         %The window
        Title (1,1) string = "";        %Shown across the top - normally the column's header
        Units (1,1) string = "";        %Shown after the value, smaller
        DisplayedValue (1,1) string = Palladium.Components.BigNumberDisplay.NoValueText;   %The value as shown
    end

    %% Properties (Private)
    properties (Access = private)
        Axes;                       %Invisible axes the text is drawn in, in pixel coordinates
        TitleText;                  %Text objects for the title, value and units
        ValueText;
        UnitsText;
        Ruler;                      %Hidden text object used to measure text, so the visible text isn't changed while measuring
        FitWidth = 1;               %Size (pixels, at ReferenceFontSize) the value's text is fitted for - the widest and tallest since the last resize
        FitHeight = 1;
        FitShape = "";              %The last value measured, with its digits as 0s - in the fixed-width font, values of the same shape take the same space
        FitWidthValue = "";         %The values that set FitWidth and FitHeight - measured again at the size chosen, to check they fit
        FitHeightValue = "";
    end

    %% Constructor
    methods
        function this = BigNumberDisplay(title, units, columnIndex, Settings)
            %Open a display window for one data column.
            %
            %Inputs:
            %   title       - shown across the top, e.g. the column's header
            %   units       - shown after the value, e.g. "K" ("" for none)
            %   columnIndex - which column of each data row to show
            %   Icon        - (name-value) window icon file. Default: the Big Number icon, if found
            %   Visible     - (name-value) "off" to keep the window hidden, e.g. in tests. Default "on"

            %Required, not optional: MATLAB takes an optional argument that
            %is text matching the start of an option's name as that option -
            %units "V" were read as Visible, and "I" as Icon
            arguments
                title {mustBeTextScalar};
                units {mustBeTextScalar};
                columnIndex (1,1) double {mustBeInteger, mustBePositive};
                Settings.Icon {mustBeTextScalar} = Palladium.Components.BigNumberDisplay.DefaultIconPath();
                Settings.Visible {mustBeMember(Settings.Visible, ["on", "off"])} = "on";
            end

            this.Title = string(title);
            this.Units = string(units);
            this.ColumnIndex = columnIndex;

            this.Figure = uifigure("Name", this.WindowName(), "Visible", "off", "AutoResizeChildren", "off", ...
                "Color", [1 1 1], "Position", [100 100 520 300]);
            if strlength(Settings.Icon) > 0 && isfile(Settings.Icon)
                this.Figure.Icon = Settings.Icon;
            end
            this.Figure.CloseRequestFcn = @(~, ~) delete(this);
            this.Figure.SizeChangedFcn = @(~, ~) this.OnResize();

            %Go with the window however it is closed - e.g. deleted by the
            %main window as it closes, which skips CloseRequestFcn
            addlistener(this.Figure, "ObjectBeingDestroyed", @(~, ~) delete(this));

            %An axes filling the window, in pixel coordinates, to draw and
            %measure the text in - with nothing of the axes itself shown
            this.Axes = axes(this.Figure, "Units", "pixels", "Visible", "off", "HitTest", "off", ...
                "XLimMode", "manual", "YLimMode", "manual");
            %Remove the axes toolbar, rather than hiding it: reading
            %Toolbar makes MATLAB create the default toolbar, which in a
            %new window intermittently errored with "Invalid or deleted
            %object" (its listener on the axes' interaction container)
            this.Axes.Toolbar = [];
            disableDefaultInteractivity(this.Axes);

            textStyle = {"Parent", this.Axes, "Units", "data", "FontUnits", "pixels", "Interpreter", "none", ...
                "Clipping", "off", "HitTest", "off"};
            this.TitleText = text(0, 0, this.Title, textStyle{:}, "FontWeight", "bold", "Color", [0.25 0.25 0.25], ...
                "HorizontalAlignment", "center", "VerticalAlignment", "top");
            this.ValueText = text(0, 0, this.DisplayedValue, textStyle{:}, "Interpreter", "tex", "FontName", this.ValueFont, "Color", [0 0 0], ...
                "HorizontalAlignment", "right", "VerticalAlignment", "bottom");
            this.UnitsText = text(0, 0, this.Units, textStyle{:}, "Color", [0.25 0.25 0.25], ...
                "HorizontalAlignment", "left", "VerticalAlignment", "bottom");
            this.Ruler = text(0, 0, "", textStyle{:}, "Visible", "off");

            %Let the new window settle first - text measured in it straight
            %away can come out at the default font size
            drawnow;
            this.OnResize();
            this.Figure.Visible = Settings.Visible;
        end

        function delete(this)
            %Close the window along with the object.

            if ~isempty(this.Figure) && isvalid(this.Figure) && this.Figure.BeingDeleted ~= "on"
                delete(this.Figure);
            end
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function UpdateValue(this, dataRow)
            %Show this display's column of a new data row - called each measurement tick.
            %NaN shows as "NaN". A row too short to have the column shows "-"
            %
            %Inputs:
            %   dataRow - the row of values, one per column

            arguments
                this;
                dataRow (1,:) double;
            end

            if this.ColumnIndex > numel(dataRow)
                this.SetDisplayedValue(Palladium.Components.BigNumberDisplay.NoValueText);
            else
                this.SetDisplayedValue(this.FormatValue(dataRow(this.ColumnIndex)));
            end
        end

        function SetTitle(this, title)
            %Change the title shown across the top, and the window's name.

            arguments
                this;
                title {mustBeTextScalar};
            end

            this.Title = string(title);
            this.TitleText.String = this.Title;
            this.Figure.Name = this.WindowName();
            this.Layout();
        end

        function SetUnits(this, units)
            %Change the units shown after the value ("" for none).

            arguments
                this;
                units {mustBeTextScalar};
            end

            this.Units = string(units);
            this.UnitsText.String = this.Units;
            this.Layout();
        end

    end

    %% Methods (Private)
    methods (Access = {?Palladium.Components.BigNumberDisplay, ?matlab.unittest.TestCase})    %Permission is Private, but also allow unit tests to see it

        function str = FormatValue(this, value)
            %A value as text, with this display's SignificantFigures and NumberFormat (see Format).

            str = Palladium.Components.BigNumberDisplay.Format(value, this.SignificantFigures, this.NumberFormat);
        end

        function SetDisplayedValue(this, str)
            %Show a new value, refitting the text only if it is wider or taller than any shown since the last resize.
            %Smaller values keep the same size (right-aligned, so the digits
            %stay put) - refitting for them made the text jump about

            this.DisplayedValue = str;
            this.ValueText.String = str;
            if this.MeasureValue()
                this.Layout();
            end
        end

        function OnResize(this)
            %Refit to the current value when the window is resized.

            this.FitWidth = 0;
            this.FitHeight = 0;
            this.FitShape = "";
            this.FitWidthValue = "";
            this.FitHeightValue = "";
            this.MeasureValue();
            this.Layout();
        end

        function grown = MeasureValue(this)
            %Measure the displayed value, growing the size the value is fitted for to take it - true if it grew.
            %In the fixed-width font, every digit takes the same space, so
            %a value of the same shape as the last one measured (the same
            %with its digits as 0s) isn't measured again

            shape = regexprep(this.DisplayedValue, "\d", "0");
            grown = false;
            if shape == this.FitShape
                return;
            end
            this.FitShape = shape;
            [w, h] = this.Measure(this.DisplayedValue, this.ReferenceFontSize, "normal", this.ValueFont, "tex");
            if w > this.FitWidth
                this.FitWidth = w;
                this.FitWidthValue = this.DisplayedValue;
                grown = true;
            end
            if h > this.FitHeight
                this.FitHeight = h;
                this.FitHeightValue = this.DisplayedValue;
                grown = true;
            end
        end

        function Layout(this)
            %Size and place the title, value and units to fill the window without being cut off.
            %The value is sized for FitWidth and FitHeight

            if isempty(this.Figure) || ~isvalid(this.Figure)
                return;
            end

            %Work in the window's pixels: the axes fills it, with matching limits
            pos = this.Figure.InnerPosition;
            W = max(pos(3), 1);
            H = max(pos(4), 1);
            this.Axes.Position = [1 1 W H];
            this.Axes.XLim = [0 W];
            this.Axes.YLim = [0 H];

            pad = this.Margin * min(W, H);
            usableWidth = max(W - 2*pad, 1);
            ref = this.ReferenceFontSize;

            %Title: as large as fits across the window, in the top band
            titleBottom = H - pad;
            if strlength(this.Title) > 0
                titleFont = get(groot, "DefaultTextFontName");
                [titleW, titleH] = this.Measure(this.Title, ref, "bold", titleFont);
                titleScale = min(usableWidth / titleW, this.TitleHeightFraction * H / titleH);
                titleSize = max(floor(ref * titleScale), 1);

                %Check it at that size - on the Ruler, then as drawn - and
                %shrink it until it fits
                for step = 1:this.MaxShrinkSteps
                    [titleW, titleH] = this.Measure(this.Title, titleSize, "bold", titleFont);
                    this.TitleText.FontSize = titleSize;
                    this.TitleText.Position = [W/2, H - pad, 0];

                    over = max(titleW / usableWidth, titleH / (this.TitleHeightFraction * H));
                    if ~this.IsInside(this.TitleText, [0, W, 0, H])
                        over = max(over, 1.01);     %Measured to fit, but drawn over the edge
                    end
                    if over <= 1 || titleSize == 1
                        break;
                    end
                    titleSize = this.ShrunkSize(titleSize, over);
                end
                titleBottom = H - pad - titleH - pad;
            end

            %Value and units: as large as fits in the rest, side by side
            valueHeight = max(titleBottom - pad, 1);
            valueW = this.FitWidth;
            valueH = this.FitHeight;
            unitsW = 0;
            gap = 0;
            if strlength(this.Units) > 0
                unitsW = this.Measure(this.Units, ref * this.UnitsSizeRatio, "normal", get(groot, "DefaultTextFontName"));
                gap = this.UnitsGap * ref;
            end
            scale = min(usableWidth / (valueW + gap + unitsW), valueHeight / valueH);
            valueSize = max(floor(ref * scale), 1);

            %Check the values the size is fitted for, and the units, at that
            %size - on the Ruler, then as drawn - and shrink it until they fit
            for step = 1:this.MaxShrinkSteps
                [valueW, valueH, unitsW, gap, unitsSize] = this.MeasureValueAndUnits(valueSize);

                %Centre the pair horizontally, and the value vertically in its
                %space. The value is right-aligned, ending just before the units
                totalWidth = valueW + gap + unitsW;
                valueRight = (W - totalWidth) / 2 + valueW;
                bottom = pad + (valueHeight - valueH) / 2;
                this.ValueText.FontSize = valueSize;
                this.ValueText.Position = [valueRight, bottom, 0];
                this.UnitsText.FontSize = unitsSize;
                this.UnitsText.Position = [valueRight + gap, bottom, 0];

                over = max(totalWidth / usableWidth, valueH / valueHeight);
                if ~this.IsInside([this.ValueText, this.UnitsText], [0, W, 0, titleBottom + pad])
                    over = max(over, 1.01);     %Measured to fit, but drawn over the edge
                end
                if over <= 1 || valueSize == 1
                    break;
                end
                valueSize = this.ShrunkSize(valueSize, over);
            end
        end

        function inside = IsInside(~, texts, box)
            %True if the text objects, as drawn, are inside a box [left, right, bottom, top] (pixels), to within half a pixel.
            %Empty text is ignored

            inside = true;
            for t = texts
                if strlength(string(t.String)) == 0
                    continue;
                end
                e = t.Extent;
                inside = inside && e(1) >= box(1) - 0.5 && e(1) + e(3) <= box(2) + 0.5 ...
                    && e(2) >= box(3) - 0.5 && e(2) + e(4) <= box(4) + 0.5;
            end
        end

        function [valueW, valueH, unitsW, gap, unitsSize] = MeasureValueAndUnits(this, valueSize)
            %The space (pixels) the value and units take at a font size - the value's being the widest and tallest it is fitted for.
            %
            %Inputs:
            %   valueSize - the value's font size
            %
            %Outputs:
            %   valueW, valueH - width and height of the value
            %   unitsW         - width of the units (0 with no units)
            %   gap            - space between the value and units (0 with no units)
            %   unitsSize      - the units' font size

            [valueW, valueH] = this.Measure(this.FitWidthValue, valueSize, "normal", this.ValueFont, "tex");
            if this.FitHeightValue ~= this.FitWidthValue
                [w, h] = this.Measure(this.FitHeightValue, valueSize, "normal", this.ValueFont, "tex");
                valueW = max(valueW, w);
                valueH = max(valueH, h);
            end

            unitsSize = max(floor(valueSize * this.UnitsSizeRatio), 1);
            unitsW = 0;
            gap = 0;
            if strlength(this.Units) > 0
                unitsW = this.Measure(this.Units, unitsSize, "normal", get(groot, "DefaultTextFontName"));
                gap = this.UnitsGap * valueSize;
            end
        end

        function newSize = ShrunkSize(~, fontSize, over)
            %A smaller font size for text that is too big by a factor of over - always at least 1 smaller, and never below 1.

            newSize = max(min(fontSize - 1, floor(fontSize / over)), 1);
        end

        function [w, h] = Measure(this, str, fontSize, fontWeight, fontName, interpreter)
            %The width and height (pixels) of text at a font size, measured on the hidden Ruler.
            %Extent isn't updated by a change of FontSize or String alone -
            %it would give the size before - but setting Position makes it
            %measure again

            arguments
                this;
                str;
                fontSize;
                fontWeight;
                fontName;
                interpreter = "none";
            end

            ruler = this.Ruler;
            ruler.Interpreter = interpreter;
            ruler.String = str;
            ruler.FontName = fontName;
            ruler.FontWeight = fontWeight;
            ruler.FontSize = fontSize;
            ruler.Position = ruler.Position;
            extent = ruler.Extent;
            w = max(extent(3), 1);
            h = max(extent(4), 1);
        end

        function name = WindowName(this)
            %The window's title bar text.

            if strlength(this.Title) > 0
                name = this.Title;
            else
                name = "Big Number Display";
            end
        end

    end

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function choice = ChooseColumn(headers, Settings)
            %Ask the user which data column to show, and how to show its value, in a small window.
            %A uifigure on top of the others (see GUIUtils.OpenDialog), like
            %GUIUtils.ChooseFromList, with the list of
            %columns, the significant figures, and a number format to use
            %instead - previewed on example values as they are changed.
            %Double-clicking a column chooses it. Blocks until the user
            %chooses or cancels
            %
            %Inputs:
            %   headers   - the data columns' headers
            %   Reference - (name-value) a window to centre on, e.g. the main window. Default: none
            %   Icon      - (name-value) window icon file, e.g. Palladium's. Default: none
            %
            %Outputs:
            %   choice - struct with fields Column (its number), SignificantFigures
            %            and NumberFormat ("" for automatic); or [] if cancelled

            arguments
                headers {mustBeText};
                Settings.Reference = [];
                Settings.Icon = [];
            end

            headers = string(headers(:))';
            choice = [];
            if isempty(headers)
                return;
            end

            %Only one at a time - clicking New Display again brings it forward
            fig = Palladium.Utilities.GUIUtils.OpenDialog("New Big Number Display", [360, 520], ...
                Reference=Settings.Reference, Icon=Settings.Icon, Tag="Palladium.BigNumberDisplay.ChooseColumn");
            if isempty(fig)
                return;
            end
            grid = uigridlayout(fig, [6, 2], "RowHeight", {"fit", "1x", 22, 22, 40, 30}, "ColumnWidth", {"fit", "1x"});

            prompt = uilabel(grid, "Text", "Choose the data column to show:", "FontWeight", "bold");
            place(prompt, 1, [1 2]);
            list = uilistbox(grid, "Items", headers, "ItemsData", 1 : numel(headers), "Value", 1, ...
                "DoubleClickedFcn", @(~, ~) choose());
            place(list, 2, [1 2]);

            place(uilabel(grid, "Text", "Significant figures:"), 3, 1);
            figures = uispinner(grid, "Limits", [1 15], "RoundFractionalValues", "on", "Step", 1, ...
                "Value", Palladium.Components.BigNumberDisplay.DefaultSignificantFigures, ...
                "ValueChangedFcn", @(~, ~) preview());
            place(figures, 3, 2);
            place(uilabel(grid, "Text", "Number format:"), 4, 1);
            formatField = uieditfield(grid, "text", "Placeholder", "Automatic - or e.g. %.3f", ...
                "Tooltip", "An sprintf format for the value, used instead of the significant figures - e.g. %.3f or %.4e. Leave empty for automatic", ...
                "ValueChangingFcn", @(~, event) preview(event.Value), "ValueChangedFcn", @(~, ~) preview());
            place(formatField, 4, 2);
            example = uilabel(grid, "Interpreter", "tex", "WordWrap", "on", "VerticalAlignment", "top");
            place(example, 5, [1 2]);

            buttons = uigridlayout(grid, [1, 3], "ColumnWidth", {"1x", 80, 80}, "Padding", [0 0 0 0]);
            place(buttons, 6, [1 2]);
            ok = uibutton(buttons, "Text", "OK", "ButtonPushedFcn", @(~, ~) choose());
            ok.Layout.Column = 2;
            cancel = uibutton(buttons, "Text", "Cancel", "ButtonPushedFcn", @(~, ~) uiresume(fig));
            cancel.Layout.Column = 3;
            fig.CloseRequestFcn = @(~, ~) uiresume(fig);    %Closing the window cancels

            preview();
            uiwait(fig);
            Palladium.Utilities.GUIUtils.CloseDialog(fig, Settings.Reference);

            function place(component, row, column)
                component.Layout.Row = row;
                component.Layout.Column = column;
            end

            function preview(numberFormat)
                %Show example values as they would be shown - or why the format can't be used.
                %Given the format while it is being typed; otherwise reads the
                %box. (The callbacks call this rather than reading the box
                %themselves: an anonymous function only sees variables that
                %existed when it was made, and the box is made after the spinner)
                if nargin < 1
                    numberFormat = formatField.Value;
                end
                numberFormat = string(numberFormat);
                figures.Enable = strlength(numberFormat) == 0;     %Not used with a format
                if Palladium.Components.BigNumberDisplay.IsNumberFormat(numberFormat)
                    examples = arrayfun(@(v) Palladium.Components.BigNumberDisplay.Format(v, figures.Value, numberFormat), ...
                        [pi, -0.00123456789, 12345678.9]);
                    example.Text = "Shown as:   " + join(examples, ",   ");
                    example.FontColor = [0 0 0];
                    ok.Enable = "on";
                else
                    example.Text = "Not a number format - it needs one number, e.g. %.3f or %.4e V";
                    example.FontColor = [0.8 0 0];
                    ok.Enable = "off";
                end
            end

            function choose()
                if ok.Enable == "off"
                    return;     %Double-clicked a column with an unusable format
                end
                choice = struct("Column", list.Value, "SignificantFigures", figures.Value, "NumberFormat", string(formatField.Value));
                uiresume(fig);
            end
        end

        function str = Format(value, significantFigures, numberFormat)
            %A value as text, as a Big Number Display shows it - in TeX, for its text object.
            %With numberFormat "": to significantFigures significant
            %figures, trailing zeros kept, in engineering notation where
            %"%g" would use e-notation - "12.3450\times10^{6}" for 1.2345e7.
            %Otherwise with sprintf(numberFormat, value), any TeX special
            %characters shown as themselves. A trailing decimal point is
            %removed either way
            %
            %Inputs:
            %   value              - the number
            %   significantFigures - significant figures, for automatic formatting
            %   numberFormat       - an sprintf format, or "" for automatic

            arguments
                value (1,1) double;
                significantFigures (1,1) double {mustBeInteger, mustBePositive};
                numberFormat {mustBeTextScalar};
            end

            if strlength(numberFormat) > 0
                str = regexprep(string(sprintf(numberFormat, value)), "([\\{}_^])", "\\$1");
            elseif ~isfinite(value)
                str = string(sprintf("%g", value));    %NaN, Inf, -Inf
            else
                str = Palladium.Components.BigNumberDisplay.FormatSignificant(value, significantFigures);
            end
            if endsWith(str, ".")
                str = extractBefore(str, strlength(str));
            end
        end

        function tf = IsNumberFormat(numberFormat)
            %True if numberFormat is "" (automatic) or an sprintf format for one number, e.g. "%.3f" or "%.4e V".
            %One conversion, of a number (d i u f e E g G x X o) - "%%" for
            %a % sign aside. Not %s or %c, or more than one value

            numberFormat = string(numberFormat);
            rest = erase(numberFormat, "%%");
            tf = strlength(numberFormat) == 0 || ...
                (count(rest, "%") == 1 && ~isempty(regexp(rest, "%[-+ #0]*\d*(\.\d+)?[diufeEgGxXo]", "once")));
        end

        function mustBeNumberFormat(numberFormat)
            %Validate that numberFormat is "" or an sprintf format for one number (see IsNumberFormat).

            if ~Palladium.Components.BigNumberDisplay.IsNumberFormat(numberFormat)
                error("BigNumberDisplay:InvalidNumberFormat", "%s", ...
                    """" + numberFormat + """ is not a format for one number - use e.g. ""%.3f"" or ""%.4e"", or """" for automatic");
            end
        end

    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function str = FormatSignificant(value, significantFigures)
            %A finite value to significantFigures significant figures - in engineering notation where "%g" would use e-notation.
            %Worked from sprintf's e-notation of the value, so the digits and
            %exponent are rounded as sprintf rounds them (999999.7 to
            %1.00000e+06), with no arithmetic to add rounding errors

            sf = significantFigures;
            parts = regexp(sprintf('%.*e', sf - 1, abs(value)), '^(\d)\.?(\d*)e([+-]\d+)$', 'tokens', 'once');
            digits = [parts{1}, parts{2}];
            exponent = str2double(parts{3});

            if exponent >= -4 && exponent < sf
                str = string(sprintf('%#.*g', sf, value));
                return;
            end

            %Engineering notation: a power of ten that is a multiple of 3,
            %with 1 to 3 digits before the decimal point
            power = 3 * floor(exponent / 3);
            leading = exponent - power + 1;
            digits = [digits, repmat('0', 1, leading - numel(digits))];    %Fewer significant figures than leading digits
            mantissa = string(digits(1:leading));
            if numel(digits) > leading
                mantissa = mantissa + "." + digits(leading+1:end);
            end
            if value < 0
                mantissa = "-" + mantissa;
            end
            str = mantissa + "\times10^{" + power + "}";
        end

        function iconPath = DefaultIconPath()
            %The Big Number icon in the Graphics folder next to this file, or "" if it isn't there.

            iconPath = fullfile(fileparts(mfilename("fullpath")), "Graphics", "BigNumDisplayIcon.png");
            if ~isfile(iconPath)
                iconPath = "";
            end
        end

    end
end
