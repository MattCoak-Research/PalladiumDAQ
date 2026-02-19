classdef (ConstructOnLoad) SettingsChangedEventData < event.EventData
   properties
      PathSettings;
      WindowSettings;
   end
   
   methods
       function data = SettingsChangedEventData(pathSettings, windowSettings)
         data.PathSettings = pathSettings;
         data.WindowSettings = windowSettings;
      end
   end
end
