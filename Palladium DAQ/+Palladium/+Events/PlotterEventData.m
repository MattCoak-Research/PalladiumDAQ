classdef (ConstructOnLoad) PlotterEventData < event.EventData
   properties
      Axes;
      Figure;
   end
   
   methods
       function data = PlotterEventData(axes, figure)
         data.Axes = axes;
         data.Figure = figure;
      end
   end
end
