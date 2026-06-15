classdef (ConstructOnLoad) InstrumentsChangedEventData < event.EventData

    %% Properties (Public)
    properties
        Instruments;
    end

    %% Constructor
    methods
        function data = InstrumentsChangedEventData(instrs)
            data.Instruments = instrs;
        end
    end
end
