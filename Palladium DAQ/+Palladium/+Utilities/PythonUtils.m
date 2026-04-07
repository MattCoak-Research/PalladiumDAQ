classdef PythonUtils
    %GUIUTILS Static methods for helping with GUI creation and functions,
    %mainly the automatic GUI for adjusting object properties

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function AppendFolderToPythonPath(directoryPath)
            pyrun("import sys");
            pyrun("sys.path.append(r""" + directoryPath + """)");
        end

    end
end

