classdef Keysight4284A_LCR_Meter < Palladium.Core.Instrument
    %Keysight4284A_LCR_Meter - Instrument driver for the Keysight (Agilent/HP) 4284A precision LCR meter.
    %Reads the latest measurement result with `FETC?` each measurement
    %tick, plus the test signal frequency and voltage. Set the measurement
    %function to a capacitance one (e.g. Cp-D) and the trigger on the front
    %panel first: the result's main and sub parameters are recorded as
    %capacitance (in F) and loss, followed by the measurement status (0 for
    %a good measurement - the readings are NaN otherwise).
    %
    %A Sweep Control can be added to step the test frequency, over the
    %4284A's 20 Hz to 1 MHz range. The 4284A has a GPIB (HP-IB) interface
    %only.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Keysight 4284A Precision LCR Meter";            %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "LCR_Mtr";                                           %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;      %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end

    %% Constructor
    methods
        function this = Keysight4284A_LCR_Meter()
            %Set the supported connection types, default connection settings and Sweep Control.

            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "VISA"]);
            this.GPIB_Address = 22;

            %Define the Instrument Controls that can be added
            this.DefineInstrumentControl(Name = "Sweep Control", ClassName = "SweepController_Stepped", TabName = "Sweep Control", EnabledByDefault = false);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [param1, param2, status] = FetchMeasurement(this)
            %Read the latest measurement result and its status.
            %
            %Outputs:
            %   param1 - main parameter, in base SI units, e.g. Cp in F for the
            %            Cp-D function. NaN if status is not 0
            %   param2 - sub parameter, e.g. D for the Cp-D function. NaN if
            %            status is not 0
            %   status - measurement status: 0 normal, -1 no data, 1 analog
            %            bridge unbalanced, 2 A/D converter not working, 3
            %            signal source overloaded, 4 ALC unable to regulate

            if (this.SimulationMode)
                param1 = this.GenerateSimulatedData(1, Baseline=17e-12, Variance=0.1e-12);
                param2 = this.GenerateSimulatedData(1, Baseline=2e-6, Variance=1e-8);
                status = 0;
                return;
            end

            %Reply is "<DATA A>,<DATA B>,<STATUS>" (plus ",<BIN No.>" when the
            %comparator is on), e.g. "-3.32504E-14,+8.03461E-01,+0"
            %(Operation Manual, chapter 7, ASCII format)
            resultStr = this.QueryString("FETC?");
            s = strsplit(resultStr, ",");

            param1 = str2double(s{1});
            param2 = str2double(s{2});
            status = str2double(s{3});

            %Without a valid measurement the data values are 9.9E37
            if status ~= 0
                param1 = NaN;
                param2 = NaN;
            end
        end

        function freqHz = GetFrequency(this)
            %Read the test signal frequency, in Hz.
            %
            %Outputs:
            %   freqHz - test frequency, in Hz

            if (this.SimulationMode)
                freqHz = 10000;
                return;
            end

            freqHz = this.QueryDouble("FREQ?");
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure
            %
            %Outputs:
            %   Headers - capacitance, loss, frequency, voltage and measurement
            %             status headers, e.g. "LCR_Mtr - Cap (F)"
            %   Units   - matching units, ["F", " ", "Hz", "V", " "]

            Headers = [this.Name + " - Cap (F)", this.Name + " - Loss ()", this.Name + " - Frequency (Hz)", this.Name + " - Voltage (V)", this.Name + " - Status"];
            Units = ["F", " ", "Hz", "V", " "];
        end

        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(this)
            %Units, limits and plot labels of the swept test frequency, for a Sweep Control.
            %
            %Outputs:
            %   str       - units of the swept value, "Hz"
            %   limits    - lowest and highest frequencies, [20, 1e6] Hz
            %   xlabelStr - label for the frequency on plots
            %   ylabelStr - label for the measured value on plots, the
            %               capacitance header

            str = "Hz";
            limits = [20, 1e6];
            xlabelStr = "Frequency (Hz)";
            headers = this.GetHeaders();
            ylabelStr = headers(1);
        end

        function voltage_V = GetVoltage(this)
            %Read the test signal voltage level, in V.
            %
            %Outputs:
            %   voltage_V - test signal level, in V

            if (this.SimulationMode)
                voltage_V = 0.1;
                return;
            end

            voltage_V = this.QueryDouble("VOLT?");
        end

        function [dataRow] = Measure(this)
            %Read the latest result, then the test frequency and voltage.
            %
            %Outputs:
            %   dataRow - [capacitance in F, loss, frequency in Hz, voltage in V,
            %             status], matching GetHeaders

            [cap_F, loss, status] = this.FetchMeasurement();
            freq_Hz = this.GetFrequency();
            voltage_V = this.GetVoltage();

            dataRow = [cap_F, loss, freq_Hz, voltage_V, status];
        end

        function SetFrequency(this, freqHz)
            %Set the test signal frequency.
            %
            %Inputs:
            %   freqHz - test frequency, in Hz (20 Hz to 1 MHz)

            if(this.SimulationMode)
                disp("Setting LCR Meter frequency to " + num2str(freqHz) + " Hz");
                return;
            end

            this.WriteCommand("FREQ " + num2str(freqHz) + "HZ");
        end

        function SetNewSweepStepValue(this, value)
            %Go to the next step of a frequency sweep - called by a Sweep Control.
            %
            %Inputs:
            %   value - test frequency, in Hz

            this.SetFrequency(value);
        end

        function SetVoltage(this, voltage_V)
            %Set the test signal voltage level.
            %
            %Inputs:
            %   voltage_V - test signal level, in V (5 mV to 2 V in the standard
            %               configuration)

            if(this.SimulationMode)
                disp("Setting LCR Meter voltage to " + num2str(voltage_V) + " V");
                return;
            end

            this.WriteCommand("VOLT " + num2str(voltage_V) + "V");
        end

    end
end
