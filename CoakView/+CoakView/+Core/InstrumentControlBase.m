classdef InstrumentControlBase < handle
    %InstrumentControlBase - Base class for a Logic controller add-on object to be added on to an
    %Instrument object, eg LakeshoreHeaterControl.m
    
    properties
        ControlDetailsStruct;
        FileNamePropertyDelimiters = "[]";
        DecimalPointReplacementCharacter = "p";
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

        %% DataRowCollected
        function DataRowCollected(this, dataRow, headers)
            %Gets triggered every tick once the loop has collected the
            %entire dataRow from all instruments. Use to e.g. write sweep
            %data that includes columns from other instruments
        end

        %% GetName
        function name = GetName(this)
            name = this.ControlDetailsStruct.Name;
        end

        %% MeasurementsInitialised
        function MeasurementsInitialised(this, src, eventArgs)

        end

        %% MeasurementsStarted
        function MeasurementsStarted(this, src, eventArgs)
        
        end

        %% MeasurementsPaused
        function MeasurementsPaused(this, src, eventArgs)
        
        end
        
        %% MeasurementsResumed
        function MeasurementsResumed(this, src, eventArgs)
        
        end 
        
        %% MeasurementsStopped
        function MeasurementsStopped(this, src, eventArgs)
        
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

        %% GetParameterValueFromLastMeasurementRow
        function stringVal = GetParameterValueFromLastMeasurementRow(this, parameterName, Settings)
            %Grab a parameter - ie Temperature, Magnetic Field, to use to
            %e.g. automatically name a Sweep File when [Temperature (K)] is
            %given as part of it's file name.
            arguments
                this;
                parameterName {mustBeTextScalar};
                Settings.Format {mustBeTextScalar} = "%03.2f";
            end

            %Pull data and headers from Instrument. Note at least one
            %Update must have run prior to this, or it'll be unpopulated
            dataRow = this.Instrument.LastFullDataRow;
            hdrsRow = this.Instrument.FullHeadersRow;

            %Initialise to empty
            stringVal = "<VAL-MISSING>";

            %Error checking
            if isempty(dataRow)
                warning("Data row empty in " + this.Instrument.FullName + ", cannot GetParameterValueFromLastMeasurementRow");
                return;
            end
            if isempty(hdrsRow)
                warning("Data row empty in "  + this.Instrument.FullName + ", cannot GetParameterValueFromLastMeasurementRow");
                return;
            end

            %Check the provided Parameter Name is indeed one of the headers
            if ~any(contains(hdrsRow, parameterName))
                warning("Could not find parameter " + parameterName + " in the measurement headers file (InstrumentControlBase.GetParameterValueFromLastMeasurementRow).");
                return;
            end

            %Extract data
            idx = ismember(hdrsRow, parameterName);
            dat = dataRow(idx);
            stringVal = num2str(dat, Settings.Format);
        end

        %% InitialiseDataWriter
        function dataWriter = InitialiseDataWriter(this, fileNameSuffix)
            fileWriteDetails = this.Instrument.FileWriteDetails;
            fileWriteDetails.FileName = string(fileWriteDetails.FileName) + fileNameSuffix;
            fileWriteDetails.WriteMode = 'Increment File No.';
            fileWriteDetails.SaveFile = true;

            %Process the file name of e.g. a sweep. Make it a valid filename and do operations like: Grab a parameter - ie Temperature, Magnetic Field, to use to
            %e.g. automatically name a Sweep File when [Temperature (K)] - one of the data file headers - is
            %given as part of it's file name. Replaces . characeters with a
            %chosen replacement too
            fileWriteDetails.FileName = this.ProcessFileName(fileWriteDetails.FileName);

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

        %% ProcessFileName
        function fileNameOut = ProcessFileName(this, fileName, Settings)
            %Process the file name of e.g. a sweep. Make it a valid filename and do operations like: Grab a parameter - ie Temperature, Magnetic Field, to use to
            %e.g. automatically name a Sweep File when [Temperature (K)] is
            %given as part of it's file name.
            arguments
                this;
                fileName {mustBeTextScalar};
                Settings.DefaultFormat {mustBeTextScalar} = "%03.2f";
            end

            delims = char(this.FileNamePropertyDelimiters);
            assert(length(delims) == 2, "Delimeters string must be of 2 characters length");

            %This little snippet pulls out all text delimited by the
            %selected delimters (by Default [ ]) and returns a string array
            %of all the contents of those. ie "Sweep File [Temperature] at
            %field [Field] T" will return ["Temperature", "Field"]
            segments = extractBetween(fileName, delims(1), delims(2));

            fileNameOut = fileName;

            %If there are no segments to replace, we can just return
            if isempty(segments)
                return;
            end

            for i = 1 : length(segments)
                %Retrieve the corresponding property to this tag, as a
                %string

                %Expect (but do not demand) something formatted like
                %"Sample Temperature(K),%6f2" - ie the property, a comma
                %delimiter, and then the num2str format spec. If 
                splitSegs = strsplit(segments(i), ",");

                if length(splitSegs) == 1
                   format = Settings.DefaultFormat;
                elseif length(splitSegs) == 2
                    format = strtrim(splitSegs(2));
                else
                    error("Incorrect string format, epxect something like " + "Sample Temperature(K),%6f2" + " or " + "Sample Temperature(K)");
                end

                newSeg = this.GetParameterValueFromLastMeasurementRow(strtrim(splitSegs(1)), "Format", format);

                %Replace the "[Tag]" bit of the string with this segment.
                fileNameOut = replace(fileNameOut, segments(i), newSeg);
            end

            %Remove the delimeters too
            fileNameOut = replace(fileNameOut, delims(1), "");
            fileNameOut = replace(fileNameOut, delims(2), "");

            %Replace any decimal points with hyphens, as . messes up file
            %names
            fileNameOut = replace(fileNameOut, ".", this.DecimalPointReplacementCharacter);
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

