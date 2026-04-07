classdef (ConstructOnLoad) PlotterEventData < event.EventData

    %% Properties (Public)
    properties
        Axes;
        Figure;
    end

    %% Constructor
    methods
        function data = PlotterEventData(axes, figure)
            data.Axes = axes;
            data.Figure = figure;
        end
    end
end
