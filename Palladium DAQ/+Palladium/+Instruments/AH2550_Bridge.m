classdef AH2550_Bridge < Palladium.Core.Instrument
    %AH2550_Bridge - Instrument driver for the Andeen-Hagerling 2550A (and 2550) capacitance bridge.
    %Records capacitance (pF), loss and the test signal voltage (V) each
    %measurement tick, read from the bridge's result line, e.g.
    %`C= 454.688993 PF L= 0.01744 NS V= 15.0 V`. The result line must
    %include field labels (the default, set with the bridge's FORMAT
    %command).
    %
    %In `Continuous_Mode` (the default), start continuous measurements on the
    %bridge first; each Measure reads its newest result. Otherwise each
    %Measure takes one measurement with the SINGLE command, which can take
    %several seconds. `Record_Times` adds columns with the time just before
    %and after the measurement, as the temperature etc. can change during a
    %long one.
    %
    %Choose the loss units set on the bridge (its UNITS command) in
    %`Loss_Units`, which names the loss column. The driver doesn't change
    %the bridge's units: it checks the units label of the first result after
    %connecting, and stops with a message if they don't match.
    %
    %The bridge has GPIB and RS-232 interfaces. Over RS-232 the defaults
    %match the bridge's own (9600 baud, 8 data bits, no parity, 1 stop bit),
    %and command echoing - on by default on the bridge - is turned off on
    %connecting, as it would be read as part of the replies.
    %
    %The command details are from the AH 2500A manual (no 2550A manual was
    %available), so are not checked against a 2550A.

    %% Properties (Public)
    properties(Access = public)
        FullName = "AH Bridge";                                     %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "AH_Br";                                             %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;      %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Loss_Units categorical;                                     %Loss units set on the bridge (its UNITS command), for the loss column: TanDelta (dissipation factor), kOhm (series resistance), nS (conductance - the bridge's default), GOhm (parallel resistance) or jpF (G/omega)
        Continuous_Mode (1,1) logical = true;                       %If true, the bridge is measuring continuously and Measure reads its newest result. If false, Measure takes a single measurement.
        Record_Times (1,1) logical = false;                         %Add columns with the time (in minutes, UTC) just before and after each measurement - a measurement can take a long time
    end

    %% Properties (Private)
    properties(Access = private)
        UnitsChecked = false;                                       %True once a result's loss units have been checked against Loss_Units, since connecting
    end

    %% Properties (Dependent, Private)
    properties(Dependent, Access = private)
        LossUnit;                                                   %Units string of the loss column, from Loss_Units: e.g. "" for TanDelta, "kOhm" for kOhm
        LossLabel;                                                  %The bridge's label for Loss_Units on a result line: NS, DS, KO, GO or GW
    end

    %% Get and Set Accessors
    methods
        function unitStr = get.LossUnit(this)
            switch(this.Loss_Units)
                case(this.LossUnitsType("TanDelta"));   unitStr = "";
                case(this.LossUnitsType("kOhm"));       unitStr = "kOhm";
                case(this.LossUnitsType("nS"));         unitStr = "nS";
                case(this.LossUnitsType("GOhm"));       unitStr = "GOhm";
                case(this.LossUnitsType("jpF"));        unitStr = "jpF";
                otherwise
                    error("AH2550_Bridge:UnsupportedLossUnits", 'Unsupported Loss Units');
            end
        end

        function label = get.LossLabel(this)
            %As the bridge labels each of its UNITS settings (2500A manual, UNITS)
            switch(this.Loss_Units)
                case(this.LossUnitsType("nS"));         label = "NS";
                case(this.LossUnitsType("TanDelta"));   label = "DS";
                case(this.LossUnitsType("kOhm"));       label = "KO";
                case(this.LossUnitsType("GOhm"));       label = "GO";
                case(this.LossUnitsType("jpF"));        label = "GW";
                otherwise
                    error("AH2550_Bridge:UnsupportedLossUnits", 'Unsupported Loss Units');
            end
        end
    end

    %% Categoricals
    methods
        function catOut = LossUnitsType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["TanDelta", "kOhm", "nS", "GOhm", "jpF"]); end
    end

    %% Constructor
    methods
        function this = AH2550_Bridge()
            %Set the supported connection types, default connection settings and loss units.

            %The bridge has GPIB and RS-232 ports; VISA can address either
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Serial", "VISA"]);
            this.GPIB_Address = 28;     %Factory default of the 2500A (no 2550A manual was available to check)
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

            %RS-232: the bridge's defaults (2500A manual, BAUD). It ends
            %replies with CR LF; commands are sent ending CR (see OnConnected)
            this.ConnectionSettings.SerialSettings = struct('BaudRate', 9600, 'DataBits', 8, 'Parity', 'none', 'StopBits', 1, 'Terminator', 'CR/LF');

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
            %The newest continuous result, or a new single measurement - see
            %Continuous_Mode. The first result after connecting is checked
            %for the loss units in Loss_Units
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
                data = sprintf("C= %.7f PF L= %.7f %s V= 0.100 V", capacitance, loss, this.LossLabel);
            elseif(this.Continuous_Mode)
                data = this.ReadNewestResult();
            else
                %SINGLE (abbreviated SI) takes one measurement and replies
                %with its result line
                data = this.QueryString("SI");
            end

            [dataRow, lossLabel] = this.ParseResult(data);
            if ~this.UnitsChecked
                this.CheckLossUnits(lossLabel);
                this.UnitsChecked = true;
            end

            %Record the time now the measurement has just finished
            finishTime = posixtime(datetime('now')) / 60;

            if(this.Record_Times)
                dataRow = [dataRow, beginTime, finishTime];
            end
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function OnConnected(this)
            %Get ready to read results: check the units again, and over RS-232 send commands ending CR and turn echoing off.

            this.UnitsChecked = false;
            if this.SimulationMode || this.Connection_Type ~= Palladium.Enums.ConnectionType.Serial
                return;
            end

            %Replies end CR LF; commands end with a carriage return (2500A
            %manual, First-Time Serial Link Operation)
            configureTerminator(this.DeviceHandle, "CR/LF", "CR");

            %Echoing (on by default) would put each command into its reply.
            %BAUD's seventh parameter is echo; the periods leave the others
            %as they are (2500A manual, BAUD and Positional Parameters). Then
            %discard the echo and prompt it may have sent
            this.WriteCommand("BAUD ......0");
            pause(0.2);
            flush(this.DeviceHandle, "input");
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function data = ReadNewestResult(this)
            %The newest result the bridge has sent, in continuous mode.
            %Over GPIB the bridge keeps only its newest result - an unread one
            %is overwritten (2500A manual, Receiving Every Response Message) -
            %so a read gets it, waiting for the next if needed. Over RS-232 it
            %sends every result, and they queue up in the port's buffer if
            %Palladium measures less often than the bridge: read through them
            %all and keep the newest, waiting for the next only if none is
            %waiting. (Reading one at a time used to fall further and further
            %behind)

            data = "";
            if this.Connection_Type == Palladium.Enums.ConnectionType.Serial
                while this.DeviceHandle.NumBytesAvailable > 0
                    line = string(this.ReadString());
                    if contains(line, "C")      %A result line - not just a prompt
                        data = line;
                    end
                end
            end
            if data == ""
                data = this.ReadString();
            end
        end

        function CheckLossUnits(this, lossLabel)
            %Check a result's loss units label matches Loss_Units - stop with a message if not.
            %No label (e.g. labels turned off with FORMAT) can't be checked

            if lossLabel == "" || lossLabel == this.LossLabel
                return;
            end
            labels = ["NS", "DS", "KO", "GO", "GW"];
            names = ["nS", "TanDelta", "kOhm", "GOhm", "jpF"];
            bridgeUnits = names(labels == lossLabel);
            if isempty(bridgeUnits)
                bridgeUnits = lossLabel;
            end
            error("AH2550_Bridge:LossUnitsMismatch", "%s", this.Name + " reports loss in " + bridgeUnits + " (" + lossLabel + ...
                "), but its Loss_Units setting is " + string(this.Loss_Units) + ", which names the loss column. Set Loss_Units to " + ...
                bridgeUnits + ", or change the bridge's units to match (UNITS command: 1 nS, 2 TanDelta, 3 kOhm, 4 GOhm, 5 jpF).");
        end

    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function [values, lossLabel] = ParseResult(data)
            %Read the capacitance, loss and voltage out of a bridge result line, and the loss units label.
            %Uses the field labels, so works with fixed or variable field widths,
            %and with "C>"/"L>" (lower bound) labels
            %
            %Inputs:
            %   data - result line, e.g. "C= 454.688993 PF L= 0.01744 NS V= 15.0 V"
            %
            %Outputs:
            %   values    - [capacitance, loss, voltage]. A field missing from
            %               the line (e.g. disabled with FORMAT) is NaN
            %   lossLabel - the loss units label after the loss, e.g. "NS"; "" if none

            labels = ["C", "L", "V"];
            values = NaN(1, numel(labels));
            for i = 1:numel(labels)
                token = regexp(string(data), labels(i) + "\s*[=>]\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)", "tokens", "once");
                if ~isempty(token)
                    values(i) = str2double(token(1));
                end
            end

            lossLabel = "";
            token = regexp(string(data), "L\s*[=>]\s*[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?\s+([A-Z]{2})(?:\s|$)", "tokens", "once");
            if ~isempty(token)
                lossLabel = token(1);
            end
        end

    end
end
