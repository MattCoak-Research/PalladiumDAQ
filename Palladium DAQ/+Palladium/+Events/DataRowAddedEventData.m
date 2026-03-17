classdef (ConstructOnLoad) DataRowAddedEventData < event.EventData
   properties
      DataRow;
      Headers;      
   end
   
   methods
       function data = DataRowAddedEventData(dataRow, headers)
         data.DataRow = dataRow;
         data.Headers = headers;
      end
   end
end
