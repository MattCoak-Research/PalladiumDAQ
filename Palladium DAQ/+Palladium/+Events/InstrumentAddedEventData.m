classdef (ConstructOnLoad) InstrumentAddedEventData < event.EventData

    %% Properties (Public)
    properties
        InstrumentRef;
        InstrStringToAdd;
    end

    %% Constructor
    methods
        function data = InstrumentAddedEventData(instrStringToAdd, instrRef)
            data.InstrStringToAdd = instrStringToAdd;
            data.InstrumentRef = instrRef;
        end
    end
end
