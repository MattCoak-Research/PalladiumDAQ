classdef (ConstructOnLoad) CommandEntryEventData < event.EventData
    %CommandEntryEventData - Event data for a command entered in the Sequence Editor.
    %Sent with the CommandInsert event by the Sequence Editor and its
    %command entry panels (Wait, Instrument, Data File, Run Sequence).
    %`Details` holds the values entered in the form, which
    %`CommandEncoder.BuildCommandFromEventDetails` turns into a command.

    %% Properties (Public)
    properties
        Details     %Struct of the values entered: Type (e.g. "WAIT" or "DATAFILE") and that command's fields
    end

    %% Constructor
    methods
        function data = CommandEntryEventData(value)
            %Create the event data for the values entered for a command.

            data.Details = value;
        end
    end
end
