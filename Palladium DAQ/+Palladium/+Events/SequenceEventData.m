classdef (ConstructOnLoad) SequenceEventData < event.EventData
    %SequenceEventData - Event data for a sequence, as text or as commands.
    %Sent by the Sequence Editor with its SequenceRun and SaveButtonPressed
    %events, holding the sequence's text. The SequenceEditorController then
    %sends the parsed commands with its SequenceQueue event, for the
    %Controller to run.

    %% Properties (Public)
    properties
        Value   %The sequence text, or a cell array of its commands
    end

    %% Constructor
    methods
        function data = SequenceEventData(value)
            %Create the event data for a sequence.

            data.Value = value;
        end
    end
end
