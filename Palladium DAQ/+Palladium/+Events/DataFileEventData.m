classdef (ConstructOnLoad) DataFileEventData < event.EventData
    %DataFileEventData - Event data for a sequence's change of data file.
    %Sent with the CommandController's DataFileCommandRun event when a
    %`[DATAFILE]` command runs in a sequence. The Controller then switches
    %writing to file on or off, and to a new file if one is given.

    %% Properties (Public)
    properties
        FileWriteDetails    %Struct with FullPath (the new data file, or "" to keep the current name) and SaveFile (true to write to file)
    end

    %% Constructor
    methods
        function data = DataFileEventData(fileWriteDetails)
            %Create the event data for a change of data file.
            %
            %Inputs:
            %   fileWriteDetails - struct with fields FullPath and SaveFile

            data.FileWriteDetails = fileWriteDetails;
        end
    end
end
