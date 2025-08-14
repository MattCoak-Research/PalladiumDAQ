classdef (ConstructOnLoad) ValueChangedEventData < event.EventData
   properties
      Value
   end
   
   methods
       function data = ValueChangedEventData(value)
         data.Value = value;
      end
   end
end
