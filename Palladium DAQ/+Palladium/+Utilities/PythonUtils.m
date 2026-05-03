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

