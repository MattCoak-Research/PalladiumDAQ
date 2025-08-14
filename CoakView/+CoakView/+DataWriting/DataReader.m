classdef DataReader < handle
    %DATAREADER - Handles the reading of data files in CoakView

    properties

    end

    methods
        %% Constructor
        function this = DataReader()
        end

        %% ReadFile
        function [headerMetadataLines, dataColNames, dataArray] = ReadFile(this, filePath)
            % Open the text file.
            fileID = fopen(filePath, 'r');

            %Read metadata (and work out how many lines it was so we know
            %where to read the Headers Row)
            endOfMetadataTextLine = "<<< END METADATA LINES >>>";
            [numMetadataLines, headerMetadataLines] = this.ScanFileForMetadataRows(fileID, endOfMetadataTextLine);

            %Read one line - there is a space between metadata and
            %headers
            fgetl(fileID);

            %Read the Headers
            [dataColNames] = this.ReadHeadersLine(fileID);

            % Close the text file.
            fclose(fileID);

            %Now read the data, which should be the rest of the file
            numTotalHeaderLines = numMetadataLines + 2;
            dataArray = this.ReadDataArray(filePath, numTotalHeaderLines);

        end
    end

    methods (Access = protected)

        %% ReadDataArray
        function [dataArray] = ReadDataArray(this, filePath, numHeaderLines)
            %Read the data
            dataArray = readmatrix(filePath, 'FileType', 'text', 'NumHeaderLines', numHeaderLines, 'OutputType', 'double');
        end

        %% ReadHeadersLine
        function [headersStrArray] = ReadHeadersLine(this, fileID)

            %Read one line
            line = fgetl(fileID);

            headersStrArray = [];

            %Split into the headers
            cellArray = strsplit(line, "\t");
            for i = 1 : length(cellArray)
                if ~isempty(cellArray{i})
                    headersStrArray = [headersStrArray string(cellArray{i})];
                end
            end


            %Error checking
            assert(~isempty(headersStrArray), "Headers row loaded from file empty");
        end

        %% ScanFileForMetadataRows
        function [RowNo, metadataStrArray] = ScanFileForMetadataRows(~, fileID, endOfMetadataTextLine)
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
                    metadataStrArray = [metadataStrArray string(line)];
                end

                %Increment row number
                RowNo = RowNo + 1;

                %Read one line
                line = fgetl(fileID);
            end


            %Handle the case where we never found the header string and
            %reached end of file
            if(~success)
                error('Could not find headers in datafile');
            end
        end
    end

end

