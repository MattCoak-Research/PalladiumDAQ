classdef PNA_L_NetworkAnalyser < Palladium.Core.Instrument
    %PNA_L_NetworkAnalyser - Instrument driver for the Keysight (Agilent) PNA-L N5232A vector network analyser.
    %Records whole frequency sweeps through the Scan Control tab, rather
    %than a value each measurement tick. Running a scan triggers one sweep
    %on channel 1; when the channel returns to HOLD the sweep is read back
    %and saved to its own data file as two columns, frequency (Hz) and the
    %formatted trace data of the selected measurement. `Measure` returns no
    %values, so the analyser adds no columns to the main data file. The
    %sweep settings are recorded in the data-file header.
    %
    %Set up the measurement (S-parameter, format, frequency range, points)
    %on the instrument, with the trigger source set to Internal. `MeasMode`
    %and `MeasUnit` label the data column; `MeasMode` is also the parameter
    %used by `DefineMeasurement`.
    %
    %The PNA-L is controlled with SCPI commands over GPIB or LAN. Other PNA
    %series analysers share the command set and should work too, but have
    %not been tested.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Keysight PNA-L N5232A Network Analyser";    %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'PNA';                                           %Instrument name, used as the prefix of its scan data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;                                               %S-parameter measured: S11, S21, S12 or S22. Labels the data column, and is the parameter DefineMeasurement creates.
        MeasUnit;                                               %Units label (dB or Absolute) for the data column header. Only labels the column - set the trace format on the instrument.
    end

    %% Properties (Private)
    properties(Access = private)
        SimulatedSweepTime_s = 0.2;                             %In SimulationMode, how long a sweep takes
        SimulatedSweepStartTime = [];                           %In SimulationMode, tic of the last sweep triggered - empty if none
    end

    %% Categoricals
    methods
        function catOut = MeasType(this, inputStr);        catOut = this.ConvertToCategorical(inputStr, ["S11", "S21", "S12", "S22"]); end
        function catOut = MeasUnitType(this, inputStr);    catOut = this.ConvertToCategorical(inputStr, ["dB", "Absolute"]); end
    end

    %% Constructor
    methods
        function this = PNA_L_NetworkAnalyser()
            %Set the supported connection types, default settings and Scan Control tab.

            %Not USB: "Use of the PNA as a USB Device is not supported" (PNA
            %Help). Ethernet is the SCPI socket, port 5025
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "VISA"]);
            this.GPIB_Address = 16;     %Factory default
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];
            this.ConnectionSettings.GPIB_Timeout = 3;

            %Default settings
            this.MeasMode = this.MeasType("S11");
            this.MeasUnit = this.MeasUnitType("dB");

            %Define the Instrument Controls that can be added
            this.DefineInstrumentControl(Name = "Scan Control", ClassName = "ScanController", TabName = "Scan Control", EnabledByDefault = true);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function complete = CheckScanComplete(this)
            %Check whether the current scan has finished, for the Scan Control tab.
            %
            %Outputs:
            %   complete - true when the sweep is complete (see CheckSystemReady)

            complete = this.CheckSystemReady();
        end

        function ready = CheckSystemReady(this)
            %Check whether channel 1 has finished its sweep and is back on HOLD.
            %In SimulationMode, a sweep takes SimulatedSweepTime_s from
            %TriggerSingle, after which it stays ready until the next one
            %
            %Outputs:
            %   ready - true when the channel's sweep mode is HOLD

            if this.SimulationMode
                ready = isempty(this.SimulatedSweepStartTime) || toc(this.SimulatedSweepStartTime) >= this.SimulatedSweepTime_s;
                return;
            end

            %We are assuming here that the instrument is on HOLD, then will
            %execute a single measurement via TriggerSingle. Then it will
            %be in status SING throughout that, then go back to HOLD when
            %the measurement is complete. HOLD therefore means Ready
            val = this.QueryTriggerStatus();
            ready = strcmp(val, "HOLD");
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
            %   metadataStruct - struct with fields Freq_Start_Hz, Freq_Stop_Hz,
            %   NumPoints, SweepTime_s and SweepType

            metadataStruct.Freq_Start_Hz = this.GetFrequencyStart();
            metadataStruct.Freq_Stop_Hz = this.GetFrequencyStop();
            metadataStruct.NumPoints = this.GetNumPoints();
            metadataStruct.SweepTime_s = this.GetSweepTime();
            metadataStruct.SweepType = this.GetSweepType();
        end

        function DefineMeasurement(this, name)
            %Create a measurement on channel 1 of the S-parameter in MeasMode.
            %
            %Inputs:
            %   name - name of the new measurement, e.g. "CH1_S11_1"

            arguments
                this;
                name {mustBeTextScalar} = "CH1_S11_1";
            end

            %scpi.Parse("CALC:PAR:DEF ""sdd21"",S11")
            this.WriteCommand("CALC:PAR:DEF " + """" + name + """," + string(this.MeasMode));
        end

        function data = FetchData(this)
            %Read the formatted trace data of the selected measurement on channel 1.
            %Call only once the sweep is complete. Sets ASCII data format
            %(CALCulate:DATA? FDATA - "formatted measurement data", as displayed)
            %
            %Outputs:
            %   data - row vector of one value per point, in the displayed format (two
            %          values per point, real and imaginary, for Polar and Smith chart formats)

            if this.SimulationMode
                %One value per point, as from the instrument
                data = this.GenerateSimulatedData(this.GetNumPoints, 1, Baseline=1, Variance=0.04);
                data = data(:)';
                return;
            end

            this.WriteCommand("FORMat ASCII");
            data = this.QueryNumbers("CALCulate1:DATA? FDATA");
        end

        function data = GetCompletedScanData(this)
            %Frequencies and trace data from a completed scan, for the Scan Control tab to save and plot.
            %Polar and Smith chart formats give two values per point (real
            %and imaginary), so three columns - see GetScanHeaders
            %
            %Outputs:
            %   data - one row per point: [frequency (Hz), value], or [frequency (Hz), real, imaginary]

            %Read the trace first: FetchData sets the ASCII data format that
            %GetFrequencyValues also needs
            traceData = this.FetchData();
            frequency = this.GetFrequencyValues();
            numPoints = numel(frequency);

            if numel(traceData) == numPoints
                data = [frequency(:), traceData(:)];
            elseif numel(traceData) == 2 * numPoints
                data = [frequency(:), reshape(traceData, 2, [])'];
            else
                error("PNA_L_NetworkAnalyser:DataSizeMismatch", "%s", this.Name + ": the trace has " + numel(traceData) + ...
                    " values but the sweep " + numPoints + " points - expected one or two values per point.");
            end
        end

        function format = GetDisplayFormat(this)
            %Read the display format of the selected measurement on channel 1, e.g. "MLOG", "POL" or "SMIT".
            %(CALCulate:FORMat? - MLINear, MLOGarithmic, PHASe, UPHase,
            %IMAGinary, REAL, POLar, SMITh, SADMittance, SWR, GDELay, KELVin,
            %FAHRenheit or CELSius, in short form.) "MLOG" in SimulationMode
            %
            %Outputs:
            %   format - the format's short form (string)

            if this.SimulationMode
                format = "MLOG";
                return;
            end

            format = upper(strip(string(this.QueryString("CALCulate1:FORMat?"))));
        end

        function freq_Hz = GetFrequencyStart(this)
            %Read the channel 1 start frequency, in Hz.

            if this.SimulationMode
                freq_Hz = 300e3;
                return;
            end

            freq_Hz = this.QueryDouble("SENSe1:FREQuency:STARt?");
        end

        function freq_Hz = GetFrequencyStop(this)
            %Read the channel 1 stop frequency, in Hz.

            if this.SimulationMode
                freq_Hz = 300e3 + this.GetNumPoints - 1;
                return;
            end

            freq_Hz = this.QueryDouble("SENSe1:FREQuency:STOP?");
        end

        function freqVals_Hz = GetFrequencyValues(this)
            %Read the stimulus (frequency) value of every point in the sweep.
            %Reply is in the current data format (FORMat), which must be ASCII
            %
            %Outputs:
            %   freqVals_Hz - row vector of frequencies, in Hz

            if this.SimulationMode
                freqVals_Hz = 300e3 : 300e3 + this.GetNumPoints - 1;
                return;
            end

            freqVals_Hz = this.QueryNumbers("SENS:X?");
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
            %Read when a scan starts. In Polar and Smith chart display
            %formats, which give two values per point, there are real and
            %imaginary columns instead of one value column
            %
            %Outputs:
            %   Headers - frequency and S-parameter headers, e.g. "PNA - S11 (dB)", or
            %             "PNA - S11 Real" and "PNA - S11 Imaginary"
            %   Units   - their units: "Hz", and "" for the S-parameter

            sParameter = this.Name + " - " + string(this.MeasMode);
            if any(this.GetDisplayFormat() == ["POL", "SMIT", "SADM"])
                Headers = [this.Name + " - Frequency_Hz", sParameter + " Real", sParameter + " Imaginary"];
                Units = ["Hz", "", ""];
            else
                Headers = [this.Name + " - Frequency_Hz", sParameter + " (" + string(this.MeasUnit) + ")"];
                Units = ["Hz", ""];
            end
        end

        function time = GetSweepTime(this)
            %Read the channel 1 sweep time, in seconds.

            if this.SimulationMode
                time = 1.4;
                return;
            end

            time = this.QueryDouble("SENS1:SWE:TIME?");
        end

        function type = GetSweepType(this)
            %Read the sweep type: "Linear" or "Log", as SetSweepType takes them - or "Power", "CW" or "Segment".
            %The instrument replies with the short form (LIN, LOG, POW, CW,
            %SEGM); anything else is returned as it came
            %
            %Outputs:
            %   type - the sweep type (string); "Linear" in SimulationMode

            if this.SimulationMode
                type = "Linear";
                return;
            end

            type = upper(strip(string(this.QueryString("SENS:SWE:TYPE?"))));
            switch type
                case "LIN";     type = "Linear";
                case "LOG";     type = "Log";
                case "POW";     type = "Power";
                case "CW";      type = "CW";
                case "SEGM";    type = "Segment";
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

            numOfPoints = this.QueryDouble("SENS:SWE:POIN?");
        end

        function [dataRow] = Measure(~)
            %Return no values - scans are recorded through the Scan Control tab instead.
            %Sweeps are slow and standalone, so this instrument does not
            %return row-by-row data
            %
            %Outputs:
            %   dataRow - empty, matching GetHeaders

            dataRow = [];
        end

        function statusStr = QueryTriggerStatus(this)
            %Read the channel 1 sweep (trigger) mode: HOLD, CONT, GRO or SING.

            result = this.QueryString("SENS1:SWEep:MODE?");
            statusStr = strip(string(result));
        end

        function RunScan(this)
            %Start a scan, when Run is pressed on the Scan Control tab, by triggering one sweep.

            this.TriggerSingle();
        end

        function SetFrequencyStartAndStop(this, start_Hz, stop_Hz)
            %Set the channel 1 start and stop frequencies.
            %
            %Inputs:
            %   start_Hz - start frequency, in Hz
            %   stop_Hz  - stop frequency, in Hz

            arguments
                this;
                start_Hz (1,1) double;
                stop_Hz (1,1) double;
            end

            this.WriteCommand("SENSe1:FREQuency:STARt " + Palladium.Core.Instrument.NumberToCommandString(start_Hz));
            this.WriteCommand("SENSe1:FREQuency:STOP " + Palladium.Core.Instrument.NumberToCommandString(stop_Hz));
        end

        function SetNumPoints(this, numPts)
            %Set the number of points per sweep (1 to 20001).

            arguments
                this;
                numPts (1,1) {mustBeInteger}
            end

            if this.SimulationMode
                disp("Set simulated VNA num pts to " + num2str(numPts));
                return;
            end

            this.WriteCommand("SENS:SWE:POIN " + Palladium.Core.Instrument.NumberToCommandString(numPts));
        end

        function SetSweepTime(this, time_s)
            %Set the channel 1 sweep time, in seconds.

            arguments
                this;
                time_s (1,1) double {mustBePositive};
            end

            if this.SimulationMode
                disp("Set simulated VNA scan time to " + num2str(time_s) + " s");
                return;
            end

            this.WriteCommand("SENS1:SWE:TIME " + Palladium.Core.Instrument.NumberToCommandString(time_s));
        end

        function SetSweepType(this, type)
            %Set the sweep type to linear or logarithmic frequency.
            %
            %Inputs:
            %   type - "Linear" or "Log" (as GetSweepType returns them)

            arguments
                this;
                type {mustBeTextScalar}; %The instrument also has POWer, CW and SEGMent (SEGMent needs a segment turned ON) - not supported here
            end

            if this.SimulationMode
                disp("Set simulated VNA sweep type to " + type);
                return;
            end

            switch(type)
                case("Linear");     this.WriteCommand("SENS:SWE:TYPE LIN");
                case("Log");        this.WriteCommand("SENS:SWE:TYPE LOG");
                otherwise
                    error("PNA_L_NetworkAnalyser:UnsupportedSweepType", "%s", "Sweep type " + string(type) + " not supported");
            end
        end

        function SelectMeasurement(this, name)
            %Select a measurement on channel 1, for the CALCulate commands (e.g. FetchData) to act on.
            %
            %Inputs:
            %   name - name of the measurement, e.g. "CH1_S11_1"

            arguments
                this;
                name {mustBeTextScalar} = "CH1_S11_1";
            end

            this.WriteCommand("CALC:PAR:SEL " + """" + name + """");
        end

        function TriggerSingle(this, waitForCompletion)
            %Trigger one sweep on channel 1, after which it goes to HOLD.
            %
            %Inputs:
            %   waitForCompletion - if true, wait until the sweep is complete
            %                       (see WaitForSystemReady). Default false

            arguments
                this;
                waitForCompletion (1,1) logical = false;
            end

            if this.SimulationMode
                this.SimulatedSweepStartTime = tic();
                if waitForCompletion
                    this.WaitForSystemReady();
                end
                return;
            end

            this.WriteCommand("SENS1:SWE:MODE SINGle");

            %Polled, rather than with *OPC? - a query that waits for the
            %whole sweep would time out (3 s) on longer sweeps
            if waitForCompletion
                this.WaitForSystemReady();
            end
        end

    end

    %% Methods (Protected)
    methods(Access = protected)

        function OnConnected(this)
            %Enlarge the input buffer for trace data transfers, after connecting.
            %Big enough for the largest ASCII trace: 20001 points, two values
            %per point in Polar/Smith formats, about 21 characters each

            if this.SimulationMode
                return;
            end

            this.DeviceHandle.InputBufferSize = 2e6;
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function numbers = QueryNumbers(this, command)
            %Send a query and read its reply as a list of comma-separated numbers (ASCII data format).

            reply = string(this.QueryString(command));
            numbers = str2double(split(strip(reply), ","))';
        end

        function WaitForSystemReady(this)
            %Poll CheckSystemReady every 50 ms until the sweep is complete.
            %Errors if it takes over twice the sweep time plus 10 s - e.g.
            %if the trigger source isn't Internal, so the sweep never runs

            timeLimit_s = 2 * this.GetSweepTime() + 10;
            startTime = tic();
            while ~this.CheckSystemReady()
                if toc(startTime) > timeLimit_s
                    error("PNA_L_NetworkAnalyser:SweepTimeout", "%s", this.Name + ": the sweep did not finish within " + ...
                        timeLimit_s + " s - check the trigger source is set to Internal on the analyser.");
                end
                pause(0.05);
            end
        end

    end
end
