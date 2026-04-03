classdef DataWriter < handle
    %DATAWRITER - Handles the writing of data files in Palladium DAQ

    properties
        FileWriteDetails;
        FileInfo = "<<< Palladium DAQ data file 3.0 >>>";
    end

    properties (Constant)
        END_METADATA_LINES_STRING = "<<< END METADATA LINES >>>";
    end

    methods
        %% Constructor
        function this = DataWriter(fileWriteDetails)
            this.FileWriteDetails = fileWriteDetails;

            this.ConstructPath();
        end

        %% ConstructPath
        function ConstructPath(this)
            this.FileWriteDetails.FilePath = fullfile(string(this.FileWriteDetails.Directory), string(this.FileWriteDetails.FileName) + string(this.FileWriteDetails.FileExtension));
        end

        %% InsertMetadataLines
        function InsertMetadataLines(this, stringLinesArray)
            %Use at end of file writing, to insert an extra line of
            %metadata into the header section of the file - inserts a new
            %line before <<< END METADATA LINES >>>. stringLinesArray can
            %be a singel string or an array of them (multilines) like
            %["Walker", "747", "Holly"]
            arguments
                this;
                stringLinesArray {mustBeText};
            end

            try
                %This is the way to insert a line (??) - open the file,
                %turn to a string array, then write those one by one, with
                %the new one inserted into that array
                fid = fopen(this.FileWriteDetails.FilePath);
                scan = textscan(fid, '%s', 'Delimiter', '\n', 'CollectOutput', true);
                lines = scan{1};
                fclose(fid);

                %Find which line is the END METADATA line
                mask = strcmp(lines, Palladium.DataWriting.DataWriter.END_METADATA_LINES_STRING);
                endLineIdx = find(mask);

                %Error checking
                if isempty(endLineIdx)
                    warning("Could not find end-of-metadata string in file");   %Don't throw full error and prevent file writing entirely
                else
                    %Check how many lines to insert
                    linesToInsert = length(stringLinesArray);


                    %Same file path - shoudl overwrite
                    fid = fopen(this.FileWriteDetails.FilePath, 'w');

                    %Print the lines before the one to be inserted
                    for i = 1 : endLineIdx - 1
                        fprintf(fid, '%s\n', lines{i});
                    end

                    %Print the new line(s)
                    for i = 1 : linesToInsert
                        fprintf( fid, '%s\n', stringLinesArray(i));
                    end

                    %Print the lines after
                    for i = endLineIdx : length(lines)
                        fprintf(fid, '%s\n', lines{i});
                    end
                end

                %Close the file
                fclose(fid);

            catch err
                warning("Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying...");
                errMess = string(err.message);
                warning(errMess);
                Palladium.Logging.Logger.Log("Info", "Writing of file to " + this.FileWriteDetails.FilePath + " failed." + " Error message: " + errMess);
            end
        end

        %% SaveFigure
        function SaveFigure(~, figure, ax, directory, fileNameWithoutExtension)
            try
                %Add a title to the plot, if the axes don't already have
                %one
                if isempty(ax.Title.String)
                    title(strrep(fileNameWithoutExtension, '_', ' '));
                else
                    if iscell(ax.Title.String)
                        fileNameWithoutExtension = ax.Title.String{1};
                    else
                        fileNameWithoutExtension = string(ax.Title.String);
                    end
                end

                %Add '-Fig' to the filename, and then any needed 00x
                %numbers to prevent file overwriting if multiple figures
                %were saved on this same filename
                fileNameWithoutExtension = Palladium.Utilities.PathUtils.GetIncrementedFileName(fullfile(string(directory), string(fileNameWithoutExtension)) + "-Fig.fig");

                %Save a .fig and a .png
                saveas(figure, fullfile(directory, fileNameWithoutExtension + ".fig"));
                saveas(figure, fullfile(directory, fileNameWithoutExtension + ".png"));
            catch e
                error("Error saving figure in DataWriter" + string(e.message));
            end
        end

        %% ValidateFilePath
        function newFileName = ValidateFilePath(this)
            newFileName = this.FileWriteDetails.FileName;
            if(this.FileWriteDetails.SaveFile)
                switch(string(this.FileWriteDetails.WriteMode))
                    case("Increment File No.")
                        newFileName = Palladium.Utilities.PathUtils.GetIncrementedFileName(fullfile(string(this.FileWriteDetails.Directory), string(newFileName)) + string(this.FileWriteDetails.FileExtension));
                    case("Overwrite File")
                        if(exist(newFileName, 'file') == 2)  %If file exists already
                            delete(newFileName);    %delete the existing file, then carry on as if it neever existed!
                        end
                    case("Append To File")
                        %No action needed
                    otherwise
                        error("Unsupported file write option: " + string(this.FileWriteDetails.WriteMode));
                end
            end

            this.FileWriteDetails.FileName = newFileName;
            this.ConstructPath();
        end

        %% WriteHeaders
        function WriteHeaders(this, headers, Settings)
            arguments
                this;
                headers;
                Settings.MetadataLines = [];
            end

            %If the file exists and AppendToFile is true, we do not need to
            %write headers, return
            if ((exist(this.FileWriteDetails.FilePath, 'file') == 2) && strcmp(this.FileWriteDetails.WriteMode, 'Append To File'))
                return;
            end

            %Otherwise, write away
            fid = fopen(this.FileWriteDetails.FilePath, 'w');
            fprintf(fid, '%s\r\n', this.FileInfo);
            fprintf(fid, '%s\r\n', this.FileWriteDetails.DescriptionText);
            fprintf(fid, '%s\r\n', "");
            fprintf(fid, '%s\r\n', "<Instrument Settings and Metadata>");

            if ~isempty(Settings.MetadataLines)
                for i = 1 : length(Settings.MetadataLines)
                    str = Settings.MetadataLines(i);

                    if ismissing(str)
                        fprintf(fid, '%s\r\n', "");
                    else
                        fprintf(fid, '%s\r\n', str);
                    end
                end
            end

            fprintf(fid, '%s\r\n', Palladium.DataWriting.DataWriter.END_METADATA_LINES_STRING);
            fprintf(fid, '%s\r\n', "");
            fprintf(fid, '%s\r\n', headers);
            fclose(fid);
        end

         %% WriteData
         function WriteData(this, data)
             %Write multiple lines of data in a matrix all in one go
             %Right now this is actually identical to WriteLine...
             numRetries = 3; %Have seen in testing that (due to copying across of files?) we can get 'Permission denied' errors on the data file. These are infrequent. If we get them, just pause a short time, try writing again, and return if we fail after this many attempts
             errMess = [];

             for i = 1 : numRetries
                 try
                     writematrix(data, this.FileWriteDetails.FilePath, 'WriteMode', 'append', 'delimiter', '\t');
                     return;
                 catch err
                     warning("Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying...");
                     errMess = string(err.message);
                     warning(errMess);
                     Palladium.Logging.Logger.Log("Info", "Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying..." + " Error message: " + errMess);
                 end
             end

             %If we got here, we tried N times to write to the file and it
             %didn't work - warn
             Palladium.Logging.Logger.Log("Warning", "Writing of file to " + this.FileWriteDetails.FilePath + " failed after " + num2str(numRetries) + " attempts. Data have been lost." + " Last error: " + errMess);
         end

        %% WriteLine
        function WriteLine(this, data)
            numRetries = 3; %Have seen in testing that (due to copying across of files?) we can get 'Permission denied' errors on the data file. These are infrequent. If we get them, just pause a short time, try writing again, and return if we fail after this many attempts
            errMess = [];

            for i = 1 : numRetries
                try
                    writematrix(data, this.FileWriteDetails.FilePath, 'WriteMode', 'append', 'delimiter', '\t');
                    return;
                catch err
                    warning("Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying...");
                    errMess = string(err.message);
                    warning(errMess);
                    Palladium.Logging.Logger.Log("Info", "Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying..." + " Error message: " + errMess);
                end
            end

            %If we got here, we tried N times to write to the file and it
            %didn't work - warn
            Palladium.Logging.Logger.Log("Warning", "Writing of file to " + this.FileWriteDetails.FilePath + " failed after " + num2str(numRetries) + " attempts. Data have been lost." + " Last error: " + errMess);
        end
    end

    methods (Static)

        %% BuildMetadataLineStringFromStruct
        function stringLine = BuildMetadataLineStringFromStruct(initialString, strct)
            %Take a struct of parameters and turn into a nicely formatted
            %single line of text that can be written to file as
            %human-readable metadata
            stringLine = initialString;

            %Get the field names of the struct
            flds = fields(strct);

            %Unpack each property/field into a string, append it
            for i = 1 : length(flds)
                f = flds{i};
                prop = strct.(f);

                propValAsStr = string(prop);

                if isempty(propValAsStr)
                    propValAsStr = "[]";
                end

                if length(propValAsStr) > 1
                    propValAsStr = strjoin(propValAsStr);
                end

                stringLine = stringLine + string(f) + " = " + string(propValAsStr);

                %Add a seperator if this is not the last property
                if i ~= length(flds)
                    stringLine = stringLine + " || ";
                end
            end
        end

        %% BuildMetadataLineStringFromHeaderValuePair
        function stringLine = BuildMetadataLineStringFromHeaderValuePair(initialString, headerRow, dataRow)
            %Take a row of header strings and a row of data, and make into
            %a nicely formatted string to log as a metadata line
            stringLine = initialString;

            %Error checking
            if isempty(dataRow)
                warning("Data row empty in BuildMetadataLineStringFromHeaderValuePair, cannot log to file");
                return;
            end
            if isempty(headerRow)
                warning("Data row empty in BuildMetadataLineStringFromHeaderValuePair, cannot log to file");
                return;
            end
            assert(length(dataRow) == length(headerRow), "Header and data row length not equal");

            %Unpack each property/field into a string, append it
            for i = 1 : length(headerRow)
                h = headerRow{i};
                prop = dataRow(i);

                stringLine = stringLine + string(h) + " = " + string(prop);

                %Add a seperator if this is not the last property
                if i ~= length(headerRow)
                    stringLine = stringLine + " || ";
                end
            end
        end
    end
end

