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

        function RunScanSelectsAMeasurementThenTriggersTest(testCase)
            %CALCulate commands act on the selected measurement - with none
            %selected, the analyser showed error -420 "Query UNTERMINATED"
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("CALC1:PAR:CAT?") = """CH1_S11_1,S11,CH1_S21_2,S21""";
            instr.MeasMode = instr.MeasType("S21");

            instr.RunScan();

            testCase.verifyEqual(connection.WrittenCommands, ["CALC:PAR:SEL ""CH1_S21_2""", "CALC1:FORM MLOG", "SENS1:SWE:MODE SINGle"]);
        end

        function NoMeasurementOfTheSParameterChangesTheFirstTest(testCase)
            %The user's choice: change the first measurement on channel 1, rather than create one
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("CALC1:PAR:CAT?") = """CH1_S11_1,S11""";
            instr.MeasMode = instr.MeasType("S22");

            instr.RunScan();

            testCase.verifyEqual(connection.WrittenCommands(1:2), ["CALC:PAR:SEL ""CH1_S11_1""", "CALC1:PAR:MOD S22"]);
        end

        function NoMeasurementAtAllErrorsTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("CALC1:PAR:CAT?") = """""";
            testCase.verifyError(@() instr.RunScan(), "PNA_L_NetworkAnalyser:NoMeasurement");
            testCase.verifyEmpty(connection.WrittenCommands, "No sweep started");
        end

        function RunScanAppliesTheSettingsTest(testCase)
            %The VNA Control's settings; others (the file settings) are ignored
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("CALC1:PAR:CAT?") = """CH1_S11_1,S11""";
            settings = struct("StartFrequency_Hz", 1e7, "StopFrequency_Hz", 6e9, "NumPoints", 401, ...
                "SweepTime_s", 0.5, "SweepType", "Log", "MeasMode", "S11", "MeasUnit", "Absolute", ...
                "SaveSweepFile", true, "FileName", "x");

            instr.RunScan(settings);

            testCase.verifyEqual(connection.WrittenCommands, ["SENSe1:FREQuency:STARt 10000000", "SENSe1:FREQuency:STOP 6000000000", ...
                "SENS:SWE:POIN 401", "SENS1:SWE:TIME 0.5", "SENS:SWE:TYPE LOG", "CALC:PAR:SEL ""CH1_S11_1""", "CALC1:FORM MLIN", ...
                "SENS1:SWE:MODE SINGle"]);
            testCase.verifyEqual(string(instr.MeasUnit), "Absolute");
        end

        function ZeroSweepTimeIsAutomaticTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            instr.SetSweepTime(0);
            testCase.verifyEqual(connection.WrittenCommands, "SENS1:SWE:TIME:AUTO ON");
        end

        function GetScanSettingsReadsTheAnalyserTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            replies = ["SENSe1:FREQuency:STARt?", "3E5"; "SENSe1:FREQuency:STOP?", "2E10"; "SENS:SWE:POIN?", "201"; ...
                "SENS1:SWE:TIME:AUTO?", "1"; "SENS:SWE:TYPE?", "LIN"; "CALC1:PAR:CAT?", """CH1_S11_1,S11,CH1_S21_2,S21"""; ...
                "CALC:PAR:SEL?", """CH1_S21_2"""; "CALCulate1:FORMat?", "MLIN"];
            for i = 1:height(replies)
                connection.QueryResponses(replies(i, 1)) = replies(i, 2);
            end

            settings = instr.GetScanSettings();

            testCase.verifyEqual(settings, struct("StartFrequency_Hz", 3e5, "StopFrequency_Hz", 2e10, "NumPoints", 201, ...
                "SweepTime_s", 0, "SweepType", "Linear", "MeasMode", "S21", "MeasUnit", "Absolute"), "Automatic sweep time is 0");
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

        function RealImaginaryUnitsSetThePolarFormatTest(testCase)
            %A Smith chart needs the real and imaginary parts - polar format gives them
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("CALC1:PAR:CAT?") = """CH1_S11_1,S11""";
            instr.MeasUnit = instr.MeasUnitType("Real/Imaginary");

            instr.RunScan();

            testCase.verifyEqual(connection.WrittenCommands(2), "CALC1:FORM POL");
        end

        function RealImaginarySimulatedScanTest(testCase)
            %In Debug mode: three columns (frequency, real, imaginary) inside the Smith chart, with headers to match
            instr = Palladium.Instruments.PNA_L_NetworkAnalyser();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            instr.MeasUnit = instr.MeasUnitType("Real/Imaginary");
            evalc("instr.Connect()");

            instr.RunScan();
            pause(0.3);
            data = instr.GetCompletedScanData();
            headers = instr.GetScanHeaders();

            testCase.verifySize(data, [20, 3]);
            testCase.verifyLessThan(max(hypot(data(:, 2), data(:, 3))), 1);
            testCase.verifyEqual(headers, "PNA - " + ["Frequency_Hz", "S11 Real", "S11 Imaginary"]);
            testCase.verifyEqual(string(instr.GetScanSettings().MeasUnit), "Real/Imaginary");
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

        function SimulatedScanFollowsTheSettingsTest(testCase)
            %In Debug mode the settings are kept, and the scan follows them
            instr = Palladium.Instruments.PNA_L_NetworkAnalyser();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("instr.Connect()");

            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11, "SweepType", "Linear", "MeasMode", "S12"));
            pause(0.3);
            data = instr.GetCompletedScanData();
            settings = instr.GetScanSettings();

            testCase.verifyEqual(data(:, 1)', linspace(1e6, 2e6, 11));
            testCase.verifyEqual([settings.StartFrequency_Hz, settings.StopFrequency_Hz, settings.NumPoints], [1e6, 2e6, 11]);
            testCase.verifyEqual(settings.MeasMode, "S12");
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
