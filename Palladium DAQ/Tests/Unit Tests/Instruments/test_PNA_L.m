classdef test_PNA_L < matlab.unittest.TestCase
    %TEST_PNA_L Tests the Keysight PNA-L driver's sweep, as the Scan Control runs it, and its sweep settings
    %Commands from the PNA Help (Programming Guide). The driver is given a
    %fake connection (FakeDeviceHandle), through the RecordingPNA_L test
    %subclass.

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function NoUSBConnectionTest(testCase)
            %"Use of the PNA as a USB Device is not supported"
            instr = Palladium.Instruments.PNA_L_NetworkAnalyser();
            testCase.verifyFalse(any(instr.GetSupportedConnectionTypes() == Palladium.Enums.ConnectionType.USB));
        end

        function RunScanTriggersOneSweepTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            instr.RunScan();
            testCase.verifyEqual(connection.WrittenCommands, "SENS1:SWE:MODE SINGle");
        end

        function TriggerAndWaitPollsForHoldTest(testCase)
            %It used to wait on *OPC?, which timed out (3 s) on longer sweeps
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("SENS1:SWE:TIME?") = "1.5";
            connection.QueryResponses("SENS1:SWEep:MODE?") = "HOLD";

            instr.TriggerSingle(true);

            testCase.verifyEqual(connection.WrittenCommands, "SENS1:SWE:MODE SINGle");
            testCase.verifyFalse(any(contains(connection.QueriedCommands, "*OPC?")));
        end

        function SweepTypeNamesMatchSetSweepTypeTest(testCase)
            %GetSweepType returned LIN/LOG, but SetSweepType takes Linear/Log
            replies = ["LIN", "LOG", "POW", "CW", "SEGM"];
            names = ["Linear", "Log", "Power", "CW", "Segment"];
            for i = 1:numel(replies)
                [instr, connection] = testCase.makeInstrument();
                connection.QueryResponses("SENS:SWE:TYPE?") = replies(i);
                testCase.verifyEqual(instr.GetSweepType(), names(i), replies(i));
            end

            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("SENS:SWE:TYPE?") = "LIN";
            instr.SetSweepType(instr.GetSweepType());
            testCase.verifyEqual(connection.WrittenCommands, "SENS:SWE:TYPE LIN", "Round trip");
        end

        function ScanDataIsFrequencyAndValueTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("CALCulate1:DATA? FDATA") = "-1.5,-2.5,-3.5";
            connection.QueryResponses("SENS:X?") = "1E6,2E6,3E6";

            data = instr.GetCompletedScanData();

            testCase.verifyEqual(data, [1e6, -1.5; 2e6, -2.5; 3e6, -3.5]);
        end

        function PolarScanHasRealAndImaginaryColumnsTest(testCase)
            %Polar and Smith formats give two values per point
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("CALCulate1:DATA? FDATA") = "0.1,0.2,0.3,0.4";
            connection.QueryResponses("SENS:X?") = "1E6,2E6";
            connection.QueryResponses("CALCulate1:FORMat?") = "POL";

            data = instr.GetCompletedScanData();
            [headers, units] = instr.GetScanHeaders();

            testCase.verifyEqual(data, [1e6, 0.1, 0.2; 2e6, 0.3, 0.4]);
            testCase.verifyEqual(headers, "PNA - " + ["Frequency_Hz", "S11 Real", "S11 Imaginary"]);
            testCase.verifyEqual(units, ["Hz", "", ""]);
        end

        function OneValueFormatHeadersTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("CALCulate1:FORMat?") = "MLOG";

            [headers, units] = instr.GetScanHeaders();

            testCase.verifyEqual(headers, "PNA - " + ["Frequency_Hz", "S11 (dB)"]);
            testCase.verifyEqual(units, ["Hz", ""]);
        end

        function MismatchedLengthsErrorTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("CALCulate1:DATA? FDATA") = "-1.5,-2.5,-3.5";
            connection.QueryResponses("SENS:X?") = "1E6,2E6";

            testCase.verifyError(@() instr.GetCompletedScanData(), "PNA_L_NetworkAnalyser:DataSizeMismatch");
        end

        function SimulatedScanTest(testCase)
            %In Debug mode: a sweep takes 0.2 s, then the scan has data for each point
            instr = Palladium.Instruments.PNA_L_NetworkAnalyser();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("instr.Connect()");

            instr.RunScan();
            testCase.verifyFalse(instr.CheckScanComplete(), "Just started");
            pause(0.3);
            data = instr.GetCompletedScanData();

            testCase.verifyTrue(instr.CheckScanComplete());
            testCase.verifySize(data, [20, 2]);
            testCase.verifyEqual(instr.GetSweepType(), "Linear");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~)
            %The driver, given a fake connection as if connected
            instr = InstrumentTestingInstruments.RecordingPNA_L();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
        end
    end
end
