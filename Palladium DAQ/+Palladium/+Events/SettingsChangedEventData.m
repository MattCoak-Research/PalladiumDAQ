classdef (ConstructOnLoad) SettingsChangedEventData < event.EventData

    %% Properties (Public)
    properties
        PathSettings;
        WindowSettings;
    end

    %% Constructor
    methods
        function data = SettingsChangedEventData(pathSettings, windowSettings)
            data.PathSettings = pathSettings;
            data.WindowSettings = windowSettings;
        end
    end
end
