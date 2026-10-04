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
        TempDir;    %Fresh empty folder for each test, inside Testing Data Files
        WriteDir;   %"Test Folder 2" inside TempDir, where tests that copy or create files do so
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

        function HelpersPathSetup(testCase)
            %Test helpers, which keep everything the tests write inside Testing Data Files
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "..", "Helpers")));
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

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)

        function CreateTemporaryFolder(testCase)
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            testCase.TempDir = string(fixture.Folder);
            testCase.WriteDir = fullfile(testCase.TempDir, "Test Folder 2");
            mkdir(testCase.WriteDir);
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
            Palladium.Utilities.PathUtils.CopyFiles(fileToCopy, testCase.TestDir1, testCase.WriteDir, Overwrite= true);
            testCase.verifyEqual(exist(fullfile(testCase.TestDir1, fileToCopy), "file"), 2, "Original must still be there");
            testCase.verifyEqual(exist(fullfile(testCase.WriteDir, fileToCopy), "file"), 2, "Copy must have been made");
        end

        %% EnsureDirectoryExists
        function test_EnsureDirectoryExists_DirectoryExistsAlready(testCase)
            testDir = testCase.TestDir1;

            newDirCreated = Palladium.Utilities.PathUtils.EnsureDirectoryExists(testDir);
            testCase.verifyFalse(newDirCreated);
            testCase.verifyTrue(isfolder(testDir));
        end

        function test_EnsureDirectoryExists_DirectoryNeedsToBeCreated(testCase)
            testDir = fullfile(testCase.TempDir, testCase.TestDirToCreate);

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
            baseFileName = fullfile(testCase.WriteDir, "myfile-00001.txt"); 
            expectedFileName = "myfile-00002";

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
                fid = fopen(fullfile(testCase.WriteDir, newFileName + ".txt"), 'w');
                fclose(fid);
            catch
                testCase.verifyFail('Writing of incremented file name failed.');
            end

            %Run a second time, without the numbers appended
            baseFileName = fullfile(testCase.WriteDir, "myfile.txt"); 
            expectedFileName = "myfile-00003";

            try
                newFileName = Palladium.Utilities.PathUtils.GetIncrementedFileName(baseFileName);
                testCase.verifyEqual(newFileName, expectedFileName);
            catch
                testCase.verifyFail('Incremented file name generation failed.');
            end
        end

        function test_GetIncrementedFileName_ExtensionMissing(testCase)
            baseFileName = fullfile(testCase.WriteDir, "myfileWithNoExt");
            expectedErrorID = "GetIncrementFileNameError:MissingExtension";
            testCase.verifyError(@() Palladium.Utilities.PathUtils.GetIncrementedFileName(baseFileName), expectedErrorID);
        end

        function test_GetIncrementedFileName_NameWithoutCounterGetsFirstCounterTest(testCase)
            testCase.verifyEqual(testCase.incremented("run"), "run-00001");
        end

        function test_GetIncrementedFileName_FreeCounterNameIsUsedAsTypedTest(testCase)
            testCase.verifyEqual(testCase.incremented("run-00007"), "run-00007");
        end

        function test_GetIncrementedFileName_ExistingCounterIsIncrementedTest(testCase)
            testCase.touch("run-00007");

            testCase.verifyEqual(testCase.incremented("run-00007"), "run-00008");
        end

        function test_GetIncrementedFileName_SkipsAllExistingCountersTest(testCase)
            testCase.touch(["run-00001", "run-00002", "run-00003", "run-00005"]);

            testCase.verifyEqual(testCase.incremented("run"), "run-00004");
            testCase.verifyEqual(testCase.incremented("run-00001"), "run-00004");
        end

        function test_GetIncrementedFileName_KeepsFiveDigitsWithLeadingZerosTest(testCase)
            testCase.touch(["run-00009", "run-00099", "run-09999"]);

            testCase.verifyEqual(testCase.incremented("run-00009"), "run-00010");
            testCase.verifyEqual(testCase.incremented("run-00099"), "run-00100");
            testCase.verifyEqual(testCase.incremented("run-09999"), "run-10000");
        end

        function test_GetIncrementedFileName_OnlyFilesWithTheSameExtensionCountTest(testCase)
            testCase.touch("run-00001", Extension=".csv");

            testCase.verifyEqual(testCase.incremented("run", Extension=".txt"), "run-00001");
            testCase.verifyEqual(testCase.incremented("run", Extension=".csv"), "run-00002");
        end

        function test_GetIncrementedFileName_ResultIsAStringTest(testCase)
            testCase.verifyClass(testCase.incremented("run"), "string");
        end

        %% GetIncrementedFileName - names that end in numbers are not counters
        function test_GetIncrementedFileName_NameEndingInNumberIsNotIncrementedTest(testCase)
            %The number is part of the name, whether or not that file exists
            testCase.verifyEqual(testCase.incremented("run_Temperature297"), "run_Temperature297-00001");

            testCase.touch("run_Temperature297");
            testCase.verifyEqual(testCase.incremented("run_Temperature297"), "run_Temperature297-00001");

            testCase.touch("run_Temperature297-00001");
            testCase.verifyEqual(testCase.incremented("run_Temperature297"), "run_Temperature297-00002");
        end

        function test_GetIncrementedFileName_DatesAndYearsInTheNameAreNotCountersTest(testCase)
            names = ["sample 02-Aug-2026", "2026-08-02", "20260802", "data-2026", "data-20260802", "v-1", "x-12", "run-001", "run-0001"];
            for name = names
                testCase.touch(name);

                testCase.verifyEqual(testCase.incremented(name), name + "-00001", name);
            end
        end

        function test_GetIncrementedFileName_TextThatLooksNumericToStr2doubleIsNotACounterTest(testCase)
            %These used to be read as numbers (1e5, Inf, +12 ...), and
            %"xInf" hung forever once the file existed
            names = ["x1e5", "xInf", "x+12", "x 12", "x1.5", "x12i", "xNaN"];
            for name = names
                testCase.touch(name);

                testCase.verifyEqual(testCase.incremented(name), name + "-00001", name);
            end
        end

        function test_GetIncrementedFileName_OnlyTheCounterIsIncrementedWhenNameAlsoHasNumbersTest(testCase)
            testCase.touch("T297-00001");

            testCase.verifyEqual(testCase.incremented("T297-00001"), "T297-00002");
        end

        function test_GetIncrementedFileName_CounterMustBeAtTheEndOfTheNameTest(testCase)
            testCase.verifyEqual(testCase.incremented("run-00001 final"), "run-00001 final-00001");
        end

        %% GetIncrementedFileName - other names
        function test_GetIncrementedFileName_ShortNamesTest(testCase)
            %Regression: names under 3 characters used to error
            for name = ["a", "ab", "12", "7"]
                testCase.verifyEqual(testCase.incremented(name), name + "-00001", name);
            end
        end

        function test_GetIncrementedFileName_EmptyNameTest(testCase)
            testCase.verifyEqual(testCase.incremented(""), "-00001");
        end

        function test_GetIncrementedFileName_SpacesAndPunctuationAreKeptTest(testCase)
            testCase.touch("my file (a)-00001");

            testCase.verifyEqual(testCase.incremented("my file (a)-00001"), "my file (a)-00002");
            testCase.verifyEqual(testCase.incremented("my file (a)"), "my file (a)-00002");
        end

        function test_GetIncrementedFileName_DotsInTheNameAreNotTreatedAsAnExtensionTest(testCase)
            testCase.verifyEqual(testCase.incremented("run.v2"), "run.v2-00001");
        end

        function test_GetIncrementedFileName_NamesOfMatlabFunctionsAreNotAffectedTest(testCase)
            %exist() would find run.m and mean.m on the MATLAB path
            testCase.verifyEqual(testCase.incremented("run"), "run-00001");
            testCase.verifyEqual(testCase.incremented("mean"), "mean-00001");
        end

        function test_GetIncrementedFileName_OtherFilesInTheFolderAreIgnoredTest(testCase)
            testCase.touch(["other", "other-00001", "run-00002"]);

            testCase.verifyEqual(testCase.incremented("run"), "run-00001");
        end

        function test_GetIncrementedFileName_FolderNameWithNumbersIsNotTouchedTest(testCase)
            folder = fullfile(testCase.TempDir, "data-00001 folder");
            mkdir(folder);
            fclose(fopen(fullfile(folder, "run-00001.dat"), "w"));

            newName = Palladium.Utilities.PathUtils.GetIncrementedFileName(fullfile(folder, "run.dat"));

            testCase.verifyEqual(newName, "run-00002");
        end

        function test_GetIncrementedFileName_RelativePathTest(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(testCase.TempDir));
            testCase.touch("run-00001");

            newName = Palladium.Utilities.PathUtils.GetIncrementedFileName("run.dat");

            testCase.verifyEqual(newName, "run-00002");
        end

        %% GetIncrementedFileName - past 99999
        function test_GetIncrementedFileName_CounterGrowsToSixDigitsAfter99999Test(testCase)
            testCase.touch("run-99999");

            testCase.verifyEqual(testCase.incremented("run-99999"), "run-100000");
        end

        function test_GetIncrementedFileName_StartsNewCounterAfterASixDigitOneTest(testCase)
            %"run-100000" is not a counter (6 digits), so it is a name
            testCase.touch("run-100000");

            testCase.verifyEqual(testCase.incremented("run-100000"), "run-100000-00001");
        end

        function test_GetIncrementedFileName_SixDigitNumberFreeStillGetsACounterTest(testCase)
            testCase.verifyEqual(testCase.incremented("run-100000"), "run-100000-00001");
        end

        function test_GetIncrementedFileName_RepeatedlyFeedingBackTheResultNeverRepeatsANameTest(testCase)
            %What the file name box in the GUI does: the name returned is
            %put back in the box and used for the next file. Runs through
            %the overflow from 5 to 6 digits
            name = "run-99998";
            names = strings(1, 8);
            for i = 1 : numel(names)
                name = testCase.incremented(name);
                testCase.touch(name);
                names(i) = name;
            end

            testCase.verifyEqual(names, ["run-99998" "run-99999" "run-100000" "run-100000-00001" "run-100000-00002" "run-100000-00003" "run-100000-00004" "run-100000-00005"]);
            testCase.verifyEqual(numel(unique(names)), numel(names));
        end

        function test_GetIncrementedFileName_NeverReturnsAnExistingFileTest(testCase)
            %Whatever is in the folder, the result must be a free name
            rng(1);
            names = ["run", "run-00001", "run-00002", "run-00003", "run-00010", "run-99999", "run-100000", "x-12", "a", "run-100000-00001"];
            testCase.touch(names(randperm(numel(names), 6)));

            for name = names
                result = testCase.incremented(name);

                testCase.verifyFalse(isfile(fullfile(testCase.TempDir, result + ".dat")), name + " -> " + result);
            end
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

        %% GetDocumentsDirectory
        function test_GetDocumentsDirectory(testCase)
            %Note this, by design, gives different results on different
            %platforms. Just check that it returns an absolute path to a
            %folder which exists
            actualPath = Palladium.Utilities.PathUtils.GetDocumentsDirectory();
            testCase.verifyClass(actualPath, "string");
            testCase.verifyTrue(isfolder(actualPath));
            isAbsolute = startsWith(actualPath, ["/", "\"]) || ~isempty(regexp(actualPath, "^[A-Za-z]:", "once"));
            testCase.verifyTrue(isAbsolute);
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

        function test_MakeFilePathRelative_CheckFolderHeirachy(testCase)
            %This test added because the Utilities folder heirachy being
            %changed did lead to a bug - the default setting for
            %MakePathRelative uses the Palladium root dir as the reference,
            %and the path to that is hardcoded into the function. If the
            %folder structure is changed but this function not updated, it
            %breaks things.
            path = fullfile(testCase.ApplicationDir, testCase.TestDir2);
            palladiumRootFileLoc = Palladium.Utilities.PathUtils.CleanPath(fullfile(testCase.ApplicationDir, "..", "..", "..", "Palladium.m"));
            palladiumRootDir = fileparts(palladiumRootFileLoc);
            refDir = palladiumRootDir;

            %Check we have that directory right - the Palladium.m file
            %should be in there
            testCase.verifyEqual(exist(palladiumRootFileLoc, "File"), 2);

            %These should be the same - refDir should match the built-in
            %default
            [actualNewPathWithRefDir, actualSuccessfullyMadeRelativeWithRefDir] = Palladium.Utilities.PathUtils.MakeFilePathRelative(path, RefDir=refDir);
            [actualNewPathWithNoRefDir, actualSuccessfullyMadeRelativeWithNoRefDir] = Palladium.Utilities.PathUtils.MakeFilePathRelative(path);

            testCase.verifyTrue(actualSuccessfullyMadeRelativeWithRefDir);
            testCase.verifyTrue(actualSuccessfullyMadeRelativeWithNoRefDir);
            testCase.verifyEqual(actualNewPathWithRefDir, actualNewPathWithNoRefDir);
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

    %% Methods (Private)
    methods (Access = private)

        function newName = incremented(testCase, name, Settings)
            %GetIncrementedFileName for a file of this name in the
            %temporary folder
            arguments
                testCase;
                name (1,1) string;
                Settings.Extension (1,1) string = ".dat";
            end

            newName = Palladium.Utilities.PathUtils.GetIncrementedFileName(fullfile(testCase.TempDir, name + Settings.Extension));
        end

        function touch(testCase, names, Settings)
            %Create empty files in the temporary folder
            arguments
                testCase;
                names (1,:) string;
                Settings.Extension (1,1) string = ".dat";
            end

            for name = names
                fclose(fopen(fullfile(testCase.TempDir, name + Settings.Extension), "w"));
            end
        end

    end

end