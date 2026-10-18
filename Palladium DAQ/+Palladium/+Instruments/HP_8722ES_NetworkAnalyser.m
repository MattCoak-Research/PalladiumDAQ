classdef HP_8722ES_NetworkAnalyser < Palladium.Core.Instrument
    %HP_8722ES_NetworkAnalyser - Instrument driver for the HP 8722ES vector network analyser.
    %Records whole frequency sweeps through the Scan Control tab, rather
    %than a value each measurement tick: each scan is saved to its own data
    %file as two columns, frequency (Hz) and the S-parameter selected by
    %`MeasMode`. `Measure` returns no values, so the analyser adds no
    %columns to the main data file.
    %
    %Before each sweep the driver selects `MeasMode`'s S-parameter and the
    %display format for `MeasUnit` (log magnitude for dB, linear magnitude
    %for Absolute), then takes one sweep (`OPC?;SING;`), checking for its
    %completion each tick without waiting. The trace is read as ASCII
    %(`FORM4;`, `OUTPFORM;`) and the frequency of each point from the
    %limit-test array (`OUTPLIML;`), which gives them for linear, log and
    %list sweeps alike. Set the frequency range, points, power and
    %calibration on the analyser. (Commands from the 8719ES/8720ES/8722ES
    %Programmer's Guide.)
    %
    %The 8722ES (50 MHz to 40 GHz) is remote-controlled over HP-IB (GPIB)
    %only - its RS-232 and parallel ports are for printers and plotters.
    %Other analysers in the HP 8719/8720/8722 ES and ET family share its
    %HP-IB command set and should work too.

    %% Properties (Public)
    properties(Access = public)
        FullName = "HP 8722ES Network Analyser";                %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'HP_8722ES_NetworkAnalyser';                     %Instrument name, used as the prefix of its scan data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;                                               %S-parameter to measure: S11, S21, S12 or S22 - selected on the analyser before each sweep
        MeasUnit;                                               %dB (log magnitude) or Absolute (linear magnitude) - the display format is set to match before each sweep
    end

    %% Properties (Private)
    properties(Access = private)
        ScanComplete = true;                                    %False while a sweep started by RunScan is under way
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr);        catOut = this.ConvertToCategorical(inputStr, ["S11", "S21", "S12", "S22"]); end
        function catOut = MeasUnitType(this, inputStr);    catOut = this.ConvertToCategorical(inputStr, ["dB", "Absolute"]); end
    end

    %% Constructor
    methods
        function this = HP_8722ES_NetworkAnalyser()
            %Set the supported connection types, default settings and Scan Control tab.

            %HP-IB is the only remote-control interface; VISA can address
            %it through a GPIB adapter
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "VISA"]);
            this.GPIB_Address = 16;     %Factory default
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

            %Default settings
            this.MeasMode = this.MeasType("S11");
            this.MeasUnit = this.MeasUnitType("dB");

            %Define the Instrument Controls that can be added
            this.DefineInstrumentControl(Name = "Scan Control", ClassName = "ScanController", TabName = "Scan Control", EnabledByDefault = true);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function RunScan(this)
            %Start one sweep, for the Scan Control tab - without waiting for it (see CheckScanComplete).
            %Selects MeasMode's S-parameter and MeasUnit's display format
            %first. A device clear first discards any reply left from an
            %aborted sweep

            this.ScanComplete = false;
            if this.SimulationMode
                return;
            end

            this.Clear();
            this.WriteCommand(string(this.MeasMode) + ";");
            this.WriteCommand(this.DisplayFormatCommand() + ";");

            %OPC? makes the analyser reply 1 once the single sweep is done
            %(Programmer's Guide, Example 3B)
            this.WriteCommand("OPC?;SING;");
        end

        function complete = CheckScanComplete(this)
            %Check, without waiting, whether the sweep started by RunScan has finished - for the Scan Control tab.
            %The sweep has finished once the reply to OPC?;SING; is waiting
            %(a serial poll); it is then read. In SimulationMode, finishes at
            %random, one call in ten
            %
            %Outputs:
            %   complete - true once the sweep has finished

            if ~this.ScanComplete
                if this.SimulationMode
                    this.ScanComplete = randi(100) > 90;
                elseif this.IsReplyWaiting()
                    this.ReadString();      %The "1" from OPC?
                    this.ScanComplete = true;
                end
            end
            complete = this.ScanComplete;
        end

        function Clear(this)
            %Send a device clear to the instrument, clearing its input and output buffers.

            if this.SimulationMode
                return;
            end

            clrdevice(this.DeviceHandle);
        end

        function metadataStruct = CollectMetaData(this)
            %Sweep settings, recorded in the data-file header.
            %
            %Outputs:
            %   metadataStruct - struct with fields Freq_Start_Hz, Freq_Stop_Hz and NumPoints

            metadataStruct.Freq_Start_Hz = this.GetStartFrequency();
            metadataStruct.Freq_Stop_Hz = this.GetStopFrequency();
            metadataStruct.NumPoints = this.GetNumPoints();
        end

        function data = GetCompletedScanData(this)
            %The completed sweep, for the Scan Control tab to save and plot.
            %The formatted trace (OUTPFORM sends two values per point; in log
            %and linear magnitude formats the first is the value) and the
            %frequency of each point (the first of OUTPLIML's four values
            %per point), both in ASCII (FORM4) - Programmer's Guide,
            %Examples 3B and 3D
            %
            %Outputs:
            %   data - one row per point: [frequency in Hz, S-parameter in MeasUnit]

            if this.SimulationMode
                numPoints = this.GetNumPoints();
                frequency = linspace(this.GetStartFrequency(), this.GetStopFrequency(), numPoints)';
                values = this.GenerateSimulatedData(numPoints, 1, Baseline=-3, Variance=0.1);
                data = [frequency, values(:)];
                return;
            end

            this.WriteCommand("FORM4;");
            trace = this.QueryNumbers("OUTPFORM;");
            limits = this.QueryNumbers("OUTPLIML;");

            values = trace(1:2:end);
            frequency = limits(1:4:end);
            assert(numel(values) == numel(frequency), "HP_8722ES_NetworkAnalyser:DataSizeMismatch", "%s", ...
                this.Name + ": the trace has " + numel(values) + " points but the frequency list " + numel(frequency) + ".");
            data = [frequency(:), values(:)];
        end

        function [Headers, Units] = GetHeaders(~)
            %No per-tick data columns - scans are recorded through the Scan Control tab.
            %
            %Outputs:
            %   Headers - empty
            %   Units   - empty

            Headers = [];
            Units = [];
        end

        function [Headers, Units] = GetScanHeaders(this)
            %Column headers and units of the scan data files written by the Scan Control tab.
            %
            %Outputs:
            %   Headers - frequency and S-parameter headers, e.g. "HP_8722ES_NetworkAnalyser - S11 (dB)"
            %   Units   - their units: "Hz", and "dB" or "" for the S-parameter

            Headers = [this.Name + " - Frequency_Hz", this.Name + " - " + string(this.MeasMode) + " (" + string(this.MeasUnit) + ")"];
            if this.MeasUnit == this.MeasUnitType("dB")
                Units = ["Hz", "dB"];
            else
                Units = ["Hz", ""];
            end
        end

        function numOfPoints = GetNumPoints(this)
            %Read the number of points per sweep.
            %
            %Outputs:
            %   numOfPoints - number of points (20 in SimulationMode)

            if this.SimulationMode
                numOfPoints = 20;
                return;
            end

            numOfPoints = this.QueryDouble("POIN?;");
        end

        function startFreq_Hz = GetStartFrequency(this)
            %Read the sweep start frequency, in Hz.

            if this.SimulationMode
                startFreq_Hz = 50e6;
                return;
            end

            startFreq_Hz = this.QueryDouble("STAR?;");
        end

        function stopFreq_Hz = GetStopFrequency(this)
            %Read the sweep stop frequency, in Hz.

            if this.SimulationMode
                stopFreq_Hz = 40e9;
                return;
            end

            stopFreq_Hz = this.QueryDouble("STOP?;");
        end

        function [dataRow] = Measure(~)
            %Return no values - scans are recorded through the Scan Control tab instead.
            %
            %Outputs:
            %   dataRow - empty, matching GetHeaders

            dataRow = [];
        end

    end

    %% Methods (Protected)
    methods(Access = protected)

        function OnConnected(this)
            %Allow a long timeout, for slow sweeps and large data transfers, after connecting.
            %(The connection's input buffer has no fixed size to enlarge -
            %setting InputBufferSize, as this used to, errored on connecting)

            this.ScanComplete = true;
            if this.SimulationMode
                return;
            end

            this.DeviceHandle.Timeout = 30;
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function command = DisplayFormatCommand(this)
            %The display format command for MeasUnit: LOGM (log magnitude, dB) or LINM (linear magnitude).

            switch(this.MeasUnit)
                case(this.MeasUnitType("dB"));          command = "LOGM";
                case(this.MeasUnitType("Absolute"));    command = "LINM";
                otherwise
                    error("HP_8722ES_NetworkAnalyser:InvalidMeasUnit", "%s", "MeasUnit must be dB or Absolute, received " + string(this.MeasUnit));
            end
        end

        function numbers = QueryNumbers(this, command)
            %Send an output command and read its reply as a list of comma-separated numbers (FORM4 ASCII).

            reply = string(this.QueryString(command));
            numbers = str2double(strsplit(strtrim(reply), ","));
            numbers = numbers(:)';
        end

    end
end
