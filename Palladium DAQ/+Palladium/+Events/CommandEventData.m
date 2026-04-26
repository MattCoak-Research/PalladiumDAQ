classdef (ConstructOnLoad) CommandEventData < event.EventData

    %% Properties (Public)
    properties
        InstrumentRef;
        CommandString
        ControlName;    %Empty by default
        FunctionToRunOnComplete;
    end

    %% Constructor
    methods
        function data = CommandEventData(instrRef, commandStr, controlName, completeFunc)
            arguments
                instrRef (1,1) Palladium.Core.Instrument;
                commandStr {mustBeTextScalar};
                controlName = "";
                completeFunc = [];
            end

            data.InstrumentRef = instrRef;
            data.CommandString = commandStr;

            if isempty(char(controlName))
                data.ControlName = string.empty;
            else
                data.ControlName = controlName;
            end

            data.FunctionToRunOnComplete = completeFunc;
        end
    end
end
