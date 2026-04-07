classdef (ConstructOnLoad) MeasurementsInitialisedEventData < event.EventData

    %% Properties (Public)
    properties
        Headers; %As string array
    end

    %% Constructor
    methods
        function data = MeasurementsInitialisedEventData(headers)
            data.Headers = headers;
        end
    end
end
