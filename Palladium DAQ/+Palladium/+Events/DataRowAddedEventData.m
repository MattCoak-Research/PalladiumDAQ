classdef (ConstructOnLoad) DataRowAddedEventData < event.EventData
    %DataRowAddedEventData - Event data for one measurement tick's row of data.
    %Sent each tick with the InstrumentController's DataRowCollected event
    %(to the Instrument Controls) and the Controller's DataRowUpdated event
    %(for anything else that needs each new row, e.g. a script).

    %% Properties (Public)
    properties
        DataRow     %The values measured this tick, from all instruments, in column order
        Headers     %The data column headers, matching DataRow
    end

    %% Constructor
    methods
        function data = DataRowAddedEventData(dataRow, headers)
            %Create the event data for one row of data and its headers.

            data.DataRow = dataRow;
            data.Headers = headers;
        end
    end
end
