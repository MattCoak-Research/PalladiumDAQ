classdef (ConstructOnLoad) PlotterEventData < event.EventData
    %PlotterEventData - Event data for a plot to save.
    %Sent with a plotter's SavePlot event (PlotterPanel and
    %SimplePlotterPanel), giving the axes to save and the figure they are in.

    %% Properties (Public)
    properties
        Axes        %The plot's axes
        Figure      %The figure the axes are in
    end

    %% Constructor
    methods
        function data = PlotterEventData(axes, figure)
            %Create the event data for a plot's axes and figure.

            data.Axes = axes;
            data.Figure = figure;
        end
    end
end
