classdef (ConstructOnLoad) AddPlottersEventData < event.EventData
   properties
      Rows;
      Cols
   end
   
   methods
       function data = AddPlottersEventData(rows, cols)
         data.Rows = rows;
         data.Cols = cols;
      end
   end
end
