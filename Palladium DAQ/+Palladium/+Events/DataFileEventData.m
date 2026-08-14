classdef (ConstructOnLoad) DataFileEventData < event.EventData

    %% Properties (Public)
    properties
        FileWriteDetails
    end

    %% Constructor
    methods
        function data = DataFileEventData(fileWriteDetails)
            data.FileWriteDetails = fileWriteDetails;
        end
    end
end
