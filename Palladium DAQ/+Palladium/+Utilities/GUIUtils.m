classdef GUIUtils
    %GUIUtils - Static functions for the GUI, mainly the Instrument Options panel that edits instrument settings.
    %The Instrument Options panel builds a field for each property that
    %`ComputePropertyList` returns, shows its value with `ToScalarString`,
    %and reads typed number lists back with `ToDoubleArrayFromScalarString`.
    %`MessageToHTML` formats messages for dialogue boxes,
    %`ChooseFromList` asks the user to pick one item from a list,
    %`ChooseFile` asks for a file or folder, and `ShowWarning` shows a
    %warning in the window it concerns.

    %% Methods (Static, Public)
    methods (Static, Access = public)

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
            %Uses the system's dialogues (uigetfile, uiputfile and uigetdir),
            %which can leave Palladium's window behind others when they close
            %- the Reference window is brought back with BringToFront
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
            %With no window to show it in - e.g. running without a GUI, or a
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
                uialert(fig, message, title, "Icon", "warning");
            end
        end

        function index = ChooseFromList(items, Settings)
            %Ask the user to pick one item from a list, in a small modal window - like listdlg, but a uifigure.
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

            %Centred on the reference window if there is one
            dialogSize = [300, 400];
            position = [100, 100, dialogSize];
            ref = Settings.Reference;
            if ~isempty(ref) && isvalid(ref)
                refPos = ref.Position;
                position(1:2) = refPos(1:2) + (refPos(3:4) - dialogSize) / 2;
            end

            fig = uifigure("Name", Settings.Title, "WindowStyle", "modal", "Position", position, "Resize", "off");
            if ~isempty(Settings.Icon) && isfile(Settings.Icon)
                fig.Icon = Settings.Icon;
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
            if isvalid(fig)
                delete(fig);
            end

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
            %* http(s) web addresses become links
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
            html = regexprep(html, "(https?://[^\s<]*[^\s<.,;:)])", "<a href=""$1"">$1</a>");
            html = replace(html, [sprintf("\r\n"), newline], "<br>");
        end
    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

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
