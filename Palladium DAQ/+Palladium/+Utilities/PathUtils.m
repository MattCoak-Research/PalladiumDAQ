classdef PathUtils
    %PATHUTILS static functions to help with verify and handling paths to
    %files and folders

    %% Methods (Static, Public)
    methods (Static, Access = public)

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

            function new_path_name = reduce_updir(path_name)
                pre_updir ='';
                [pre_updir, path_name] = r_reduce_updir(pre_updir, path_name);
                new_path_name = [pre_updir path_name];
            end

            function [new_pre_updir, new_path_name] = r_reduce_updir(pre_updir, path_name)
                while (length(path_name) > 3) && strcmp(path_name(1:3), ['..' filesep])
                    pre_updir = [pre_updir '..' filesep]; %#ok<AGROW>
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

        function CopyFiles(filesToCopy, sourceInstrumentDir, destInstrumentDir, Settings)
          % COPYFILES - Copy listed files if missing in the dest directory
          %
          % Input arguments:
          % filesToCopy           - string array of filenames to copy
          % sourceInstrumentDir   - source directory path (text scalar)
          % destInstrumentDir     - destination directory path (text scalar)
          %
          % Name-Value Pairs (Optional)
          % Overwrite - default false. Set to true to have file copy and
          % overwrite if a file of the same name already exists in
          % destination
            
            arguments
                filesToCopy             string;
                sourceInstrumentDir     {mustBeTextScalar};
                destInstrumentDir       {mustBeTextScalar};
                Settings.Overwrite      (1,1) logical = false;
            end

            % Iterate over each filename and copy when not already present
            for i = 1 : length(filesToCopy)
                cls = filesToCopy(i);
                if ~exist(fullfile(destInstrumentDir, cls), "file") || Settings.Overwrite
                    copyfile(fullfile(sourceInstrumentDir, cls), fullfile(destInstrumentDir, cls));
                end
            end
        end

        function newDirCreated = EnsureDirectoryExists(dirPath)
            % ENSUREDIRECTORYEXISTS - Ensure a directory exists, create if needed
            %
            % Input arguments:
            % dirPath - path to directory (string or char scalar)
            %
            % Output arguments:
            % newDirCreated - true if directory was created, false if already existed
            arguments
                dirPath {mustBeTextScalar};
            end

            if Palladium.Utilities.PathUtils.IsDirectoryValid(dirPath)
                %Directory exists, no need to do anything
                newDirCreated = false;
                return;
            else
                %Make the directory
                mkdir(dirPath);
                newDirCreated = true;
            end
        end


        function newPath = EnsureExtension(filepath, extension)
            % Send in a string filepath and string extension, and ensure
            % that the ouput contains that extension. Throw warnings if
            % not, error on full mismatch
            arguments
                filepath    {mustBeTextScalar};
                extension   {mustBeTextScalar};
            end

            %Make sure the extension starts with a '.'
            chars = char(extension);
            assert(chars(1)=='.', "EnsureExtensionError:ExtensionInvalid", "Extension must start with a . character");

            %Extract the exisiting extension (returns "" if not found)
            [~, ~, ext] = fileparts(filepath);

            %If there is an extension there already, assert it's the same
            %as the requested one, then just return
            if ext~=""      %Fileparts returns "" not [] if no extension found - this is empty string test
                assert(strcmp(string(ext), string(extension)), "EnsureExtensionError:WrongExtension", "%s", "Extension of file path " + string(filepath) + " contained an extension different to the expected " + string(extension));
                newPath = filepath;
                return;
            end

            % Append the required extension to the filepath
            newPath = strcat(filepath, extension);
        end

        function newFileName = GetIncrementedFileName(filepath)
            % GETINCREMENTEDFILENAME - Return the file name (without folder or
            % extension) to save as, so that no existing file is overwritten
            %
            % A file is numbered with a counter: a hyphen followed by
            % exactly 5 digits at the end of the name, like "run-00001".
            % A name without a counter gets "-00001" added. A name that
            % already ends in a counter is incremented from there, if the
            % file with that counter exists - so a name that has already
            % been through here ("run-00001") goes to "run-00002" next time.
            %
            % A name that merely ends in numbers is not a counter and is never
            % incremented: "run_Temperature297" becomes
            % "run_Temperature297-00001", and so does "sample 02-Aug-2026".
            % Hence exactly 5 digits - a year or a short number won't match.
            %
            % Past "-99999" the next number has 6 digits, which is no longer a
            % counter, so a new one is started after it: "run-99999",
            % "run-100000", "run-100000-00001", "run-100000-00002"...
            %
            % Input arguments:
            % filepath - text scalar path, including the file extension
            %
            % Output arguments:
            % newFileName  - file name without folder or extension
            arguments
                filepath {mustBeTextScalar};
            end

            [directory, fileNameWithoutExt, Ext] = fileparts(filepath);
            directory = Palladium.Utilities.PathUtils.CleanPath(directory);

            assert(Ext~="", "GetIncrementFileNameError:MissingExtension", "Extension must be given when passing file path into GetIncrementedFileName");

            counterPattern = '^(.*)-(\d{5})$';
            newFileName = string(fileNameWithoutExt);

            %Add a counter to a name that doesn't have one yet
            if isempty(regexp(newFileName, counterPattern, 'once'))
                newFileName = newFileName + "-00001";
            end

            %isfile, unlike exist, looks only at this exact path - exist
            %also finds anything on the MATLAB search path with the name
            candidatePath = string(fullfile(directory, newFileName)) + string(Ext);
            while isfile(candidatePath)
                tokens = regexp(newFileName, counterPattern, 'tokens', 'once');
                if isempty(tokens)
                    %Counter has overflowed to 6 or more digits, start a new one
                    newFileName = newFileName + "-00001";
                else
                    newFileName = string(tokens{1}) + "-" + string(sprintf('%05d', str2double(tokens{2}) + 1));
                end

                candidatePath = string(fullfile(directory, newFileName)) + string(Ext);
            end
        end

        function dirPath = GetPathOfFolderOnSearchPath(dirName)
            %See https://uk.mathworks.com/matlabcentral/answers/347892-get-full-path-of-directory-that-is-on-matlab-search-path
            %Get the actual directory file path to a folder that is on the
            %MATLAB search path

            esctofind = regexptranslate('escape', dirName);   %in case it has special characters

            dirs = regexp(path, pathsep,'split');          %cell of all individual paths
            temp = unique(cellfun(@(P) strjoin(P(1:find(strcmp(esctofind, P),1,'last')),filesep), regexp(dirs,filesep,'split'), 'uniform', 0));    %don't let the blue smoke escape
            dirPathCell = temp(~cellfun(@isempty,temp));     %non-empty results only

            if isempty(dirPathCell)
                error("GetPathOfFolderOnSearchPathError:DirectoryNotFound", "%s", "Could not find directory " + string(dirName) + " on the MATLAB path (PathUtils.GetPathOfFolderOnSearchPath");
            end

            dirPath = string(dirPathCell{1});
        end

        function documentsPath = GetDocumentsDirectory()
            %GetDocumentsDirectory - Return the current user's Documents folder, on Windows, Mac and Linux.
            %Falls back to the user's home folder if there is no Documents
            %folder.
            %
            %Outputs:
            %   documentsPath - absolute path of the folder (string)

            documentsPath = "";
            if ispc
                %The registry gives the actual Documents folder, which may
                %have been moved (e.g. redirected into OneDrive)
                try
                    documentsPath = string(winqueryreg('HKEY_CURRENT_USER', ...
                        'Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders', 'Personal'));
                catch
                end
                home = string(getenv("USERPROFILE"));
            else
                home = string(getenv("HOME"));
                if isunix && ~ismac
                    %Linux desktops may localise or move the Documents folder -
                    %xdg-user-dir reports it, where installed
                    [status, result] = system("xdg-user-dir DOCUMENTS");
                    if status == 0
                        documentsPath = strtrim(string(result));
                    end
                end
            end

            if documentsPath == "" || ~isfolder(documentsPath)
                documentsPath = fullfile(home, "Documents");
            end
            if ~isfolder(documentsPath)
                documentsPath = home;
            end
        end

        function valid = IsDirectoryValid(directory)
            % ISDIRECTORYVALID - Check whether a directory path is valid
            % syntactically and exists
            %
            % Input arguments:
            % directory - text scalar containing a directory path
            arguments
                directory {mustBeTextScalar}
            end

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

        function valid = IsFileNameValid(filename)
            % ISFILENAMEVALID - Check a filename string is valid, allowed format
            %
            % Input arguments:
            % filename - text scalar representing a file name to validate
            %
            % Output arguments:
            % valid    - logical indicating whether filename is valid
            arguments
                filename {mustBeTextScalar}
            end

            valid = false;

            if isempty(filename) || filename == ""
                return;
            end

            if ~isempty(regexp(filename, '[/\*:?"<>|.]', 'once'))
                return;
            end

            %Set path valid if it passed all checks and made it here
            valid = true;
        end

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
                refPath = Palladium.Utilities.PathUtils.CleanPath(string(m) + filesep + ".." + filesep + ".." + filesep + ".." + filesep);%This sets refPath to be the absolute path to the "Palladium DAQ\Palladium DAQ\"  folder where Palladium.m sits - ApplicationDir of Controller
            else
                refPath = string(Settings.RefDir);
            end            

            %Sanitise paths, remove any .. loops etc
            refPath = Palladium.Utilities.PathUtils.CleanPath(refPath);
            path = Palladium.Utilities.PathUtils.CleanPath(path);

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

        function outstr = ReplaceDateTag(str)
            %If a string has '<DATE>' in it, let's replace that with today's
            %date for convenience
            d = datetime;
            format = 'yyyy-MM-dd';
            dateStr = string(d, format);  %Today's date

            outstr = strrep(str, '<DATE>', dateStr);
        end

        function newFileName = StripExtension(fileName)
            [~, newFileName, ~] = fileparts(fileName);
        end

    end
end

