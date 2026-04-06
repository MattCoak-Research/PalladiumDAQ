classdef test_PathUtils < matlab.unittest.TestCase
    % TEST_PATHUTILS Tests for Palladium utilities functions - PathUtils
    % static class

    %% Properties
    properties
        TestingDir = fullfile("..", "data", "PathUtils Testing");
        TestDir1;
        TestDir2;
        SearchPathDir;
        TestDirToCreate = "Directory that does not exist yet";
        ApplicationDir;
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)

        function DirectorySetup(testCase)% Shared setup for the entire test class
            testCase.TestDir1 = fullfile(testCase.TestingDir, "Test Folder 1");
            testCase.TestDir2 = fullfile(testCase.TestingDir, "Test Folder 2");
            testCase.SearchPathDir = fullfile(testCase.TestingDir, "SearchPathFolder");

            applicationPath = mfilename('fullpath');
            [testCase.ApplicationDir, ~, ~] = fileparts(applicationPath);
        end

        function PathSetup(testCase)% Shared setup for the entire test class
            % Add folder to the Path temporarily
            %Because we're using this fixture tooling, it will get
            %automatically removed on test completion
            import matlab.unittest.fixtures.PathFixture
            import matlab.unittest.constraints.ContainsSubstring
            f = testCase.applyFixture(PathFixture(testCase.SearchPathDir, IncludeSubfolders=true));
            testCase.verifyThat(path,ContainsSubstring(f.Folders(1)));
        end

    end

    %% Methods (TestClassTeardown)
    methods (TestClassTeardown)

        function TeardownFiles(testCase)
            % Remove contents of folder created during test - we copy stuff
            % into it
            path = fullfile(testCase.TestDir2, "*");
            delete(path);

            dirToRemove = fullfile(testCase.TestingDir, testCase.TestDirToCreate);
            if exist(dirToRemove, "dir") == 7
                rmdir(dirToRemove);
            end
        end

    end

    %% Tests
    methods (Test)

        %% CleanPath
        function test_CleanPath_WithRedundantCharacters(testCase)
            %This is a basic test of a single simple case only - this
            %should probably be expanded and edge cases added
            pathStr = fullfile("abc", "def", "ghi", "..", "jkl")';
            expectedCleanPath = fullfile("abc", "def", "jkl");
            actualCleanPath = Palladium.Utilities.PathUtils.CleanPath(pathStr);
            testCase.verifyEqual(actualCleanPath, expectedCleanPath);
        end

        %% CopyFiles
        function test_CopyFiles(testCase)
            fileToCopy = "CopyTestFile.dat";
            Palladium.Utilities.PathUtils.CopyFiles(fileToCopy, testCase.TestDir1, testCase.TestDir2, Overwrite= true);
            testCase.verifyEqual(exist(fullfile(testCase.TestDir1, fileToCopy), "file"), 2);
        end

        %% EnsureDirectoryExists
        function test_EnsureDirectoryExists_DirectoryExistsAlready(testCase)
            testDir = testCase.TestDir1;

            newDirCreated = Palladium.Utilities.PathUtils.EnsureDirectoryExists(testDir);
            testCase.verifyFalse(newDirCreated);
            testCase.verifyTrue(isfolder(testDir));
        end

        function test_EnsureDirectoryExists_DirectoryNeedsToBeCreated(testCase)
            testDir = fullfile(testCase.TestingDir, testCase.TestDirToCreate);

            newDirCreated = Palladium.Utilities.PathUtils.EnsureDirectoryExists(testDir);
            testCase.verifyTrue(newDirCreated);
            testCase.verifyTrue(isfolder(testDir));
        end

        %% EnsureExtension
        function test_EnsureExtension_NonePresent(testCase)
            filepath = "myfile";
            extension = ".txt";
            expectedPath = "myfile.txt";

            actualPath = Palladium.Utilities.PathUtils.EnsureExtension(filepath, extension);
            testCase.verifyEqual(actualPath, expectedPath);
        end

        function test_EnsureExtension_AlreadyPresent(testCase)
            filepath = "myfile.txt";
            extension = ".txt";
            expectedPath = "myfile.txt";
            
            actualPath = Palladium.Utilities.PathUtils.EnsureExtension(filepath, extension);
            testCase.verifyEqual(actualPath, expectedPath);
        end

        function test_EnsureExtension_InvalidExtension(testCase)
            filepath = "myfile.dat";
            extension = "dat";
            expectedErrorID = "EnsureExtensionError:ExtensionInvalid";
            testCase.verifyError(@() Palladium.Utilities.PathUtils.EnsureExtension(filepath, extension), expectedErrorID);
        end

        function test_EnsureExtension_WrongExtensionPresent(testCase)
            filepath = "myfile.dat";
            extension = ".txt";
            expectedErrorID = "EnsureExtensionError:WrongExtension";
            testCase.verifyError(@() Palladium.Utilities.PathUtils.EnsureExtension(filepath, extension), expectedErrorID);
        end


        %% GetIncrementedFileName
        function test_GetIncrementedFileName(testCase)
            baseFileName = fullfile(testCase.ApplicationDir, testCase.TestDir2, "myfile-001.txt"); 
            expectedFileName = "myfile-002";

            % Create the file to simulate existing file
            fid = fopen(baseFileName, 'w');
            fclose(fid);

            try
                newFileName = Palladium.Utilities.PathUtils.GetIncrementedFileName(baseFileName);
                testCase.verifyEqual(newFileName, expectedFileName);
            catch
                testCase.verifyFail('Incremented file name generation failed.');
            end

            % write that file
            try
                fid = fopen(fullfile(testCase.ApplicationDir, testCase.TestDir2, newFileName + ".txt"), 'w');
                fclose(fid);
            catch
                testCase.verifyFail('Writing of incremented file name failed.');
            end

            %Run a second time, without the numbers appended
            baseFileName = fullfile(testCase.ApplicationDir, testCase.TestDir2, "myfile.txt"); 
            expectedFileName = "myfile-003";

            try
                newFileName = Palladium.Utilities.PathUtils.GetIncrementedFileName(baseFileName);
                testCase.verifyEqual(newFileName, expectedFileName);
            catch
                testCase.verifyFail('Incremented file name generation failed.');
            end
        end

        function test_GetIncrementedFileName_ExtensionMissing(testCase)
            baseFileName = fullfile(testCase.ApplicationDir, testCase.TestDir2, "myfileWithNoExt");
            expectedErrorID = "GetIncrementFileNameError:MissingExtension";
            testCase.verifyError(@() Palladium.Utilities.PathUtils.GetIncrementedFileName(baseFileName), expectedErrorID);
        end

        %% GetPathOfFolderOnSearchPath
        function test_GetPathOfFolderOnSearchPath(testCase)
            %This currently doesn't test any edge cases.. and the function
            %doesn't in fact HANDLE any either..
            expectedPath = fullfile(testCase.ApplicationDir, testCase.SearchPathDir);
            expectedPath = Palladium.Utilities.PathUtils.CleanPath(expectedPath);
            dirName = "SearchPathFolder";

            actualPath = Palladium.Utilities.PathUtils.GetPathOfFolderOnSearchPath(dirName);
            testCase.verifyEqual(actualPath, expectedPath);
        end

        %% GetUserDirectory
        function test_GetUserDirectory(testCase)
            %Note this, by design, gives different results on different
            %platforms. Just check that it returns some directory which
            %exists
            actualPath = Palladium.Utilities.PathUtils.GetUserDirectory();
            testCase.verifyEqual(exist(actualPath, "dir"), 7);
        end

        %% IsDirectoryValid
        function test_IsDirectoryValid(testCase)            
            try
                isValid = Palladium.Utilities.PathUtils.IsDirectoryValid(testCase.TestingDir);
                testCase.verifyTrue(isValid);
            catch
                testCase.verifyFail('Directory validation failed.');
            end

            %Check some edge cases too
            testCase.verifyFalse(Palladium.Utilities.PathUtils.IsDirectoryValid(""));
            testCase.verifyFalse(Palladium.Utilities.PathUtils.IsDirectoryValid(fullfile(testCase.TestingDir, "No Such Directory, Moron")));
        end

        %% IsFileNameValid
        function test_IsFileNameValid(testCase)
            try
                isValid = Palladium.Utilities.PathUtils.IsFileNameValid("ObviouslyOKFileName");
                testCase.verifyTrue(isValid);
            catch
                testCase.verifyFail('Directory validation failed.');
            end

            %Check some edge cases too
            testCase.verifyFalse(Palladium.Utilities.PathUtils.IsFileNameValid(""));
            testCase.verifyFalse(Palladium.Utilities.PathUtils.IsFileNameValid("Co$%rrupt?N.ame"));
        end

        %% MakeFilePathRelative
        function test_MakeFilePathRelative(testCase)
            path = fullfile(testCase.ApplicationDir, testCase.TestDir2);
            expectedPath = filesep + fullfile("Tests", "Unit Tests", "data", "PathUtils Testing", "Test Folder 2"); %This is the path to Test Folder 2 from the directory with Palladium.m in it
            expectedSuccessfullyMadeRelative = true;

            [actualNewPath, actualSuccessfullyMadeRelative] = Palladium.Utilities.PathUtils.MakeFilePathRelative(path);

            testCase.verifyEqual(actualNewPath, expectedPath);
            testCase.verifyEqual(actualSuccessfullyMadeRelative, expectedSuccessfullyMadeRelative);
        end

        function test_MakeFilePathRelative_RefDirGiven(testCase)
            path = fullfile(testCase.ApplicationDir, testCase.TestDir2);
            refDir = testCase.ApplicationDir;
            expectedPath = filesep + testCase.TestDir2; %This is the path to Test Folder 2 from the directory with Palladium.m in it
            expectedSuccessfullyMadeRelative = true;

            [actualNewPath, actualSuccessfullyMadeRelative] = Palladium.Utilities.PathUtils.MakeFilePathRelative(path, RefDir=refDir);

            testCase.verifyEqual(actualNewPath, expectedPath);
            testCase.verifyEqual(actualSuccessfullyMadeRelative, expectedSuccessfullyMadeRelative);
        end

        %% ReplaceDateTag
        function test_ReplaceDateTag(testCase)
            %Can't really write any exact test here that isn't just.. the
            %code.. so test if the function runs ok and that it returns a
            %string of the right length - if it didn't replace <DATE> the
            %length would certainly be wrong
            inputStr = "Today is <DATE>";
            actualStr = Palladium.Utilities.PathUtils.ReplaceDateTag(inputStr);
            testCase.verifyEqual(length(char(actualStr)), 19);
        end

        %% StripExtension
        function test_StripExtension(testCase)
            fileName = "listOfBears.dat";
            expectedNewFileName = "listOfBears";
            actualNewFileName = Palladium.Utilities.PathUtils.StripExtension(fileName);
            testCase.verifyEqual(actualNewFileName, expectedNewFileName);
        end

    end

end