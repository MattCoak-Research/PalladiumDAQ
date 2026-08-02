classdef (ConstructOnLoad) SequenceEventData < event.EventData

    %% Properties (Public)
    properties
        Value;
    end

    %% Constructor
    methods
        function data = SequenceEventData(value)
            data.Value = value;
        end
    end
end
