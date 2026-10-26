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
    %A Plot drop-down chooses how the finished scan is plotted: the trace
    %against frequency, or (if the instrument's MeasUnit has Real/Imaginary)
    %a Smith chart (RF Toolbox's smithplot - Palladium works without the
    %toolbox, and choosing the Smith chart without it shows a warning and
    %goes back to the trace). A Smith chart needs the real and imaginary parts, so
    %choosing it sets the units to Real/Imaginary, locked while it is
    %chosen; choosing the trace again puts the units back.
    %
    %The panel is filled in from the instrument when measurements start,
    %and again after each scan (showing what the analyser actually set),
    %if the instrument has a `GetScanSettings` method returning a struct
    %with those fields. The S-parameter and units lists are the
    %instrument's own (the categories of its MeasMode and MeasUnit).
    %
    %Used by PNA_L_NetworkAnalyser, HP_8722ES_NetworkAnalyser and PicoVNA_NetworkAnalyser.

    %% Properties (Private)
    properties (Access = private)
        Fields = struct();      %The settings panel's components, by setting: StartFrequency, StartFrequencyUnit, StopFrequency, StopFrequencyUnit, NumPoints, SweepTime, SweepType, MeasMode, MeasUnit, PlotType
        UnitsBeforeSmith = "";  %The Units chosen before the Smith chart was (which needs Real/Imaginary), to go back to when it is not
    end

    %% Properties (Constant, Private)
    properties (Constant, Access = private)
        FrequencyUnits = ["Hz", "kHz", "MHz", "GHz"];     %Units offered for the start and stop frequencies
        FrequencyUnitScales = [1, 1e3, 1e6, 1e9];           %Hz in one of each of FrequencyUnits
        TracePlot = "Trace against frequency";              %PlotType drop-down item: the values against frequency
        SmithPlot = "Smith chart";                          %PlotType drop-down item: a Smith chart (needs the instrument's Real/Imaginary units)
        ComplexUnits = "Real/Imaginary";                    %The MeasUnit that gives the real and imaginary parts - what a Smith chart plots
    end

    %% Constructor
    methods
        function this = VNAController()
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function SetFrequencyRange(this, start_Hz, stop_Hz)
            %Set the start and stop frequencies, in Hz, as typed in the panel (shown in the units chosen beside them) - for sequences and scripts.
            %Like the other Set... methods, it errors while a scan is
            %running, and acts on the panel as typing would
            %
            %Inputs:
            %   start_Hz - start frequency, in Hz
            %   stop_Hz  - stop frequency in Hz, above the start

            this.CheckNumber(start_Hz, "start_Hz", @mustBePositive, @mustBeFinite);
            this.CheckNumber(stop_Hz, "stop_Hz", @mustBePositive, @mustBeFinite);
            assert(stop_Hz > start_Hz, "VNAController:InvalidFrequencyRange", "%s", ...
                "The stop frequency (" + stop_Hz + " Hz) must be above the start frequency (" + start_Hz + " Hz).");
            this.SetStartFrequency(start_Hz);
            this.SetStopFrequency(stop_Hz);
        end

        function SetNumberOfPoints(this, numPoints)
            %Set the number of points per sweep, as typed in the panel (an analyser with set choices uses the nearest) - for sequences and scripts.
            %
            %Inputs:
            %   numPoints - number of points, a whole number

            this.CheckNumber(numPoints, "numPoints", @mustBeInteger, @mustBePositive);
            f = this.EditableFields();
            f.NumPoints.Value = numPoints;
        end

        function SetPlotType(this, plotType)
            %Choose how the finished scan is plotted, as the Plot drop-down does: the trace against frequency, or a Smith chart - for sequences and scripts.
            %A Smith chart sets the units to Real/Imaginary and locks them
            %(the units come back when the trace is chosen); it needs RF
            %Toolbox, and errors without it
            %
            %Inputs:
            %   plotType - "Trace" or "Smith" (or the drop-down's whole text)

            f = this.EditableFields();
            wanted = lower(string(plotType));
            if startsWith(wanted, "smith")
                chosen = this.SmithPlot;
            elseif startsWith(wanted, "trace")
                chosen = this.TracePlot;
            else
                chosen = this.MatchItem(f.PlotType, plotType, "plot type");
            end
            chosen = this.MatchItem(f.PlotType, chosen, "plot type");     %One this analyser offers

            f.PlotType.Value = chosen;
            this.OnPlotTypeChanged();
            assert(string(f.PlotType.Value) == chosen, "VNAController:PlotTypeNotSet", "%s", "The plot type was not changed to " + chosen + " (see the warning shown).");
        end

        function SetSParameter(this, sParameter)
            %Choose the S-parameter measured (the analyser's own list, e.g. S11, S21), as the S-parameter drop-down does - for sequences and scripts.
            %
            %Inputs:
            %   sParameter - e.g. "S21"

            f = this.EditableFields("MeasMode");
            f.MeasMode.Value = this.MatchItem(f.MeasMode, sParameter, "S-parameter");
        end

        function SetStartFrequency(this, freq_Hz)
            %Set the start frequency, in Hz, as typed in the panel (shown in the units chosen beside it) - for sequences and scripts.
            %
            %Inputs:
            %   freq_Hz - start frequency, in Hz

            this.CheckNumber(freq_Hz, "freq_Hz", @mustBePositive, @mustBeFinite);
            f = this.EditableFields();
            f.StartFrequency.Value = freq_Hz / this.UnitScale(f.StartFrequencyUnit);
        end

        function SetStopFrequency(this, freq_Hz)
            %Set the stop frequency, in Hz, as typed in the panel (shown in the units chosen beside it) - for sequences and scripts.
            %Checked to be above the start frequency when the scan runs
            %
            %Inputs:
            %   freq_Hz - stop frequency, in Hz

            this.CheckNumber(freq_Hz, "freq_Hz", @mustBePositive, @mustBeFinite);
            f = this.EditableFields();
            f.StopFrequency.Value = freq_Hz / this.UnitScale(f.StopFrequencyUnit);
        end

        function SetSweepTime(this, time_s)
            %Set the sweep time, in seconds (0 for automatic, the fastest the analyser can), as typed in the panel - for sequences and scripts.
            %
            %Inputs:
            %   time_s - sweep time in seconds

            this.CheckNumber(time_s, "time_s", @mustBeNonnegative, @mustBeFinite);
            f = this.EditableFields();
            f.SweepTime.Value = time_s;
        end

        function SetSweepType(this, sweepType)
            %Choose linear or logarithmic frequency steps, as the Sweep type drop-down does - for sequences and scripts.
            %
            %Inputs:
            %   sweepType - "Linear" or "Log"

            f = this.EditableFields();
            f.SweepType.Value = this.MatchItem(f.SweepType, sweepType, "sweep type");
        end

        function SetUnits(this, units)
            %Choose the units of the scan values (the analyser's own list, e.g. dB, Absolute, Real/Imaginary), as the Units drop-down does - for sequences and scripts.
            %Errors while the Smith chart is the plot type, which keeps the
            %units at Real/Imaginary
            %
            %Inputs:
            %   units - e.g. "dB"

            f = this.EditableFields("MeasUnit");
            assert(~this.SmithChosen(), "VNAController:UnitsLocked", "%s", ...
                "The units are Real/Imaginary while the plot type is the Smith chart. Change the plot type (SetPlotType) first.");
            f.MeasUnit.Value = this.MatchItem(f.MeasUnit, units, "units");
        end

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
            grid = uigridlayout(panel, [8, 3], "ColumnWidth", {200, 160, 70}, "RowHeight", repmat({26}, 1, 8), "RowSpacing", 6);

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

            %How the scan is plotted - a Smith chart only if the instrument can give the complex values
            plotTypes = this.TracePlot;
            if isfield(f, "MeasUnit") && any(string(f.MeasUnit.Items) == this.ComplexUnits)
                plotTypes = [plotTypes, this.SmithPlot];
            end
            f.PlotType = this.AddDropDown(grid, 8, "Plot", "How the finished scan is plotted. A Smith chart needs the real and imaginary parts, so it sets the units to Real/Imaginary", plotTypes);
            f.PlotType.ValueChangedFcn = @(~, ~) this.OnPlotTypeChanged();
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
            if isfield(f, "MeasUnit") && isvalid(f.MeasUnit) && ~this.SmithChosen()
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

        function CheckNumber(~, value, name, varargin)
            %Error unless value is a single real number that passes each of the validation functions (e.g. @mustBePositive).

            assert(isnumeric(value) && isscalar(value) && isreal(value), "VNAController:NotANumber", "%s", name + " must be a single number.");
            for validate = varargin
                validate{1}(value);
            end
        end

        function f = EditableFields(this, requiredField)
            %The settings panel's components, once it is known that they can be changed: the panel exists, has the field asked for, and no scan is running.

            arguments
                this;
                requiredField {mustBeTextScalar} = "";
            end

            f = this.Fields;
            assert(~isempty(fieldnames(f)), "VNAController:NoPanel", "%s", "The VNA Control has no settings panel to change.");
            assert(strlength(requiredField) == 0 || isfield(f, requiredField), "VNAController:NotOffered", "%s", ...
                "This analyser does not offer " + requiredField + " in the VNA Control.");
            assert(~this.Running, "VNAController:ScanRunning", "%s", "The settings cannot be changed while a scan is running - Abort it, or wait for it to finish.");
        end

        function item = MatchItem(~, dropDown, choice, what)
            %The drop-down item that is choice (ignoring case) - errors, listing the items, if there is none.

            items = string(dropDown.Items);
            match = find(strcmpi(items, string(choice)), 1);
            if isempty(match)
                error("VNAController:UnknownChoice", "%s", "Unknown " + what + " """ + string(choice) + """ - choose from: " + strjoin(items, ", ") + ".");
            end
            item = items(match);
        end

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
            if ~this.SmithChosen()
                pickIf("MeasUnit", "MeasUnit");     %A Smith chart keeps its Real/Imaginary
            end

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

        function OnPlotTypeChanged(this)
            %The Plot drop-down changed: a Smith chart sets the units to Real/Imaginary and locks them, and the last scan is plotted again.

            f = this.Fields;
            if this.SmithChosen() && ~Palladium.Utilities.GUIUtils.IsSmithPlotAvailable()
                %Palladium runs without RF Toolbox - only this plot needs it. Go back to the trace
                f.PlotType.Value = this.TracePlot;
                Palladium.Utilities.GUIUtils.ShowWarning(f.PlotType, "The Smith chart needs [RF Toolbox](https://www.mathworks.com/products/rftoolbox.html), an add-on toolbox for MATLAB that is not installed or licensed on this computer." + newline + newline + ...
                    "Install it from that link, or with MATLAB's Add-On Explorer, to use the Smith chart. Until then the plot stays as a trace against frequency.", "Smith chart unavailable");
                return;
            end
            if this.SmithChosen()
                if string(f.MeasUnit.Value) ~= this.ComplexUnits
                    this.UnitsBeforeSmith = string(f.MeasUnit.Value);
                end
                f.MeasUnit.Value = this.ComplexUnits;
                f.MeasUnit.Enable = false;
                this.SetPlotKind("Smith");
            else
                if strlength(this.UnitsBeforeSmith) > 0 && any(string(f.MeasUnit.Items) == this.UnitsBeforeSmith)
                    f.MeasUnit.Value = this.UnitsBeforeSmith;
                end
                this.UnitsBeforeSmith = "";
                f.MeasUnit.Enable = true;
                this.SetPlotKind("Scatter");
            end
        end

        function chosen = SmithChosen(this)
            %True if the Plot drop-down says Smith chart.

            chosen = isfield(this.Fields, "PlotType") && isvalid(this.Fields.PlotType) && string(this.Fields.PlotType.Value) == this.SmithPlot;
        end

        function SetFieldsEnabled(this, enabled)
            %Enable or disable all the settings fields - except the units while a Smith chart needs them to stay Real/Imaginary.

            for name = string(fieldnames(this.Fields))'
                if isvalid(this.Fields.(name))
                    this.Fields.(name).Enable = enabled;
                end
            end
            if enabled && this.SmithChosen()
                this.Fields.MeasUnit.Enable = false;
            end
        end

    end
end
