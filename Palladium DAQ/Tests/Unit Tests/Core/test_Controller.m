classdef test_Controller < matlab.unittest.TestCase
    % TEST_CONTROLLER Tests for Palladium.Core.Controller's helper methods
    % that don't need a running Palladium DAQ - the system tests cover the
    % rest.

    %% Properties
    properties
        ApplicationDir;     %An absolute folder to stand in for the folder Palladium.m is in - nothing is written to it
        TempDir;            %Fresh folder for each test, inside Testing Data Files
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function DirectorySetup(testCase)
            testCase.ApplicationDir = string(fileparts(mfilename("fullpath")));

            %Test helpers, which keep everything the tests write inside Testing Data Files
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testCase.ApplicationDir, "..", "..", "Helpers")));
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function CreateTemporaryFolder(testCase)
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            testCase.TempDir = string(fixture.Folder);
        end
    end

    %% Tests
    methods (Test)

        %% CreateFolderOrFallBack (private)
        function ExistingFolderIsUsed(testCase)
            folder = testCase.verifyWarningFree(@() Palladium.Core.Controller.CreateFolderOrFallBack([testCase.TempDir, testCase.uncreatable()], "test"));
            testCase.verifyEqual(folder, testCase.TempDir);
        end

        function MissingFolderIsCreated(testCase)
            missing = fullfile(testCase.TempDir, "New", "Folder");
            folder = testCase.verifyWarningFree(@() Palladium.Core.Controller.CreateFolderOrFallBack([missing, testCase.TempDir], "test"));
            testCase.verifyEqual(folder, missing);
            testCase.verifyTrue(isfolder(missing));
        end

        function UncreatableFolderFallsBack(testCase)
            %The first fallback that can be made is used - created if need be - with a warning
            fallback = fullfile(testCase.TempDir, "Fallback");
            folder = testCase.verifyWarning(@() Palladium.Core.Controller.CreateFolderOrFallBack([testCase.uncreatable(), testCase.uncreatable("Other"), fallback, testCase.TempDir], "test"), ...
                "LoadSettingsWarning:FolderCreationFailed");
            testCase.verifyEqual(folder, fallback);
            testCase.verifyTrue(isfolder(fallback));
        end

        function NoCreatableFolderErrors(testCase)
            testCase.verifyError(@() Palladium.Core.Controller.CreateFolderOrFallBack([testCase.uncreatable(), testCase.uncreatable("Other")], "test"), ...
                "LoadSettingsError:FolderCreationFailed");
        end

        %% MakeAbsoluteFromApplicationDir (private)
        function RelativeConfigPathIsMadeAbsolute(testCase)
            path = testCase.verifyWarningFree(@() Palladium.Core.Controller.MakeAbsoluteFromApplicationDir("Data", testCase.ApplicationDir, false));
            testCase.verifyEqual(path, fullfile(testCase.ApplicationDir, "Data"));
        end

        function AbsoluteConfigPathIsUnchanged(testCase)
            %Even in an installed copy - a full path is the right thing there
            absolutePath = fullfile(testCase.ApplicationDir, "Elsewhere", "Data");
            path = testCase.verifyWarningFree(@() Palladium.Core.Controller.MakeAbsoluteFromApplicationDir(absolutePath, testCase.ApplicationDir, true));
            testCase.verifyEqual(path, absolutePath);
        end

        function RelativeConfigPathInInstalledCopyWarns(testCase)
            %In an installed copy the installation folder may not be
            %writable, and is replaced by updates
            path = testCase.verifyWarning(@() Palladium.Core.Controller.MakeAbsoluteFromApplicationDir("Data", testCase.ApplicationDir, true), "LoadSettingsWarning:RelativePathInInstalledCopy");
            testCase.verifyEqual(path, fullfile(testCase.ApplicationDir, "Data"), "The path should still be made absolute");
        end

    end

    %% Methods (Private)
    methods (Access = private)
        function folder = uncreatable(testCase, name)
            %A folder "inside" a file, which no OS can create
            arguments
                testCase;
                name = "Data";
            end
            blocker = fullfile(testCase.TempDir, "blocker.txt");
            if ~isfile(blocker)
                writelines("Not a folder", blocker);
            end
            folder = fullfile(blocker, name);
        end
    end
end
