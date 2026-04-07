classdef (ConstructOnLoad) ValueChangedEventData < event.EventData

    %% Properties (Public)
    properties
        Value
    end

    %% Constructor
    methods
        function data = ValueChangedEventData(value)
            data.Value = value;
        end
    end
end
