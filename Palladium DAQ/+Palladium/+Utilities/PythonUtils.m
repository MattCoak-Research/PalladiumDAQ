classdef PythonUtils
    %PYTHONUTILS Static methods for setting up and using Python, for Python instruments

    %% Properties (Constant, Public)
    properties (Constant, Access = public)
        RequiredPackages = ["pyvisa", "pyserial"];  %Python packages that Python instruments need (pip names)
        RequiredModules = ["pyvisa", "serial"];     %Module names that those packages are imported as, in the same order
        SupportedVersions = "3.10 to 3.14";         %Python versions supported by MATLAB R2026b - update with the minimum MATLAB release
    end

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
            assert(exist(directoryPath, 'dir')==7, "PythonPathError:NoSuchDirectory", "%s", "Directory " + directoryPath + " not found, could not add to Python path in PythonUtils");

            %Add to python search path inside MATLAB
            pyrun("import sys");
            pyrun("sys.path.append(r""" + directoryPath + """)");
        end

        function status = CheckPythonSetup()
            %CheckPythonSetup - Check whether Python instruments can be used: that MATLAB can load Python, and that it has the required packages.
            %Loads Python, if it isn't loaded already.
            %
            %Outputs:
            %   status - struct with fields:
            %       Status - "OK", "NotFound" (no Python found), "LoadFailed"
            %           (found, but MATLAB couldn't load it) or "PackagesMissing"
            %       Version, Executable - the Python MATLAB uses ("" if none)
            %       MissingPackages - pip names of any missing required packages
            %       ErrorMessage - why Python couldn't be used ("" if it could)

            env = pyenv;
            status = Palladium.Utilities.PythonUtils.MakeSetupStatus("OK", Version=env.Version, Executable=env.Executable);

            if status.Version == ""
                status.Status = "NotFound";
                return
            end

            %Try to load Python - this fails for an unsupported version
            try
                pyrun("import sys");
            catch err
                status.Status = "LoadFailed";
                status.ErrorMessage = string(err.message);
                return
            end

            %Look for each package, without importing it
            pkgs = Palladium.Utilities.PythonUtils.RequiredPackages;
            mods = Palladium.Utilities.PythonUtils.RequiredModules;
            for i = 1 : numel(pkgs)
                found = pyrun("import importlib.util; found = importlib.util.find_spec(name) is not None", "found", name=mods(i));
                if ~logical(found)
                    status.MissingPackages(end+1) = pkgs(i);
                end
            end
            if ~isempty(status.MissingPackages)
                status.Status = "PackagesMissing";
            end
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
                    warning('ImportPythonModulesInPackageFolderWarning:ImportFailed', 'Failed to import %s: %s', fullmod, ME.message);
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

        function status = MakeSetupStatus(statusName, Settings)
            %MakeSetupStatus - Make a Python setup status struct, as returned by CheckPythonSetup.
            arguments
                statusName {mustBeTextScalar};              %"OK", "NotFound", "LoadFailed" or "PackagesMissing"
                Settings.Version = "";                      %Python version
                Settings.Executable = "";                   %Path of the Python executable
                Settings.MissingPackages = strings(1, 0);   %pip names of missing packages
                Settings.ErrorMessage = "";                 %Why Python couldn't be used
            end

            status = struct("Status", string(statusName), "Version", string(Settings.Version), ...
                "Executable", string(Settings.Executable), "MissingPackages", string(Settings.MissingPackages), ...
                "ErrorMessage", string(Settings.ErrorMessage));
        end

        function [title, message] = SetupHelpMessage(status, Settings)
            %SetupHelpMessage - Title and HTML message for a dialog explaining a Python setup problem, and how to fix it.
            arguments
                status struct;                          %As returned by CheckPythonSetup
                Settings.ConfigFilePath = "";           %Config file in use, to say where to set PythonSettings.PythonExecutable
            end

            esc = @(t) replace(replace(replace(string(t), "&", "&amp;"), "<", "&lt;"), ">", "&gt;");
            link = @(url, text) "<a href=""" + url + """>" + text + "</a>";
            pkgList = join(Palladium.Utilities.PythonUtils.RequiredPackages, " ");

            title = "Python instruments are unavailable";
            switch status.Status
                case "NotFound"
                    intro = "<p>Palladium DAQ couldn't find a Python installation, so instruments written in Python can't be used.";
                case "LoadFailed"
                    intro = "<p>Palladium DAQ couldn't load the Python at <b>" + esc(status.Executable) + "</b>, so instruments written in Python can't be used. The error was: <i>" + esc(status.ErrorMessage) + "</i>";
                case "PackagesMissing"
                    title = "Python packages missing";
                    missing = join(status.MissingPackages, " ");
                    message = "<p>Python instruments that connect by GPIB, VISA, USB or serial need the package(s) <b>" + esc(missing) + "</b>, which the Python that Palladium DAQ uses (<b>" + esc(status.Executable) + "</b>) doesn't have. " ...
                        + "Ethernet and simulated (Debug) instruments work without them. To install them, run this in a command prompt, then restart Palladium DAQ:</p>" ...
                        + "<p><code>""" + esc(status.Executable) + """ -m pip install " + esc(missing) + "</code></p>" ...
                        + "<p>More help: <b>Python instruments</b> in Palladium DAQ's Help.</p>";
                    return
                otherwise
                    title = "";
                    message = "";
                    return
            end

            message = intro + " Everything else works normally - you only need Python if you use Python instruments.</p>" ...
                + "<p><b>To set Python up:</b></p><ol>" ...
                + "<li>Install Python " + Palladium.Utilities.PythonUtils.SupportedVersions + " (the versions this MATLAB release supports) from " + link("https://www.python.org/downloads/", "python.org") ...
                + ". On Windows, tick <b>Add python.exe to PATH</b> in the installer. (" + link("https://www.mathworks.com/support/requirements/python-compatibility.html", "Python versions supported by each MATLAB release") + ")</li>" ...
                + "<li>Install the packages Palladium DAQ needs, in a command prompt: <code>python -m pip install " + pkgList + "</code> (use <code>python3</code> on Mac and Linux)</li>" ...
                + "<li>For GPIB and VISA instruments, pyvisa also needs a VISA library: NI-VISA, or the pure-Python pyvisa-py (<code>python -m pip install pyvisa-py</code>). " + link("https://pyvisa.readthedocs.io/en/latest/introduction/getting.html", "How pyvisa finds a VISA library") + "</li>" ...
                + "<li>Restart Palladium DAQ.</li></ol>";
            if string(Settings.ConfigFilePath) ~= ""
                message = message + "<p>To use a particular Python, set <code>PythonSettings.PythonExecutable</code> in " + esc(Settings.ConfigFilePath) + " to its python executable.</p>";
            end
            message = message + "<p>More help: " + link("https://www.mathworks.com/help/matlab/matlab_external/install-supported-python-implementation.html", "Configure your system to use Python") ...
                + ", and <b>Python instruments</b> in Palladium DAQ's Help.</p>";
        end

        function [success, message] = UsePythonExecutable(executable)
            %UsePythonExecutable - Make MATLAB use the given Python executable, if it isn't using it already.
            %Python can only be changed before it is loaded in a MATLAB
            %session, so this fails if a different Python is already loaded.
            %
            %Outputs:
            %   success - true if MATLAB now uses that Python
            %   message - why not, if it doesn't ("" if it does)
            arguments
                executable {mustBeTextScalar};  %Path of the Python executable, e.g. python.exe
            end

            success = true;
            message = "";
            env = pyenv;
            if strcmpi(string(env.Executable), string(executable))
                return
            end
            if string(env.Status) == "Loaded"
                success = false;
                message = "Python " + string(env.Version) + " (" + string(env.Executable) + ") is already loaded in this MATLAB session, so " + string(executable) + " can't be used. Restart MATLAB to use it.";
                return
            end
            try
                pyenv(Version=executable);
            catch err
                success = false;
                message = "Could not use the Python at " + string(executable) + ": " + string(err.message);
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

