classdef ProgrammeOutputFixture < matlab.unittest.fixtures.Fixture
    %ProgrammeOutputFixture - For tests that run Palladium itself using
    %Tests/TestingConfig.json, which sends its data files, sequences and logs
    %to the Data, Sequences and Logs folders inside "Testing Data Files".
    %Those folders are removed again at the end of the test, so afterwards
    %Testing Data Files is back to how it was found.

    properties (Constant)
        OutputFolderNames = ["Data", "Sequences", "Logs"];  %As set in TestingConfig.json
    end

    methods

        function setup(fixture)
            root = TestHelpers.TestingPaths.DataFilesDir();
            assert(isfolder(root), "ProgrammeOutputFixtureError:MissingRoot", "%s", ...
                "The Testing Data Files folder is missing, expected at " + root);

            %Start from a clean slate, and make sure it is left clean
            TestHelpers.ProgrammeOutputFixture.RemoveOutputFolders();
            fixture.addTeardown(@() TestHelpers.ProgrammeOutputFixture.RemoveOutputFolders());
        end

    end

    methods (Static)

        function RemoveOutputFolders()
            root = TestHelpers.TestingPaths.DataFilesDir();
            for name = TestHelpers.ProgrammeOutputFixture.OutputFolderNames
                folder = fullfile(root, name);
                if isfolder(folder)
                    rmdir(folder, "s");
                end
            end
        end

    end

end
