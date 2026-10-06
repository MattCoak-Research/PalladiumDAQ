classdef AH2550_Bridge < Palladium.Core.Instrument
    %AH2550_Bridge - Instrument driver for the Andeen-Hagerling 2550A (and 2550) capacitance bridge.
    %Records capacitance (pF), loss and the test signal voltage (V) each
    %measurement tick, read from the bridge's result line, e.g.
    %`C= 454.688993 PF L= 0.01744 NS V= 15.0 V`. The result line must
    %include field labels (the default, set with the bridge's FORMAT
    %command).
    %
    %In `Continuous_Mode` (the default), start continuous measurements on the
    %bridge first; each Measure reads the next result the bridge sends.
    %Otherwise each Measure takes one measurement with the SINGLE command,
    %which can take several seconds. `Record_Times` adds columns with the
    %time just before and after the measurement, as the temperature etc.
    %can change during a long one.
    %
    %Set the loss units on the bridge (UNITS command) and choose the same
    %ones in `Loss_Units`, which only sets the column header. The bridge
    %has GPIB and RS-232 interfaces.

    %% Properties (Public)
    properties(Access = public)
        FullName = "AH Bridge";                                     %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "AH_Br";                                             %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;      %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Loss_Units categorical;                                     %Loss units set on the bridge, for the loss column header: TanDelta (dissipation factor) or kOhm (series resistance)
        Continuous_Mode (1,1) logical = true;                       %If true, the bridge is measuring continuously and Measure reads its latest result. If false, Measure takes a single measurement.
        Record_Times (1,1) logical = false;                         %Add columns with the time (in minutes, UTC) just before and after each measurement - a measurement can take a long time
    end

    %% Properties (Dependent, Private)
    properties(Dependent, Access = private)
        LossUnit;                                                   %Units string of the loss column, from Loss_Units: "" for TanDelta, "kOhm" for kOhm
    end

    %% Get and Set Accessors
    methods
        function unitStr = get.LossUnit(this)
            switch(this.Loss_Units)
                case(this.LossUnitsType("TanDelta"));   unitStr = "";
                case(this.LossUnitsType("kOhm"));       unitStr = "kOhm";
                otherwise
                    error("AH2550_Bridge:UnsupportedLossUnits", 'Unsupported Loss Units');
            end
        end
    end

    %% Categoricals
    methods
        function catOut = LossUnitsType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["TanDelta", "kOhm"]); end
    end

    %% Constructor
    methods
        function this = AH2550_Bridge()
            %Set the supported connection types, default connection settings and loss units.

            %The bridge has GPIB and RS-232 ports; VISA can address either
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial", "VISA"]);
            this.GPIB_Address = 28;     %Factory default of the 2500A (no 2550A manual was available to check)
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];
            this.Loss_Units = this.LossUnitsType("TanDelta");
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %Capacitance, loss and voltage, then the before and after times if
            %Record_Times is on
            %
            %Outputs:
            %   Headers - e.g. ["AH_Br - Cap (pF)", "AH_Br - Loss (kOhm)", "AH_Br - Voltage (V)"]
            %   Units   - matching units, e.g. ["pF", "kOhm", "V"]

            Headers = [this.Name + " - Cap (pF)", this.Name + " - Loss (" + this.LossUnit + ")", this.Name + " - Voltage (V)"];
            Units = ["pF", this.LossUnit, "V"];

            if(this.Record_Times)
                Headers = [Headers, this.Name + " - Time before (min)", this.Name + " - Time after (min)"];
                Units = [Units, "min", "min"];
            end
        end

        function [dataRow] = Measure(this)
            %Read a measurement result from the bridge.
            %The latest continuous result, or a new single measurement - see
            %Continuous_Mode
            %
            %Outputs:
            %   dataRow - capacitance in pF, loss, and test voltage in V, then
            %             the times before and after in minutes if
            %             Record_Times is on. A value missing from the result
            %             line is NaN

            %Record the time just before the measurement, in minutes since
            %1970 (UTC). Only really meaningful for single measurements
            beginTime = posixtime(datetime('now')) / 60;

            if(this.SimulationMode)
                capacitance = this.GenerateSimulatedData(1, Baseline=0.4, Variance=0.001);
                loss = this.GenerateSimulatedData(1, Baseline=1e-3, Variance=1e-5);
                data = sprintf("C= %.7f PF L= %.7f DS V= 0.100 V", capacitance, loss);
            elseif(this.Continuous_Mode)
                %The bridge sends each result as it is measured - read the
                %next one
                data = this.ReadString();
            else
                %SINGLE (abbreviated SI) takes one measurement and replies
                %with its result line
                data = this.QueryString("SI");
            end

            dataRow = this.ParseResult(data);

            %Record the time now the measurement has just finished
            finishTime = posixtime(datetime('now')) / 60;

            if(this.Record_Times)
                dataRow = [dataRow, beginTime, finishTime];
            end
        end

    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function values = ParseResult(data)
            %Read the capacitance, loss and voltage out of a bridge result line.
            %Uses the field labels, so works with fixed or variable field widths,
            %and with "C>"/"L>" (lower bound) labels
            %
            %Inputs:
            %   data - result line, e.g. "C= 454.688993 PF L= 0.01744 NS V= 15.0 V"
            %
            %Outputs:
            %   values - [capacitance, loss, voltage]. A field missing from
            %            the line (e.g. disabled with FORMAT) is NaN

            labels = ["C", "L", "V"];
            values = NaN(1, numel(labels));
            for i = 1:numel(labels)
                token = regexp(string(data), labels(i) + "\s*[=>]\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)", "tokens", "once");
                if ~isempty(token)
                    values(i) = str2double(token(1));
                end
            end
        end

    end
end
