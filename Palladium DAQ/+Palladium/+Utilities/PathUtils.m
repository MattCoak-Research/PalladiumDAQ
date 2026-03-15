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

        %% GetPathOfFolderOnSearchPath
        function dirPath = GetPathOfFolderOnSearchPath(dirName)
            %See https://uk.mathworks.com/matlabcentral/answers/347892-get-full-path-of-directory-that-is-on-matlab-search-path
            %Get the actual directory file path to a folder that is on the
            %MATLAB search path

            esctofind = regexptranslate('escape', dirName);   %in case it has special characters

            dirs = regexp(path, pathsep,'split');          %cell of all individual paths
            temp = unique(cellfun(@(P) strjoin(P(1:find(strcmp(esctofind, P),1,'last')),filesep), regexp(dirs,filesep,'split'), 'uniform', 0));    %don't let the blue smoke escape
            dirPath = temp(~cellfun(@isempty,temp));     %non-empty results only
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

        %% MakeFilePathRelative
        function [newPath, successfullyMadeRelative] = MakeFilePathRelative(path, Settings)
            %Make an absolute path into a relative one, relative to the
            %Palladium folder by default, or to that given as optional
            %argument RefDir
            arguments
                path {mustBeTextScalar};
                Settings.RefDir = [];
            end

            successfullyMadeRelative = false;

            if isempty(Settings.RefDir)
                %Get path of this file
                m = mfilename("fullpath");
                refPath = Palladium.Utilities.PathUtils.CleanPath(string(m) + filesep + ".." + filesep + ".." + filesep + ".." + filesep + ".." + filesep);%This sets refPath to be the absolute path to the "Palladium\Palladium\Palladium" inner folder - ApplicationDir of Controller
            else
                refPath = string(Settings.RefDir);
            end            

            %Clean trailing \ if present
            refPath = strip(refPath, filesep);
            path = strip(path, filesep);

            %Case for if the path totally contains the refPath - ie the
            %path is a folder inside that root reference path. Just remove
            %the ref bit and return
            if contains(path, refPath)
                newPath = strrep(path, refPath, "");
                successfullyMadeRelative = true;
                return;
            end

            %Split up the paths into the directories, seperate by "\"
            pathCellArray = strsplit(path, filesep);
            refPathCellArray = strsplit(refPath, filesep);

            if strcmp(pathCellArray{1}, refPathCellArray{1})    %Make sure we're at least on the same drive, otherwise forget it
                i = 1;
                while(strcmp(pathCellArray{i}, refPathCellArray{i}))
                    i = i +1;

                    if i == length(pathCellArray) || i == length(refPathCellArray)
                        break;
                    end
                end

                %This is the section of the path that the two string s have
                %in common. Right now this is not output or used, but is
                %nice to have if doing more with this
                commonStr = pathCellArray{1};
                for j = 2 : i-1
                    commonStr = commonStr + string(filesep) + pathCellArray{j};
                end

                %This is the part of the path that is left over once the
                %common section is stripped out
                ps = "";
                for j = i : length(pathCellArray)
                    ps = ps + string(filesep) + pathCellArray{j};
                end


                refs = "";
                for j = i : length(refPathCellArray)
                    refs = refs + string(filesep) + "..";
                end

                % Stitch those two together to give something like "..\NewFolder"
                newPath = refs + ps;
                successfullyMadeRelative = true;
                return;
            end

            %Just return the original path (but ensure it's consistently a
            %string) if we fall back down to here. No relative path
            %extracted
            newPath = string(path);

        end

        %% ReplaceDateTag
        function outstr = ReplaceDateTag(str)
            %If a string has '<DATE>' in it, let's replace that with today's
            %date for convenience
            d = datetime;
            format = 'yyyy-MM-dd';
            dateStr = string(d, format);  %Today's date

            outstr = strrep(str, '<DATE>', dateStr);
        end

        %% StripExtension
        function newFileName = StripExtension(fileName)

            [~, newFileName, ~] = fileparts(fileName);
        end

    end
end

