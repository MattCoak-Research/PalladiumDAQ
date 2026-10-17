classdef DataWriter < handle
    %DataWriter - Writes Palladium DAQ's tab-separated data files: a metadata header, the column headers, then the data.
    %The Controller makes one for the main data file when measurements
    %start, and Instrument Controls make their own for sweep and scan
    %files (`InstrumentControlBase.InitialiseDataWriter`). The file
    %settings come from a FileWriteDetails struct, as set in the GUI's file
    %panel. `ValidateFilePath` picks the file name for the write mode,
    %`WriteHeaders` starts the file, and `WriteLine` or `WriteData` add
    %data. A file looks like:
    %
    %    <<< Palladium DAQ data file 3.0 >>>
    %    Description text
    %
    %    <Instrument Settings and Metadata>
    %    ...metadata lines...
    %    <<< END METADATA LINES >>>
    %
    %    Time (mins)    Field (T)    ...
    %    0.1            2.5          ...
    %
    %Nothing is written when FileWriteDetails.SaveFile is false.
    %`DataReader` reads the files back. See [Data files](../data-files.md).

    %% Properties (Constant, Public)
    properties (Constant, Access = public)
        END_METADATA_LINES_STRING = "<<< END METADATA LINES >>>";   %Line marking the end of the metadata, just before the column headers
    end

    %% Properties (Constant, Private)
    properties (Constant, Access = {?Palladium.DataWriting.DataWriter, ?matlab.unittest.TestCase})    %Permission is Private, but also allow unit tests to see it
        WriteAttempts = 3;          %Times to try writing data before giving up
        WriteRetryPause = 0.2;      %Seconds to wait between attempts, for a file that is briefly locked
    end

    %% Properties (Public)
    properties (Access = public)
        FileWriteDetails;                                   %File settings struct: Directory, FileName, FileExtension, DescriptionText, WriteMode, SaveFile, and FilePath (set from the others)
        FileInfo = "<<< Palladium DAQ data file 3.0 >>>";   %First line of every file, identifying the file format
    end

    %% Constructor
    methods
        function this = DataWriter(fileWriteDetails)
            %Create a writer for the file described by a FileWriteDetails struct, setting its FilePath.
            %
            %Inputs:
            %   fileWriteDetails - struct with Directory, FileName,
            %                      FileExtension, DescriptionText,
            %                      WriteMode ("Increment File No.",
            %                      "Overwrite File" or "Append To File")
            %                      and SaveFile

            this.FileWriteDetails = fileWriteDetails;

            this.ConstructPath();
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function InsertMetadataLines(this, stringLinesArray)
            %Add lines to the end of the metadata section of a file already written, e.g. a sweep's end time.
            %Rewrites the file with the new lines just before
            %`<<< END METADATA LINES >>>`. Warns (and leaves the file as it
            %is) if that marker isn't found
            %
            %Inputs:
            %   stringLinesArray - the line, or lines as a string array, e.g. ["Ended at 10:31", "Final field = 2 T"]

            arguments
                this;
                stringLinesArray {mustBeText};
            end

            %Nothing to write if saving is switched off (Write to File unticked)
            if ~this.FileWriteDetails.SaveFile
                return;
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

                    %Same file path - should overwrite
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

        function SaveFigure(~, figure, ax, directory, fileNameWithoutExtension, Settings)
            %Save a figure as both a .fig and a .png in a folder.
            %Untitled axes are given the file name as their title.
            %Otherwise, unless ExactFileName is true, the files are named
            %after the axes' title (with any characters not allowed in file
            %names replaced by "-"), with "-Fig" and a number added so that
            %nothing is overwritten
            %
            %Inputs:
            %   figure, ax, directory, fileNameWithoutExtension - see the arguments block
            %   ExactFileName - (name-value) true to use exactly the name given. Default false

            arguments
                ~;
                figure;                         %Figure to save
                ax;                             %Its axes - titled from the file name if untitled
                directory;                      %Folder to save in
                fileNameWithoutExtension;       %File name, without extension
                Settings.ExactFileName (1,1) logical = false;   %True to save with exactly this name (e.g. one chosen in a Save As dialog). False: name after the axes' title if they have one, and add -Fig and a number so nothing is overwritten
            end

            try
                %Add a title to the plot, if the axes don't already have
                %one
                if isempty(ax.Title.String)
                    title(ax, strrep(fileNameWithoutExtension, '_', ' '));
                elseif ~Settings.ExactFileName
                    if iscell(ax.Title.String)
                        titleText = string(ax.Title.String{1});
                    else
                        titleText = string(ax.Title.String);
                    end

                    %A title can hold characters a file name can't (e.g.
                    %"Field / Temperature") - replace them, and keep the
                    %name given if nothing usable is left
                    titleName = strtrim(regexprep(titleText(1), '[\\/:*?"<>|\x00-\x1F]', '-'));
                    if strlength(titleName) > 0
                        fileNameWithoutExtension = titleName;
                    end
                end

                %Add '-Fig' to the filename, and then any needed -0000x
                %numbers to prevent file overwriting if multiple figures
                %were saved on this same filename
                if ~Settings.ExactFileName
                    fileNameWithoutExtension = Palladium.Utilities.PathUtils.GetIncrementedFileName(fullfile(string(directory), string(fileNameWithoutExtension)) + "-Fig.fig");
                end

                %Save a .fig and a .png
                saveas(figure, fullfile(directory, fileNameWithoutExtension + ".fig"));
                saveas(figure, fullfile(directory, fileNameWithoutExtension + ".png"));
            catch e
                error("SaveFigureError:SaveFailed", "%s", "Error saving figure in DataWriter: " + string(e.message));
            end
        end

        function newFileName = ValidateFilePath(this)
            %Choose the file name to write to, for the write mode, and update FileName and FilePath.
            %For "Increment File No." the name is numbered so that no file
            %is overwritten (see `PathUtils.GetIncrementedFileName`).
            %"Overwrite File" and "Append To File" keep the name. Nothing
            %is deleted here - this also runs whenever the file settings are
            %edited in the GUI
            %
            %Outputs:
            %   newFileName - the file name, without folder or extension

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
            %Start the file: write the file-format line, description, metadata lines and column headers.
            %Replaces any existing file - except in "Append To File" mode,
            %where an existing file is added to and nothing is written here.
            %Errors (WriteHeadersError:OpenFailed) if the file can't be created
            %
            %Inputs:
            %   headers       - the column headers, as one tab-separated line
            %   MetadataLines - (name-value) lines of instrument settings and
            %                   metadata (string array). Default []

            arguments
                this;
                headers;
                Settings.MetadataLines = [];
            end

            %Nothing to write if saving is switched off (Write to File unticked)
            if ~this.FileWriteDetails.SaveFile
                return;
            end

            %If the file exists and AppendToFile is true, we do not need to
            %write headers, return
            if ((exist(this.FileWriteDetails.FilePath, 'file') == 2) && strcmp(this.FileWriteDetails.WriteMode, 'Append To File'))
                return;
            end

            %Otherwise, write away. Say clearly if the file can't be
            %created (e.g. the folder is missing or read-only), rather than
            %failing on the first write with "Invalid file identifier"
            [fid, openMessage] = fopen(this.FileWriteDetails.FilePath, 'w');
            if fid == -1
                error("WriteHeadersError:OpenFailed", "%s", "Could not create the data file " + string(this.FileWriteDetails.FilePath) + ": " + string(openMessage));
            end
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
            %Add several rows of data to the file at once, e.g. a whole sweep - tab-separated.
            %Retries a few times if the file can't be written (e.g. it is
            %briefly locked), then logs a warning that the data were lost
            %
            %Inputs:
            %   data - the rows (numeric matrix)

            this.AppendRows(data, "WriteDataWarning");
        end

        function WriteLine(this, data)
            %Add one row of data to the file - tab-separated.
            %Retries a few times if the file can't be written (e.g. it is
            %briefly locked), then logs a warning that the data were lost
            %
            %Inputs:
            %   data - the row (numeric row vector)

            this.AppendRows(data, "WriteLineWarning");
        end
    end

    %% Methods (Private)
    methods (Access = {?Palladium.DataWriting.DataWriter, ?matlab.unittest.TestCase})    %Permission is Private, but also allow unit tests to see it

        function ConstructPath(this)
            %Set FileWriteDetails.FilePath from its Directory, FileName and FileExtension.

            this.FileWriteDetails.FilePath = fullfile(string(this.FileWriteDetails.Directory), string(this.FileWriteDetails.FileName) + string(this.FileWriteDetails.FileExtension));
        end

        function AppendRows(this, data, warningIdPrefix)
            %Append rows of data to the file, tab-separated, retrying if the write fails - for WriteData and WriteLine.
            %
            %Inputs:
            %   data            - the rows (numeric)
            %   warningIdPrefix - start of the warning IDs, e.g. "WriteLineWarning"

            %Nothing to write if saving is switched off (Write to File unticked)
            if ~this.FileWriteDetails.SaveFile
                return;
            end

            %Have seen in testing that (due to copying across of files?) we
            %can get 'Permission denied' errors on the data file. These are
            %infrequent. If we get them, pause a short time, try writing
            %again, and give up after WriteAttempts attempts
            numRetries = Palladium.DataWriting.DataWriter.WriteAttempts;
            errMess = [];

            for i = 1 : numRetries
                try
                    writematrix(data, this.FileWriteDetails.FilePath, 'WriteMode', 'append', 'delimiter', '\t');
                    return;
                catch err
                    warning(warningIdPrefix + ":WriteFailed", "%s", "Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying...");
                    errMess = string(err.message);
                    warning(warningIdPrefix + ":WriteErrorMessage", "%s", errMess);
                    Palladium.Logging.Logger.Log("Info", "Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying..." + " Error message: " + errMess);

                    %Give a briefly locked file time to be released (the
                    %attempts used to follow each other at once)
                    if i < numRetries
                        pause(Palladium.DataWriting.DataWriter.WriteRetryPause);
                    end
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
            %Turn a struct of settings into one metadata line, e.g. "K2000_1: Range = 10 || NPLC = 1".
            %Numbers are written with all their digits (see
            %FormatMetadataValue); arrays are joined with spaces, and an
            %empty value is written as "[]"
            %
            %Inputs:
            %   initialString - text to start the line with, e.g. the instrument's name
            %   strct         - the settings
            %
            %Outputs:
            %   stringLine - the line

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

                %Add a separator if this is not the last property
                if i ~= length(flds)
                    stringLine = stringLine + " || ";
                end
            end
        end

        function stringLine = BuildMetadataLineStringFromHeaderValuePair(initialString, headerRow, dataRow)
            %Turn column headers and a row of values into one metadata line, e.g. "Start: Field (T) = 2.5 || ...".
            %Used to record the latest measurements in a sweep file's
            %metadata. Warns and gives just initialString if either row is
            %empty; errors if they differ in length
            %
            %Inputs:
            %   initialString - text to start the line with
            %   headerRow     - the column headers (cell array)
            %   dataRow       - the values, one per header
            %
            %Outputs:
            %   stringLine - the line

            stringLine = initialString;

            %Error checking
            if isempty(dataRow)
                warning("BuildMetadataLineStringFromHeaderValuePairWarning:EmptyDataRow", "Data row empty in BuildMetadataLineStringFromHeaderValuePair, cannot log to file");
                return;
            end
            if isempty(headerRow)
                warning("BuildMetadataLineStringFromHeaderValuePairWarning:EmptyHeaderRow", "Header row empty in BuildMetadataLineStringFromHeaderValuePair, cannot log to file");
                return;
            end
            assert(length(dataRow) == length(headerRow), "BuildMetadataLineStringFromHeaderValuePairError:LengthMismatch", "Header and data row length not equal");

            %Unpack each property/field into a string, append it
            for i = 1 : length(headerRow)
                h = headerRow{i};
                prop = dataRow(i);

                stringLine = stringLine + string(h) + " = " + Palladium.DataWriting.DataWriter.FormatMetadataValue(prop);

                %Add a separator if this is not the last property
                if i ~= length(headerRow)
                    stringLine = stringLine + " || ";
                end
            end
        end
    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function str = FormatMetadataValue(value)
            %Convert a value to text for a metadata line, keeping every digit of floating point numbers.
            %Floating point numbers are written with as many digits as it
            %takes to read back as exactly the same number (string() would
            %keep only 5 significant digits, and turns NaN into a missing
            %string, which would blank the whole line). Everything else is
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
            %The shortest text that reads back as exactly x, trying 15 to 17 significant digits (6 to 9 for single precision).

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
