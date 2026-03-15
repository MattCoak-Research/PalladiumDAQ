classdef (ConstructOnLoad) SweepSectionsEventData < event.EventData
   properties
      Start;
      Stop;
   end
   
   methods
       function data = SweepSectionsEventData(start, stop)
         data.Start = start;
         data.Stop = stop;
      end
   end
end
