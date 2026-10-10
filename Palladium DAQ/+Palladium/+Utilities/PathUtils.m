classdef PathUtils
    %PathUtils - Static functions for checking and handling file and folder paths.
    %Cleaning and comparing paths, creating folders, numbering data files so
    %none is overwritten, and finding the user's Documents and application
    %settings folders on Windows, Mac and Linux.

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function cleanPath = CleanPath(pathStr)
            %Tidy a path: remove redundant parts and use the platform's file separator.
            %Removes '//', '/./', an initial './' and circular parts such as
            %'abc/def/../def/', and trims whitespace. All file separators
            %become the platform's (filesep)
            %
            %Inputs:
            %   pathStr - the path, as text
            %
            %Outputs:
            %   cleanPath - the tidied path, as a string

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
            %Copy files from one folder to another, skipping any already there.
            %
            %Inputs:
            %   filesToCopy         - string array of file names to copy
            %   sourceInstrumentDir - the folder to copy from
            %   destInstrumentDir   - the folder to copy to
            %   Overwrite           - true to copy over files of the same name
            %                         that are already there. Default false
            
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
            %Create a folder if it doesn't exist yet.
            %
            %Inputs:
            %   dirPath - path of the folder
            %
            %Outputs:
            %   newDirCreated - true if the folder was created, false if it
            %                   already existed

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
            %Add an extension to a file path that has none, checking any it has.
            %Errors if the path already has a different extension
            %
            %Inputs:
            %   filepath  - the file path
            %   extension - the extension, starting with ".", e.g. ".dat"
            %
            %Outputs:
            %   newPath - filepath, with the extension added if it had none

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
            %The file name to save as, numbered so that no existing file is overwritten.
            %A file is numbered with a counter: a hyphen followed by exactly 5
            %digits at the end of the name, like "run-00001". A name without a
            %counter gets "-00001" added. A name that already ends in a counter
            %is incremented from there, if the file with that counter exists -
            %so a name that has already been through here ("run-00001") goes to
            %"run-00002" next time.
            %
            %A name that merely ends in numbers is not a counter and is never
            %incremented: "run_Temperature297" becomes "run_Temperature297-00001",
            %and so does "sample 02-Aug-2026". Hence exactly 5 digits - a year
            %or a short number won't match.
            %
            %Past "-99999" the next number has 6 digits, which is no longer a
            %counter, so a new one is started after it: "run-99999",
            %"run-100000", "run-100000-00001", "run-100000-00002"...
            %
            %Inputs:
            %   filepath - the path to save to, including the file extension
            %
            %Outputs:
            %   newFileName - the file name to use, without folder or extension

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
            %Full path of a folder on the MATLAB search path, found by its name.
            %Errors if no folder of that name is on the path. Method from
            %https://uk.mathworks.com/matlabcentral/answers/347892
            %
            %Inputs:
            %   dirName - the folder's name, e.g. "PPMS Communication"
            %
            %Outputs:
            %   dirPath - its full path (the first match), as a string


            esctofind = regexptranslate('escape', dirName);   %in case it has special characters

            dirs = regexp(path, pathsep,'split');          %cell of all individual paths
            temp = unique(cellfun(@(P) strjoin(P(1:find(strcmp(esctofind, P),1,'last')),filesep), regexp(dirs,filesep,'split'), 'uniform', 0));    %don't let the blue smoke escape
            dirPathCell = temp(~cellfun(@isempty,temp));     %non-empty results only

            if isempty(dirPathCell)
                error("GetPathOfFolderOnSearchPathError:DirectoryNotFound", "%s", "Could not find directory " + string(dirName) + " on the MATLAB path (PathUtils.GetPathOfFolderOnSearchPath");
            end

            dirPath = string(dirPathCell{1});
        end

        function appDataPath = GetAppDataDirectory()
            %The current user's folder for application settings, on Windows, Mac and Linux.
            %This is %APPDATA% on Windows, ~/Library/Application Support on
            %Mac, and $XDG_CONFIG_HOME (by default ~/.config) on Linux. The
            %folder may not exist yet.
            %
            %Outputs:
            %   appDataPath - absolute path of the folder (string)

            if ispc
                appDataPath = string(getenv("APPDATA"));
                if appDataPath == ""
                    appDataPath = fullfile(string(getenv("USERPROFILE")), "AppData", "Roaming");
                end
            elseif ismac
                appDataPath = fullfile(string(getenv("HOME")), "Library", "Application Support");
            else
                appDataPath = string(getenv("XDG_CONFIG_HOME"));
                if appDataPath == ""
                    appDataPath = fullfile(string(getenv("HOME")), ".config");
                end
            end
        end

        function documentsPath = GetDocumentsDirectory()
            %The current user's Documents folder, on Windows, Mac and Linux.
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
            %Whether a folder path is given and the folder exists.
            %
            %Inputs:
            %   directory - the folder path
            %
            %Outputs:
            %   valid - true if it is not empty and the folder exists

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
            %Whether text can be used as a file name (without folder or extension).
            %Not valid if empty, or if it contains any of / * : ? " < > | or "."
            %
            %Inputs:
            %   filename - the file name to check
            %
            %Outputs:
            %   valid - true if it can be used

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
            %Make an absolute path relative to a folder - by default the one Palladium.m is in.
            %
            %Inputs:
            %   path   - the absolute path
            %   RefDir - the folder to make it relative to. Default [], the
            %            folder Palladium.m is in
            %
            %Outputs:
            %   newPath                  - the relative path, e.g. "../Data", or
            %                              path itself if it is on a different drive
            %   successfullyMadeRelative - true if a relative path was made

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

            %Case for the path being the reference folder or a folder inside it - just
            %remove the reference folder from the front. Whole folder names are
            %compared, so a sibling such as "Palladium DAQ Data" is not taken to be
            %inside "Palladium DAQ"
            if path == refPath || startsWith(path, refPath + filesep)
                newPath = extractAfter(path, strlength(refPath));
                successfullyMadeRelative = true;
                return;
            end

            %Split up the paths into the directories, separated by filesep
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
            %Replace each <DATE> tag in text with today's date, as yyyy-MM-dd.
            %
            %Inputs:
            %   str - the text, e.g. "<DATE>_run"
            %
            %Outputs:
            %   outstr - e.g. "2026-10-10_run"

            d = datetime;
            format = 'yyyy-MM-dd';
            dateStr = string(d, format);  %Today's date

            outstr = strrep(str, '<DATE>', dateStr);
        end

        function newFileName = StripExtension(fileName)
            %The name of a file, without its folder or extension.
            %
            %Inputs:
            %   fileName - the file name or path, e.g. "Data/run.dat"
            %
            %Outputs:
            %   newFileName - e.g. "run"

            [~, newFileName, ~] = fileparts(fileName);
        end

    end
end

