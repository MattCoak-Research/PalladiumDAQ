classdef test_CommandController < matlab.unittest.TestCase
    %TEST_COMMANDCONTROLLER Tests running sequence instrument commands: how a command such as Record(10, "Sample A") becomes a method call with those arguments

    %% Properties
    properties
        Controller;     %The CommandController under test
        Instrument;     %A TestHelpers.RecordingInstrument, which records its arguments
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function helpersPath(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "..", "Helpers")));
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function setup(testCase)
            testCase.Controller = Palladium.Core.CommandController();
            testCase.Instrument = TestHelpers.RecordingInstrument();
        end
    end

    %% Methods (Test)
    methods (Test)
        function NumbersAndLogicals(testCase)
            testCase.runCommand("Record(10, -2.5e-3, true, FALSE)");
            testCase.verifyEqual(testCase.Instrument.LastArgs, {10, -2.5e-3, true, false});
        end

        function QuotedTextKeptExactly(testCase)
            %Quoted text keeps its spaces, commas and colons, and isn't read as a number
            testCase.runCommand("Record(""Sample A, run 2"", 'C:\Data\run.dat', ""10"")");
            testCase.verifyEqual(testCase.Instrument.LastArgs, {"Sample A, run 2", "C:\Data\run.dat", "10"});
        end

        function UnquotedTextKeepsInnerSpaces(testCase)
            %Unquoted text is trimmed, but keeps spaces inside it (they used to be removed)
            testCase.runCommand("Record(  Sample A  , 3 )");
            testCase.verifyEqual(testCase.Instrument.LastArgs, {"Sample A", 3});
        end

        function NoArguments(testCase)
            %With or without brackets, and with a trailing semicolon
            for cmd = ["RecordNothing()", "RecordNothing", " RecordNothing ( ) ;"]
                testCase.Instrument.LastCall = "";
                testCase.runCommand(cmd);
                testCase.verifyEqual(testCase.Instrument.LastCall, "RecordNothing", cmd);
            end
        end

        function ManyArguments(testCase)
            %8 or more arguments used to fail (the 8th argument's internal name was "h,")
            testCase.runCommand("Record(1, 2, 3, 4, 5, 6, 7, 8, 9)");
            testCase.verifyEqual(testCase.Instrument.LastArgs, num2cell(1:9));
        end

        function InvalidCommandsError(testCase)
            testCase.verifyError(@() testCase.runCommand("Record(""unclosed)"), "SplitArgumentsError:UnclosedQuote");
            testCase.verifyError(@() testCase.runCommand("Record(1, , 2)"), "SplitArgumentsError:EmptyArgument");
            testCase.verifyError(@() testCase.runCommand("Record(1"), "ParseCommandStringError:MissingBracket");
            testCase.verifyError(@() testCase.runCommand("Re cord(1)"), "ParseCommandStringError:InvalidMethodName");
            testCase.verifyError(@() testCase.runCommand("other.Record(1)"), "ParseCommandStringError:InvalidMethodName");
        end

        function CommandIsNotRunAsCode(testCase)
            %Commands used to be built into MATLAB code and run. Now only a
            %method of the instrument can be called - here "disp", which the
            %instrument doesn't have, so it errors rather than printing
            testCase.verifyError(@() testCase.runCommand("disp('x'); Record(1)"), "MATLAB:class:UndefinedMethod");
            testCase.verifyEqual(testCase.Instrument.LastCall, "", "Record should not have been called");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function runCommand(testCase, commandString)
            %Run an instrument command on the recording instrument, as a sequence does
            command = Palladium.Sequence.Commands.InstrumentCommand(testCase.Instrument, commandString);
            testCase.Controller.ExecuteCommand(command);
        end
    end
end
