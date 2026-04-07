classdef (ConstructOnLoad) AddPlottersEventData < event.EventData

    %% Properties (Public)
    properties
        Rows;
        Cols
    end

    %% Constructor
    methods
        function data = AddPlottersEventData(rows, cols)
            data.Rows = rows;
            data.Cols = cols;
        end
    end
end
