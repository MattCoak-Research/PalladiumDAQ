classdef QCoDeSParametersControl < Palladium.Core.InstrumentControlBase
    %QCoDeSParametersControl - The "Parameters" tab of a QCoDeS instrument: choose which parameters to record, and which settings to apply.
    %Added automatically to a `Palladium.PythonInstruments.QCoDeSInstrument`.
    %A table lists the driver's parameters. Ticking **Record** adds a
    %data column for the parameter (numeric ones only), and typing a **Value
    %to set on connecting** applies that setting when measurements start -
    %checked by the driver's own validators then. The choices are written to
    %the instrument's RecordedParameters and ParameterSettings, so they are
    %saved in Presets, and a change made there (loading a Preset, or from a
    %script) shows in the table. The parameters come from the driver with no
    %instrument connected, for a driver that can run that way; for any other,
    %connect once (start measurements) and they are listed from then on.

    %% Properties (Private)
    properties (Access = private)
        Grid;               %Layout holding the GUI in the tab
        Table;              %The parameters table
        FilterField;        %Text box to show only parameters whose name contains the text
        StatusLabel;        %Says how many parameters there are, and anything the user should know
        AllParameters;      %Table of every parameter the driver has, from the instrument's GetAvailableParameters
        IgnoreChanges = false;  %True while this control writes the instrument's properties, so the table isn't rebuilt under the user's cursor
    end

    %% Constructor
    methods
        function this = QCoDeSParametersControl()
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function CreateInstrumentControlGUI(this, controller, tab, instrRef) %#ok<INUSL>
            %Build the filter box, table and status line in the tab, and show the instrument's choices.

            this.Instrument = instrRef;

            this.Grid = uigridlayout(tab, [4 1], "RowHeight", {'fit', 'fit', '1x', 'fit'}, "ColumnWidth", {'1x'}, "RowSpacing", 4);

            info = uilabel(this.Grid, "WordWrap", "on", "Text", ...
                "Tick Record to add a parameter's reading to the data. Type a value to apply a setting when measurements start (e.g. voltage for source_function) - the driver checks it then.");
            info.Layout.Row = 1;

            this.FilterField = uieditfield(this.Grid, "text", "Placeholder", "Filter parameters by name", "ValueChangedFcn", @(~, ~) this.Render());
            this.FilterField.Layout.Row = 2;

            this.Table = uitable(this.Grid, ...
                "ColumnName", ["Record", "Parameter", "Unit", "Value to set on connecting", "Allowed values"], ...
                "ColumnEditable", [true false false true false], ...
                "ColumnFormat", {'logical', 'char', 'char', 'char', 'char'}, ...
                "ColumnWidth", {70, 230, 70, 190, '1x'}, ...
                "RowName", {}, ...
                "CellEditCallback", @(src, event) this.CellEdited(src, event));
            this.Table.Layout.Row = 3;

            this.StatusLabel = uilabel(this.Grid, "WordWrap", "on", "Text", "");
            this.StatusLabel.Layout.Row = 4;

            %Show a change made to the instrument's choices elsewhere, such as a Preset loading
            this.RegisterEventListener(this.AddGuardedListener(instrRef, "PropertyChanged", @(~, ~) this.Render()));

            this.Reload();
        end

        function RemoveControl(this, ~)
            %Delete the GUI.
            if ~isempty(this.Grid) && isvalid(this.Grid)
                delete(this.Grid);
            end
            this.Grid = [];
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function OnMeasurementsInitialised(this, ~)
            %Measurements have started, so the driver is connected: list its parameters now, as a driver that can't run offline has none until then.
            this.Reload();
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function Reload(this)
            %Ask the instrument for the driver's parameters, then show them.
            try
                this.AllParameters = this.Instrument.GetAvailableParameters();
            catch err
                this.AllParameters = table(strings(0,1), strings(0,1), strings(0,1), false(0,1), false(0,1), strings(0,1), ...
                    'VariableNames', ["Name" "Label" "Unit" "Gettable" "Settable" "Vals"]);
                Palladium.Logging.Logger.Log("Warning", "Could not list the parameters of " + this.Instrument.Name + ": " + string(err.message));
            end
            this.Render();
        end

        function Render(this)
            %Show the parameters, with the instrument's recorded parameters and settings, filtered by the filter box.
            if this.IgnoreChanges || isempty(this.Table) || ~isvalid(this.Table)
                return;
            end

            P = this.AllParameters;
            filterText = lower(strtrim(string(this.FilterField.Value)));
            if filterText ~= ""
                P = P(contains(lower(P.Name), filterText) | contains(lower(P.Label), filterText), :);
            end

            recorded = this.Instrument.RecordedParameters;
            settings = this.SettingsStruct();

            n = height(P);
            data = cell(n, 5);
            for i = 1 : n
                name = P.Name(i);
                data{i, 1} = any(recorded == name);
                data{i, 2} = char(name);
                data{i, 3} = char(P.Unit(i));
                if isfield(settings, name)
                    data{i, 4} = char(this.ValueToText(settings.(name)));
                else
                    data{i, 4} = '';
                end
                data{i, 5} = char(P.Vals(i));
            end
            this.Table.Data = data;

            %Grey out what can't be done: reading a parameter with no way to read it, and setting one that can't be set
            removeStyle(this.Table);
            unreadable = find(~P.Gettable);
            unsettable = find(~P.Settable);
            grey = uistyle("FontColor", [0.55 0.55 0.55]);
            if ~isempty(unreadable)
                addStyle(this.Table, grey, "cell", [unreadable, ones(size(unreadable))]);
            end
            if ~isempty(unsettable)
                addStyle(this.Table, grey, "cell", [unsettable, 4 * ones(size(unsettable))]);
            end

            this.StatusLabel.Text = this.StatusText(height(this.AllParameters), n);
        end

        function text = StatusText(this, total, shown)
            %The line under the table.
            if total == 0
                problem = this.Instrument.SimulationProblem();
                text = "No parameters to list yet: this driver can't run with no instrument connected" + ...
                    ", so connect to it once (start measurements) and they will be listed. " + problem;
                return;
            end
            nSettings = numel(fieldnames(this.SettingsStruct()));
            text = sprintf("%d of %d parameters shown. %d recorded, %d settings applied on connecting. Changes take effect the next time measurements start.", ...
                shown, total, numel(this.Instrument.RecordedParameters), nSettings);
            problem = this.Instrument.SimulationProblem();
            if problem ~= ""
                text = text + " Debug mode isn't available for this driver: " + problem;
            end
        end

        function CellEdited(this, ~, event)
            %Write a Record tick or a typed value to the instrument's RecordedParameters or ParameterSettings.
            row = event.Indices(1);
            column = event.Indices(2);
            name = string(this.Table.Data{row, 2});
            info = this.AllParameters(this.AllParameters.Name == name, :);

            this.IgnoreChanges = true;
            cleanup = onCleanup(@() this.SetIgnoreChanges(false));
            try
                switch column
                    case 1      %Record
                        if event.NewData && ~info.Gettable
                            error("QCoDeSParametersControl:NotReadable", "'%s' can't be read, so it can't be recorded.", name);
                        end
                        recorded = this.Instrument.RecordedParameters;
                        if event.NewData
                            recorded = unique([recorded, name], "stable");
                        else
                            recorded(recorded == name) = [];
                        end
                        this.Instrument.RecordedParameters = recorded;
                    case 4      %Value to set
                        text = strtrim(string(event.NewData));
                        if text ~= "" && ~info.Settable
                            error("QCoDeSParametersControl:NotSettable", "'%s' can't be set.", name);
                        end
                        settings = this.SettingsStruct();
                        if text == ""
                            if isfield(settings, name)
                                settings = rmfield(settings, name);
                            end
                        else
                            settings.(name) = this.TextToValue(text);
                        end
                        this.Instrument.ParameterSettings = string(jsonencode(settings));
                end
            catch err
                %Put the table back as it was, and say why
                this.Table.Data{row, column} = event.PreviousData;
                Palladium.Utilities.GUIUtils.ShowWarning(this.Table, string(err.message), "QCoDeS parameters");
            end
            this.StatusLabel.Text = this.StatusText(height(this.AllParameters), size(this.Table.Data, 1));
        end

        function SetIgnoreChanges(this, value)
            %Used by an onCleanup, to stop ignoring the instrument's changes however CellEdited ends.
            this.IgnoreChanges = value;
        end

        function s = SettingsStruct(this)
            %The instrument's ParameterSettings text as a struct of parameter name: value ({} gives an empty struct).
            try
                s = jsondecode(char(this.Instrument.ParameterSettings));
            catch
                s = struct();
            end
            if ~isstruct(s)
                s = struct();
            end
        end

    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function text = ValueToText(value)
            %How a setting's value is shown in the table: numbers and logicals as numbers and true/false, text as it is.
            if ischar(value) || isstring(value)
                text = string(value);
            elseif islogical(value) && isscalar(value)
                text = string(lower(string(value)));
            elseif isnumeric(value) && isscalar(value)
                text = string(num2str(value, 15));
            else
                text = string(jsonencode(value));
            end
        end

        function value = TextToValue(text)
            %A typed setting as a value: a number, true or false if it reads as one, and otherwise the text.
            %Text in quotes is always text, so "5" is the text 5.
            try
                decoded = jsondecode(char(text));
                if (isnumeric(decoded) || islogical(decoded) || ischar(decoded)) && isscalar(decoded) || ischar(decoded)
                    value = decoded;
                    return;
                end
            catch
                %Not JSON, so it is plain text
            end
            value = char(text);
        end

    end
end
