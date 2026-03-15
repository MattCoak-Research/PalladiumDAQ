classdef (ConstructOnLoad) InstrumentControlAddEventData < event.EventData
   properties
      InstrumentRef;
      ControlDetailsStruct;
   end
   
   methods
       function data = InstrumentControlAddEventData(instrRef, controlDetailsStruct)
           data.InstrumentRef = instrRef;
           data.ControlDetailsStruct = controlDetailsStruct;
      end
   end
end
