classdef TestingPaths
    %TestingPaths - Where the tests may read and write, independent of the
    %current folder. The tests only ever create or delete things inside
    %DataFilesDir (and the programme itself maintains UserFilesDir).

    methods (Static)

        function dirPath = TestsDir()
            %The Tests folder: this file is Tests/Helpers/+TestHelpers/TestingPaths.m
            dirPath = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end

        function dirPath = DataFilesDir()
            %"Testing Data Files" - the one folder tests create and delete things in
            dirPath = fullfile(TestHelpers.TestingPaths.TestsDir(), "Testing Data Files");
        end

        function dirPath = UserFilesDir()
            %"Testing User Files" - the user files folder the programme is pointed at
            dirPath = fullfile(TestHelpers.TestingPaths.TestsDir(), "Testing User Files");
        end

        function tf = IsInsideDataFilesDir(path)
            %True for a path strictly inside Testing Data Files (not the folder itself)
            root = TestHelpers.TestingPaths.DataFilesDir();
            tf = startsWith(string(path), root + filesep);
        end

    end
end
