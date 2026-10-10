classdef (ConstructOnLoad) InstrumentEventData < event.EventData
    %InstrumentEventData - Event data naming one instrument.
    %Sent with the Instrument browser's SelectionChange event, giving the
    %instrument selected, so its settings are shown.

    %% Properties (Public)
    properties
        InstrumentRef   %The instrument
    end

    %% Constructor
    methods
        function data = InstrumentEventData(instrRef)
            %Create the event data for an instrument.

            data.InstrumentRef = instrRef;
        end
    end
end
