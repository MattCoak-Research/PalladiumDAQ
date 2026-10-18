classdef test_LakeshoreCommandNumbers < matlab.unittest.TestCase
    %TEST_LAKESHORECOMMANDNUMBERS Tests the numbers the Lakeshore drivers send: each to the digits its manual's command format shows
    %A Lakeshore's number fields are a fixed width (e.g. the 350's SETP is
    %+-nnnnnn, its ramp rate nnnn) and it ignores commands it can't parse,
    %so each value is sent to that many significant figures (the 340's
    %manual gives no widths - "floating point format" - so it gets full
    %precision). They were sent with num2str, about 5 significant figures
    %whatever the field. The drivers are given a fake connection
    %(FakeDeviceHandle) that records what they send.

    %% Properties (TestParameter)
    properties (TestParameter)
        %Digits per field, from each manual's command Format lines: SETP, P, I, D, MOUT, RAMP rate (15 = no limit)
        Model = struct( ...
            "LS331", struct("Number", "331", "Widths", [6 6 6 6 6 5]), ...
            "LS340", struct("Number", "340", "Widths", [15 15 15 15 15 15]), ...
            "LS350", struct("Number", "350", "Widths", [6 5 5 4 5 4]), ...
            "LS370", struct("Number", "370", "Widths", [6 6 6 6 6 5]), ...
            "LS372", struct("Number", "372", "Widths", [6 6 6 6 5 5]));
    end

    properties (Constant)
        Values = [1.23456789012345, 12.3456789012345, 23.4567890123456, 3.45678901234567, 12.3456789012345, 1.23456789012345];   %SETP, P, I, D, MOUT, RAMP rate - more digits than any field
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function SetpointTest(testCase, Model)
            [instr, connection] = testCase.makeInstrument(Model);
            args = testCase.channelArgs(instr, Model, "Heater");

            instr.SetHeaterSetpoint(args{:}, testCase.Values(1));

            testCase.verifyCommand(connection, "SETP", testCase.expected(Model, 1));
        end

        function PIDTest(testCase, Model)
            [instr, connection] = testCase.makeInstrument(Model);
            args = testCase.channelArgs(instr, Model, "Loop");

            instr.SetPIDValues(args{:}, testCase.Values(2), testCase.Values(3), testCase.Values(4));

            testCase.verifyCommand(connection, "PID", testCase.expected(Model, 2) + "," + testCase.expected(Model, 3) + "," + testCase.expected(Model, 4));
        end

        function ManualOutputTest(testCase, Model)
            [instr, connection] = testCase.makeInstrument(Model);
            args = testCase.channelArgs(instr, Model, "Loop");

            instr.SetManualOutputPercent(args{:}, testCase.Values(5));

            testCase.verifyCommand(connection, "MOUT", testCase.expected(Model, 5));
        end

        function RampTest(testCase, Model)
            [instr, connection] = testCase.makeInstrument(Model);
            args = testCase.channelArgs(instr, Model, "Ramp");

            instr.SetRamp(args{:}, true, testCase.Values(6));

            testCase.verifyCommand(connection, "RAMP", "1," + testCase.expected(Model, 6));
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~, model)
            %The driver, given a fake connection as if connected
            instr = InstrumentTestingInstruments.("RecordingLakeshore" + model.Number)();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
        end

        function args = channelArgs(~, instr, model, method)
            %The channel argument a method takes before its values, if any
            args = {};
            switch model.Number
                case "340"
                    if method == "Loop"
                        args = {instr.Channel("A")};
                    end
                case "350"
                    args = {instr.OutputChannel("Ch1")};
            end
        end

        function str = expected(testCase, model, field)
            %The value of a field (1 to 6, see Values), as the manual's format allows
            str = string(sprintf("%.*G", model.Widths(field), testCase.Values(field)));
        end

        function verifyCommand(testCase, connection, keyword, endText)
            %The last command starting with keyword ends with endText
            commands = connection.WrittenCommands(startsWith(connection.WrittenCommands, keyword + " "));
            testCase.assertNotEmpty(commands, "No " + keyword + " command sent: " + join(connection.WrittenCommands, " | "));
            testCase.verifyTrue(endsWith(commands(end), endText), commands(end) + " should end with " + endText);
        end
    end
end
