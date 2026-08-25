classdef PythonUtils
    %GUIUTILS Static methods for helping with GUI creation and functions,
    %mainly the automatic GUI for adjusting object properties

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function AppendFolderToPythonPath(directoryPath)
            %APPENDFOLDERTOPYTHONPATH - Add a directory to MATLAB's Python path
            %
            % Input arguments:
            % directoryPath - folder path to prepend to Python search paths
            %
            % This function ensures the provided directory is available to the
            % Python interpreter invoked from MATLAB.
            arguments
                directoryPath {mustBeTextScalar};
            end

            %Check the path exists first
            assert(exist(directoryPath, 'dir')==7, "PythonPathError:NoSuchDirectory", "Directory " + strrep(directoryPath, "\", "\\") + " not found, could not add to Python path in PythonUtils");

            %Add to python search path inside MATLAB
            pyrun("import sys");
            pyrun("sys.path.append(r""" + directoryPath + """)");
        end

        function [importedNames, importedModules, shortNames] = ImportPythonModulesInPackageFolder(parentFolder, packageName)
            %Import all python modules (classes) in a folder (package).
            %Scans a folder contained in the parentFolder (path), imports each .py file as
            % packageName.<modname>, and returns a cell array of imported module objects and their names.
            %parentFolder will be added to the Python path if not already on it.
            arguments
                parentFolder {mustBeTextScalar};
                packageName {mustBeTextScalar};
            end

            % Ensure Python search path includes the package parent
            if count(py.sys.path, parentFolder) == 0
                py.sys.path().insert(int32(0), py.str(parentFolder));
            end

            pkgFolder = fullfile(parentFolder, packageName);
            d = dir(fullfile(pkgFolder, '*.py'));

            importedModules = {};   % cell array of py.module objects
            importedNames = [];     % corresponding module names (strings)
            shortNames = [];

            for k = 1:numel(d)
                fname = d(k).name;

                % skip built-in and private modules
                if startsWith(fname, "__", "IgnoreCase", true)
                    continue
                end

                modname = fname(1:end-3); % remove .py
                fullmod = string(packageName) + "." + string(modname);

                try
                    %Query list of already-imported python modules and
                    %parse into a list of module names as strings
                    keys = py.importlib.import_module('sys').modules.keys();

                    % Convert to a Python list, then to a MATLAB cell array of py.str
                    keys_cell_py = cell(py.list(keys));  % cell array of py.str
                    % Convert each element to a char and then to a string array
                    keys_cell_char = cellfun(@char, keys_cell_py, 'UniformOutput', false);
                    keys_string = string(keys_cell_char);

                    % If already imported, reload to pick up changes
                    if ismember(keys_string, fullmod)
                        m = py.importlib.reload(py.importlib.import_module(fullmod));
                    else
                        m = py.importlib.import_module(fullmod);
                    end
                catch ME
                    warning('Failed to import %s: %s', fullmod, ME.message);
                    continue
                end

                %Add the imported module to the output lists
                importedModules{end+1} = m; %#ok<SAGROW>
                if isempty(importedNames)
                    importedNames = string(fullmod);                    
                    s = strsplit(importedNames, '.');
                    shortNames = string(s(end));    %ShortNames are without the the namespaces and dots
                else
                    importedNames(end+1) = string(fullmod); %#ok<SAGROW>
                    s = strsplit(string(fullmod), '.');
                    shortNames(end+1) = string(s(end));    %ShortNames are without the the namespaces and dots
                end
            end

        end

        function instance = InstantiatePythonModule(moduleName, module)
            %Create instance of python module (class)
            arguments
                moduleName {mustBeTextScalar};
                module (1,1) py.module;
            end

            s = strsplit(moduleName, '.');
            nameAfterNamespaces = s(end);
            instance = module.(nameAfterNamespaces)();
        end

        function [classObjs] = InstantiatePythonModulesInPackageFolder(parentFolder, packageName, Settings)
            %Create instances of all python modules (classes) in a folder (package).
            %Scans a folder contained in the parentFolder (path), imports each .py file as
            %packageName.<modname>, creates an instance of that class (empty constructor required)
            %and returns a cell array of imported module objects and their names.
            %parentFolder will be added to the Python path if not already on it.
            arguments
                parentFolder {mustBeTextScalar};
                packageName {mustBeTextScalar};
                Settings.ModulesToExclude = [];
            end

            [names, outp] = Palladium.Utilities.PythonUtils.ImportPythonModulesInPackageFolder(parentFolder, packageName);

            classObjs = {};

            for i = 1 : length(outp)
                mod = outp{i};
                name = names(i);

                s = strsplit(name, '.');
                nameAfterNamespaces = s(end);

                if ~isempty(Settings.ModulesToExclude) && ismember(Settings.ModulesToExclude, nameAfterNamespaces)
                    continue;
                end

                instance = mod.(nameAfterNamespaces)();
                instance
            end
        end

        function [isInstalled, verNo, subVerNo] = VerifyPythonInstall(Settings)
            %VERIFYPYTHONINSTALL - Check if Python meets minimum version requirements
            %
            % Input arguments:
            % Settings.MinimumMainVersionNumber - minimum major version (optional)
            % Settings.MinimumSubVersionNumber  - minimum minor version (optional)
            %
            % Output arguments:
            % isInstalled - true if installed and meets requirements
            % verNo       - detected major version number
            % subVerNo    - detected minor version number
            arguments
                Settings.MinimumMainVersionNumber = [];
                Settings.MinimumSubVersionNumber = [];
            end

            % Query MATLAB's Python environment
            env = pyenv;

            % If no Python environment configured, report not installed
            if isempty(env)
                isInstalled = false;
                verNo = 0;
                subVerNo = 0;
                return;
            end

            %Else, extract version info
            ver = env.Version;

            %Empty version info means no install, report not installed
            if isempty(ver) || strcmp(ver, "")
                isInstalled = false;
                verNo = 0;
                subVerNo = 0;
                return;
            end

            c = strsplit(ver, '.');
            verNo = double(c(1));
            subVerNo = double(c(2));

            % If no minimum main version requested, accept current installation
            if isempty(Settings.MinimumMainVersionNumber)
                isInstalled = true;
                return;
            end

            % Compare detected version against requested minima
            if isempty(Settings.MinimumSubVersionNumber)
                isInstalled = verNo >= Settings.MinimumMainVersionNumber;
            else
                isInstalled = verNo >= Settings.MinimumMainVersionNumber && subVerNo >= Settings.MinimumSubVersionNumber;
            end
        end

        function isInstalled = VerifyPythonPackageInstalled(packageName)
            %VERIFYPYTHONPACKAGEINSTALLED - Check if a Python package is importable
            %
            % Input arguments:
            % packageName - package name as a text scalar (e.g., "numpy")
            %
            % Output arguments:
            % isInstalled - logical true if import succeeds, false otherwise
            arguments
                packageName {mustBeTextScalar};
            end
            try
                % Check if the package is installed by attempting to import it
                pyrun("import " + packageName);
                isInstalled = true;
            catch
                % Import failed => package not available or import error
                isInstalled = false;
            end
        end

    end
end

