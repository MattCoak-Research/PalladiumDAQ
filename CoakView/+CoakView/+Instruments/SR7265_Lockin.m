classdef SR7265_Lockin < CoakView.Core.Instrument
    %Instrument implementation for Signal Recovery 7265 or 7260 Model lockin
    %amplifiers
    
    properties(Constant, Access = public)
        FullName = "SR7265 Lockin";     %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = "SR7265";             %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.Debug;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        AutoSensitivity = true;    %Toggle if the instrument should change voltage range automatically
    end
    
    properties(Access = private)
        DefaultGPIB_Address = 8;          %GPIB address
    end
    
    methods
        
        %% Constructor
        function this = SR7265_Lockin()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = this.DefaultGPIB_Address;
        end

        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
            Headers = [this.Name + " - Vx (V)", this.Name + " - Vy (V)"];
            Units = ["V", "V"];
        end

        %% Measure
        function [dataRow] = Measure(this)
            if(this.SimulationMode)
                data = "0.0705876,0.00256349";
            else
                %Query the lockin for simultaneous x and y values measurement and get a ???? seperated string
                %returned. example for x, y of 70mV and 2.5mV: '??????
                %TEST THIS'. Note the '.' after commands to specify
                %'floating-point' mode. This is important! Refer to
                %instrument manual.
                data = this.QueryString("XY.");
            end

            %Split the string into a cell array, split at the commas
            splitData = strsplit(data, ',');

            %Get measurement values from the split string
            x = str2double(splitData{1});
            y = str2double(splitData{2});
            
            %Assign data to output data row
            dataRow = [x, y];
            
            %If sensitivity autotune is enabled, auto adjust the
            %sensitivity level
            if(this.AutoSensitivity)
                this.AutoTuneSensitivity();
            end
        end
    end
    
    methods (Access = private)

        %% AutoTuneSensitivity
        function AutoTuneSensitivity(this)
        %Automatically increase or decrease sensitivity range by 1 if
        %voltage outside useful range

            %Grab 'magnitude' of signal (sqrt(vxvx+vyvy))
            %Because we didn't write the '.' afterwards, MAG is returned as
            %an Int, range 0 to 30000, full-scale being 10000, independent
            %of voltage range - ie a fraction of current range saturation
            mag = this.QueryMagnitudeLevel();       
            
            %Grab the current sensitivity range, as an index. See p208 of
            %the manual. We may decide to increment or decrement this shortly 
            sen = this.QuerySensitivityLevel();         
            
            %Specify level at which to move up a range. 20,000 / 30,000
            upperCutoff = 20000;
            
            %Specify level at which to move down a range
            lowerCutoff = 4000;
            
            if(mag >= upperCutoff)                              %If voltage is equal to or above cutoff of the current range, we need to switch up a range
                sensIndex = sen +1;                             %Increase range index by 1 - higher voltage range
                sensIndex = min(sensIndex, 27);                 %27 is highest value, top range
                
                %Set the new range
                this.SetSensitivityLevel(sensIndex);
            elseif(mag < lowerCutoff)                           %if voltage is less than the lower factor x the max value of the range below this one, switch down
                sensIndex = sen -1;                             %Decrease range index by 1 - lower voltage range
                sensIndex = max(sensIndex, 0);                  %0 is minimum value, lowest range
                
                %Set the new range
                this.SetSensitivityLevel(sensIndex);
            end
        end   
        
        %% QueryMagnitudeLevel
        function magnitude = QueryMagnitudeLevel(this)
        %Returns an integer corresponding to the current
        %sensitivity / voltage range of the instrument.
        if(this.SimulationMode)
            magnitude = 15000;
        else
            magnitude = this.QueryDouble("MAG");
        end
        end

        %% QuerySensitivityLevel
        function sensitivityIndex = QuerySensitivityLevel(this)
            %Returns an integer corresponding to the current
            %sensitivity / voltage range of the instrument.
            if(this.SimulationMode)
                sensitivityIndex = 3;
            else
                sensitivityIndex = this.QueryDouble("SEN");
            end
        end
        
        %% SetSensitivityLevel
        function SetSensitivityLevel(this, levelIndexInt)
            %Set a sensitivity level by passing an integer (from 0 to
            %27)
            if(this.SimulationMode); return; end

            this.WriteCommand("SEN " + string(levelIndexInt));
        end
    end
end

