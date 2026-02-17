classdef (ConstructOnLoad) MeasurementsInitialisedEventData < event.EventData
   properties
      Headers; %As string array
   end
   
   methods
       function data = MeasurementsInitialisedEventData(headers)
         data.Headers = headers;
      end
   end
end
