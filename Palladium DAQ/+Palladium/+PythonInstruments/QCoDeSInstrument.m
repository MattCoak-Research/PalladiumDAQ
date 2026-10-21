classdef QCoDeSInstrument < Palladium.PythonInstruments.PythonInstrument
    %QCoDeSInstrument - A QCoDeS instrument driver used as a Palladium DAQ instrument, with the parameters to record chosen in the GUI.
    %Made by `PythonInstrumentController.CreateInstrument` for an entry of
    %the instruments list such as "QCoDeS: Keithley2450" (see
    %`PythonInstrumentController.LoadQCoDeSDrivers`). Its Python object is a
    %QCoDeSGeneric (PalladiumPythonCore/QCoDeSInstrument.py), which runs the
    %QCoDeS driver. It adds an Instrument Control tab, "Parameters", where
    %the user picks the parameters to record and the settings to apply
    %(see `QCoDeSParametersControl`); the two choices, RecordedParameters and
    %ParameterSettings, are saved in Presets with the instrument's other
    %settings. Debug is offered only if the driver can run with no
    %instrument. See [Python instruments](../python-instruments.md).

    %% Properties (Public, Set Observable)
    properties (Access = public, SetObservable)
        %Names of the QCoDeS parameters to record, one data column each - numeric ones only. Chosen in the Parameters tab
        RecordedParameters (1,:) string = strings(1, 0);

        %Settings to apply when connecting, as JSON text of parameter name: value, e.g. {"source_function": "voltage"}. Chosen in the Parameters tab
        ParameterSettings (1,1) string = "{}";
    end

    %% Set Accessors
    methods
        function set.RecordedParameters(this, value)
            %Keep the names as a row of strings (a Preset gives them back as a cell array), and pass them to Python.
            if isempty(value)
                value = strings(1, 0);
            end
            this.RecordedParameters = reshape(string(value), 1, []);
            this.PushParameters();
        end

        function set.ParameterSettings(this, value)
            %Pass the settings to Python, which errors if they aren't JSON of the right form - the setting is then unchanged.
            if strlength(value) == 0
                value = "{}";
            end
            if ~isempty(this.PyInstr)
                this.PyInstr.set_settings_json(char(value));
            end
            this.ParameterSettings = value;
        end
    end

    %% Constructor
    methods
        function this = QCoDeSInstrument(pyInstr)
            %Wrap a QCoDeSGeneric Python instrument, and offer the Parameters tab.
            %
            %Inputs:
            %   pyInstr - the Python instrument, from PythonInstrumentController. Optional, so the API reference can construct one

            arguments
                pyInstr = [];
            end

            this@Palladium.PythonInstruments.PythonInstrument(pyInstr);

            this.DefineInstrumentControl(Name = "QCoDeS Parameters", ClassName = "QCoDeSParametersControl", TabName = "Parameters", EnabledByDefault = true);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function T = GetAvailableParameters(this)
            %The QCoDeS driver's parameters, to choose from.
            %From the connected driver, or - for a driver that can run with no
            %instrument - found without one. Empty for a driver that can't
            %until it has been connected once; see SimulationProblem
            %
            %Outputs:
            %   T - table with Name, Label, Unit, Gettable, Settable and Vals (the validator, as text)

            list = jsondecode(string(this.PyInstr.available_parameters_json()));
            n = numel(list);
            T = table(strings(n,1), strings(n,1), strings(n,1), false(n,1), false(n,1), strings(n,1), ...
                'VariableNames', ["Name" "Label" "Unit" "Gettable" "Settable" "Vals"]);
            for i = 1 : n
                T.Name(i) = string(list(i).name);
                T.Label(i) = string(list(i).label);
                T.Unit(i) = string(list(i).unit);
                T.Gettable(i) = logical(list(i).gettable);
                T.Settable(i) = logical(list(i).settable);
                T.Vals(i) = string(list(i).vals);
            end
            %The driver's own internal parameters (leading underscore) are for it, not for the user
            T = T(~startsWith(T.Name, "_"), :);
        end

        function text = SimulationProblem(this)
            %Why Debug isn't offered for this driver: it can't be created with no instrument. "" if it is.
            %
            %Outputs:
            %   text - the reason, or ""

            text = "";
            if ~isempty(this.PyInstr) && ~logical(this.PyInstr.SupportsSimulation)
                text = string(this.PyInstr.SimulationProblem);
            end
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function OpenConnection(this)
            %Pass the chosen parameters and settings to Python, then connect as any Python instrument does.
            this.PushParameters();
            this.PyInstr.set_settings_json(char(this.ParameterSettings));
            OpenConnection@Palladium.PythonInstruments.PythonInstrument(this);
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function PushParameters(this)
            %Pass RecordedParameters to the Python instrument.
            if ~isempty(this.PyInstr)
                this.PyInstr.set_parameters_json(char(jsonencode(this.RecordedParameters)));
            end
        end

    end
end
