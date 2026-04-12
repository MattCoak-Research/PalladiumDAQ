classdef (ConstructOnLoad) CommandEventData < event.EventData

    %% Properties (Public)
    properties
        InstrumentRef;
        CommandString
    end

    %% Constructor
    methods
        function data = CommandEventData(instrRef, commandStr)
            data.InstrumentRef = instrRef;
            data.CommandString = commandStr;
        end
    end
end
