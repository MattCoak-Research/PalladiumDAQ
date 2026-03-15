classdef Agilent_53220A_FreqCounter < Palladium.Core.Instrument
    %Instrument implementation for Agilent 53220A Frequency Counter.
    %Assumes device has already been manually configured and is measuring
    %frequency.

    properties(Constant, Access = public)
        FullName = 'Aglient 53220A Frequency Counter';              %Full name, just for displaying on GUI
    end
    
    properties(Access = public, SetObservable)
        Name = 'A53220A';                                           %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;      %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end
    
    
    methods
        
        %% Constructor
        function this = Agilent_53220A_FreqCounter()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = 3;      %Default Address
        end

        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
            Headers = this.Name + " - Freq (Hz)";
            Units = "Hz";
        end

        %% Measure
        function [dataRow] = Measure(this)
            if(this.SimulationMode)
                    %Dummy values
                    freq_Hz = 17e6 + rand * 0.1e6;
            else
                    %Define some values
                    expectedFreq = 20e6;
                    resolution = 0.01;
                    
                    %Measure
                    freq_Hz = this.QueryDouble("MEAS:FREQ? " + num2str(expectedFreq) + " " + num2str(resolution) + " (@1)");
            end            
            
            %Assign data to output data row - data array is just the
            %frequency value
            dataRow = freq_Hz;
        end


    end
end

