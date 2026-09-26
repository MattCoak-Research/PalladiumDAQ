classdef (ConstructOnLoad) SweepDataEventData < event.EventData
   properties
      Data;
   end
   
   methods
       function data = SweepDataEventData(data)
         data.Data = data;
      end
   end
end
