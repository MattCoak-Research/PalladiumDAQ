classdef TestInstrument < CoakView.Core.Instrument
    %Instrument implementation for .. insert details here
    %Make a copy of this class and modify it when adding a new instrument

    properties(Access = public, SetObservable)
        FullName = 'Test Instrument';       %Full name, just for displaying on GUI
        Name = 'TestInstrument';                            %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.Debug;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end

    properties(Access = private)
        FirstRun = true;
    end

    methods

        %% Constructor
        function this = TestInstrument()

        end


        %% GetSupportedConnectionTypes
        function connectionTypes = GetSupportedConnectionTypes(this)
            connectionTypes = [...
                CoakView.Enums.ConnectionType.Debug
                ];
        end


        %% GetAvailableControlOptions
        function [controlDetailsStructs] = GetAvailableControlOptions(this)
            %Tell the GUI what options for Control GUIs to create
            controlDetailsStructs = struct(...
                "Name", "Sweep Control",...
                "ControlClassFileName", "SweepController_Stepped",...
                "TabName", "Sweep Control",...
                "EnabledByDefault", false);
        end


        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
            %Gets the column headers for data columns returned by this
            %instrument. There must be the same number as Measure returns.
            Headers = [this.Name + " - Resistance_Ohms", this.Name + " - Current_A"];
            Units = ["Ohms", "A"];

        end

        %% Measure
        function [dataRow] = Measure(this)

            pause(1);

            if this.FirstRun
                this.FirstRun = false;
                error("test error that only runs once");
            end
            
            if(this.SimulationMode)
                %Dummy values
                dataRow = [500 0.1];
                return;
            end
    


        end

    end
end

