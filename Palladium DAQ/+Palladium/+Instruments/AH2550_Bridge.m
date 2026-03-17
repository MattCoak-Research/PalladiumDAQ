classdef AH2550_Bridge < Palladium.Core.Instrument
    %Instrument implementation for Andeen Hagerling 2550 and 2550A
    %capacitance bridge. Assumes instrument has already been set measuring,
    %and grabs latest values only.

    properties(Constant, Access = public)
        FullName = "AH Bridge";     %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = "AH_Br";             %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Loss_Units;                 %Selected units of capacitive loss, for column headers and extracting data from measurement string. 'TanDelta', 'kOhm' supported at this time.
        Continuous_Mode = true;     %If false, bridge will perform single measurement only on Measure call. If true, bridge should be set to be continuously measure, and Measure will read the screen display - default.
        Record_Times = false;       %Set this to true to create additional data columns of universal time in minutes before the measurement and immediately after it - AH Bridge measurements can take a long time, during which temperaature etc can change
    end

    properties(Dependent, Access = private)
        LossUnit;
    end

    
    methods

        %% Categoricals
        function catOut = LossUnitsType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["TanDelta", "kOhm"]); end

        %% Constructor
        function this = AH2550_Bridge()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = 22;      %Default Address
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];
            this.Loss_Units = this.LossUnitsType("TanDelta");
        end

        %% LossUnit Get Accessor
        function unitStr = get.LossUnit(this)
            switch(this.Loss_Units)
                case(this.LossUnitsType("TanDelta"))
                    unitStr = "";
                case(this.LossUnitsType("kOhm"))
                    unitStr = " kOhm";
                otherwise
                    error('Unsupported Loss Units');
            end
        end
        
        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
            if(this.Record_Times)
                Headers = [this.Name + " - Cap (pF)", this.Name + " - Loss (" + string(this.LossUnit) + ")", "Voltage (V)", this.Name + " - Time before (min)", this.Name + " - Time after (min)"];
                Units = ["pF", string(this.LossUnit), "V", "min", "min"];
            else
                Headers = [this.Name + " - Cap (pF)", this.Name + "Loss (" + string(this.LossUnit) + ")", this.Name + " - Voltage (V)"];
                Units = ["pF", string(this.LossUnit), "V"];
            end
        end
        
        %% Measure        
        function [dataRow] = Measure(this)
            %Record the time just before querying the measurement - note
            %this is only really sensible in immediate mode, and is only
            %used if Record_Time is set to true
            beginTime = posixtime(datetime('now')) /60; %Get current time in universal coordinated time (seconds since 1970) then divide by 60 to get minutes

            if(this.SimulationMode)
                %Just generate some dummy random numbers
                capacitance = rand() * 4e-1 + 3.1e2;
                loss = rand() * 1e-3;
                voltage = 0.1;
                dataRow = [capacitance, loss, voltage];
            else
                if(this.Continuous_Mode)
                    % Communicating with instrument object. It should be continuously measuring (set manually) - then its output buffer will keep being updated and we can simply read it out as a string
                    data= this.ReadString();
                else
                    %Query a single triggered measurement
                    data = this.QueryString("SI");
                end

                switch(this.Loss_Units)
                    case(this.LossUnitsType("TanDelta"))
                        lossUnitsStr = "TODO";
                    case(this.LossUnitsType("kOhm"))
                        lossUnitsStr = " KO";
                    otherwise
                        error("Unsupported Loss Units");
                end

                xStr1 = strfind(data, "C=");
                xStr2 = strfind(data, " PF");   %Potentially an issue? - unit may differ. Seems ok.

                xStr3 = strfind(data, " L=");
                xStr4 = strfind(data, lossUnitsStr);   %Problematic - unit may differ

                xStr5 = strfind(data, " V=");
                xStr6 = strfind(data, "  V");

                %Snip the values out of the string
                capacitance=data(xStr1+2:xStr2);
                loss=data(xStr3+3:xStr3+13);
                voltage=data(xStr5+3:xStr6);

                %Assign C, L, V, to output data row
                dataRow = [str2double(capacitance), str2double(loss), str2double(voltage)];
            end

            %Record the time now the measurement has just finished
            finishTime = posixtime(datetime('now')) /60; %Get current time in universal coordinated time (seconds since 1970) then divide by 60 to get minutes

            %Append time records to the datarow if desired
            if(this.Record_Times)
                dataRow = [dataRow, beginTime, finishTime];
            end
            
        end
    end
end

