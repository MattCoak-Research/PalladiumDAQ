classdef DataWriter < handle
    %DATAWRITER - Handles the writing of data files in Palladium DAQ

    %% Properties (Constant, Public)
    properties (Constant, Access = public)
        END_METADATA_LINES_STRING = "<<< END METADATA LINES >>>";
    end

    %% Properties (Public)
    properties (Access = public)
        FileWriteDetails;
        FileInfo = "<<< Palladium DAQ data file 3.0 >>>";
    end


    %% Constructor
    methods
        function this = DataWriter(fileWriteDetails)
            this.FileWriteDetails = fileWriteDetails;

            this.ConstructPath();
        end
    end

    %% Methods (Public)
    methods (Access = public)
        function ConstructPath(this)
            this.FileWriteDetails.FilePath = fullfile(string(this.FileWriteDetails.Directory), string(this.FileWriteDetails.FileName) + string(this.FileWriteDetails.FileExtension));
        end

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
                    warning("InsertMetadataLinesWarning:MetadataMarkerNotFound", "Could not find end-of-metadata string in file");   %Don't throw full error and prevent file writing entirely
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
                warning("InsertMetadataLinesWarning:WriteFailed", "%s", "Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying...");
                errMess = string(err.message);
                warning("InsertMetadataLinesWarning:WriteErrorMessage", "%s", errMess);
                Palladium.Logging.Logger.Log("Info", "Writing of file to " + this.FileWriteDetails.FilePath + " failed." + " Error message: " + errMess);
            end
        end

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

                %Add '-Fig' to the filename, and then any needed -0000x
                %numbers to prevent file overwriting if multiple figures
                %were saved on this same filename
                fileNameWithoutExtension = Palladium.Utilities.PathUtils.GetIncrementedFileName(fullfile(string(directory), string(fileNameWithoutExtension)) + "-Fig.fig");

                %Save a .fig and a .png
                saveas(figure, fullfile(directory, fileNameWithoutExtension + ".fig"));
                saveas(figure, fullfile(directory, fileNameWithoutExtension + ".png"));
            catch e
                error("SaveFigureError:SaveFailed", "%s", "Error saving figure in DataWriter" + string(e.message));
            end
        end

        function newFileName = ValidateFilePath(this)
            newFileName = this.FileWriteDetails.FileName;
            if(this.FileWriteDetails.SaveFile)
                switch(string(this.FileWriteDetails.WriteMode))
                    case("Increment File No.")
                        newFileName = Palladium.Utilities.PathUtils.GetIncrementedFileName(fullfile(string(this.FileWriteDetails.Directory), string(newFileName)) + string(this.FileWriteDetails.FileExtension));
                    case("Overwrite File")
                        %No action needed: an existing file is replaced when
                        %WriteHeaders opens it for writing. This must NOT
                        %delete anything - ValidateFilePath runs whenever the
                        %file settings are edited in the GUI, and before the
                        %instruments have connected, not just when
                        %measurements actually start
                    case("Append To File")
                        %No action needed
                    otherwise
                        error("ValidateFilePathError:UnsupportedWriteMode", "%s", "Unsupported file write option: " + string(this.FileWriteDetails.WriteMode));
                end
            end

            this.FileWriteDetails.FileName = newFileName;
            this.ConstructPath();
        end

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
                    warning("WriteDataWarning:WriteFailed", "%s", "Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying...");
                    errMess = string(err.message);
                    warning("WriteDataWarning:WriteErrorMessage", "%s", errMess);
                    Palladium.Logging.Logger.Log("Info", "Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying..." + " Error message: " + errMess);
                end
            end

            %If we got here, we tried N times to write to the file and it
            %didn't work - warn
            Palladium.Logging.Logger.Log("Warning", "Writing of file to " + this.FileWriteDetails.FilePath + " failed after " + num2str(numRetries) + " attempts. Data have been lost." + " Last error: " + errMess);
        end

        function WriteLine(this, data)
            numRetries = 3; %Have seen in testing that (due to copying across of files?) we can get 'Permission denied' errors on the data file. These are infrequent. If we get them, just pause a short time, try writing again, and return if we fail after this many attempts
            errMess = [];

            for i = 1 : numRetries
                try
                    writematrix(data, this.FileWriteDetails.FilePath, 'WriteMode', 'append', 'delimiter', '\t');
                    return;
                catch err
                    warning("WriteLineWarning:WriteFailed", "%s", "Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying...");
                    errMess = string(err.message);
                    warning("WriteLineWarning:WriteErrorMessage", "%s", errMess);
                    Palladium.Logging.Logger.Log("Info", "Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying..." + " Error message: " + errMess);
                end
            end

            %If we got here, we tried N times to write to the file and it
            %didn't work - warn
            Palladium.Logging.Logger.Log("Warning", "Writing of file to " + this.FileWriteDetails.FilePath + " failed after " + num2str(numRetries) + " attempts. Data have been lost." + " Last error: " + errMess);
        end
    end

    %% Methods (Static, Public)
    methods (Static, Access = public)

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

                propValAsStr = Palladium.DataWriting.DataWriter.FormatMetadataValue(prop);

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

        function stringLine = BuildMetadataLineStringFromHeaderValuePair(initialString, headerRow, dataRow)
            %Take a row of header strings and a row of data, and make into
            %a nicely formatted string to log as a metadata line
            stringLine = initialString;

            %Error checking
            if isempty(dataRow)
                warning("BuildMetadataLineStringFromHeaderValuePairWarning:EmptyDataRow", "Data row empty in BuildMetadataLineStringFromHeaderValuePair, cannot log to file");
                return;
            end
            if isempty(headerRow)
                warning("BuildMetadataLineStringFromHeaderValuePairWarning:EmptyDataRow", "Data row empty in BuildMetadataLineStringFromHeaderValuePair, cannot log to file");
                return;
            end
            assert(length(dataRow) == length(headerRow), "BuildMetadataLineStringFromHeaderValuePairError:LengthMismatch", "Header and data row length not equal");

            %Unpack each property/field into a string, append it
            for i = 1 : length(headerRow)
                h = headerRow{i};
                prop = dataRow(i);

                stringLine = stringLine + string(h) + " = " + Palladium.DataWriting.DataWriter.FormatMetadataValue(prop);

                %Add a seperator if this is not the last property
                if i ~= length(headerRow)
                    stringLine = stringLine + " || ";
                end
            end
        end
    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function str = FormatMetadataValue(value)
            %Convert a value to text for a metadata line. Floating point
            %numbers are written with as many digits as it takes to read
            %back as exactly the same number (string() would keep only 5
            %significant digits, and turns NaN into a missing string,
            %which would blank the whole line). Everything else is
            %converted by string(), as before.
            if isfloat(value) && isreal(value) && ~isempty(value)
                str = strings(1, numel(value));
                for k = 1 : numel(value)
                    str(k) = Palladium.DataWriting.DataWriter.FormatFloatingPointNumber(value(k));
                end
            else
                str = string(value);
            end
        end

        function str = FormatFloatingPointNumber(x)
            %The shortest text that reads back as exactly x, trying 15 to 17
            %significant digits (6 to 9 for single precision)
            if ~isfinite(x)
                str = string(sprintf("%g", x));    %NaN, Inf or -Inf
                return;
            end

            if isa(x, "single")
                digitCounts = 6 : 9;
            else
                digitCounts = 15 : 17;
            end

            for digits = digitCounts
                candidate = sprintf("%.*g", digits, x);
                if cast(str2double(candidate), class(x)) == x
                    break;
                end
            end

            str = string(candidate);
        end

    end
end

