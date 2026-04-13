classdef DataReader < handle
    %DATAREADER - Handles the reading of data files in Palladium

    %% Constructor
    methods
        function this = DataReader()
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function [headerMetadataLines, headers, dataArray] = ReadFile(this, filePath)
            % READFILE - Read and parse a delimited data file into components
            %
            % Input arguments:
            % ~        - unused object handle (method of a class) - this
            % whole class could right now be made static, but leaving it as a
            % shell with no actual properties for now, as data loading might
            % require more functionality in the future.
            % filePath - path to the input data file (string)
            %
            % Output arguments:
            % headerMetadataLines - cell array of header/metadata lines
            % dataColNames        - cell array of column names from header
            % dataArray           - numeric or cell array of parsed data

            % Open the text file and read the headers
            [headers, headerMetadataLines, numTotalHeaderLines] = this.ReadHeadersFromFile(filePath);

            %Now read the data, which should be the rest of the file
            dataArray = Palladium.DataWriting.DataReader.ReadDataArray(filePath, numTotalHeaderLines);
        end

        function [headers, headerMetadataLines, numTotalHeaderLines] = ReadHeadersFromFile(~, filePath)
            % READHEADERSFROMFILE - Read just the headers line from a file,
            % not the data (for speed). Scans down a standard Palladium
            % file until it finds the end of the initial metadata and the
            % start of the headers. Splits and returns that line
            %
            % Input arguments:
            % ~        - unused object handle (method of a class) - this
            % whole class could right now be made static, but leaving it as a
            % shell with no actual properties for now, as data loading might
            % require more functionality in the future.
            % filePath - path to the input data file (string)
            %
            % Output arguments:
            % headerMetadataLines - cell array of header/metadata lines
            % dataColNames        - cell array of column names from header
           
            % Open the text file.
            fileID = fopen(filePath, 'r');
            if fileID == -1
                error('DataReader:OpenFileFailure','Failed to open data file');
            end

            %Read metadata (and work out how many lines it was so we know
            %where to read the Headers Row)
            endOfMetadataTextLine = "<<< END METADATA LINES >>>";
            [numMetadataLines, headerMetadataLines] = Palladium.DataWriting.DataReader.ScanFileForMetadataRows(fileID, endOfMetadataTextLine);
            numTotalHeaderLines = numMetadataLines + 2;

            %Read one line - there is a space between metadata and
            %headers
            fgetl(fileID);

            %Read the Headers
            [headers] = Palladium.DataWriting.DataReader.ReadHeadersLine(fileID);

            % Close the text file.
            fclose(fileID);
        end

    end

    %% Methods (Static)
    methods (Access = public, Static)

        function [dataArray] = ReadDataArray(filePath, numHeaderLines)
            %Read the data
            dataArray = readmatrix(filePath, 'FileType', 'text', 'NumHeaderLines', numHeaderLines, 'OutputType', 'double');
        end

        function [headersStrArray] = ReadHeadersLine(fileID)

            %Read one line
            line = fgetl(fileID);

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
            %There can be a varying number of metadata lines before the headers and then data: scan
            %the file line by line until the first item matches the string 'endOfMetadataTextLine' -
            %then we know we've found the headers row (there is an empty

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
                    %Return this line as a cell array
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

