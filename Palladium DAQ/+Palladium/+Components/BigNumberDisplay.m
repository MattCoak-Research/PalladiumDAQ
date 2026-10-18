classdef BigNumberDisplay < handle
    %BigNumberDisplay - A window showing the latest value of one data column in large type, sized to fill the window.
    %Opened from the main window's **New Display** button, so a reading can
    %be seen across the lab. The Controller calls `UpdateValue` with each
    %new data row. The title (the column's header) runs across the top, and
    %the value, with its units in smaller type, fills the rest - never cut
    %off at the sides.
    %
    %To keep the text steady from tick to tick, values are shown to a fixed
    %number of significant figures (trailing zeros kept), in a fixed-width
    %font, right-aligned against the units. The text is sized to fit the
    %longest value shown since the window was last resized, so it only
    %shrinks when a longer value arrives, and is refitted to the current
    %value when the window is resized.
    %
    %Closing the window deletes the object, so `isvalid` shows whether it
    %is still open.
    %
    %The text is drawn in an invisible axes whose units are the window's
    %pixels, as an axes can measure text (a text object's Extent) and a GUI
    %label can't. Text width and height scale in proportion to font size,
    %so each piece is measured at a reference size and scaled to fit. The
    %measuring is done on a hidden text object, so the visible text only
    %ever changes to its final size.

    %% Properties (Constant, Private)
    properties (Constant, Access = private)
        ReferenceFontSize = 100;    %Font size (pixels) text is measured at before scaling to fit
        Margin = 0.05;              %Space around the text, as a fraction of the window's smaller side
        TitleHeightFraction = 0.2;  %Most of the window's height the title can take
        UnitsSizeRatio = 0.5;       %Size of the units text, relative to the value's
        UnitsGap = 0.25;            %Space between the value and its units, as a fraction of the value's font size
        NoValueText = "-";          %Shown until the first value arrives
        ValueFont = "FixedWidth";   %Font of the value - fixed-width, so each character takes the same space
    end

    %% Properties (Public)
    properties (Access = public)
        ColumnIndex (1,1) double {mustBeInteger, mustBePositive} = 1;  %Which column of each data row to show
        NumberFormat (1,1) string = "%#.6g";                           %sprintf format of the value, e.g. "%.3f". The default keeps 6 significant figures, trailing zeros included
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
        FitLength = 1;              %Number of characters the value's size is fitted for - the longest since the last resize
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
            this.Axes.Toolbar.Visible = "off";
            disableDefaultInteractivity(this.Axes);

            textStyle = {"Parent", this.Axes, "Units", "data", "FontUnits", "pixels", "Interpreter", "none", ...
                "Clipping", "off", "HitTest", "off"};
            this.TitleText = text(0, 0, this.Title, textStyle{:}, "FontWeight", "bold", "Color", [0.25 0.25 0.25], ...
                "HorizontalAlignment", "center", "VerticalAlignment", "top");
            this.ValueText = text(0, 0, this.DisplayedValue, textStyle{:}, "FontName", this.ValueFont, "Color", [0 0 0], ...
                "HorizontalAlignment", "right", "VerticalAlignment", "bottom");
            this.UnitsText = text(0, 0, this.Units, textStyle{:}, "Color", [0.25 0.25 0.25], ...
                "HorizontalAlignment", "left", "VerticalAlignment", "bottom");
            this.Ruler = text(0, 0, "", textStyle{:}, "Visible", "off");

            %Let the new window settle first - text measured in it straight
            %away can come out at the default font size
            drawnow;
            this.Layout();
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
            %A value as text, with NumberFormat - a trailing decimal point removed (e.g. "123457." from "%#.6g").

            str = string(sprintf(this.NumberFormat, value));
            if endsWith(str, ".")
                str = extractBefore(str, strlength(str));
            end
        end

        function SetDisplayedValue(this, str)
            %Show a new value, refitting the text only if it is longer than any shown since the last resize.
            %Shorter values keep the same size (right-aligned, so the digits
            %stay put) - refitting for them made the text jump about

            this.DisplayedValue = str;
            this.ValueText.String = str;
            if strlength(str) > this.FitLength
                this.FitLength = strlength(str);
                this.Layout();
            end
        end

        function OnResize(this)
            %Refit to the current value when the window is resized.

            this.FitLength = max(strlength(this.DisplayedValue), 1);
            this.Layout();
        end

        function Layout(this)
            %Size and place the title, value and units to fill the window without being cut off.
            %The value is sized for FitLength characters

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
                [titleW, titleH] = this.Measure(this.Title, ref, "bold", get(groot, "DefaultTextFontName"));
                titleScale = min(usableWidth / titleW, this.TitleHeightFraction * H / titleH);
                titleSize = max(floor(ref * titleScale), 1);
                this.TitleText.FontSize = titleSize;
                this.TitleText.Position = [W/2, H - pad, 0];
                titleBottom = H - pad - titleH * titleSize / ref - pad;
            end

            %Value and units: as large as fits in the rest, side by side.
            %The value is measured as FitLength characters - in the
            %fixed-width font, any characters take the same space
            valueHeight = max(titleBottom - pad, 1);
            [valueW, valueH] = this.Measure(string(repmat('0', 1, this.FitLength)), ref, "normal", this.ValueFont);
            unitsW = 0;
            gap = 0;
            if strlength(this.Units) > 0
                unitsW = this.Measure(this.Units, ref * this.UnitsSizeRatio, "normal", get(groot, "DefaultTextFontName"));
                gap = this.UnitsGap * ref;
            end
            scale = min(usableWidth / (valueW + gap + unitsW), valueHeight / valueH);
            valueSize = max(floor(ref * scale), 1);
            scale = valueSize / ref;

            %Centre the pair horizontally, and the value vertically in its
            %space. The value is right-aligned, ending just before the units
            totalWidth = scale * (valueW + gap + unitsW);
            valueRight = (W - totalWidth) / 2 + scale * valueW;
            bottom = pad + (valueHeight - scale * valueH) / 2;
            this.ValueText.FontSize = valueSize;
            this.ValueText.Position = [valueRight, bottom, 0];
            this.UnitsText.FontSize = max(floor(valueSize * this.UnitsSizeRatio), 1);
            this.UnitsText.Position = [valueRight + scale * gap, bottom, 0];
        end

        function [w, h] = Measure(this, str, fontSize, fontWeight, fontName)
            %The width and height (pixels) of text at a font size, measured on the hidden Ruler.
            %Extent isn't updated by a change of FontSize or String alone -
            %it would give the size before - but setting Position makes it
            %measure again

            ruler = this.Ruler;
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

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function iconPath = DefaultIconPath()
            %The Big Number icon in the Graphics folder next to this file, or "" if it isn't there.

            iconPath = fullfile(fileparts(mfilename("fullpath")), "Graphics", "BigNumDisplayIcon.png");
            if ~isfile(iconPath)
                iconPath = "";
            end
        end

    end
end
