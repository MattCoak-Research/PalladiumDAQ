classdef (ConstructOnLoad) DataRowAddedEventData < event.EventData
   properties
      DataRow
   end
   
   methods
       function data = DataRowAddedEventData(value)
         data.DataRow = value;
      end
   end
end
