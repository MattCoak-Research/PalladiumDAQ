classdef test_HP8722ES < matlab.unittest.TestCase
    %TEST_HP8722ES Tests the HP 8722ES driver's sweep, as the Scan Control runs it: start, check for completion, read the data
    %Commands from the 8719ES/8720ES/8722ES Programmer's Guide. The driver
    %is given a fake connection (FakeDeviceHandle): a line in its ReadQueue
    %stands for a reply waiting, as a serial poll would show.

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function RunScanSelectsAndStartsOneSweepTest(testCase)
            %There was no RunScan, so the Scan Control errored
            [instr, connection] = testCase.makeInstrument();
            instr.MeasMode = instr.MeasType("S21");
            instr.MeasUnit = instr.MeasUnitType("Absolute");

            instr.RunScan();

            testCase.verifyEqual(connection.ClearCount, 1, "Any reply left from an aborted sweep is cleared first");
            testCase.verifyEqual(connection.WrittenCommands, ["S21;", "LINM;", "OPC?;SING;"]);
        end

        function DisplayFormatFollowsMeasUnitTest(testCase)
            %MeasUnit used to only label the column
            [instr, connection] = testCase.makeInstrument();
            instr.MeasUnit = instr.MeasUnitType("dB");

            instr.RunScan();

            testCase.verifyEqual(connection.WrittenCommands(2), "LOGM;");
        end

        function CompleteOnceTheReplyIsWaitingTest(testCase)
            %Checked each tick without waiting: done once OPC?'s "1" has arrived
            [instr, connection] = testCase.makeInstrument();
            instr.RunScan();

            testCase.verifyFalse(instr.CheckScanComplete(), "Sweep still running");

            connection.ReadQueue = "1";
            testCase.verifyTrue(instr.CheckScanComplete());
            testCase.verifyEmpty(connection.ReadQueue, "The reply is read");
            testCase.verifyTrue(instr.CheckScanComplete(), "Stays complete");
        end

        function ScanDataIsFrequencyAndValueTest(testCase)
            %ASCII trace (two values per point - the first is the value) and
            %the frequency of each point (the first of four limit-test values)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTPFORM;") = "-1.5,0,-2.5,0,-3.5,0";
            connection.QueryResponses("OUTPLIML;") = "5E7,0,0,0,1E8,0,0,0,2E8,0,0,0";

            data = instr.GetCompletedScanData();

            testCase.verifyEqual(connection.WrittenCommands, "FORM4;");
            testCase.verifyEqual(data, [5e7, -1.5; 1e8, -2.5; 2e8, -3.5]);
        end

        function MismatchedLengthsErrorTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTPFORM;") = "-1.5,0,-2.5,0";
            connection.QueryResponses("OUTPLIML;") = "5E7,0,0,0";

            testCase.verifyError(@() instr.GetCompletedScanData(), "HP_8722ES_NetworkAnalyser:DataSizeMismatch");
        end

        function ScanHeadersTest(testCase)
            instr = Palladium.Instruments.HP_8722ES_NetworkAnalyser();
            instr.MeasMode = instr.MeasType("S21");

            [headers, units] = instr.GetScanHeaders();

            testCase.verifyEqual(headers, "HP_8722ES_NetworkAnalyser - " + ["Frequency_Hz", "S21 (dB)"]);
            testCase.verifyEqual(units, ["Hz", "dB"]);
        end

        function SimulatedScanTest(testCase)
            %In Debug mode: a scan completes within a few checks, with data for each point
            instr = Palladium.Instruments.HP_8722ES_NetworkAnalyser();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("instr.Connect()");

            instr.RunScan();
            for k = 1:500
                if instr.CheckScanComplete(); break; end
            end
            data = instr.GetCompletedScanData();

            testCase.verifyTrue(instr.CheckScanComplete());
            testCase.verifySize(data, [20, 2]);
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~)
            %The driver, given a fake connection as if connected
            instr = InstrumentTestingInstruments.RecordingHP8722ES();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
        end
    end
end
