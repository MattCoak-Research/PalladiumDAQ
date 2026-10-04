classdef TemplateInstrumentClass < Palladium.Core.Instrument
    %TemplateInstrumentClass - Starting point for a new instrument driver: copy this file, then rename the class and file.
    %Replace the example commands and readings with your instrument's. It
    %measures a resistance and a current, has an example setting (Range)
    %shown in the Instrument Settings panel, and supports a Sweep Control.
    %See "Writing an instrument driver" in the documentation.

    %% Properties (Public)
    properties (Access = public)
        FullName = "Template Instrument"     %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties (Access = public, SetObservable)
        Name = "Template"                                           %Instrument name, used in data column headers
        Connection_Type = Palladium.Enums.ConnectionType.Ethernet   %Type of connection used to talk to the instrument. Debug simulates it, with no hardware
        Range categorical                                           %Example setting with a fixed list of options, shown as a drop-down; set in the constructor
    end

    %% Categoricals
    methods
        function catOut = RangeType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Auto", "Low", "High"]); end
    end

    %% Constructor
    methods
        function this = TemplateInstrumentClass()
            %Specify communication options and default settings. This must
            %work with no hardware connected - connecting happens later

            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = 22;
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];
            this.Range = this.RangeType("Auto");

            %Instrument Controls that can be added - a Sweep Control needs
            %SetNewSweepStepValue and GetSweepUnitsString, below
            this.DefineInstrumentControl(Name = "Sweep Control", ClassName = "SweepController_Stepped", TabName = "Sweep Control", EnabledByDefault = false);
        end
    end

    %% Methods (Public)
    methods (Access = public)
        function metadataStruct = CollectMetaData(this)
            %Settings to record in the data file's header, which don't change during a run.
            %Each field becomes a "Setting = value" pair. Delete this method
            %if there is nothing to record.

            metadataStruct.Range = string(this.Range);
        end

        function [headers, units] = GetHeaders(this)
            %Column headers and units of the values returned by Measure - one each, in the same order

            headers = [this.Name + " - Resistance_Ohms", this.Name + " - Current_A"];
            units = ["Ohms", "A"];
        end

        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(this)
            %Units, limits and plot labels of the swept quantity, for a Sweep Control.
            %
            %Outputs:
            %   str - units of the swept value, e.g. "V"
            %   limits - lowest and highest values allowed, [min, max]
            %   xlabelStr - label for the swept value on plots
            %   ylabelStr - label for the measured value on plots

            str = "V";
            limits = [-10, 10];
            xlabelStr = "Source Voltage (V)";
            headers = this.GetHeaders();
            ylabelStr = headers(1);
        end

        function dataRow = Measure(this)
            %Read the resistance and current, or generate synthetic data in SimulationMode

            if this.SimulationMode
                dataRow = this.GenerateSimulatedData(1, 2, Baseline=[500; 1e-3], Variance=[5; 1e-5]);
                return;
            end

            %Replace these with your instrument's commands
            dataRow = [this.QueryDouble("MEAS:RES?"), this.QueryDouble("MEAS:CURR?")];
        end

        function SetParameter(this, valueToSet)
            %Example of a method that sends a setting to the instrument - can be called from a Sequence.

            this.WriteCommand("PARAM " + string(valueToSet));    %Replace with your instrument's command
        end

        function SetNewSweepStepValue(this, value)
            %Go to the next step of a sweep - called by a Sweep Control.

            this.WriteCommand("SOUR:VOLT " + string(value));    %Replace with your instrument's command
        end
    end

    %% Methods (Protected)
    methods (Access = protected)
        function propertiesToIgnore = GetPropertiesToIgnore(~)
            %Names of public SetObservable properties to hide from the Instrument Settings panel.
            %The address settings for connection types other than the one
            %chosen are hidden automatically, so this only needs any extra
            %ones. Delete this method if there are none.

            propertiesToIgnore = {};
        end
    end
end
