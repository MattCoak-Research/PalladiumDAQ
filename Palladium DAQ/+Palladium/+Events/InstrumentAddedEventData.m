classdef (ConstructOnLoad) InstrumentAddedEventData < event.EventData
   properties
      InstrumentRef;
      InstrStringToAdd;
   end
   
   methods
       function data = InstrumentAddedEventData(instrStringToAdd, instrRef)
           data.InstrStringToAdd = instrStringToAdd;
           data.InstrumentRef = instrRef;
      end
   end
end
