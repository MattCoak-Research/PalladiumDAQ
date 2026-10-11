classdef PythonUtils
    %PythonUtils - Static functions for setting up and using Python, for Python instruments.
    %At start-up the Controller chooses the Python to use
    %(`UsePythonExecutable`) and checks it (`CheckPythonSetup`), showing
    %`SetupHelpMessage` if Python instruments can't be used. The
    %PythonInstrumentController then imports the instrument modules
    %(`ImportPythonModulesInPackageFolder`) and creates them
    %(`InstantiatePythonModule`). See [Python instruments](../python-instruments.md).

    %% Properties (Constant, Public)
    properties (Constant, Access = public)
        RequiredPackages = ["pyvisa", "pyserial"];  %Python packages that Python instruments need (pip names)
        RequiredModules = ["pyvisa", "serial"];     %Module names that those packages are imported as, in the same order
        SupportedVersions = "3.10 to 3.14";         %Python versions supported by MATLAB R2026b - update with the minimum MATLAB release
    end

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function AppendFolderToPythonPath(directoryPath)
            %Add a folder to the end of Python's module search path (sys.path), so Python can import from it.
            %Errors if the folder doesn't exist
            %
            %Inputs:
            %   directoryPath - the folder

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
            %Check whether Python instruments can be used: that MATLAB can load Python, and it has the packages needed.
            %Loads Python, if it isn't loaded already. The packages are
            %RequiredPackages, looked for without importing them
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
            %Convert the Python text in a value from Python into MATLAB strings, looking inside structs and cell arrays.
            %A py.str becomes a string; a py.list or py.tuple becomes a
            %string array if all its elements are text, otherwise a cell
            %array; Python None becomes []. Anything else is unchanged
            %
            %Inputs:
            %   in - the value: a struct, cell array or Python object
            %
            %Outputs:
            %   out - the value with its Python text converted

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
            %Import every Python module in a package folder - one per Python instrument.
            %Imports each .py file in parentFolder/packageName (except those
            %starting "__") as packageName.<file name>. parentFolder is added
            %to the Python path if it isn't on it. A module that fails to
            %import gives a warning and is skipped
            %
            %Inputs:
            %   parentFolder - the folder holding the package folder
            %   packageName  - the package folder's name, e.g. "PythonInstruments"
            %
            %Outputs:
            %   importedNames   - full module names, e.g. "PythonInstruments.MyInstrument" (string array)
            %   importedModules - the py.module objects (cell array)
            %   shortNames      - the names without the package, e.g. "MyInstrument"

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
                    % (fullmod first: the other way round gives one result
                    % per loaded module, and the reload never happened)
                    if ismember(fullmod, keys_string)
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
                    shortNames = string(s(end));    %ShortNames are without the namespaces and dots
                else
                    importedNames(end+1) = string(fullmod); %#ok<SAGROW>
                    s = strsplit(string(fullmod), '.');
                    shortNames(end+1) = string(s(end));    %ShortNames are without the namespaces and dots
                end
            end

        end

        function instance = InstantiatePythonModule(moduleName, module)
            %Create an instance of the class with the same name as its module, e.g. MyInstrument in PythonInstruments.MyInstrument.
            %
            %Inputs:
            %   moduleName - the module's full name
            %   module     - the imported py.module
            %
            %Outputs:
            %   instance - the new Python object

            arguments
                moduleName {mustBeTextScalar};
                module (1,1) py.module;
            end

            s = strsplit(moduleName, '.');
            nameAfterNamespaces = s(end);
            instance = module.(nameAfterNamespaces)();
        end

        function status = MakeSetupStatus(statusName, Settings)
            %Make a Python setup status struct, as returned by CheckPythonSetup.

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
            %The title and HTML message for a dialogue explaining a Python setup problem, and how to fix it.
            %Title and message are "" if status.Status is "OK"

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
            %Make MATLAB use the given Python executable, if it isn't using it already.
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

    end
end

