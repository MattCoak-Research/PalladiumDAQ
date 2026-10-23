classdef GUIUtils
    %GUIUtils - Static functions for the GUI, mainly the Instrument Options panel that edits instrument settings.
    %The Instrument Options panel builds a field for each property that
    %`ComputePropertyList` returns, shows its value with `ToScalarString`,
    %and reads typed number lists back with `ToDoubleArrayFromScalarString`.
    %`MessageToHTML` formats messages for dialogue boxes, `EscapeLaTeX`
    %makes any text (e.g. a column header) show as typed in LaTeX-interpreted
    %labels (`GreekToLaTeX` converts just the Greek letters),
    %`ChooseFromList` asks the user to pick one item from a list,
    %`ChooseFile` asks for a file or folder, `IsSmithPlotAvailable` says
    %whether RF Toolbox's Smith chart can be used, and `ShowWarning` shows a
    %warning in the window it concerns.

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function available = IsSmithPlotAvailable()
            %True if RF Toolbox, which has the Smith chart plot (smithplot), is installed and licensed.
            %Palladium runs without it - only the Smith chart option needs it
            %
            %Outputs:
            %   available - true if smithplot can be used

            available = exist("smithplot", "file") > 0 && license("test", "RF_Toolbox") == 1;
        end

        function BringToFront(owner)
            %Bring the window holding owner back to the front, and give it focus.
            %For after a dialogue such as uigetfile, which can leave
            %Palladium's window behind others. Uses figure(fig), which brings
            %a uifigure forward. Does nothing if there is no window showing
            %
            %Inputs:
            %   owner - anything in the window: a figure, a component in it, or an App Designer app

            fig = Palladium.Utilities.GUIUtils.FindUIFigure(owner);
            if isempty(fig)
                return;
            end
            figure(fig);
        end

        function path = ChooseFile(mode, Settings)
            %Ask the user for a file to open or save, or a folder, then bring the window back to the front.
            %Uses the system's dialogues (uigetfile, uiputfile and uigetdir).
            %These belong to the MATLAB desktop window, so Windows raises the
            %desktop beneath them while they are open - Palladium's window
            %goes behind it, and there is no option to prevent that. When
            %the dialogue closes, the Reference window is brought back to
            %the front with BringToFront
            %
            %Inputs:
            %   mode      - "open" (a file to open), "save" (a file to save to) or "folder"
            %   Filter    - (name-value) file types for "open" and "save", e.g.
            %               {'*.json', 'JSON files'}. Default: all files
            %   Title     - (name-value) the dialogue's title. Default ""
            %   Default   - (name-value) the file or folder it starts at. Default ""
            %   Reference - (name-value) the window to bring back afterwards, e.g. the main window. Default: none
            %
            %Outputs:
            %   path - the full path chosen, or "" if cancelled

            arguments
                mode {mustBeMember(mode, ["open", "save", "folder"])};
                Settings.Filter = {'*.*', 'All Files'};
                Settings.Title {mustBeTextScalar} = "";
                Settings.Default {mustBeTextScalar} = "";
                Settings.Reference = [];
            end

            title = char(Settings.Title);
            default = char(Settings.Default);
            switch mode
                case "open";    [file, location] = uigetfile(Settings.Filter, title, default);
                case "save";    [file, location] = uiputfile(Settings.Filter, title, default);
                case "folder";  file = "";  location = uigetdir(default, title);
            end

            Palladium.Utilities.GUIUtils.BringToFront(Settings.Reference);

            %0 when cancelled
            if isequal(location, 0) || isequal(file, 0)
                path = "";
            else
                path = string(fullfile(location, file));
            end
        end

        function ShowWarning(owner, message, title)
            %Show a warning box in the window holding owner (a uialert) - or log it if there is no window.
            %Use in place of warndlg: that is an old-style figure, which can
            %send Palladium's (uifigure) windows to the back when it closes.
            %The message is shown as MessageToHTML formats it (links, code
            %in backticks). With no window to show it in - e.g. running without a GUI, or a
            %hidden window - the warning is logged instead
            %
            %Inputs:
            %   owner   - anything in the window: a figure, a component in
            %             it, or an App Designer app; or [] for none
            %   message - the warning
            %   title   - (optional) the warning box's title. Default "Warning"

            arguments
                owner;
                message {mustBeTextScalar};
                title {mustBeTextScalar} = "Warning";
            end

            fig = Palladium.Utilities.GUIUtils.FindUIFigure(owner);
            if isempty(fig)
                Palladium.Logging.Logger.Log("Warning", message);
            else
                uialert(fig, Palladium.Utilities.GUIUtils.MessageToHTML(message), title, "Icon", "warning", "Interpreter", "html");
            end
        end

        function position = CentredPosition(dialogSize, reference)
            %The Position for a dialogue window of a size, centred on a reference window - or near the screen's corner without one.
            %
            %Inputs:
            %   dialogSize - [width, height] of the dialogue, in pixels
            %   reference  - the window to centre on, e.g. the main window; or [] for none
            %
            %Outputs:
            %   position - [left, bottom, width, height]

            position = [100, 100, dialogSize];
            if ~isempty(reference) && isvalid(reference)
                refPos = reference.Position;
                position(1:2) = refPos(1:2) + (refPos(3:4) - dialogSize) / 2;
            end
        end

        function fig = OpenDialog(title, dialogSize, Settings)
            %Open a dialogue window, on top of the others and centred on the window it is opened from - or bring it forward if it is already open.
            %Not modal: when a modal uifigure closed, MATLAB sometimes put
            %its desktop window at the top of the stack, above the window
            %the dialogue was opened from - seen in a log of the window
            %order, whenever another program's window had come between
            %them. Instead the dialogue stays on top ("alwaysontop"), and
            %only one with the same Tag can be open at a time. Close it with
            %CloseDialog
            %
            %Inputs:
            %   title      - the window's title
            %   dialogSize - [width, height] in pixels
            %   Reference  - (name-value) the window to centre on, e.g. the main window - or anything
            %                in it: a component or an App Designer app. Default: none
            %   Icon       - (name-value) window icon file. Default: none
            %   Tag        - (name-value) identifies the dialogue, so only one is open at a time. Default "": no limit
            %
            %Outputs:
            %   fig - the new uifigure, or [] if one with this Tag was already open (it is brought to the front instead)

            arguments
                title {mustBeTextScalar};
                dialogSize (1,2) double;
                Settings.Reference = [];
                Settings.Icon = [];
                Settings.Tag {mustBeTextScalar} = "";
            end

            if strlength(Settings.Tag) > 0
                existing = findall(groot, "Type", "figure", "Tag", Settings.Tag);
                if ~isempty(existing)
                    figure(existing(1));
                    fig = [];
                    return;
                end
            end

            fig = uifigure("Name", title, "WindowStyle", "alwaysontop", "Resize", "off", "Tag", Settings.Tag, ...
                "Position", Palladium.Utilities.GUIUtils.CentredPosition(dialogSize, Palladium.Utilities.GUIUtils.FindUIFigure(Settings.Reference)));
            if ~isempty(Settings.Icon) && isfile(Settings.Icon)
                fig.Icon = Settings.Icon;
            end
        end

        function CloseDialog(fig, reference)
            %Close a dialogue window opened with OpenDialog, and bring the window it was opened from back to the front.
            %When a window closes, Windows picks the next window to be the
            %front one, which may be another program's - so the window it
            %was opened from is brought back explicitly
            %
            %Inputs:
            %   fig       - the dialogue's uifigure (already deleted is fine)
            %   reference - the window it was opened from; or [] for none

            if isvalid(fig)
                delete(fig);
            end
            drawnow;
            Palladium.Utilities.GUIUtils.BringToFront(reference);
        end

        function index = ChooseFromList(items, Settings)
            %Ask the user to pick one item from a list, in a small window - like listdlg, but a uifigure.
            %listdlg is an old-style figure: when it closes, the system can
            %hand focus to some other window, sending Palladium's (uifigure)
            %windows to the back. This keeps the exchange in uifigures.
            %Double-clicking an item chooses it. Blocks until the user
            %chooses or cancels
            %
            %Inputs:
            %   items     - the items to show (string array or cell array of text)
            %   Title     - (name-value) window title. Default "Select"
            %   Prompt    - (name-value) text above the list. Default ""
            %   Reference - (name-value) a window to centre on, e.g. the main window. Default: none
            %   Icon      - (name-value) window icon file, e.g. Palladium's. Default: none
            %
            %Outputs:
            %   index - the number of the item chosen, or [] if cancelled

            arguments
                items {mustBeText};
                Settings.Title {mustBeTextScalar} = "Select";
                Settings.Prompt {mustBeTextScalar} = "";
                Settings.Reference = [];
                Settings.Icon = [];
            end

            items = string(items(:))';
            index = [];
            if isempty(items)
                return;
            end

            fig = Palladium.Utilities.GUIUtils.OpenDialog(Settings.Title, [300, 400], ...
                Reference=Settings.Reference, Icon=Settings.Icon, Tag="Palladium.ChooseFromList." + Settings.Title);
            if isempty(fig)
                return;
            end
            grid = uigridlayout(fig, [3, 1], "RowHeight", {"fit", "1x", 30});
            if strlength(Settings.Prompt) > 0
                prompt = uilabel(grid, "Text", Settings.Prompt, "WordWrap", "on", "FontWeight", "bold");
                prompt.Layout.Row = 1;
            end
            list = uilistbox(grid, "Items", items, "ItemsData", 1 : numel(items), "Value", 1, ...
                "DoubleClickedFcn", @(~, ~) choose());
            list.Layout.Row = 2;
            buttons = uigridlayout(grid, [1, 3], "ColumnWidth", {"1x", 80, 80}, "Padding", [0 0 0 0]);
            buttons.Layout.Row = 3;
            ok = uibutton(buttons, "Text", "OK", "ButtonPushedFcn", @(~, ~) choose());
            ok.Layout.Column = 2;
            cancel = uibutton(buttons, "Text", "Cancel", "ButtonPushedFcn", @(~, ~) uiresume(fig));
            cancel.Layout.Column = 3;
            fig.CloseRequestFcn = @(~, ~) uiresume(fig);    %Closing the window cancels

            uiwait(fig);
            Palladium.Utilities.GUIUtils.CloseDialog(fig, Settings.Reference);

            function choose()
                index = list.Value;
                uiresume(fig);
            end
        end

        function propertyList = ComputePropertyList(instrument, exposeSubClassProperties)
            %The names of an instrument's GUI-editable properties: public, SetObservable and not hidden.
            %Properties the instrument hides for its connection type (see
            %`Instrument.ShowProperty`), such as the GPIB address when it is
            %connected by serial, are left out
            %
            %Inputs:
            %   instrument               - the instrument, or [] (giving [])
            %   exposeSubClassProperties - true to include properties it
            %                              inherits; false for only those its
            %                              own class defines
            %
            %Outputs:
            %   propertyList - the property names, as a column string array

            %Handle case of empty reference
            if(isempty(instrument))
                propertyList = [];
                return;
            end

            objectClass = string(class(instrument));

            % If we're exposing subclass properties this is trivial.
            if exposeSubClassProperties
                propertyList = strings(0);
                metaClass = metaclass(instrument);

                for i=1:length(metaClass.PropertyList)
                    prop = metaClass.PropertyList(i);
                    % Add to the list only non-hidden publicly settable
                    % properties. SetObservable are the properties we label
                    % to trigger events when they change - use that to
                    % indicate properties that should appear in the GUI too.
                    if( isequal(prop.SetAccess, 'public') && ~prop.Hidden && prop.SetObservable)
                        if Palladium.Utilities.GUIUtils.IsPropertyValidToUse(prop.Name)
                            propertyList(end+1, 1) = prop.Name; %#ok<AGROW>
                        end
                    end
                end
            else
                % If we only want to expose properties defined in this
                % class, and not its subclasses, it's more complicated. We
                % can use the metaclass, but be wary of exposing private or
                % hidden properties.
                propertyList = strings(0);
                metaClass = metaclass(instrument);

                for i=1:length(metaClass.PropertyList)
                    prop = metaClass.PropertyList(i);
                    % Add to the list only non-hidden publicly settable
                    % properties defined in this class. SetObservable are
                    % the properties we label to trigger events when they
                    % change - use that to indicate properties that should
                    % appear in the GUI too.
                    if( isequal(prop.SetAccess, 'public') && prop.DefiningClass.Name == objectClass && ~prop.Hidden && prop.SetObservable)
                        if Palladium.Utilities.GUIUtils.IsPropertyValidToUse(prop.Name)
                            propertyList(end+1, 1) = prop.Name; %#ok<AGROW>
                        end
                    end
                end
            end

            %Remove any properties from this list that the instrument
            %specifies, e.g. ConnectionSettings that do not apply to the
            %selected ConnectionType
            for i = length(propertyList) : -1 : 1
                if(~instrument.ShowProperty(propertyList{i}))
                    propertyList(i) = [];
                end
            end

        end

        function tf = IsPropertyValidToUse(propName)
            %Whether a property name can be shown in the GUI - it must be a valid MATLAB name.

            tf = isvarname(propName);
        end

        function [da, conversionSuccessful] = ToDoubleArrayFromScalarString(str, delimiter)
            %Turn text such as "200 300 400" or "[1, 2]" into an array of numbers - the reverse of ToScalarString.
            %Square brackets are ignored. If any part isn't a number, the
            %text is returned unchanged and conversionSuccessful is false
            %
            %Inputs:
            %   str       - the text
            %   delimiter - what separates the numbers. Default {' ', ','}
            %
            %Outputs:
            %   da                   - the numbers (row vector), or str if they couldn't all be read
            %   conversionSuccessful - false if any part wasn't a number

            arguments
                str {mustBeTextScalar}
                delimiter = {' ', ','};
            end

            conversionSuccessful = true;

            %Trim leading and trailing whitespace
            str = strtrim(str);

            %Remove any [,] bracket characters, not required
            str = replace(str, '[', '');
            str = replace(str, ']', '');

            %Split the string and convert each element to double
            da =  str2double(strsplit(str, delimiter));

            %Verify that it worked - no NaNs
            if any(isnan(da))
                da = str;
                conversionSuccessful = false;
                return;
            end
        end

        function str = ToScalarString(value)
            %Show a value as one string, for a GUI field - a vector's elements are joined with spaces.
            %Errors for a matrix (more than one row and column)
            %
            %Inputs:
            %   value - a scalar, vector, or text
            %
            %Outputs:
            %   str - e.g. "200 300 400" for [200 300 400]

            if size(value, 2) ~= 1 && size(value, 1) ~= 1
                error("ToScalarStringError:HighDimensionalArray",...
                    "Value isn't a scalar or vector so it's a high-dimensional array, that's probably bad news.") ;
            end

            str = string(value);
            if ~isscalar(str)
                str = join(str, " ");
            end
        end

        function html = MessageToHTML(msg)
            %Turn a plain-text message into HTML for a dialogue box with the HTML interpreter.
            %For `uialert` and `uiconfirm`. The message stays readable as
            %plain text in the log and Command Window:
            %
            %* `<`, `>` and `&` are shown as typed (e.g. "value < 0")
            %* text in backticks is shown as code (a monospaced font), for
            %  file names and paths
            %* `[text](https://address)` becomes a link showing the text
            %* other http(s) web addresses become links
            %* line breaks are kept
            %
            %Backslashes are left alone, so Windows paths show correctly.
            %
            %Inputs:
            %   msg - the message
            %
            %Outputs:
            %   html - the message as HTML (string)

            html = string(msg);
            html = replace(html, ["&", "<", ">"], ["&amp;", "&lt;", "&gt;"]);
            html = regexprep(html, "`([^`]+)`", "<code>$1</code>");
            html = regexprep(html, "\[([^\]]+)\]\((https?://[^)\s]+)\)", "<a href=""$2"">$1</a>");
            html = regexprep(html, "(?<!"")(https?://[^\s<]*[^\s<.,;:)])", "<a href=""$1"">$1</a>");
            html = replace(html, [sprintf("\r\n"), newline], "<br>");
        end

        function latex = GreekToLaTeX(text)
            %Turn the Greek letters in text into LaTeX, for labels shown with the LaTeX interpreter.
            %MATLAB's LaTeX interpreter can't show Unicode Greek letters - a
            %label with "Ω" fails to draw, with a warning - but shows
            %LaTeX's math symbols: "Resistance (Ω)" becomes
            %"Resistance ($\Omega$)". Neighbouring letters share one math
            %group ("Δθ" becomes "$\Delta\theta$"). The capitals that look
            %like Latin letters (Alpha, Beta, ...) become those letters, as
            %LaTeX has no symbols for them. Also converts the micro sign (µ)
            %and the ohm sign (Ω, U+2126). Other text is unchanged
            %
            %Inputs:
            %   text - the text (string array, char or cellstr)
            %
            %Outputs:
            %   latex - the text, with LaTeX for the Greek letters (string, same size)

            latex = Palladium.Utilities.GUIUtils.ConvertToLaTeX(text, false);
        end

        function latex = EscapeLaTeX(text)
            %Make text show as typed in a label with the LaTeX interpreter, e.g. a data column header.
            %LaTeX's special characters are escaped - otherwise "_" makes
            %a subscript, "%" hides the rest of the label, and "&", "#",
            %"$", "{", "}", "^", "~" and "\" break it or vanish - and Greek
            %letters become LaTeX symbols, as GreekToLaTeX does. For
            %example "dV/dI_x (kΩ) 50%" becomes
            %"dV/dI\_x (k$\Omega$) 50\%". Each escape is one MATLAB's LaTeX
            %interpreter draws as the character itself: "&" is "{\&}" (it
            %shows "\&" as "&amp;"), and "^", "~" and "\" are math symbols
            %(\hat{}, \tilde{}, \backslash), sharing a math group with any
            %neighbouring Greek letters
            %
            %Inputs:
            %   text - the text (string array, char or cellstr)
            %
            %Outputs:
            %   latex - the text, ready for the LaTeX interpreter (string, same size)

            latex = Palladium.Utilities.GUIUtils.ConvertToLaTeX(text, true);
        end
    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function latex = ConvertToLaTeX(text, escapeSpecials)
            %Convert text for the LaTeX interpreter, one character at a time - shared by GreekToLaTeX and EscapeLaTeX.
            %Greek letters (and, when escaping, ^ ~ and \) become math
            %symbols, with neighbouring ones in one $...$ group - two groups
            %touching ("$$") would start display maths. When escaping,
            %_ % & # $ { } become their text-mode escapes. Done in one pass,
            %so nothing is escaped twice
            %
            %Inputs:
            %   text           - the text (string array, char or cellstr)
            %   escapeSpecials - true to escape LaTeX's special characters too
            %
            %Outputs:
            %   latex - the converted text (string, same size)

            persistent greek mathSpecials textSpecials
            if isempty(greek)
                %Lower case α-ω (U+03B1-U+03C9, including final sigma ς), the
                %variant forms, then capitals Α-Ω (U+0391-U+03A9, no U+03A2)
                lower = ["\alpha", "\beta", "\gamma", "\delta", "\varepsilon", "\zeta", "\eta", "\theta", "\iota", "\kappa", ...
                    "\lambda", "\mu", "\nu", "\xi", "o", "\pi", "\rho", "\varsigma", "\sigma", "\tau", "\upsilon", "\varphi", ...
                    "\chi", "\psi", "\omega"];
                upper = ["A", "B", "\Gamma", "\Delta", "E", "Z", "H", "\Theta", "I", "K", "\Lambda", "M", "N", "\Xi", "O", ...
                    "\Pi", "P", "\Sigma", "T", "\Upsilon", "\Phi", "X", "\Psi", "\Omega"];
                upperCodes = [913:929, 931:937];
                variants = dictionary(string(char([977, 981, 982, 1009, 1013, 181, 8486]')), ...
                    ["\vartheta"; "\phi"; "\varpi"; "\varrho"; "\epsilon"; "\mu"; "\Omega"]);   %ϑ ϕ ϖ ϱ ϵ, micro sign, ohm sign
                greek = dictionary([string(char((945:969)')); string(char(upperCodes'))], [lower'; upper']);
                greek(keys(variants)) = values(variants);

                %Escapes MATLAB's LaTeX interpreter draws as the character
                mathSpecials = dictionary(["^", "~", "\"], ["\hat{}", "\tilde{}", "\backslash"]);
                textSpecials = dictionary(["_", "%", "&", "#", "$", "{", "}"], ["\_", "\%", "{\&}", "\#", "\$", "\{", "\}"]);
            end

            latex = string(text);
            for i = 1:numel(latex)
                if ismissing(latex(i))
                    continue;
                end
                out = "";
                inMath = false;
                for c = char(latex(i))
                    ch = string(c);
                    if isKey(greek, ch) && startsWith(greek(ch), "\")
                        mathText = greek(ch);
                    elseif escapeSpecials && isKey(mathSpecials, ch)
                        mathText = mathSpecials(ch);
                    else
                        mathText = "";
                    end

                    if strlength(mathText) > 0
                        if ~inMath
                            out = out + "$";
                            inMath = true;
                        end
                        out = out + mathText;
                        continue;
                    end

                    if inMath
                        out = out + "$";
                        inMath = false;
                    end
                    if isKey(greek, ch)
                        out = out + greek(ch);              %A capital that looks like a Latin letter
                    elseif escapeSpecials && isKey(textSpecials, ch)
                        out = out + textSpecials(ch);
                    else
                        out = out + ch;
                    end
                end
                if inMath
                    out = out + "$";
                end
                latex(i) = out;
            end
        end

        function fig = FindUIFigure(owner)
            %The uifigure holding owner - a figure, a component in one, or an App Designer app's window - or [] if none showing.

            fig = [];
            if isempty(owner) || (isobject(owner) && ~all(isvalid(owner)))
                return;
            end

            if isgraphics(owner)
                fig = ancestor(owner, "figure");
            elseif isobject(owner)
                %An App Designer app: its window is one of its properties
                for name = string(properties(owner))'
                    value = owner.(name);
                    if isa(value, "matlab.ui.Figure") && isscalar(value) && isvalid(value)
                        fig = value;
                        break;
                    end
                end
            end

            %uialert needs a uifigure, still open and showing
            if isempty(fig) || ~isvalid(fig) || ~matlab.ui.internal.isUIFigure(fig) || fig.Visible ~= "on"
                fig = [];
            end
        end

    end
end
