classdef Agilent_53220A_FreqCounter < Palladium.Core.Instrument
    %Agilent_53220A_FreqCounter - Instrument driver for the Agilent (Keysight) 53220A 350 MHz frequency counter.
    %Measures the frequency of the signal on channel 1 each measurement
    %tick, with `MEAS:FREQ?` set up for the signal expected
    %(`ExpectedFrequency_Hz`, 20 MHz by default) and the resolution wanted
    %(`Resolution_Hz`, 0.01 Hz by default). MEASure sets the counter's
    %trigger and gate settings itself (internal trigger, one reading, a
    %gate time from the resolution - a finer resolution takes longer), so
    %those set on the front panel are not used.
    %
    %The 53220A has LAN, USB and (option 400) GPIB interfaces. Over LAN,
    %connect to its SCPI socket, port 5025.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Agilent 53220A Frequency Counter";              %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "A53220A";                                           %Instrument name, used as the prefix of its data column header
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;      %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        ExpectedFrequency_Hz (1,1) double {mustBePositive} = 20e6;  %Frequency of the signal expected, in Hz - with Resolution_Hz, sets the gate time
        Resolution_Hz (1,1) double {mustBePositive} = 0.01;         %Resolution wanted, in Hz - finer resolution needs a longer gate time, so each reading takes longer
    end

    %% Constructor
    methods
        function this = Agilent_53220A_FreqCounter()
            %Set the supported connection types and default connection settings.

            %The 53220A has LAN, USB and GPIB ports - no RS-232
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "USB", "VISA"]);
            this.GPIB_Address = 3;      %Factory default
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [Headers, Units] = GetHeaders(this)
            %Data column header and units for the frequency returned by Measure
            %
            %Outputs:
            %   Headers - e.g. "A53220A - Freq (Hz)"
            %   Units   - "Hz"

            Headers = this.Name + " - Freq (Hz)";
            Units = "Hz";
        end

        function [dataRow] = Measure(this)
            %Take a frequency reading on channel 1, in Hz.
            %
            %Outputs:
            %   dataRow - the frequency, in Hz

            if(this.SimulationMode)
                freq_Hz = this.GenerateSimulatedData(1, Baseline=17e6, Variance=0.1e6);
            else
                %Expected frequency and resolution, both in Hz - together
                %they set the gate time. Parameters are comma separated,
                %e.g. MEAS:FREQ? 20E6, 0.1, (@1) (User's Guide, chapter 3,
                %Frequency measurements)
                freq_Hz = this.QueryDouble("MEAS:FREQ? " + Palladium.Core.Instrument.NumberToCommandString(this.ExpectedFrequency_Hz) + "," + ...
                    Palladium.Core.Instrument.NumberToCommandString(this.Resolution_Hz) + ",(@1)");
            end

            dataRow = freq_Hz;
        end

    end
end
