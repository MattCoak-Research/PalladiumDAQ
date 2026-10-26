classdef PythonUtils
    %PythonUtils - Static functions for setting up and using Python, for Python instruments.
    %At start-up the Controller chooses the Python to use
    %(`ApplyPythonExecutable`) and checks it (`CheckPythonSetup`), showing
    %`SetupHelpMessage` if Python instruments can't be used. Candidate
    %Pythons are first run in a separate process (`ProbePython`), so their
    %version and packages can be checked without loading them into MATLAB
    %(Python can't be changed once it is loaded). The
    %PythonInstrumentController then imports the instrument modules
    %(`ImportPythonModulesInPackageFolder`) and creates them
    %(`InstantiatePythonModule`). See [Python instruments](../python-instruments.md).

    %% Properties (Constant, Public)
    properties (Constant, Access = public)
        RequiredPackages = ["pyvisa", "pyserial"];  %Python packages that Python instruments need (pip names)
        RequiredModules = ["pyvisa", "serial"];     %Module names that those packages are imported as, in the same order
        SupportedVersions = "3.10 to 3.14";         %Python versions supported by MATLAB R2026b - update with the minimum MATLAB release
        MinimumVersion = [3 10];                    %Oldest supported Python [major minor] - keep in step with SupportedVersions
        MaximumVersion = [3 14];                    %Newest supported Python [major minor]
    end

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function [success, message, probe] = ApplyPythonExecutable(executable)
            %Check a Python in a separate process, and if it is usable make MATLAB use it.
            %The Python is run first (ProbePython) and its version checked,
            %so one that can't be used is rejected without being loaded or
            %set in pyenv. Then UsePythonExecutable points MATLAB at it
            %
            %Inputs:
            %   executable - path of the Python executable
            %
            %Outputs:
            %   success - true if MATLAB now uses that Python
            %   message - why not, if it doesn't ("" if it does)
            %   probe   - what ProbePython found (its Details say what happened)

            arguments
                executable {mustBeTextScalar};
            end

            probe = Palladium.Utilities.PythonUtils.ProbePython(executable);
            if ~probe.Runnable
                success = false;
                message = probe.ErrorMessage;
                return
            end
            [success, message] = Palladium.Utilities.PythonUtils.CheckVersionSupported(probe.VersionNumber);
            if ~success
                probe.Details(end+1, 1) = "Version check failed: " + message;
                return
            end
            [success, message] = Palladium.Utilities.PythonUtils.UsePythonExecutable(executable);
            if success
                probe.Details(end+1, 1) = "pyenv now uses " + string(executable);
            else
                probe.Details(end+1, 1) = "Could not point pyenv at it: " + message;
            end
        end

        function AppendFolderToPythonPath(directoryPath)
            %Add a folder to the end of Python's module search path (sys.path), so Python can import from it.
            %Does nothing if it is there already. Errors if the folder
            %doesn't exist
            %
            %Inputs:
            %   directoryPath - the folder

            arguments
                directoryPath {mustBeTextScalar};
            end

            %Check the path exists first
            assert(exist(directoryPath, 'dir')==7, "PythonPathError:NoSuchDirectory", "%s", "Directory " + directoryPath + " not found, could not add to Python path in PythonUtils");

            %Add to python search path inside MATLAB - only once (each
            %Palladium start in a MATLAB session used to add it again). The
            %folder is passed in as a variable, not written into the code,
            %so any character in it is safe
            pyrun("import sys" + newline + "if folder not in sys.path: sys.path.append(folder)", folder=char(directoryPath));
        end

        function [success, message] = CheckVersionSupported(versionNumber)
            %Whether a Python version is one MATLAB supports (MinimumVersion to MaximumVersion).
            %
            %Inputs:
            %   versionNumber - [major minor ...] of the Python
            %
            %Outputs:
            %   success - true if the version is supported
            %   message - why not, if it isn't ("" if it is)

            minV = Palladium.Utilities.PythonUtils.MinimumVersion;
            maxV = Palladium.Utilities.PythonUtils.MaximumVersion;
            mm = versionNumber(1:2);
            versionText = join(string(versionNumber), ".");
            success = true;
            message = "";
            if mm(1) < minV(1) || (mm(1) == minV(1) && mm(2) < minV(2)) || mm(1) > maxV(1) || (mm(1) == maxV(1) && mm(2) > maxV(2))
                success = false;
                message = "Python " + versionText + " is not supported - MATLAB can use Python " + Palladium.Utilities.PythonUtils.SupportedVersions + ".";
            end
        end

        function status = CheckPythonSetup(Settings)
            %Check whether Python instruments can be used: that MATLAB can load Python, and it has the packages needed.
            %First runs the Python MATLAB is set to use in a separate
            %process (ProbePython), and stops there if its version isn't
            %supported - so an unusable Python is never loaded into MATLAB
            %(where it would stay until MATLAB restarts). If the probe
            %itself can't run, carries on and tries to load it anyway. Then
            %loads Python, if it isn't loaded already, and looks for the
            %packages (RequiredPackages) in the loaded Python, without
            %importing them
            %
            %Inputs:
            %   Probe - (name-value) the result of ProbePython for the Python in pyenv, if it has just been run. Default: run it here
            %
            %Outputs:
            %   status - struct with fields:
            %       Status - "OK", "NotFound" (no Python found), "LoadFailed"
            %           (found, but not usable or MATLAB couldn't load it) or "PackagesMissing"
            %       Version, Executable - the Python MATLAB uses ("" if none)
            %       MissingPackages - pip names of any missing required packages
            %       ErrorMessage - why Python couldn't be used ("" if it could)
            %       Details - what was tried and found, line by line, for the Debug log

            arguments
                Settings.Probe = [];
            end

            env = pyenv;
            details = Palladium.Utilities.PythonUtils.EnvironmentDetails();
            status = Palladium.Utilities.PythonUtils.MakeSetupStatus("OK", Version=env.Version, Executable=env.Executable);

            if status.Version == ""
                details(end+1, 1) = "pyenv found no Python";
                status.Status = "NotFound";
                status.Details = details;
                return
            end

            %Run it in a separate process first
            probe = Settings.Probe;
            if isempty(probe)
                probe = Palladium.Utilities.PythonUtils.ProbePython(env.Executable);
            end
            details = [details; probe.Details];
            if probe.Runnable
                [supported, message] = Palladium.Utilities.PythonUtils.CheckVersionSupported(probe.VersionNumber);
                if ~supported
                    details(end+1, 1) = "Not loading it into MATLAB: " + message;
                    status.Status = "LoadFailed";
                    status.ErrorMessage = message;
                    status.Details = details;
                    return
                end
            else
                details(end+1, 1) = "The probe could not run it, so trying to load it into MATLAB anyway";
            end

            %Try to load Python - this fails for an unsupported version
            try
                pyrun("import sys");
            catch err
                details(end+1, 1) = "MATLAB could not load it: " + string(err.message);
                status.Status = "LoadFailed";
                status.ErrorMessage = string(err.message);
                status.Details = details;
                return
            end

            %Check it is the Python the probe saw
            [loadedExe, loadedVersion] = pyrun("import sys" + newline + "exe = str(sys.executable)" + newline + "ver = '%d.%d.%d' % tuple(sys.version_info[:3])", ["exe", "ver"]);
            loadedExe = string(loadedExe);
            loadedVersion = string(loadedVersion);
            details(end+1, 1) = "Loaded in MATLAB: Python " + loadedVersion + ", sys.executable " + loadedExe;
            if probe.Runnable
                if loadedVersion ~= probe.Version
                    details(end+1, 1) = "MISMATCH: the probe ran Python " + probe.Version + " but MATLAB loaded Python " + loadedVersion;
                elseif ~strcmpi(loadedExe, probe.ResolvedExecutable)
                    details(end+1, 1) = "Note: same version, but the probe's sys.executable (" + probe.ResolvedExecutable + ") differs from MATLAB's (" + loadedExe + ") - a launcher, link or virtual environment";
                else
                    details(end+1, 1) = "The probe and MATLAB are using the same Python";
                end
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
            if isempty(status.MissingPackages)
                details(end+1, 1) = "Required packages (" + join(pkgs, ", ") + ") are all present in the loaded Python";
            else
                details(end+1, 1) = "Missing packages in the loaded Python: " + join(status.MissingPackages, ", ");
                status.Status = "PackagesMissing";
            end
            status.Details = details;
        end

        function details = EnvironmentDetails()
            %Lines describing MATLAB's Python settings and the environment variables that affect Python, for the Debug log.
            %
            %Outputs:
            %   details - the lines (string column)

            details = strings(0, 1);
            details(end+1, 1) = "MATLAB " + string(version) + " on " + string(computer) + ", looking for Python";
            try
                env = pyenv;
                details(end+1, 1) = "pyenv: Version '" + string(env.Version) + "', Executable '" + string(env.Executable) + "', Status " + string(env.Status) + ", ExecutionMode " + string(env.ExecutionMode);
                details(end+1, 1) = "pyenv: Library '" + string(env.Library) + "', Home '" + string(env.Home) + "'";
            catch err
                details(end+1, 1) = "pyenv could not be read: " + string(err.message);
            end
            for name = ["PYTHONHOME", "PYTHONPATH", "PYTHONNOUSERSITE", "VIRTUAL_ENV", "CONDA_PREFIX", "CONDA_DEFAULT_ENV"]
                value = string(getenv(name));
                if value == ""
                    value = "(not set)";
                end
                details(end+1, 1) = "Environment " + name + ": " + value;
            end
        end

        function probe = ProbePython(executable)
            %Run a Python executable in a separate process, and report its version, packages and where it lives.
            %Nothing is loaded into MATLAB or changed in pyenv, so it works
            %for any Python, even one MATLAB can't load. Runs a small script
            %(from a new empty temporary folder, so nothing on sys.path
            %shadows a standard module) that prints what it finds
            %
            %Inputs:
            %   executable - path of the Python executable
            %
            %Outputs:
            %   probe - struct with fields:
            %       Runnable - true if it ran and reported
            %       Executable - the path given
            %       ResolvedExecutable, Version ("3.12.4"), VersionNumber ([3 12 4]),
            %           Implementation, Prefix - what that Python says about itself
            %       MissingPackages - pip names of missing required packages
            %       ExitCode, Output - what the process returned
            %       ErrorMessage - why it didn't run ("" if it did)
            %       Details - what was done and found, line by line, for the Debug log

            arguments
                executable {mustBeTextScalar};
            end

            executable = string(executable);
            probe = struct("Runnable", false, "Executable", executable, "ResolvedExecutable", "", "Version", "", ...
                "VersionNumber", [0 0 0], "Implementation", "", "Prefix", "", "MissingPackages", strings(1, 0), ...
                "ExitCode", NaN, "Output", "", "ErrorMessage", "", "Details", strings(0, 1));
            details = "Probing Python at " + executable;

            if ~isfile(executable)
                probe.ErrorMessage = "There is no file at " + executable + ".";
                probe.Details = [details; probe.ErrorMessage];
                return
            end

            %Only run programs: running anything else can hang (Windows can
            %wait on an "open with" prompt) or do something unexpected
            if ispc
                runnable = endsWith(executable, ".exe", IgnoreCase=true);
            else
                [~, attributes] = fileattrib(char(executable));
                runnable = isstruct(attributes) && (attributes.UserExecute || attributes.GroupExecute || attributes.OtherExecute);
            end
            if ~runnable
                probe.ErrorMessage = executable + " is not a program (an executable file) that can be run.";
                probe.Details = [details; probe.ErrorMessage];
                return
            end

            %Write the script to a new, empty folder
            folder = string(tempname);
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, "s"));
            script = fullfile(folder, "PalladiumPythonProbe.py");
            pkgs = Palladium.Utilities.PythonUtils.RequiredPackages;
            mods = Palladium.Utilities.PythonUtils.RequiredModules;
            writelines([ ...
                "import sys", ...
                "print('PALLADIUM_PROBE_BEGIN')", ...
                "print('version=%d.%d.%d' % tuple(sys.version_info[:3]))", ...
                "print('implementation=' + str(getattr(getattr(sys, 'implementation', None), 'name', 'unknown')))", ...
                "print('executable=' + str(sys.executable))", ...
                "print('prefix=' + str(sys.prefix))", ...
                "import importlib.util", ...
                "missing = [m for m in sys.argv[1:] if importlib.util.find_spec(m) is None]", ...
                "print('missing=' + ','.join(missing))", ...
                "print('PALLADIUM_PROBE_END')"], script);

            command = """" + executable + """ """ + script + """ " + join(mods, " ");
            details(end+1, 1) = "Command: " + command;
            details(end+1, 1) = "Script folder: " + folder + " (deleted afterwards)";
            stopwatch = tic;
            [exitCode, output] = system(command);
            elapsed = toc(stopwatch);
            probe.ExitCode = exitCode;
            probe.Output = string(strtrim(output));
            details(end+1, 1) = sprintf("Exit code %d after %.2f s", exitCode, elapsed);
            details(end+1, 1) = "Output:" + newline + probe.Output;

            %Parse the lines the script printed (any other output, such as warnings, is ignored)
            lines = splitlines(probe.Output);
            lines = strtrim(lines(startsWith(strtrim(lines), ["PALLADIUM_PROBE_BEGIN", "version=", "implementation=", "executable=", "prefix=", "missing=", "PALLADIUM_PROBE_END"])));
            if exitCode ~= 0 || ~any(lines == "PALLADIUM_PROBE_BEGIN") || ~any(lines == "PALLADIUM_PROBE_END")
                probe.ErrorMessage = "Running " + executable + " didn't work (exit code " + string(exitCode) + "): " + extractBefore(probe.Output + newline, newline) + ".";
                probe.Details = [details; probe.ErrorMessage];
                return
            end
            value = @(key) extractAfter(lines(startsWith(lines, key + "=")), strlength(key) + 1);
            probe.Version = value("version");
            probe.VersionNumber = double(split(probe.Version, "."))';
            probe.Implementation = value("implementation");
            probe.ResolvedExecutable = value("executable");
            probe.Prefix = value("prefix");
            missing = value("missing");
            if missing ~= ""
                missing = split(missing, ",")';
                probe.MissingPackages = pkgs(ismember(mods, missing));
            end
            probe.Runnable = true;

            details(end+1, 1) = "Python " + probe.Version + " (" + probe.Implementation + "), sys.executable " + probe.ResolvedExecutable + ", sys.prefix " + probe.Prefix;
            if isempty(probe.MissingPackages)
                details(end+1, 1) = "Required packages (" + join(pkgs, ", ") + ") are all present";
            else
                details(end+1, 1) = "Missing packages: " + join(probe.MissingPackages, ", ");
            end
            probe.Details = details;
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
                    Palladium.Logging.Logger.Log("Warning", "Failed to import Python module " + fullmod + ": " + string(ME.message));
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
                Settings.Details = strings(0, 1);           %What was tried and found, line by line, for the Debug log
            end

            status = struct("Status", string(statusName), "Version", string(Settings.Version), ...
                "Executable", string(Settings.Executable), "MissingPackages", string(Settings.MissingPackages), ...
                "ErrorMessage", string(Settings.ErrorMessage), "Details", string(Settings.Details(:)));
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
                        + "<p>If you have another Python that has them, click <b>Browse for Python...</b> to use that instead.</p>" ...
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
                message = message + "<p>If you already have a suitable Python installed, click <b>Browse for Python...</b> to choose it (or set <code>PythonSettings.PythonExecutable</code> in " + esc(Settings.ConfigFilePath) + " to its python executable). Palladium DAQ will check it, remember it, and use it from the next start.</p>";
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

