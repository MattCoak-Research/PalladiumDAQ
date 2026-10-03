classdef DataFolderFixture < matlab.unittest.fixtures.Fixture
    %DataFolderFixture - A new, empty, uniquely named folder inside
    %"Testing Data Files", removed again (with everything in it) at the end
    %of the test. Use instead of TemporaryFolderFixture so that tests only
    %ever create files in the one delineated place.
    %
    %   fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
    %   folder = fixture.Folder;

    properties (SetAccess = private)
        Folder = "";
    end

    methods

        function setup(fixture)
            root = TestHelpers.TestingPaths.DataFilesDir();
            assert(isfolder(root), "DataFolderFixtureError:MissingRoot", "%s", ...
                "The Testing Data Files folder is missing, expected at " + root);

            %tempname only supplies a unique name here, nothing is created in the system temp folder
            [~, uniqueName] = fileparts(tempname);
            folder = fullfile(root, "test_" + extractAfter(string(uniqueName), "tp"));
            mkdir(folder);

            fixture.Folder = folder;
            fixture.addTeardown(@() TestHelpers.DataFolderFixture.RemoveFolder(folder));
        end

    end

    methods (Access = protected)

        function tf = isCompatible(~, ~)
            %Every application of this fixture gets its own folder
            tf = false;
        end

    end

    methods (Static)

        function RemoveFolder(folder)
            %Delete a folder created by this fixture - but only ever one inside Testing Data Files
            assert(TestHelpers.TestingPaths.IsInsideDataFilesDir(folder), "DataFolderFixtureError:OutsideTestingDataFiles", "%s", ...
                "Refusing to delete " + string(folder) + " as it is not inside " + TestHelpers.TestingPaths.DataFilesDir());

            if isfolder(folder)
                rmdir(folder, "s");
            end
        end

    end

end
