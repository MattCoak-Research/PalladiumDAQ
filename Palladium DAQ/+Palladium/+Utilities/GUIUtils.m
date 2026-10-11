classdef GUIUtils
    %GUIUtils - Static functions for the GUI, mainly the Instrument Options panel that edits instrument settings.
    %The Instrument Options panel builds a field for each property that
    %`ComputePropertyList` returns, shows its value with `ToScalarString`,
    %and reads typed number lists back with `ToDoubleArrayFromScalarString`.
    %`MessageToHTML` formats messages for dialogue boxes.

    %% Methods (Static, Public)
    methods (Static, Access = public)

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
end
