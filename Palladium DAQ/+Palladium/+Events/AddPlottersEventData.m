classdef (ConstructOnLoad) AddPlottersEventData < event.EventData
    %AddPlottersEventData - Event data giving the layout of a new grid of plotters.
    %Sent with the NewTabButtonClicked and NewWindowButtonClicked events of
    %the New Tab and New Window buttons (NewPlotButtonsPanel): the plotters
    %are laid out in a grid of `Rows` by `Cols`.

    %% Properties (Public)
    properties
        Rows    %Number of rows of plotters
        Cols    %Number of columns of plotters
    end

    %% Constructor
    methods
        function data = AddPlottersEventData(rows, cols)
            %Create the event data for a rows-by-cols grid of plotters.

            data.Rows = rows;
            data.Cols = cols;
        end
    end
end
