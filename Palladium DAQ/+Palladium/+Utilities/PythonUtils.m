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

    end
end

