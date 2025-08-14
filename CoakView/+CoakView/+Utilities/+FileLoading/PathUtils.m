classdef PathUtils
    %PATHUTILS static functions to help with verify and handling paths to
    %files and folders

    methods (Static)

        %% CleanPath
        function cleanPath = CleanPath(pathStr)
            %CLEANPATH Clean a file path name. Removes redundant characters from
            %   the path name, e.g. '//', '/./' as well as initial './' and circular
            %   paths e.g. 'abc/def/../def/'.
            %   Additionally, all file separators are set to the platform file
            %   separator.
            % get the possible file separators
            allowed_file_separators = '/';  % add the "standard" file separator
            if filesep ~= '/' % add the system file separator if different
                allowed_file_separators = [filesep allowed_file_separators];
            end

            %Make sure the path is a char vector, not a newer String type.
            pathStr = char(pathStr);
            % remove insignificant (i.e. initial and ending) white spaces
            pathStr = strtrim(pathStr);

            % replace "wrong" file separators
            for i=length(allowed_file_separators)
                pathStr = strrep(pathStr, allowed_file_separators(i), filesep);
            end

            % remove redundant './'
            pathStr = strrep(pathStr, [filesep '.' filesep], filesep);

            % remove double slashes
            prev_len = 0;
            while prev_len ~= length(pathStr)
                prev_len = length(pathStr);
                pathStr = strrep(pathStr, [filesep filesep], filesep);
            end

            % remove initial './' if path name is not empty
            if length(pathStr) > 2 && strcmp(pathStr(1:2), ['.' filesep])
                pathStr = pathStr(3:end);
            end

            % remove redundant '../'
            pathStr = reduce_updir(pathStr);

            %Return a proper string
            cleanPath = string(pathStr);

            %% reduce_updir
            function new_path_name = reduce_updir(path_name)
                pre_updir ='';
                [pre_updir, path_name] = r_reduce_updir(pre_updir, path_name);
                new_path_name = [pre_updir path_name];
            end

            %% r_reduce_updir
            function [new_pre_updir, new_path_name] = r_reduce_updir(pre_updir, path_name)
                while (length(path_name) > 3) && strcmp(path_name(1:3), ['..' filesep])
                    pre_updir = [pre_updir '..' filesep];
                    path_name = path_name(4:end);
                end
                % search for the first occurrence of '/../'
                idx_2 = min(strfind(path_name, [filesep '..' filesep]));
                if ~isempty(idx_2) % if found
                    % search for the previous occurrence of '/'
                    idx_1 = max(strfind(path_name(1:idx_2-1), filesep));
                    path_name = [path_name(1:idx_1) path_name(idx_2+4:end)];
                    % search for the next '../'to be removed
                    [pre_updir, path_name] = r_reduce_updir(pre_updir, path_name);
                end
                new_pre_updir = pre_updir;
                new_path_name = path_name;
            end

        end

        %% GetIncrementedFileName
        function newPath = GetIncrementedFileName(filepath)
            [directory, fileNameWithoutExt, Ext] = fileparts(filepath);

            %Check last 3 characters to see if they are already a number.
            %If not add em. We will then need to check if that filename
            %already exists.
            lastThree = extractBetween(fileNameWithoutExt, strlength(fileNameWithoutExt) - 2, strlength(fileNameWithoutExt));
            if(isnan(str2double(lastThree)))    %If not numbers
                fileNameWithoutExt = strcat(fileNameWithoutExt, '-001');
            end

            %Rebuild filepath to check if it exists
            filepath = string(fullfile(directory, fileNameWithoutExt)) + string(Ext);

            while(exist(filepath, 'file') == 2)  %If file exists already
                lastThree = extractBetween(fileNameWithoutExt, strlength(fileNameWithoutExt) - 2, strlength(fileNameWithoutExt));
                n = str2double(lastThree);
                numstring = num2str(n+1, '%03.f');

                startStr = char(extractBetween(fileNameWithoutExt, 1, strlength(fileNameWithoutExt) - 3));
                fileNameWithoutExt = strcat(startStr, numstring);

                filepath = string(fullfile(directory, fileNameWithoutExt)) + Ext;
            end

            newPath = fileNameWithoutExt;
        end

        %% IsDirectoryValid
        function valid = IsDirectoryValid(directory)
            valid = false;

            if isempty(directory)
                return;
            end

            if(~isfolder(directory))
                return;
            end

            %Set path valid if it passed all checks and made it here
            valid = true;
        end

        %% IsFileNameValid
        function valid = IsFileNameValid(filename)
            valid = false;

            if isempty(filename)
                return;
            end

            if ~isempty(regexp(filename, '[/\*:?"<>|.]', 'once'))
                return;
            end

            %Set path valid if it passed all checks and made it here
            valid = true;
        end

        %% StripExtension
        function newFileName = StripExtension(fileName)

            [~, newFileName, ~] = fileparts(fileName);
        end

    end
end

