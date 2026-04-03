classdef (ConstructOnLoad) ProgressUpdateEventData < event.EventData

    %% Properties (Public)
    properties
        Progress;
        Message;
    end

    %% Constructor
    methods
        function data = ProgressUpdateEventData(progress, message)
            arguments
                progress (1,1) double;
                message {mustBeTextScalar};
            end

            data.Progress = progress;
            data.Message = message;
        end
    end
end
