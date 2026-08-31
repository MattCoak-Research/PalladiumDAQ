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

        function out = ConvertPyStrFields(in)
            % ConvertPyStrFields Convert py.str fields in a struct to MATLAB string
            %   out = ConvertPyStrFields(in) scans fields of struct (recursively) and
            %   converts Python strings (py.str) and Python sequences of strings
            %   (py.list, py.tuple) to MATLAB string scalars/arrays.

            if isempty(in)
                out = in;
                return
            end

            if isstruct(in)
                out = in;
                fn = fieldnames(in);
                for i = 1:numel(fn)
                    f = fn{i};
                    out.(f) = Palladium.Utilities.PythonUtils.ConvertPyStrFields(in.(f));
                end
                return
            end

            % Cell arrays -> convert each element
            if iscell(in)
                out = cellfun(@Palladium.Utilities.PythonUtils.ConvertPyStrFields, in, 'UniformOutput', false);
                return
            end

            % Python None -> empty
            if isa(in, 'py.NoneType')
                out = [];
                return
            end

            % Python string -> MATLAB string scalar
            if isa(in, 'py.str')
                out = string(char(in));
                return
            end

            % Python list/tuple -> try to convert each element; if elements are str produce string array
            if isa(in, 'py.list') || isa(in, 'py.tuple')
                try
                    matlabCell = cell(in); % convert py sequence to cell
                catch
                    % fallback: iterate indices
                    n = int32(py.len(in));
                    matlabCell = cell(1,double(n));
                    for k = 1:double(n)
                        matlabCell{k} = in{k-1};
                    end
                end
                % Convert each element
                conv = cellfun(@Palladium.Utilities.PythonUtils.ConvertPyStrFields, matlabCell, 'UniformOutput', false);
                % If all converted elements are strings, return string array
                if all(cellfun(@(c) isstring(c) && isscalar(c), conv))
                    out = string(conv);
                else
                    out = conv;
                end
                return
            end

            % Leave numeric, logical, datetime, etc. unchanged
            out = in;
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
            end
        end

        function out = PyToMatlab(pyObj)
            % Convert simple py types (from json.loads) to MATLAB using char/double/cell/struct
            % pyObj here is typically a py.dict/list/str/numbers.
            if isa(pyObj, 'py.dict')
                keys = cell(pyObj.keys());
                s = struct();
                for i = 1:numel(keys)
                    key = keys{i};
                    val = pyObj{key};
                    s.(char(key)) = matlabFromPy(val);
                end
                out = s;
            else
                out = matlabFromPy(pyObj);
            end

            function m = matlabFromPy(x)
                if isa(x, 'py.str')
                    m = char(x);
                elseif isa(x, 'py.int') || isa(x, 'py.float')
                    m = double(x);
                elseif isa(x, 'py.bool')
                    m = logical(x);
                elseif isa(x, 'py.list') || isa(x, 'py.tuple')
                    n = int64(py.len(x));
                    c = cell(1,n);
                    for ii = 1:n
                        c{ii} = matlabFromPy(x{ii});
                    end
                    m = c;
                elseif isa(x, 'py.dict')
                    % recursive
                    keys2 = cell(x.keys());
                    t = struct();
                    for ii = 1:numel(keys2)
                        k2 = keys2{ii};
                        t.(char(k2)) = matlabFromPy(x{k2});
                    end
                    m = t;
                else
                    try
                        m = char(py.str(x));
                    catch
                        m = x;
                    end
                end
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

