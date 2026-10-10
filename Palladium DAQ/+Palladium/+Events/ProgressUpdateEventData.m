classdef (ConstructOnLoad) ProgressUpdateEventData < event.EventData
    %ProgressUpdateEventData - Event data for an update to a progress dialog.
    %Sent with the Controller's UpdatedProgress event during slow operations
    %such as connecting to instruments.

    %% Properties (Public)
    properties
        Progress    %Fraction complete, from 0 to 1
        Message     %Text describing the current step, e.g. "Connecting to K2000_1"
    end

    %% Constructor
    methods
        function data = ProgressUpdateEventData(progress, message)
            %Create the event data for a progress update.
            %
            %Inputs:
            %   progress - fraction complete, from 0 to 1
            %   message  - text describing the current step

            arguments
                progress (1,1) double;
                message {mustBeTextScalar};
            end

            data.Progress = progress;
            data.Message = message;
        end
    end
end
