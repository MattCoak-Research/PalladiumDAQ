classdef PythonInstrumentController < handle
    %PythonInstrumentController - Finds the user's Python instruments and creates them, wrapped as PythonInstrument objects.
    %The Controller creates one at start-up, if Python can be used (see
    %`PythonUtils.CheckPythonSetup`), and loads the instrument modules from
    %the PythonInstruments folder of the user files folder. The
    %InstrumentController then lists them with the MATLAB instruments, and
    %calls `CreateInstrument` for one that is added. See
    %[Python instruments](../python-instruments.md).

    %% Properties (Public, Private Set)
    properties (GetAccess = public, SetAccess = private)
        AvailableInstrModules;      %The imported Python modules, one per instrument (cell array of py.module)
        AvailableInstrNames;        %Their instrument names - each module's name, which is also its class name (string array)
        PythonInstrumentNamespace;  %Name of the package folder holding the instruments, e.g. "PythonInstruments"
        QCoDeSCatalog = struct("entry", {}, "name", {}, "class_path", {}, "source", {}, "vendor", {}, "file", {}, "folder", {});   %The QCoDeS drivers that can be added, from LoadQCoDeSDrivers: one struct each, whose entry is its name in the instruments list
    end

    %% Constructor
    methods
        function this = PythonInstrumentController(pythonInstrNamespace, rootDir)
            %Set up for Python instruments, adding PalladiumPythonCore (their base class) to Python's path.
            %Errors if the PalladiumPythonCore folder isn't in rootDir
            %
            %Inputs:
            %   pythonInstrNamespace - package folder name of the instruments, e.g. "PythonInstruments"
            %   rootDir              - the folder Palladium.m is in, which holds PalladiumPythonCore

            arguments
                pythonInstrNamespace {mustBeTextScalar};
                rootDir = [];%Location of Palladium.m root - PalladiumPythonCore is in this folder
            end

            this.PythonInstrumentNamespace = pythonInstrNamespace;

            %Make sure the PalladiumPythonCore folder is in a parent folder
            %which is on the Python path, so it can be seen
            dr = fullfile(rootDir, "PalladiumPythonCore");
            assert(exist(dr, "dir"), "PythonInstrumentControllerError:CoreDirectoryNotFound", "%s", "PalladiumPythonCore directory not found at " + dr);
            Palladium.Utilities.PythonUtils.AppendFolderToPythonPath(rootDir);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function instrRef = CreateInstrument(this, instrName)
            %Create a Python instrument by name, wrapped in a PythonInstrument so Palladium can use it.
            %Errors if no loaded instrument has that name
            %
            %Inputs:
            %   instrName - the instrument's name, e.g. "TemplatePythonInstrument"
            %
            %Outputs:
            %   instrRef - the new PythonInstrument

            arguments
                this;
                instrName {mustBeTextScalar};
            end

            if this.IsQCoDeSEntry(instrName)
                instrRef = this.CreateQCoDeSInstrument(instrName);
                return;
            end

            pyInstrRef = this.InstantiateInstrument(instrName);

            if isempty(pyInstrRef)
                error("CreateInstrumentError:InstantiationFailed", "Py instrument instantiation failed");
            end

            instrRef = Palladium.PythonInstruments.PythonInstrument(pyInstrRef);
            instrRef.Type = string(instrName);
        end

        function tf = IsQCoDeSEntry(this, instrName)
            %Whether a name in the instruments list is a QCoDeS driver, found by LoadQCoDeSDrivers.
            %
            %Inputs:
            %   instrName - the name, e.g. "QCoDeS: Keithley2450"
            %
            %Outputs:
            %   tf - true if it is one

            tf = ~isempty(this.QCoDeSCatalog) && any(string({this.QCoDeSCatalog.entry}) == string(instrName));
        end

        function names = QCoDeSEntryNames(this)
            %The names of the QCoDeS drivers that can be added, in the instruments list.
            %
            %Outputs:
            %   names - string array, empty if QCoDeS isn't installed or has no drivers

            names = strings(1, 0);
            if ~isempty(this.QCoDeSCatalog)
                names = string({this.QCoDeSCatalog.entry});
            end
        end

        function LoadQCoDeSDrivers(this, userFolder)
            %Find the QCoDeS drivers that can be added: the installed qcodes and qcodes_contrib_drivers ones, and .py files in a folder.
            %The driver files are read as text, not imported, so this is
            %fast (about half a second). Lists nothing if qcodes isn't
            %installed in the Python in use, which only affects QCoDeS
            %drivers - everything else works. Sets QCoDeSCatalog
            %
            %Inputs:
            %   userFolder - the user's QCoDeS Drivers folder, or "" for none

            arguments
                this;
                userFolder {mustBeTextScalar} = "";
            end

            this.QCoDeSCatalog = this.QCoDeSCatalog([]);
            hasQcodes = logical(pyrun("import importlib.util; found = importlib.util.find_spec('qcodes') is not None", "found"));
            if ~hasQcodes
                return;
            end

            jsonText = string(py.PalladiumPythonCore.QCoDeSCatalog.build_catalog_json(char(userFolder)));
            decoded = jsondecode(jsonText);
            if ~isempty(decoded)
                this.QCoDeSCatalog = reshape(decoded, 1, []);
            end
        end

        function LoadInstrumentClasses(this, directory)
            %Import every Python instrument module in the instruments package folder, and list them.
            %Imports the .py files in directory/PythonInstrumentNamespace
            %(reloading any already imported, to pick up changes), setting
            %AvailableInstrModules and AvailableInstrNames. Errors if the
            %folder doesn't exist
            %
            %Inputs:
            %   directory - the folder holding the package folder (the user files folder)

            arguments
                this
                directory {mustBeTextScalar};
            end

            assert(exist(directory,"dir"), "LoadInstrumentClassesError:DirectoryNotFound", "%s", "Directory " + string(directory) + " not found (PythonInstrumentController Load)");

            % Load all Python instrument classes from the specified directory
            [~, outp, shortNames] = Palladium.Utilities.PythonUtils.ImportPythonModulesInPackageFolder(directory, this.PythonInstrumentNamespace);
            this.AvailableInstrModules = outp;
            this.AvailableInstrNames = shortNames;
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function instrRef = CreateQCoDeSInstrument(this, entryName)
            %Create the QCoDeS instrument for an entry of the instruments list, configured with its driver.
            %The driver is imported here, so a driver that fails to import
            %errors now, with Python's message

            entry = this.QCoDeSCatalog(string({this.QCoDeSCatalog.entry}) == string(entryName));
            pyInstr = py.PalladiumPythonCore.QCoDeSInstrument.QCoDeSGeneric();
            pyInstr.configure(char(entry.class_path), char(entry.folder));
            instrRef = Palladium.PythonInstruments.QCoDeSInstrument(pyInstr);
            instrRef.Type = string(entryName);
        end

        function pyInstrRef = InstantiateInstrument(this, instrName)
            %Create the Python object of a loaded instrument, from its module.
            %Errors if no loaded instrument has that name

            arguments
                this;
                instrName {mustBeTextScalar};
            end

            %No instruments loaded: say so in the error (this used to be a
            %MATLAB warning, followed by the not-found error anyway)
            if isempty(this.AvailableInstrNames)
                error("InstantiateInstrumentError:NoInstrumentsLoaded", "%s", "Cannot create Python instrument '" + string(instrName) + "': no Python instruments have been loaded (see LoadInstrumentClasses)");
            end

            index = find(ismember(this.AvailableInstrNames, instrName));

            if isempty(index)
                error("InstantiateInstrumentError:InstrumentNotFound", "Instrument name '%s' not found in available instruments.", instrName);
            end

            name = this.AvailableInstrNames(index);
            module = this.AvailableInstrModules{index};

            pyInstrRef = Palladium.Utilities.PythonUtils.InstantiatePythonModule(name, module);
        end

    end

end
