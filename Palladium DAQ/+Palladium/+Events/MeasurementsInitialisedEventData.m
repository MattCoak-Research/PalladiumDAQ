classdef (ConstructOnLoad) MeasurementsInitialisedEventData < event.EventData
    %MeasurementsInitialisedEventData - Event data for measurements that are ready to start.
    %Sent with the TimingLoopController's MeasurementsInitialised event once
    %the instruments are connected and the data column headers are known,
    %just before the measurement loop starts.

    %% Properties (Public)
    properties
        Headers     %The data column headers, as a string array
    end

    %% Constructor
    methods
        function data = MeasurementsInitialisedEventData(headers)
            %Create the event data for the data column headers.

            data.Headers = headers;
        end
    end
end
