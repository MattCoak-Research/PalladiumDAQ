classdef (ConstructOnLoad) DataRowAddedEventData < event.EventData

    %% Properties (Public)
    properties
        DataRow;
        Headers;
    end

    %% Constructor
    methods
        function data = DataRowAddedEventData(dataRow, headers)
            data.DataRow = dataRow;
            data.Headers = headers;
        end
    end
end
