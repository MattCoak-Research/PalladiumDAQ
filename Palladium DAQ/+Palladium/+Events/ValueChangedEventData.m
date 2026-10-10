classdef (ConstructOnLoad) ValueChangedEventData < event.EventData
    %ValueChangedEventData - Event data carrying a single new value.
    %The general-purpose event data, sent with many events whose payload is
    %one value - for example the Controller's FileWriteOptionsChanged (the
    %file write details), the TimingLoopController's TargetUpdateTimeChanged
    %and UpdateTimeChanged (the target and actual time between ticks, in s),
    %and the GUI's DirectoryChanged and FileNameChanged.

    %% Properties (Public)
    properties
        Value   %The new value
    end

    %% Constructor
    methods
        function data = ValueChangedEventData(value)
            %Create the event data for a new value.

            data.Value = value;
        end
    end
end
