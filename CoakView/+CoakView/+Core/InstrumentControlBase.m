classdef InstrumentControlBase < handle
    %InstrumentControlBase - Base class for a Logic controller add-on object to be added on to an
    %Instrument object, eg LakeshoreHeaterControl.m
    
    properties
        ControlDetailsStruct;
    end

    properties (Access = protected)
        Instrument;
    end
    
    properties (Access = private)
    end

    methods (Abstract)  
        CreateInstrumentControlGUI(this, controller, tab, instrRef);
        RemoveControl(this);
    end
    
    methods

        %% Constructor
        function this = InstrumentControlBase()
        end        

        %% GetName
        function name = GetName(this)
            name = this.ControlDetailsStruct.Name;
        end
        
    end

    methods (Access = protected)
       
        %% CreateDataRowHeaderString
        function stringLine = CreateDataRowHeaderString(this)
            %Create a line of metadata to log to a datafile that has
            %header-value pairs for each column in the overall programme
            %datarow for the last tick. This is intended for logging
            %diagnostic data like temperature at the start/end of a sweep
            %that an Instrument is writing to file itself, outside the
            %usual programme structure
            dataRow = this.Instrument.LastFullDataRow;
            hdrsRow = this.Instrument.FullHeadersRow;

            %Error checking
            if isempty(dataRow)
                warning("Data row empty in " + this.Instrument.FullName + ", cannot log to file");
                return;
            end
            if isempty(hdrsRow)
                warning("Data row empty in "  + this.Instrument.FullName + ", cannot log to file");
                return;
            end

            stringLine = CoakView.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("", hdrsRow, dataRow);
        end

        %% InitialiseDataWriter
        function dataWriter = InitialiseDataWriter(this, fileNameSuffix)
            fileWriteDetails = this.Instrument.FileWriteDetails;
            fileWriteDetails.FileName = string(fileWriteDetails.FileName) + fileNameSuffix;
            fileWriteDetails.WriteMode = 'Increment File No.';
            fileWriteDetails.SaveFile = true;

            dataWriter = CoakView.DataWriting.DataWriter(fileWriteDetails);
        end

        %% InsertEndMetadataIntoFile
        function InsertEndMetadataIntoFile(this, dataWriter)
            metadataDescLine = this.Instrument.FullName + " Scan - Measurement data at Scan End:";

            %Write the data row of all instruments/diagnostics at the end
            %of the sweep, for things like temperature, time
            dataRowMetadataLine = this.CreateDataRowHeaderString();

            dataWriter.InsertMetadataLines([metadataDescLine, dataRowMetadataLine]);
        end

        %% StartNewDataFile
        function StartNewDataFile(this, dataWriter, headers, extraMetadataLines)
           
            %This will increment the number of the filename etc
            dataWriter.ValidateFilePath();

            %Write the data row of all instruments/diagnostics at the start
            %of the sweep, for things like temperature, time
            dataRowMetadataLine = this.CreateDataRowHeaderString();

            %Write the metadata string for this instrument - frequencies,
            %voltages, settings etc
            metadataDescLine = this.Instrument.FullName + " Scan - Measurement data at Scan Start:";
            metadataLine = this.Instrument.GrabMetadataString();
                        
            %Write to file
            dataWriter.WriteHeaders(headers, "MetadataLines", [metadataDescLine, dataRowMetadataLine, metadataLine, extraMetadataLines]);
        end

    end
end

