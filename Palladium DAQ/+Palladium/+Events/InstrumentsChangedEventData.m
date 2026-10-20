classdef (ConstructOnLoad) InstrumentsChangedEventData < event.EventData
    %InstrumentsChangedEventData - Event data listing the instruments added, after a change.
    %Sent with the InstrumentController's InstrumentsChanged event whenever
    %an instrument is added or removed.

    %% Properties (Public)
    properties
        Instruments     %Cell array of all the instruments now added
    end

    %% Constructor
    methods
        function data = InstrumentsChangedEventData(instrs)
            %Create the event data for the current list of instruments.

            data.Instruments = instrs;
        end
    end
end
