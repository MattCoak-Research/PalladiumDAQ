classdef (ConstructOnLoad) SweepSetupEventData < event.EventData
    %SweepSetupEventData - Event data for the settings of a sweep to run.
    %Sent with the Keithley 2450 Double Gate Sweep panel's Run event (with the
    %sweep settings) and Abort event (empty).

    %% Properties (Public)
    properties
        SweepDetails    %Struct of the sweep settings entered, or [] when aborting
    end

    %% Constructor
    methods
        function data = SweepSetupEventData(sweepDetails)
            %Create the event data for a sweep's settings.

            data.SweepDetails = sweepDetails;
        end
    end
end
