classdef (ConstructOnLoad) InstrumentEventData < event.EventData

    %% Properties (Public)
    properties
        InstrumentRef;
    end

    %% Constructor
    methods
        function data = InstrumentEventData(instrRef)
            data.InstrumentRef = instrRef;
        end
    end
end
