classdef (ConstructOnLoad) InstrumentControlAddEventData < event.EventData

    %% Properties (Public)
    properties
        InstrumentRef;
        ControlDetailsStruct;
    end

    %% Constructor
    methods
        function data = InstrumentControlAddEventData(instrRef, controlDetailsStruct)
            data.InstrumentRef = instrRef;
            data.ControlDetailsStruct = controlDetailsStruct;
        end
    end
end
