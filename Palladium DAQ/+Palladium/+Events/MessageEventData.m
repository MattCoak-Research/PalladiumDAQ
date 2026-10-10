classdef (ConstructOnLoad) MessageEventData < event.EventData
    %MessageEventData - Event data for a message to show in the GUI.
    %Sent with the Controller's GreenStatus, YellowStatus and RedStatus
    %events (the status bar) and its StartedShowingProgress event (the
    %progress dialog, which also has a title).

    %% Properties (Public)
    properties
        Message     %The message text
        Title       %Title of the dialog the message is shown in, or "" for none
    end

    %% Constructor
    methods
        function data = MessageEventData(message, title)
            %Create the event data for a message, with an optional title.

            arguments
                message {mustBeTextScalar};
                title = "";
            end

            data.Message = message;
            data.Title = title;
        end
    end
end
