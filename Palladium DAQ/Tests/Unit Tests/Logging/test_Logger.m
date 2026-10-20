classdef test_Logger < matlab.unittest.TestCase
    % TEST_LOGGER Tests for Palladium.Logging.Logger - where messages go,
    % and that logging and error handling never fail themselves. The
    % Logger keeps its settings between calls (persistent), so each test
    % sets them up, and they are switched off again afterwards.

    %% Properties
    properties
        LogDir;         %Fresh folder for each test's log file, inside Testing Data Files
        LogFileName = "test.log";
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function HelpersPathSetup(testCase)
            %Test helpers, which keep everything the tests write inside Testing Data Files
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "..", "Helpers")));
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function CreateLogFolder(testCase)
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            testCase.LogDir = string(fixture.Folder);

            %Afterwards: no dialogue answers left set, and logging off, as
            %other tests expect
            testCase.addTeardown(@() Palladium.Logging.Logger.TestDialogResponse("set", ""));
            testCase.addTeardown(@() testCase.configure(CommandWindow="Off", LogFile="Off", LogDir=""));
        end
    end

    %% Tests
    methods (Test)

        %% Log
        function MessagesBelowTheCutoffAreNotShownTest(testCase)
            testCase.configure(CommandWindow="Warning", LogFile="Off");

            output = evalc("Palladium.Logging.Logger.Log(""Info"", ""quiet info""); Palladium.Logging.Logger.Log(""Warning"", ""loud warning"")");

            testCase.verifyFalse(contains(output, "quiet info"));
            testCase.verifySubstring(output, "loud warning");
        end

        function LogFileGetsEachMessageOnceWithABlankLineTest(testCase)
            %The message and the blank line after it are one write - written
            %separately, a failed second write repeated the message on retry
            testCase.configure(CommandWindow="Off", LogFile="Debug");

            Palladium.Logging.Logger.Log("Info", "hello file");

            lines = readlines(testCase.logPath(), EmptyLineRule="read");
            idx = find(contains(lines, "hello file"));
            testCase.verifyNumElements(idx, 1);
            testCase.verifyTrue(startsWith(lines(idx), "[INFO]"));
            testCase.verifyEqual(lines(idx + 1), "");
        end

        function UncreatableLogFolderDoesNotThrowTest(testCase)
            %Logging is used while handling errors, so must never throw. A
            %log folder that can't be made used to make every call throw;
            %now it is reported once, and messages still go elsewhere
            blocker = fullfile(testCase.LogDir, "blocker.txt");
            writelines("Not a folder", blocker);
            gui = testCase.configure(CommandWindow="Info", LogFile="Debug", LogDir=fullfile(blocker, "Logs"), GUI="Warning");

            output = "";
            testCase.verifyWarningFree(@() logTwice());

            testCase.verifyEqual(nnz(contains(gui.Messages, "can't be written to the log file")), 1, join(gui.Messages, newline));
            testCase.verifySubstring(output, "first");
            testCase.verifySubstring(output, "second");

            function logTwice()
                output = evalc("Palladium.Logging.Logger.Log(""Info"", ""first""); Palladium.Logging.Logger.Log(""Info"", ""second"")");
            end
        end

        function UnwritableLogFileIsReportedOnceTest(testCase)
            %A log file that can't be written (here the name is a folder) is
            %reported once, rather than messages being lost without trace
            mkdir(fullfile(testCase.LogDir, testCase.LogFileName));
            gui = testCase.configure(CommandWindow="Off", LogFile="Debug", GUI="Warning");

            Palladium.Logging.Logger.Log("Info", "one");
            Palladium.Logging.Logger.Log("Info", "two");

            testCase.verifyEqual(nnz(contains(gui.Messages, "can't be written to the log file")), 1, join(gui.Messages, newline));
        end

        function FirstMessageBeforeSetUpDoesNotFixTheLevelsTest(testCase)
            %Before Palladium creates the Logger, the defaults apply whatever
            %the first call passes. A LogError first (which passed "Error"
            %for every level) used to hide every later Info message
            Palladium.Logging.Logger.ResetForTest();

            evalc("Palladium.Logging.Logger.LogError(MException(""Test:First"", ""first error""), ""before set-up"")");
            output = evalc("Palladium.Logging.Logger.Log(""Info"", ""later info"")");

            testCase.verifySubstring(output, "later info");
        end

        function ResetForTestGoesBackToTheDefaultsTest(testCase)
            %Command Window from Debug up, and no log file
            testCase.configure(CommandWindow="Off", LogFile="Debug");
            Palladium.Logging.Logger.ResetForTest();

            output = evalc("Palladium.Logging.Logger.Log(""Debug"", ""after reset"")");

            testCase.verifySubstring(output, "after reset");
            testCase.verifyFalse(contains(fileread(testCase.logPath()), "after reset"), "No log file before set-up");
        end

        %% LogError
        function LogErrorWithoutMessageIsLoggedTest(testCase)
            %The message is optional - without one, nothing used to be
            %logged ("text" + [] is an empty string array)
            testCase.configure(CommandWindow="Off", LogFile="Debug");

            testCase.verifyWarningFree(@() Palladium.Logging.Logger.LogError(MException("Test:Boom", "boom")));

            logText = fileread(testCase.logPath());
            testCase.verifySubstring(logText, "boom");
            testCase.verifyFalse(contains(logText, "boom :"), "No separator without a message");
        end

        function LogErrorWithMessageAddsItTest(testCase)
            %In the log file too - it used to get only the error's report,
            %without what was happening (e.g. "Error in main measurement loop")
            testCase.configure(CommandWindow="Off", LogFile="Debug");

            Palladium.Logging.Logger.LogError(MException("Test:Boom", "boom"), "while testing");

            testCase.verifySubstring(fileread(testCase.logPath()), "boom : while testing");
        end

        %% HandleError
        function HandleErrorWithUnthrownErrorTest(testCase)
            %An error created but never thrown has no stack. It used to
            %crash with "Index exceeds array bounds"
            testCase.configure(CommandWindow="Off", LogFile="Off");
            err = MException("Test:Unthrown", "never thrown");

            Palladium.Logging.Logger.TestDialogResponse("set", "Ignore");
            [halt, suppress] = Palladium.Logging.Logger.HandleError("Testing", err, []);
            testCase.verifyFalse(halt);
            testCase.verifyFalse(suppress);

            %Go to Code has no code to go to - stops, without trying to open a file
            Palladium.Logging.Logger.TestDialogResponse("set", "Stop & Go to Code");
            halt = [];
            testCase.verifyWarningFree(@() answer());
            testCase.verifyTrue(halt);

            function answer()
                evalc("halt = Palladium.Logging.Logger.HandleError(""Testing"", err, [])");
            end
        end

        function HandleErrorReturnsTheChoiceTest(testCase)
            testCase.configure(CommandWindow="Off", LogFile="Off");
            try
                error("Test:Thrown", "thrown error");
            catch err
            end

            Palladium.Logging.Logger.TestDialogResponse("set", "Stop Measurements");
            testCase.verifyTrue(Palladium.Logging.Logger.HandleError("Testing", err, []));
            testCase.verifyEqual(Palladium.Logging.Logger.TestDialogResponse("count"), 1);

            Palladium.Logging.Logger.TestDialogResponse("set", "Suppress Error");
            [halt, suppress] = Palladium.Logging.Logger.HandleError("Testing", err, []);
            testCase.verifyFalse(halt);
            testCase.verifyTrue(suppress);
        end

        function TestAnsweredErrorPrintsWhereItWasTest(testCase)
            %When a test answers the error dialogue, the full report is
            %printed - the dialogue would have shown where the error was,
            %and the log has only the message, so intermittent failures in
            %test runs left no clue where they happened
            testCase.configure(CommandWindow="Off", LogFile="Off");
            try
                throwFromHere();
            catch err
            end
            Palladium.Logging.Logger.TestDialogResponse("set", "Ignore");

            output = evalc("Palladium.Logging.Logger.HandleError(""Testing"", err, [])");

            testCase.verifySubstring(output, "Error dialogue answered by the test (""Ignore"")");
            testCase.verifySubstring(output, "thrown from here");
            testCase.verifySubstring(output, "throwFromHere", "The function it was thrown in");

            function throwFromHere()
                error("Test:Thrown", "thrown from here");
            end
        end

    end

    %% Methods (Private)
    methods (Access = private)
        function gui = configure(testCase, Settings)
            %Set the Logger up as the Controller does. gui records what reaches the GUI
            arguments
                testCase;
                Settings.CommandWindow = "Off";
                Settings.LogFile = "Debug";
                Settings.LogDir = testCase.LogDir;
                Settings.GUI = "Off";
            end
            gui = TestHelpers.RecordingController();
            Palladium.Logging.Logger.Log("Debug", "Logger set up for test", "Controller", gui, ...
                "LogFileDirectory", Settings.LogDir, "LogFileFileName", testCase.LogFileName, ...
                "CommandWindowMessageLevel", Settings.CommandWindow, "GUIMessageLevel", Settings.GUI, "LogFileMessageLevel", Settings.LogFile);
        end

        function path = logPath(testCase)
            path = fullfile(testCase.LogDir, testCase.LogFileName);
        end
    end
end
