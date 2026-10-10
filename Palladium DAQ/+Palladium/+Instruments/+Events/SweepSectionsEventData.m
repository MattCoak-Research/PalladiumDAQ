classdef (ConstructOnLoad) SweepSectionsEventData < event.EventData
    %SweepSectionsEventData - Event data for the sections of a sweep selected to run.
    %Sent with the sweep sections control's SelectionChanged event. A full
    %sweep passes through 7 key points, numbered 0 to 6: middle, maximum,
    %middle, minimum, middle, maximum, middle. The sweep runs through the key
    %points from `Start` to `Stop` (`SweepController.CalculateExtremalPoints`).

    %% Properties (Public)
    properties
        Start   %Number of the first key point of the sweep, 0 to 6
        Stop    %Number of the last key point of the sweep, 0 to 6
    end

    %% Constructor
    methods
        function data = SweepSectionsEventData(start, stop)
            %Create the event data for the selected range of key points.

            data.Start = start;
            data.Stop = stop;
        end
    end
end
