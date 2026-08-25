classdef PythonInstrumentController < handle
    %PYTHONINSTRUMENTCONTROLLER - logic/container/manager class for handling
    %instrument creation and management in Palladium, for Instruments
    %defined in an external user-defined Python class.

    %% Properties (Constant, Private)
    properties (Access = private, Constant)
    end

    %% Properties (Public)
    properties (Access = public)
       end

    %% Properties (Public, Private Set)
    properties (GetAccess = public, SetAccess = private)
        AvailableInstrModules;
        AvaialableInstrNames;
        PythonInstrumentNamespace;
    end

    %% Properties (Private)
    properties (Access = private)
        InstrController; %Reference back to the parent general Instrument Controller - feed things back to there
    end

    %% Events
    events
    end

    %% Constructor
    methods
        function this = PythonInstrumentController(pythonInstrNamespace, rootDir)
            arguments
                pythonInstrNamespace {mustBeTextScalar};
                rootDir = [];%Location of Palladium.m root - PalladiumPythonCore is in this folder
            end

            this.PythonInstrumentNamespace = pythonInstrNamespace;

            %Make sure the PalladiumPythonCore folder is in a parent folder
            %which is on the Python path, so it can be seen
            dr = fullfile(rootDir, "PalladiumPythonCore");
            assert(exist(dr, "dir"), "PalladiumPythonCore directory not found at " + dr);
            Palladium.Utilities.PythonUtils.AppendFolderToPythonPath(rootDir);
        end

        function pyInstrRef = InstantiateInstrument(this, instrName)
            arguments
                this;
                instrName {mustBeTextScalar};
            end

            if isempty(this.AvaialableInstrNames)
                warning("Available Python instruments not yet populated");
            end

            index = find(ismember(this.AvaialableInstrNames, instrName));

            if isempty(index)
                error("Instrument name '%s' not found in available instruments.", instrName);
            end

            name = this.AvaialableInstrNames(index);
            module = this.AvailableInstrModules{index};

            pyInstrRef = Palladium.Utilities.PythonUtils.InstantiatePythonModule(name, module);
        end

        function LoadInstrumentClasses(this, directory)
            arguments
                this
                directory {mustBeTextScalar};
            end

            assert(exist(directory,"dir"), "Directory " + string(directory) + " not found (PythonInstrumentController Load)");

           
            % Load all Python instrument classes from the specified directory
            [~, outp, shortNames] = Palladium.Utilities.PythonUtils.ImportPythonModulesInPackageFolder(directory, this.PythonInstrumentNamespace);
            this.AvailableInstrModules = outp;
            this.AvaialableInstrNames = shortNames;
        end
    end

    %% Methods (Public)
    methods (Access = public)
     
    end

    %% Methods (Private)
    methods(Access = private)


    end

end

