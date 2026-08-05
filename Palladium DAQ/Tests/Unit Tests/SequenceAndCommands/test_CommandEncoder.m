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


    end

end