classdef DataWriter < handle
    %DATAWRITER - Handles the writing of data files in CoakView
    
    properties
        FileWriteDetails;
        FileInfo = "<<< CoakView data file 3.0 >>>";
    end
    
    methods
        function this = DataWriter(fileWriteDetails)
            this.FileWriteDetails = fileWriteDetails;

            this.ConstructPath();
        end

        %% ConstructPath
        function ConstructPath(this)
            this.FileWriteDetails.FilePath = fullfile(string(this.FileWriteDetails.Directory), string(this.FileWriteDetails.FileName) + string(this.FileWriteDetails.FileExtension));
        end

        %% SaveFigure
        function SaveFigure(~, figure, directory, fileNameWithoutExtension)
            try
                %Add a title to the plot 
                title(strrep(fileNameWithoutExtension, '_', ' '));

                %Add '-Fig' to the filename, and then any needed 00x
                %numbers to prevent file overwriting if multiple figures
                %were saved on this same filename
                fileNameWithoutExtension = CoakView.Utilities.FileLoading.PathUtils.GetIncrementedFileName(fullfile(string(directory), string(fileNameWithoutExtension)) + "-Fig.fig");
            
                %Save a .fig and a .png
                saveas(figure, fullfile(directory, fileNameWithoutExtension + ".fig"));
                saveas(figure, fullfile(directory, fileNameWithoutExtension + ".png"));
            catch e
                CoakView.Utilities.ErrorHandling.ErrorHandler.HandleError('Error saving figure in DataWriter', e);
            end
        end
        
        %% ValidateFilePath
        function newFileName = ValidateFilePath(this)
            newFileName = this.FileWriteDetails.FileName;
            if(this.FileWriteDetails.SaveFile)
                switch(this.FileWriteDetails.WriteMode)
                    case('Increment File No.')
                        newFileName = CoakView.Utilities.FileLoading.PathUtils.GetIncrementedFileName(fullfile(string(this.FileWriteDetails.Directory), string(newFileName)) + string(this.FileWriteDetails.FileExtension));
                    case('Overwrite File')
                        if(exist(newFileName, 'file') == 2)  %If file exists already
                            delete(newFileName);    %delete the existing file, then carry on as if it neever existed!
                        end
                    case('Append To File')
                        %No action needed
                    otherwise
                     error("Unsupported file write option");
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
                    fprintf(fid, '%s\r\n', Settings.MetadataLines(i));
                end
            end

            fprintf(fid, '%s\r\n', "<<< END METADATA LINES >>>");
            fprintf(fid, '%s\r\n', "");
            fprintf(fid, '%s\r\n', headers);
            fclose(fid);
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
                    CoakView.Logging.Logger.Log("Info", "Writing of file to " + this.FileWriteDetails.FilePath + " failed, retrying..." + " Error message: " + errMess);
                end
            end

            %If we got here, we tried N times to write to the file and it
            %didn't work - warn
            CoakView.Logging.Logger.Log("Warning", "Writing of file to " + this.FileWriteDetails.FilePath + " failed after " + num2str(numRetries) + " attempts. Data have been lost." + " Last error: " + errMess);
        end
    end
end

