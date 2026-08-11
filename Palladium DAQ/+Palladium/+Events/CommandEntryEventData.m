classdef (ConstructOnLoad) CommandEntryEventData < event.EventData

    %% Properties (Public)
    properties
        Details
    end

    %% Constructor
    methods
        function data = CommandEntryEventData(value)
            data.Details = value;
        end
    end
end
