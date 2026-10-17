classdef DataReader < handle
    %DataReader - Reads Palladium DAQ data files back: their metadata, column headers and data.
    %Reads the files `DataWriter` writes; the DataViewer uses it.
    %`ReadFile` reads a whole file, and `ReadHeadersFromFile` just the
    %metadata and headers, which is quicker for a large file.

    %% Constructor
    methods
        function this = DataReader()
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [headerMetadataLines, headers, dataArray] = ReadFile(this, filePath)
            %Read a whole data file: its metadata lines, column headers and data.
            %
            %Inputs:
            %   filePath - the data file
            %
            %Outputs:
            %   headerMetadataLines - the lines before the end-of-metadata marker (string array)
            %   headers             - the column headers (string array)
            %   dataArray           - the data (double matrix, one column per header)

            % Open the text file and read the headers
            [headers, headerMetadataLines, numTotalHeaderLines] = this.ReadHeadersFromFile(filePath);

            %Now read the data, which should be the rest of the file
            dataArray = Palladium.DataWriting.DataReader.ReadDataArray(filePath, numTotalHeaderLines);
        end

        function [headers, headerMetadataLines, numTotalHeaderLines] = ReadHeadersFromFile(~, filePath)
            %Read a data file's metadata lines and column headers, but not its data - quicker for a large file.
            %Errors if the file can't be opened, has no end-of-metadata
            %marker, or its headers line is empty or numeric
            %
            %Inputs:
            %   filePath - the data file
            %
            %Outputs:
            %   headers             - the column headers (string array)
            %   headerMetadataLines - the lines before the end-of-metadata marker (string array)
            %   numTotalHeaderLines - the number of lines before the data

            % Open the text file.
            fileID = fopen(filePath, 'r');
            if fileID == -1
                error('DataReader:OpenFileFailure','Failed to open data file');
            end

            %Close the file on leaving this function however that happens -
            %the checks below throw errors for malformed files, which would
            %otherwise leave it open (and locked on Windows)
            closeFile = onCleanup(@() fclose(fileID));

            %Read metadata (and work out how many lines it was so we know
            %where to read the Headers Row)
            endOfMetadataTextLine = Palladium.DataWriting.DataWriter.END_METADATA_LINES_STRING;
            [numMetadataLines, headerMetadataLines] = Palladium.DataWriting.DataReader.ScanFileForMetadataRows(fileID, endOfMetadataTextLine);
            numTotalHeaderLines = numMetadataLines + 2;

            %Read one line - there is a space between metadata and
            %headers
            fgetl(fileID);

            %Read the Headers
            [headers] = Palladium.DataWriting.DataReader.ReadHeadersLine(fileID);
        end

    end

    %% Methods (Static, Private)
    methods (Static, Access = {?Palladium.DataWriting.DataReader, ?matlab.unittest.TestCase})    %Permission is Private, but also allow unit tests to see it

        function [dataArray] = ReadDataArray(filePath, numHeaderLines)
            %Read the data rows of a file, after the given number of header lines.
            %The delimiter is given explicitly (DataWriter always writes
            %tab-delimited files) - left to auto-detection, readmatrix can
            %fail on files with only a few data rows or with NaN/Inf in the
            %first row, silently returning a column of NaN

            dataArray = readmatrix(filePath, 'FileType', 'text', 'NumHeaderLines', numHeaderLines, 'Delimiter', '\t', 'OutputType', 'double');
        end

        function [headersStrArray] = ReadHeadersLine(fileID)
            %Read the next line of an open file as the tab-separated column headers.
            %Empty fields are skipped. Errors if a header is a number
            %(probably a data row, from a file with no headers), or there are
            %none - including when the file has ended

            %Read one line. At the end of the file fgetl gives -1, not text -
            %say so clearly, rather than failing in strsplit
            line = fgetl(fileID);
            if ~ischar(line)
                error('DataReader:NoHeaderString', "No headers row - the file ends before it");
            end

            headersStrArray = [];

            %Split into the headers
            cellArray = strsplit(line, "\t");
            for i = 1 : length(cellArray)
                if ~isempty(cellArray{i})
                    % Check that header line is not purely numeric
                    % (probably first line of data due to missing headers)
                    assert(isnan(str2double(cellArray{i})), 'DataReader:NumericHeaderString', "Numeric data in headers row");
                    headersStrArray = [headersStrArray string(cellArray{i})]; %#ok<AGROW>
                end
            end

            % Error checking - that header is not missing
            assert(~isempty(headersStrArray), 'DataReader:NoHeaderString', "Headers row loaded from file empty");
        end

        function [RowNo, metadataStrArray] = ScanFileForMetadataRows(fileID, endOfMetadataTextLine)
            %Read an open file line by line up to the end-of-metadata marker, returning the lines before it.
            %There can be any number of metadata lines before the headers.
            %Errors if the marker isn't found
            %
            %Outputs:
            %   RowNo            - the marker's line number
            %   metadataStrArray - the lines before it (string array)

            RowNo = 1;
            metadataStrArray = [];
            success = false;

            %Read one line
            line = fgetl(fileID);

            %Keep looping until we reach end of file,
            while(ischar(line))

                %Compare the newly-read line to the <<END METADATA>> line expected, break if they match
                if(strcmp(string(line), endOfMetadataTextLine))
                    success = true;
                    break;
                else
                    metadataStrArray = [metadataStrArray string(line)]; %#ok<AGROW>
                end

                %Increment row number
                RowNo = RowNo + 1;

                %Read one line
                line = fgetl(fileID);
            end

            %Handle the case where we never found the header string and
            %reached end of file
            if(~success)
                error('DataReader:NoMetadataMarker','Could not find headers in datafile');
            end
        end
    end

end
