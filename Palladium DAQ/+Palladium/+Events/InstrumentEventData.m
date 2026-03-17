classdef (ConstructOnLoad) InstrumentEventData < event.EventData
   properties
      InstrumentRef;
   end
   
   methods
       function data = InstrumentEventData(instrRef)
         data.InstrumentRef = instrRef;
      end
   end
end
