classdef test_CommandEncoder < matlab.unittest.TestCase
    % TEST_GUIUTILS Tests for Palladium utilities functions - GUIUtils
    % static class

    %% Properties
    properties
         TestingDir = fullfile("..", "data", "SequenceAndCommands Testing");
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)

        function PathSetup(testCase)% Shared setup for the entire test class
            % Set up shared state for all tests.
            % Add SequenceAndCommands Testing folder to the Path temporarily
            %Because we're using this fixture tooling, it will get
            %automatically removed on test completion
            import matlab.unittest.fixtures.PathFixture
            import matlab.unittest.constraints.ContainsSubstring
            f = testCase.applyFixture(PathFixture(testCase.TestingDir, IncludeSubfolders=true));
            testCase.verifyThat(path,ContainsSubstring(f.Folders(1)));
        end

    end

    %% Tests
    methods (Test)

        function test_WaitCommandEncoding(testCase)
            %Encode an example wait command into string, then translate it
            %back into a new command and check they match
            w = Palladium.Sequence.Commands.WaitCommand(2, "WaitDisplayUnits", "sec");

            ce = Palladium.Sequence.CommandEncoder();

            str = ce.CommandToString(w);
            w2 = ce.StringToCommand(str);

            testCase.verifyEqual(w.Wait_seconds, w2.Wait_seconds);
            testCase.verifyEqual(w.WaitDisplayUnit, w2.WaitDisplayUnit);
        end

        %% [DATAFILE] commands
        function test_DataFile_WriteWithWindowsPath(testCase)
            %Only the first : splits the flag from the path - the drive's : stays in the path
            com = Palladium.Sequence.CommandEncoder().StringToCommand("[DATAFILE] 1 : C:\Data\Run2.dat");
            testCase.verifyTrue(com.WriteToFile);
            testCase.verifyEqual(com.DataFilePath, "C:\Data\Run2.dat");
        end

        function test_DataFile_StopWriting(testCase)
            %0 stops writing, with or without a colon - and any path is ignored
            ce = Palladium.Sequence.CommandEncoder();
            for str = ["[DATAFILE] 0", "[DATAFILE] 0 :", "[DATAFILE] 0 : C:\Data\Run2.dat", "[DATAFILE] false"]
                com = ce.StringToCommand(str);
                testCase.verifyFalse(com.WriteToFile, str);
                testCase.verifyEqual(com.DataFilePath, "", str);
            end
        end

        function test_DataFile_WriteWithoutPathKeepsCurrentFile(testCase)
            %1 with no path switches writing back on, with the current file name (empty path)
            ce = Palladium.Sequence.CommandEncoder();
            for str = ["[DATAFILE] 1", "[DATAFILE] 1 :", "[DATAFILE] TRUE"]
                com = ce.StringToCommand(str);
                testCase.verifyTrue(com.WriteToFile, str);
                testCase.verifyEqual(com.DataFilePath, "", str);
            end
        end

        function test_DataFile_InvalidFlagErrors(testCase)
            ce = Palladium.Sequence.CommandEncoder();
            for str = ["[DATAFILE] 2 : C:\Data\Run2.dat", "[DATAFILE] yes", "[DATAFILE]"]
                testCase.verifyError(@() ce.StringToCommand(str), "ParseDataFileCommandError:InvalidFlag", str);
            end
        end

        function test_DataFile_SaveAndReadBack(testCase)
            %What the Sequence Editor saves can be read back as the same command
            ce = Palladium.Sequence.CommandEncoder();
            commands = {Palladium.Sequence.Commands.DataFileCommand(true, DataFilePath="C:\Data\Run2.dat"), ...
                Palladium.Sequence.Commands.DataFileCommand(true), ...
                Palladium.Sequence.Commands.DataFileCommand(false)};
            expectedText = ["[DATAFILE] 1 : C:\Data\Run2.dat", "[DATAFILE] 1", "[DATAFILE] 0"];
            for i = 1 : numel(commands)
                str = ce.CommandToString(commands{i});
                testCase.verifyEqual(str, expectedText(i));
                readBack = ce.StringToCommand(str);
                testCase.verifyEqual(readBack.WriteToFile, commands{i}.WriteToFile, str);
                testCase.verifyEqual(readBack.DataFilePath, commands{i}.DataFilePath, str);
            end
        end

        function test_DataFile_FromEditorForm(testCase)
            %The Sequence Editor's Data File form: folder + name gives a path; an empty
            %name gives no path (resume with the current file name), not the folder
            ce = Palladium.Sequence.CommandEncoder();
            details = struct("Type", "DATAFILE", "Directory", "C:\Data", "FileName", "Run2.dat", "WriteToFile", true);
            testCase.verifyEqual(ce.BuildCommandFromEventDetails(details).DataFilePath, "C:\Data\Run2.dat");

            details.FileName = "  ";
            com = ce.BuildCommandFromEventDetails(details);
            testCase.verifyTrue(com.WriteToFile);
            testCase.verifyEqual(com.DataFilePath, "");

            details.WriteToFile = false;
            com = ce.BuildCommandFromEventDetails(details);
            testCase.verifyFalse(com.WriteToFile);
            testCase.verifyEqual(com.DataFilePath, "");
        end

        function test_DataFile_Descriptions(testCase)
            testCase.verifyEqual(Palladium.Sequence.Commands.DataFileCommand(true, DataFilePath="C:\Data\Run2.dat").GetDescription(), "Write to: C:\Data\Run2.dat");
            testCase.verifyEqual(Palladium.Sequence.Commands.DataFileCommand(true).GetDescription(), "Write Enable (current file name)");
            testCase.verifyEqual(Palladium.Sequence.Commands.DataFileCommand(false).GetDescription(), "Write Disable");
        end


    end

end