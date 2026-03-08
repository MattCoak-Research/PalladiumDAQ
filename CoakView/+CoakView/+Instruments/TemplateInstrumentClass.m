classdef TemplateInstrumentClass < CoakView.Core.Instrument
    %Instrument implementation for .. insert details here
    %Make a copy of this class and modify it when adding a new instrument

    properties(Constant, Access = public)
        FullName = 'FULLNAME';       %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = 'NAME';                            %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.Ethernet;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end

    properties(Access = private)

    end

    methods

        %% Constructor
        function this = TemplateInstrumentClass()

        end


        %% GetSupportedConnectionTypes
        function connectionTypes = GetSupportedConnectionTypes(this)
            connectionTypes = [...
                CoakView.Enums.ConnectionType.Debug,...
                CoakView.Enums.ConnectionType.GPIB,...
                CoakView.Enums.ConnectionType.VISA,...
                CoakView.Enums.ConnectionType.Ethernet,...
                CoakView.Enums.ConnectionType.USB...
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

        %% CollectMetadata
        function metadataStruct = CollectMetaData(this)
            %Does nothing by default - implementations of individual
            %instruments can override this to give functionality.
            %Delete this function if no metadata is desired for this
            %instrument.
            %If a struct is returned it will be parsed
            %into a string and that added as a line in the data file
            %header.
            %Use this to record instrument settings and metadata like
            %frequency, voltage, measurement mode, that will not change
            %during the measurement and therefore don't merit logging each
            %step
            metadataStruct.ExampleProperty1 = "String Prop";
            metadataStruct.ExampleProperty2 = 10.3;
        end

        %% Measure
        function [dataRow] = Measure(this)

            if(this.SimulationMode)
                %Dummy values
                dataRow = [500 0.1 nan];
                return;
            end


        end

    end

    methods(Access = protected)

        %% GetPropertiesToIgnore
        function propertiesToIgnore = GetPropertiesToIgnore(this)
            %MFLI does not connect in the usual way, has a device ID only -
            %hide all these connection options in the GUI..
            propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address", "VISA_Address"};
        end

    end
end

