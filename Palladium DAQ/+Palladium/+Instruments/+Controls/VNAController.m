classdef VNAController < Palladium.Instruments.Controls.ScanController
    %VNAController - Scan Control for vector network analysers, with the analyser's sweep settings on the tab.
    %Adds a panel of sweep settings under the Scan Control's Run and file
    %panel: start and stop frequency (each in Hz, kHz, MHz or GHz, chosen
    %beside it), number of points, sweep time (0 for
    %automatic), linear or log sweep, S-parameter (the instrument's
    %`MeasMode`) and units (its `MeasUnit`). On each Run they are added to
    %the scan details passed to the instrument's `RunScan(scanDetails)`,
    %as the fields StartFrequency_Hz, StopFrequency_Hz, NumPoints,
    %SweepTime_s, SweepType, MeasMode and MeasUnit. The control doesn't
    %know how any instrument sets them - each instrument applies those it
    %can, in its own way.
    %
    %The panel is filled in from the instrument when measurements start,
    %and again after each scan (showing what the analyser actually set),
    %if the instrument has a `GetScanSettings` method returning a struct
    %with those fields. The S-parameter and units lists are the
    %instrument's own (the categories of its MeasMode and MeasUnit).
    %
    %Used by PNA_L_NetworkAnalyser and HP_8722ES_NetworkAnalyser.

    %% Properties (Private)
    properties (Access = private)
        Fields = struct();      %The settings panel's components, by setting: StartFrequency, StartFrequencyUnit, StopFrequency, StopFrequencyUnit, NumPoints, SweepTime, SweepType, MeasMode, MeasUnit
    end

    %% Properties (Constant, Private)
    properties (Constant, Access = private)
        FrequencyUnits = ["Hz", "kHz", "MHz", "GHz"];     %Units offered for the start and stop frequencies
        FrequencyUnitScales = [1, 1e3, 1e6, 1e9];           %Hz in one of each of FrequencyUnits
    end

    %% Constructor
    methods
        function this = VNAController()
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function OnScanAbort(this)
            OnScanAbort@Palladium.Instruments.Controls.ScanController(this);
            this.SetFieldsEnabled(true);
        end

        function OnScanComplete(this)
            %Show what the analyser actually set (e.g. the 8722ES rounds the number of points), and allow changes again.
            OnScanComplete@Palladium.Instruments.Controls.ScanController(this);
            this.RefreshFromInstrument();
            this.SetFieldsEnabled(true);
        end

        function OnScanRun(this)
            %No changes to the settings while a scan is under way.
            this.SetFieldsEnabled(false);
            OnScanRun@Palladium.Instruments.Controls.ScanController(this);
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function scanDetails = CollectScanDetails(this)
            %The Run/file panel's settings, plus the sweep settings - checked first.
            %
            %Outputs:
            %   scanDetails - struct of settings, for the instrument's RunScan

            scanDetails = CollectScanDetails@Palladium.Instruments.Controls.ScanController(this);
            f = this.Fields;
            if isempty(fieldnames(f))
                return;     %No panel (e.g. in tests)
            end

            start_Hz = f.StartFrequency.Value * this.UnitScale(f.StartFrequencyUnit);
            stop_Hz = f.StopFrequency.Value * this.UnitScale(f.StopFrequencyUnit);
            assert(stop_Hz > start_Hz, "VNAController:InvalidFrequencyRange", "%s", ...
                "The stop frequency (" + f.StopFrequency.Value + " " + f.StopFrequencyUnit.Value + ") must be above the start frequency (" + ...
                f.StartFrequency.Value + " " + f.StartFrequencyUnit.Value + ").");

            scanDetails.StartFrequency_Hz = start_Hz;
            scanDetails.StopFrequency_Hz = stop_Hz;
            scanDetails.NumPoints = f.NumPoints.Value;
            scanDetails.SweepTime_s = f.SweepTime.Value;
            scanDetails.SweepType = string(f.SweepType.Value);
            if isfield(f, "MeasMode");  scanDetails.MeasMode = string(f.MeasMode.Value);    end
            if isfield(f, "MeasUnit");  scanDetails.MeasUnit = string(f.MeasUnit.Value);    end
        end

        function CreateSettingsPanel(this, parentGrid, row)
            %Add the sweep settings panel under the Run/file panel.
            %
            %Inputs:
            %   parentGrid - the tab's scrollable grid
            %   row        - the row of parentGrid to put it in

            parentGrid.RowHeight{row} = "fit";
            panel = uipanel(parentGrid, "Title", "Analyser Settings - sent on each Run", "FontName", "Georgia", "FontSize", 14);
            panel.Layout.Row = row;
            grid = uigridlayout(panel, [7, 3], "ColumnWidth", {200, 160, 70}, "RowHeight", repmat({26}, 1, 7), "RowSpacing", 6);

            f.StartFrequency = this.AddNumberField(grid, 1, "Start frequency", "Start of the frequency sweep, in the units beside it", [0, Inf], "%.9g");
            f.StartFrequencyUnit = this.AddUnitDropDown(grid, 1, f.StartFrequency);
            f.StopFrequency = this.AddNumberField(grid, 2, "Stop frequency", "End of the frequency sweep, in the units beside it", [0, Inf], "%.9g");
            f.StopFrequencyUnit = this.AddUnitDropDown(grid, 2, f.StopFrequency);
            f.NumPoints = this.AddNumberField(grid, 3, "Number of points", "Points per sweep - an analyser with set choices uses the nearest", [1, Inf], "%d");
            f.NumPoints.RoundFractionalValues = "on";
            f.SweepTime = this.AddNumberField(grid, 4, "Sweep time (s, 0 = automatic)", "Time for one sweep, in seconds - 0 for the fastest the analyser can (automatic)", [0, Inf], "%.6g");
            f.SweepType = this.AddDropDown(grid, 5, "Sweep type", "Linear or logarithmic frequency steps", ["Linear", "Log"]);

            %The S-parameters and units are the instrument's own lists
            instr = this.Instrument;
            if isprop(instr, "MeasMode") && iscategorical(instr.MeasMode)
                f.MeasMode = this.AddDropDown(grid, 6, "S-parameter", "The S-parameter measured", string(categories(instr.MeasMode)));
                f.MeasMode.Value = string(instr.MeasMode);
            end
            if isprop(instr, "MeasUnit") && iscategorical(instr.MeasUnit)
                f.MeasUnit = this.AddDropDown(grid, 7, "Units", "The units (display format) of the measured values", string(categories(instr.MeasUnit)));
                f.MeasUnit.Value = string(instr.MeasUnit);
            end
            this.Fields = f;

            %Start from the instrument's settings, if it is already connected
            this.RefreshFromInstrument();
        end

        function OnInstrumentPropertyChanged(this)
            %Keep the S-parameter and units in step with the instrument's (e.g. changed in Instrument Options).

            f = this.Fields;
            if isfield(f, "MeasMode") && isvalid(f.MeasMode)
                f.MeasMode.Value = string(this.Instrument.MeasMode);
            end
            if isfield(f, "MeasUnit") && isvalid(f.MeasUnit)
                f.MeasUnit.Value = string(this.Instrument.MeasUnit);
            end
        end

        function OnMeasurementsInitialised(this, headers)
            %The analyser is connected now, so the panel can start from its settings.
            OnMeasurementsInitialised@Palladium.Instruments.Controls.ScanController(this, headers);
            this.RefreshFromInstrument();
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function field = AddNumberField(~, grid, row, labelText, tooltip, limits, displayFormat)
            %A labelled number field in a row of the settings grid.

            label = uilabel(grid, "Text", labelText, "Tooltip", tooltip);
            label.Layout.Row = row;
            label.Layout.Column = 1;
            field = uieditfield(grid, "numeric", "Limits", limits, "ValueDisplayFormat", displayFormat, "Tooltip", tooltip, ...
                "HorizontalAlignment", "center");
            field.Layout.Row = row;
            field.Layout.Column = 2;
        end

        function dropDown = AddUnitDropDown(this, grid, row, valueField)
            %A frequency units drop-down (MHz to start with) in the third column of a row, beside its value field.
            %Changing the units converts the value shown, so the frequency
            %stays the same (300 MHz becomes 0.3 GHz)

            dropDown = uidropdown(grid, "Items", this.FrequencyUnits, "Value", "MHz", "Tooltip", "Units of the frequency beside it", ...
                "ValueChangedFcn", @(~, event) convertValue(event));
            dropDown.Layout.Row = row;
            dropDown.Layout.Column = 3;

            function convertValue(event)
                scales = this.FrequencyUnitScales;
                valueField.Value = valueField.Value * scales(this.FrequencyUnits == event.PreviousValue) / scales(this.FrequencyUnits == event.Value);
            end
        end

        function scale = UnitScale(this, unitDropDown)
            %Hz in one of the units chosen in a frequency units drop-down.

            scale = this.FrequencyUnitScales(this.FrequencyUnits == string(unitDropDown.Value));
        end

        function dropDown = AddDropDown(~, grid, row, labelText, tooltip, items)
            %A labelled drop-down list in a row of the settings grid.

            label = uilabel(grid, "Text", labelText, "Tooltip", tooltip);
            label.Layout.Row = row;
            label.Layout.Column = 1;
            dropDown = uidropdown(grid, "Items", items, "Tooltip", tooltip);
            dropDown.Layout.Row = row;
            dropDown.Layout.Column = 2;
        end

        function RefreshFromInstrument(this)
            %Fill the panel in from the instrument's GetScanSettings, if it has one and is connected.
            %A failure is logged rather than raised - the panel just keeps its values

            f = this.Fields;
            instr = this.Instrument;
            if isempty(fieldnames(f)) || isempty(instr) || ~ismethod(instr, "GetScanSettings") || ~instr.IsConnected()
                return;
            end

            try
                settings = instr.GetScanSettings();
            catch err
                Palladium.Logging.Logger.Log("Warning", instr.Name + ": could not read the analyser's settings for the VNA Control - " + err.message);
                return;
            end

            setIf("StartFrequency_Hz", f.StartFrequency, 1 / this.UnitScale(f.StartFrequencyUnit));
            setIf("StopFrequency_Hz", f.StopFrequency, 1 / this.UnitScale(f.StopFrequencyUnit));
            setIf("NumPoints", f.NumPoints, 1);
            setIf("SweepTime_s", f.SweepTime, 1);
            pickIf("SweepType", "SweepType");
            pickIf("MeasMode", "MeasMode");
            pickIf("MeasUnit", "MeasUnit");

            function setIf(name, field, scale)
                %A number field, if the setting is there and a number
                if isfield(settings, name) && isnumeric(settings.(name)) && isscalar(settings.(name)) && isfinite(settings.(name))
                    field.Value = max(min(settings.(name) * scale, field.Limits(2)), field.Limits(1));
                end
            end

            function pickIf(name, fieldName)
                %A drop-down, if the setting is there and one of its items
                if isfield(settings, name) && isfield(f, fieldName) && any(string(f.(fieldName).Items) == string(settings.(name)))
                    f.(fieldName).Value = string(settings.(name));
                end
            end
        end

        function SetFieldsEnabled(this, enabled)
            %Enable or disable all the settings fields.

            for name = string(fieldnames(this.Fields))'
                if isvalid(this.Fields.(name))
                    this.Fields.(name).Enable = enabled;
                end
            end
        end

    end
end
