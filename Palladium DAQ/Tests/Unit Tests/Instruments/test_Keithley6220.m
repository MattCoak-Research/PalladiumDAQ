classdef test_Keithley6220 < matlab.unittest.TestCase
    %TEST_KEITHLEY6220 Tests the Keithley 6220 driver: units read from the instrument, repeated Delta readings, and without Delta mode
    %From the 6220 Reference Manual. The driver is given a fake connection
    %(FakeDeviceHandle), through the RecordingKeithley6220 test subclass.

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function ConnectingReadsUnitsAndAddsReadingNumbersTest(testCase)
            %Units used to only label the column - never read from the instrument
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("UNIT?") = "V";

            evalc("instr.OnConnectedForTest()");

            testCase.verifyEqual(connection.WrittenCommands, "FORM:ELEM READ,RNUM");
            testCase.verifyEqual(string(instr.Units), "Volts");
            testCase.verifyEqual(instr.GetHeaders(), "K6220 - Volts (V)");
        end

        function EachUnitsReplyTest(testCase)
            replies = ["V", "OHMS", "W", "SIEM"];
            units = ["Volts", "Ohms", "Watts", "Siemens"];
            for i = 1:numel(replies)
                [instr, connection] = testCase.makeInstrument();
                connection.QueryResponses("UNIT?") = replies(i);
                evalc("instr.OnConnectedForTest()");
                testCase.verifyEqual(string(instr.Units), units(i), replies(i));
            end
        end

        function UnexpectedUnitsStopConnectingTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("UNIT?") = "XYZ";
            testCase.verifyError(@() instr.OnConnectedForTest(), "Keithley6220:UnexpectedUnits");
        end

        function RepeatedReadingIsNaNTest(testCase)
            %SENS:DATA? returns the latest reading again if there is no new
            %one - it used to be recorded again
            [instr, connection] = testCase.makeInstrument();

            connection.QueryResponses("SENS:DATA?") = "+1.23456789E-03,+00001RDNG#";
            first = instr.Measure();
            again = instr.Measure();
            connection.QueryResponses("SENS:DATA?") = "+1.30000000E-03,+00002RDNG#";
            next = instr.Measure();

            testCase.verifyEqual(first, 1.23456789e-3, RelTol=1e-12);
            testCase.verifyEqual(again, NaN, "The same reading");
            testCase.verifyEqual(next, 1.3e-3, RelTol=1e-12);
        end

        function ReadingNumbersStartAgainOnConnectingTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("UNIT?") = "OHMS";
            connection.QueryResponses("SENS:DATA?") = "+17.0,+00001";
            instr.Measure();

            evalc("instr.OnConnectedForTest()");

            testCase.verifyEqual(instr.Measure(), 17, "Reading 1 of the new connection is new");
        end

        function OverflowIsNaNTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("SENS:DATA?") = "+9.9E37,+00003";
            testCase.verifyEqual(instr.Measure(), NaN);
        end

        function WithoutDeltaModeRecordsTheSourceCurrentTest(testCase)
            %This used to raise "Not implemented"
            [instr, connection] = testCase.makeInstrument();
            instr.DeltaMode = false;
            connection.QueryResponses("SOUR:CURR?") = "1.0E-04";

            [headers, units] = instr.GetHeaders();
            evalc("instr.OnConnectedForTest()");
            value = instr.Measure();

            testCase.verifyEqual(headers, "K6220 - Source Current (A)");
            testCase.verifyEqual(units, "A");
            testCase.verifyEqual(value, 1e-4);
            testCase.verifyEmpty(connection.WrittenCommands, "No Delta mode set-up");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~)
            %The driver, given a fake connection as if connected
            instr = InstrumentTestingInstruments.RecordingKeithley6220();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
        end
    end
end
