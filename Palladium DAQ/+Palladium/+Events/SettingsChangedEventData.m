classdef (ConstructOnLoad) SettingsChangedEventData < event.EventData
    %SettingsChangedEventData - Event data for the settings applied from the config file.
    %Sent with the Controller's SettingsApplied event once the settings in
    %Config.json have been loaded, so the GUI can show the default folders
    %and apply the window settings.

    %% Properties (Public)
    properties
        PathSettings    %The PathSettings section of Config.json: data, sequence and user files folders
        WindowSettings  %The WindowSettings section of Config.json
    end

    %% Constructor
    methods
        function data = SettingsChangedEventData(pathSettings, windowSettings)
            %Create the event data for the path and window settings.

            data.PathSettings = pathSettings;
            data.WindowSettings = windowSettings;
        end
    end
end
