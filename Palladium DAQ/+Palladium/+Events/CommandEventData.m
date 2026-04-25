classdef (ConstructOnLoad) CommandEventData < event.EventData

    %% Properties (Public)
    properties
        InstrumentRef;
        CommandString
        FunctionToRunOnComplete;
    end

    %% Constructor
    methods
        function data = CommandEventData(instrRef, commandStr, completeFunc)
            data.InstrumentRef = instrRef;
            data.CommandString = commandStr;
            data.FunctionToRunOnComplete = completeFunc;
        end
    end
end
