classdef (ConstructOnLoad) LakeshoreHeaterControlSetEventData < event.EventData
   properties
      Settings;
   end
   
   methods
       function data = LakeshoreHeaterControlSetEventData(settings)
         data.Settings = settings;
      end
   end
end
