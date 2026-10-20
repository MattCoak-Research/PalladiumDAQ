classdef (ConstructOnLoad) InstrumentAddedEventData < event.EventData
    %InstrumentAddedEventData - Event data for an instrument that has been added.
    %Sent with the InstrumentController's InstrumentAdded event, so the GUI
    %can list the new instrument and show its settings.

    %% Properties (Public)
    properties
        InstrumentRef       %The instrument added
        InstrStringToAdd    %Class name of the instrument added, e.g. "Keithley2000"
    end

    %% Constructor
    methods
        function data = InstrumentAddedEventData(instrStringToAdd, instrRef)
            %Create the event data for an added instrument.
            %
            %Inputs:
            %   instrStringToAdd - class name of the instrument, e.g. "Keithley2000"
            %   instrRef         - the instrument added

            data.InstrStringToAdd = instrStringToAdd;
            data.InstrumentRef = instrRef;
        end
    end
end
