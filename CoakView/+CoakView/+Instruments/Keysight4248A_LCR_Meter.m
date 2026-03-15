classdef Keysight4248A_LCR_Meter < CoakView.Core.Instrument
    %Instrument implementation for Keysight 4248A LCR Meter. Assumes instrument has already been set measuring,
    %and grabs latest values only.

    properties(Constant, Access = public)
        FullName = "4248A LCR Meter";     %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = "LCR_Mtr";             %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end


    properties(Access = private)
        DefaultGPIB_Address = 22;          %GPIB address
    end

    methods

        %% Constructor
        function this = Keysight4248A_LCR_Meter()
            this.GPIB_Address = this.DefaultGPIB_Address;

            %Define the Instrument Controls that can be added to the
            %Instrument
            this.DefineInstrumentControl(Name = "Sweep Control", ClassName = "SweepController_Stepped", TabName = "Sweep Control", EnabledByDefault = false);
        end

        %% GetSweepUnitsString
        function [str, limits] = GetSweepUnitsString(this)
            %Tells the Sweep controller what the units and limits are of
            %the parameter it is sweeping
            str = "Hz";
            limits = [20, 1e6];    %max and min Frequency, in Hz
        end

        %% GetSupportedConnectionTypes
        function connectionTypes = GetSupportedConnectionTypes(this)
            connectionTypes = [...
                CoakView.Enums.ConnectionType.Debug,...
                CoakView.Enums.ConnectionType.GPIB
                ];
        end

        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
            Headers = [this.Name + " - Cap (pF)", this.Name + "Loss ()", this.Name + " - Frequency (Hz)", this.Name + " - Voltage (V)", this.Name + " - Bias Voltage (V)"];
            Units = ["pF", " ", "Hz", "V", "V"];
        end

        %% Measure
        function [dataRow] = Measure(this)
            %Update the sweep controller, if one is added and a sweep is currently running, and apply its
            %latest target source level
            if ~isempty(this.SweepController)
                if this.SweepController.Running
                    valueToSet = this.SweepController.Update();
                    this.SetFrequency(valueToSet);
                end
            end

          %Query instrument for latest data with a Fetch command
          [cap_pF, loss, bias] = this.FetchMeasurement();

          %Query measurement paramters - frequency and voltage
          freq_Hz = this.GetFrequency();
          voltage_V = this.GetVoltage();

          %Assemble values into a table row to return
          dataRow = [cap_pF, loss, freq_Hz, voltage_V, bias];
        end

        %% FetchMeasurement
        function [param1, param2, bias] = FetchMeasurement(this) 
            if (this.SimulationMode)
                %Dummy values if simulating instrument
                param1 = 17 + rand()*0.1;
                param2 = 1.563e-6 + rand()*0.1e-6;
                bias = 0;
                return;
            end

          %resultStr = this.QueryString("FETC[:IMP]?");
          resultStr = this.QueryString("FETC?");

          %We expect resultStr to be in the format e.g.
          %"-3.32504E-14,+8.03461E-01,+0"
          s = strsplit(resultStr, ",");

          %Extract values and parse into numbers - could add error handling
          %here and return NaNs if so
          param1 = str2double(s{1});
          param2 = str2double(s{2});
          bias = str2double(s{3});
        end

        %% GetFrequency
        function freqHz = GetFrequency(this) 
            if (this.SimulationMode)
                %Dummy values if simulating instrument
                freqHz = 10000;
                return;
            end

            freqHz = this.QueryDouble("FREQ?");
        end

        %% SetFrequency
        function SetFrequency(this, freqHz)
             if(this.SimulationMode)
                %Do nothing, just print
                disp("Setting LCR Meter frequency to " + num2str(freqHz) + " Hz");
                return;
             end

            freqStr = numstr(freqHz);
            this.WriteCommand("FREQ " + freqStr + "HZ");
        end

        %% GetVoltage
        function voltage_V = GetVoltage(this)
            if (this.SimulationMode)
                %Dummy values if simulating instrument
                voltage_V = 0.1;
                return;
            end

            voltage_V = this.QueryDouble("VOLT?");
        end

        %% SetVoltage
        function SetVoltage(this, voltage_V)
              if(this.SimulationMode)
                %Do nothing, just print
                disp("Setting LCR Meter voltage to " + num2str(voltage_V) + " V");
                return;
              end

            vStr = numstr(voltage_V);
            this.WriteCommand("VOLT " + vStr + "V");
        end
    end
end

