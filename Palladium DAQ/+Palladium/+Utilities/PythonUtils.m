classdef PythonUtils
    %GUIUTILS Static methods for helping with GUI creation and functions,
    %mainly the automatic GUI for adjusting object properties

    methods (Static)

        %% AppendFolderToPythonPath
        function AppendFolderToPythonPath(directoryPath)
            pyrun("import sys");
            pyrun("sys.path.append(r""" + directoryPath + """)");
        end
        
    end
end

