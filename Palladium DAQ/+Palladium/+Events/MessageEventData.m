classdef (ConstructOnLoad) MessageEventData < event.EventData

    %% Properties (Public)
    properties
        Message;
        Title;
    end

    %% Constructor
    methods
        function data = MessageEventData(message, title)
            arguments
                message {mustBeTextScalar};
                title = "";
            end

            data.Message = message;
            data.Title = title;
        end
    end
end
