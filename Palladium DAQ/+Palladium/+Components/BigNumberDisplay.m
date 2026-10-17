classdef BigNumberDisplay < handle
    %BigNumberDisplay - A window showing the latest value of one data column in large type, sized to fill the window.
    %Opened from the main window's **New Display** button, so a reading can
    %be seen across the lab. The main GUI calls `UpdateValue` with each new
    %data row. The title (the column's header) runs across the top, and the
    %value, with its units in smaller type, fills the rest. The text is
    %resized to the largest that fits whenever the window is resized or the
    %value gets longer or shorter - never cut off at the sides.
    %
    %Closing the window deletes the object, so `isvalid` shows whether it
    %is still open.
    %
    %The text is drawn in an invisible axes whose units are the window's
    %pixels, as an axes can measure text (a text object's Extent) and a GUI
    %label can't. Text width and height scale in proportion to font size,
    %so each piece is measured once at a reference size and scaled to fit.

    %% Properties (Constant, Private)
    properties (Constant, Access = private)
        ReferenceFontSize = 100;    %Font size (pixels) text is measured at before scaling to fit
        Margin = 0.05;              %Space around the text, as a fraction of the window's smaller side
        TitleHeightFraction = 0.2;  %Most of the window's height the title can take
        UnitsSizeRatio = 0.5;       %Size of the units text, relative to the value's
        UnitsGap = 0.25;            %Space between the value and its units, as a fraction of the value's font size
        NoValueText = "-";          %Shown until the first value arrives
    end

    %% Properties (Public)
    properties (Access = public)
        ColumnIndex (1,1) double {mustBeInteger, mustBePositive} = 1;  %Which column of each data row to show
        NumberFormat (1,1) string = "%.6g";                            %sprintf format of the value, e.g. "%.3f"
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
        FittedLength = -1;          %Number of characters of the value when the text was last fitted
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

            arguments
                title {mustBeTextScalar} = "";
                units {mustBeTextScalar} = "";
                columnIndex (1,1) double {mustBeInteger, mustBePositive} = 1;
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
            this.Figure.SizeChangedFcn = @(~, ~) this.Layout();

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
            this.ValueText = text(0, 0, this.DisplayedValue, textStyle{:}, "FontName", "FixedWidth", "Color", [0 0 0], ...
                "HorizontalAlignment", "left", "VerticalAlignment", "bottom");
            this.UnitsText = text(0, 0, this.Units, textStyle{:}, "Color", [0.25 0.25 0.25], ...
                "HorizontalAlignment", "left", "VerticalAlignment", "bottom");

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
                this.SetDisplayedValue(string(sprintf(this.NumberFormat, dataRow(this.ColumnIndex))));
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

        function SetDisplayedValue(this, str)
            %Show a new value, refitting the text only if its length changed.
            %The value uses a fixed-width font, so the same number of
            %characters always takes the same space

            this.DisplayedValue = str;
            this.ValueText.String = str;
            if strlength(str) ~= this.FittedLength
                this.Layout();
            end
        end

        function Layout(this)
            %Size and place the title, value and units to fill the window without being cut off.

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

            %Title: as large as fits across the window, in the top band
            titleBottom = H - pad;
            if strlength(this.Title) > 0
                titleBand = this.TitleHeightFraction * H;
                titleSize = this.FitFontSize(this.TitleText, usableWidth, titleBand);
                this.TitleText.FontSize = titleSize;
                this.TitleText.Position = [W/2, H - pad, 0];
                titleBottom = H - pad - this.TextSize(this.TitleText, titleSize, "height") - pad;
            end

            %Value and units: as large as fits in the rest, side by side
            valueHeight = max(titleBottom - pad, 1);
            ref = this.ReferenceFontSize;
            [valueW, valueH] = this.MeasureAt(this.ValueText, ref);
            unitsW = 0;
            gap = 0;
            if strlength(this.Units) > 0
                unitsW = this.MeasureAt(this.UnitsText, ref * this.UnitsSizeRatio);
                gap = this.UnitsGap * ref;
            end
            scale = min(usableWidth / (valueW + gap + unitsW), valueHeight / valueH);
            valueSize = max(floor(ref * scale), 1);
            scale = valueSize / ref;

            %Centre the pair horizontally, and the value vertically in its space
            totalWidth = scale * (valueW + gap + unitsW);
            left = (W - totalWidth) / 2;
            bottom = pad + (valueHeight - scale * valueH) / 2;
            this.ValueText.FontSize = valueSize;
            this.ValueText.Position = [left, bottom, 0];
            this.UnitsText.FontSize = max(floor(valueSize * this.UnitsSizeRatio), 1);
            this.UnitsText.Position = [left + scale * (valueW + gap), bottom, 0];

            this.FittedLength = strlength(this.DisplayedValue);
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

        function [w, h] = MeasureAt(textObj, fontSize)
            %The width and height (pixels) of a text object at a font size.
            %Extent isn't updated by a change of FontSize or String alone -
            %it would give the size before - but setting Position makes it
            %measure again

            textObj.FontSize = fontSize;
            textObj.Position = textObj.Position;
            extent = textObj.Extent;
            w = max(extent(3), 1);
            h = max(extent(4), 1);
        end

        function value = TextSize(textObj, fontSize, which)
            %The width or height of a text object at a font size.

            [w, h] = Palladium.Components.BigNumberDisplay.MeasureAt(textObj, fontSize);
            if which == "width"
                value = w;
            else
                value = h;
            end
        end

        function fontSize = FitFontSize(textObj, maxWidth, maxHeight)
            %The largest font size (pixels) at which a text object fits in a box.

            ref = Palladium.Components.BigNumberDisplay.ReferenceFontSize;
            [w, h] = Palladium.Components.BigNumberDisplay.MeasureAt(textObj, ref);
            fontSize = max(floor(ref * min(maxWidth / w, maxHeight / h)), 1);
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
