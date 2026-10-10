classdef (ConstructOnLoad) LakeshoreHeaterControlSetEventData < event.EventData
    %LakeshoreHeaterControlSetEventData - Event data for heater settings entered in a Heater Control.
    %Sent with the Lakeshore Heater Control's HeaterSettingsInput event when
    %Set is pressed. The instrument applies the settings on its next
    %measurement tick (`Instrument.SettingsInput`).

    %% Properties (Public)
    properties
        Settings    %Struct of the settings entered: ControlMode, HeaterRange, SetPoint, RampRate, RampEnabled, ManualOutput, and PID_Settings (P, I and D)
    end

    %% Constructor
    methods
        function data = LakeshoreHeaterControlSetEventData(settings)
            %Create the event data for a set of heater settings.

            data.Settings = settings;
        end
    end
end
