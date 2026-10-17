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

            pyInstrRef = this.InstantiateInstrument(instrName);

            if isempty(pyInstrRef)
                error("CreateInstrumentError:InstantiationFailed", "Py instrument instantiation failed");
            end

            instrRef = Palladium.PythonInstruments.PythonInstrument(pyInstrRef);
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

        function pyInstrRef = InstantiateInstrument(this, instrName)
            %Create the Python object of a loaded instrument, from its module.
            %Errors if no loaded instrument has that name

            arguments
                this;
                instrName {mustBeTextScalar};
            end

            if isempty(this.AvailableInstrNames)
                warning("InstantiateInstrumentWarning:NoInstrumentsAvailable", "Available Python instruments not yet populated");
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
