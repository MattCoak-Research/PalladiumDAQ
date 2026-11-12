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

            instr.RunScan(struct("MeasMode", "S21", "MeasUnit", "Absolute"));

            testCase.verifyEqual(connection.ClearCount, 1, "Any reply left from an aborted sweep is cleared first");
            testCase.verifyEqual(connection.WrittenCommands, ["S21;", "LINM;", "OPC?;NUMG1;"]);
        end

        function DisplayFormatFollowsMeasUnitTest(testCase)
            %MeasUnit used to only label the column
            [instr, connection] = testCase.makeInstrument();

            instr.RunScan(struct("MeasUnit", "dB"));

            testCase.verifyEqual(connection.WrittenCommands(2), "LOGM;");
        end

        function RealImaginaryUnitsSetThePolarFormatTest(testCase)
            %A Smith chart needs the real and imaginary parts - polar format gives them
            [instr, connection] = testCase.makeInstrument();

            instr.RunScan(struct("MeasUnit", "Real/Imaginary"));

            testCase.verifyEqual(connection.WrittenCommands(2), "POLA;");
        end

        function RealImaginaryScanDataHasThreeColumnsTest(testCase)
            %In polar format OUTPFORM gives the real and imaginary parts of each point
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("POIN?;") = "3";
            connection.QueryResponses("OUTPFORM;") = "0.1,0.2";
            connection.QueryResponses("OUTPLIML;") = "5E7,0,0,0";
            instr.RunScan(struct("MeasUnit", "Real/Imaginary"));
            connection.ReadQueue = "1";
            instr.CheckScanComplete();
            connection.ReadQueue = ["0.3,0.4", "0.5,0.6", "1E8,0,0,0", "2E8,0,0,0"];

            data = instr.GetCompletedScanData();
            [headers, units] = instr.GetScanHeaders();

            testCase.verifyEqual(data, [5e7, 0.1, 0.2; 1e8, 0.3, 0.4; 2e8, 0.5, 0.6]);
            testCase.verifyEqual(headers, instr.Name + " - " + ["Frequency_Hz", "S11 Real", "S11 Imaginary"]);
            testCase.verifyEqual(units, ["Hz", "", ""]);
        end

        function RealImaginarySimulatedScanTest(testCase)
            instr = Palladium.Instruments.HP_8722ES_NetworkAnalyser();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("instr.Connect()");

            instr.RunScan(struct("NumPoints", 51, "MeasUnit", "Real/Imaginary"));
            for k = 1:500
                if instr.CheckScanComplete(); break; end
            end
            data = instr.GetCompletedScanData();

            testCase.verifySize(data, [51, 3]);
            testCase.verifyLessThan(max(hypot(data(:, 2), data(:, 3))), 1);
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
            %the frequency of each point (the first of four limit-test values).
            %As the analyser sends them: the first line comes in answer to the
            %command, the rest are read after it
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("POIN?;") = "3";
            connection.QueryResponses("OUTPFORM;") = "-1.5,0";
            connection.QueryResponses("OUTPLIML;") = "5E7,0,0,0";

            %The limit test's lines follow the trace's in the analyser's output
            connection.ReadQueue = ["-2.5,0", "-3.5,0", "1E8,0,0,0", "2E8,0,0,0"];

            data = instr.GetCompletedScanData();

            testCase.verifyEqual(connection.WrittenCommands, "FORM4;");
            testCase.verifyEqual(data, [5e7, -1.5; 1e8, -2.5; 2e8, -3.5]);
            testCase.verifyEmpty(connection.ReadQueue, "Every line of both replies is read - none left for the next command");
        end

        function ScanDataIsAllPointsNotJustTheFirstTest(testCase)
            %A 201-point sweep gave one point: a single read got only the first line of the trace
            [instr, connection] = testCase.makeInstrument();
            numPoints = 201;
            frequency = linspace(5e7, 4e10, numPoints);
            value = -(1:numPoints) / 10;
            connection.QueryResponses("POIN?;") = string(numPoints);
            connection.QueryResponses("OUTPFORM;") = sprintf("%.15E,%.15E", value(1), 0);
            connection.QueryResponses("OUTPLIML;") = sprintf("%.15E,%.15E,%.15E,%.15E", frequency(1), 0, 0, 0);
            traceLines = compose("%.15E,%.15E", value(2:end)', zeros(numPoints - 1, 1))';
            limitLines = compose("%.15E,%.15E,%.15E,%.15E", frequency(2:end)', zeros(numPoints - 1, 3))';
            connection.ReadQueue = [traceLines, limitLines];

            data = instr.GetCompletedScanData();

            testCase.verifySize(data, [numPoints, 2]);
            testCase.verifyEqual(data(:, 1)', frequency, RelTol=1e-12);
            testCase.verifyEqual(data(:, 2)', value, RelTol=1e-12);
            testCase.verifyEmpty(connection.ReadQueue);
        end

        function MismatchedLengthsErrorTest(testCase)
            %The analyser sent fewer points than the sweep has
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("POIN?;") = "3";
            connection.QueryResponses("OUTPFORM;") = "-1.5,0";
            connection.QueryResponses("OUTPLIML;") = "5E7,0,0,0";
            connection.ReadQueue = ["-2.5,0", ""];     %Two points of the trace, then nothing more

            testCase.verifyError(@() instr.GetCompletedScanData(), "HP_8722ES_NetworkAnalyser:DataSizeMismatch");
        end

        function ScanHeadersTest(testCase)
            instr = Palladium.Instruments.HP_8722ES_NetworkAnalyser();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("instr.Connect()");
            instr.RunScan(struct("MeasMode", "S21"));

            [headers, units] = instr.GetScanHeaders();

            testCase.verifyEqual(headers, "HP_8722ES_NetworkAnalyser - " + ["Frequency_Hz", "S21 (dB)"]);
            testCase.verifyEqual(units, ["Hz", "dB"]);
        end

        function SimulatedScanTest(testCase)
            %In Debug mode: a scan completes within a few checks, with data for each point
            instr = Palladium.Instruments.HP_8722ES_NetworkAnalyser();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("instr.Connect()");

            instr.RunScan(struct("NumPoints", 51));
            for k = 1:500
                if instr.CheckScanComplete(); break; end
            end
            data = instr.GetCompletedScanData();

            testCase.verifyTrue(instr.CheckScanComplete());
            testCase.verifySize(data, [51, 2]);
        end

        function RunScanAppliesTheSettingsTest(testCase)
            %The VNA Control's settings, from the Programmer's Guide - numbers
            %without exponents, as the guide doesn't say they're accepted
            [instr, connection] = testCase.makeInstrument();
            settings = struct("StartFrequency_Hz", 1.5e9, "StopFrequency_Hz", 2e10, "NumPoints", 150, ...
                "SweepTime_s", 0.25, "SweepType", "Log", "MeasMode", "S21", "MeasUnit", "dB", ...
                "SaveSweepFile", true, "FileName", "x");
            connection.QueryResponses("POIN?;") = "101";

            instr.RunScan(settings);

            testCase.verifyEqual(connection.WrittenCommands, ["STAR1500000000HZ;", "STOP20000000000HZ;", "POIN101;", ...
                "SWET0.250000S;", "LOGFREQ;", "S21;", "LOGM;", "OPC?;NUMG1;"], "150 points is nearest 101 of the analyser's choices");
            testCase.verifyEqual(string(instr.MeasMode), "S21");
        end

        function ZeroSweepTimeIsAutomaticTest(testCase)
            %SWET0 is the same as SWEA (automatic)
            [instr, connection] = testCase.makeInstrument();
            instr.RunScan(struct("SweepTime_s", 0));
            testCase.verifyEqual(connection.WrittenCommands(1), "SWET0.000000S;");
        end

        function SettingsAreAnsweredFromMemoryDuringASweepTest(testCase)
            %Once OPC?;SING; is sent no query can be answered until the sweep
            %ends - the settings read back before it are used instead
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("STAR?;") = "1E9";
            connection.QueryResponses("STOP?;") = "2E9";
            connection.QueryResponses("POIN?;") = "101";
            instr.RunScan();
            queriesBefore = numel(connection.QueriedCommands);

            start_Hz = instr.GetStartFrequency();
            settings = instr.GetScanSettings();
            metadata = instr.CollectMetaData();

            testCase.verifyNumElements(connection.QueriedCommands, queriesBefore, "No queries during the sweep");
            testCase.verifyEqual(start_Hz, 1e9);
            testCase.verifyEqual(settings.StopFrequency_Hz, 2e9);
            testCase.verifyEqual(metadata.NumPoints, 101);
        end

        function SelectChannelWaitsAndChecksTest(testCase)
            %Manual: CHAN<n> should use OPC?. Its reply must be read (a query), or the "1" is left for the next command
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTPCHAN;") = "3";

            instr.SelectChannel(3);

            testCase.verifyEqual(connection.QueriedCommands, ["OPC?;CHAN3;", "OUTPCHAN;"]);
            testCase.verifyEmpty(connection.WrittenCommands, "Nothing written without its reply read");
        end

        function UnavailableChannelIsAnErrorTest(testCase)
            %Channels 3 and 4 only exist with the auxiliary channels on - the analyser stays on the channel it was
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTPCHAN;") = "1";

            testCase.verifyError(@() instr.SelectChannel(3), "HP_8722ES_NetworkAnalyser:ChannelUnavailable");
            testCase.verifyError(@() instr.SelectChannel(5), "HP_8722ES_NetworkAnalyser:InvalidChannel");
            testCase.verifyError(@() instr.SelectChannel("two"), "HP_8722ES_NetworkAnalyser:InvalidChannel");
        end

        function RunScanSelectsTheChannelFirstTest(testCase)
            %Settings and data are the active channel's, so the channel is selected before any is set
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTPCHAN;") = "3";
            connection.QueryResponses("POIN?;") = "201";

            instr.RunScan(struct("Channel", "3", "NumPoints", 201, "MeasMode", "S21"));

            testCase.verifyEqual(connection.QueriedCommands(1), "OPC?;CHAN3;");
            testCase.verifyEqual(connection.WrittenCommands, ["POIN201;", "S21;", "LOGM;", "OPC?;NUMG1;"]);
            testCase.verifyEqual(instr.CollectMetaData().Channel, 3);
        end

        function RunScanWithoutAChannelUsesTheActiveOneTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTPCHAN;") = "2";

            instr.RunScan();

            testCase.verifyEqual(instr.CollectMetaData().Channel, 2);
            testCase.verifyFalse(any(startsWith(connection.QueriedCommands, "OPC?;CHAN")), "The channel is not changed");
        end

        function DataIsReadFromTheScansChannelTest(testCase)
            %Someone pressing Chan 1 at the front panel during the sweep must not give channel 1's data as channel 3's
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTPCHAN;") = "3";
            instr.RunScan(struct("Channel", 3));
            connection.ReadQueue = "1";
            instr.CheckScanComplete();
            connection.QueryResponses("OUTPCHAN;") = "1";      %Which the analyser then stays on
            connection.QueryResponses("POIN?;") = "3";

            testCase.verifyError(@() instr.GetCompletedScanData(), "HP_8722ES_NetworkAnalyser:ChannelUnavailable");
            testCase.verifyTrue(any(connection.QueriedCommands == "OPC?;CHAN3;"), "It tried to put the scan's channel back");
        end

        function ChangedNumberOfPointsTakesTwoGroupsTest(testCase)
            %The manual says to wait two sweeps after POIN
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("POIN?;") = "201";

            instr.RunScan(struct("NumPoints", 401));

            testCase.verifyEqual(connection.WrittenCommands(end), "OPC?;NUMG2;");
        end

        function PointsAreRoundedToTheAnalysersChoicesTest(testCase)
            testCase.verifyEqual(Palladium.Instruments.HP_8722ES_NetworkAnalyser.NumPointsChoices, [3, 11, 21, 26, 51, 101, 201, 401, 801, 1601]);
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("POIN?;") = "801";

            instr.RunScan(struct("NumPoints", 1000));

            testCase.verifyEqual(connection.WrittenCommands(1), "POIN801;");
        end

        function ScanDataIsTwoValuesPerPointTest(testCase)
            %The trace holds a pair of numbers per point (and the limit test four) - a trace shorter than POIN says is an error, not quietly fewer points
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("POIN?;") = "11";
            connection.QueryResponses("OUTPFORM;") = "-1,0";
            connection.QueryResponses("OUTPLIML;") = "5E7,0,0,0";
            connection.ReadQueue = [repmat("-1,0", 1, 4), repmat("1E8,0,0,0", 1, 4)];

            testCase.verifyError(@() instr.GetCompletedScanData(), "HP_8722ES_NetworkAnalyser:DataSizeMismatch");
            connection.QueryResponses("POIN?;") = "11";
            connection.ReadQueue = strings(1, 0);
            try
                instr.GetCompletedScanData();
            catch err
                testCase.verifySubstring(err.message, "expected 11 points");
            end
        end

        function LoadSavedDataRecallsARegisterTest(testCase)
            %Recall (OPC-compatible, so its reply is read), hold so the saved trace isn't swept over, and adopt the register's channel and format
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTPCHAN;") = "2";
            connection.QueryResponses("S21?;") = "1";
            connection.QueryResponses("LINM?;") = "1";
            connection.QueryResponses("POIN?;") = "3";
            connection.QueryResponses("OUTPERRO;") = "0,NO ERROR";
            connection.QueryResponses("OUTPFORM;") = "0.1,0";
            connection.QueryResponses("OUTPLIML;") = "5E7,0,0,0";
            connection.ReadQueue = ["0.2,0", "0.3,0", "1E8,0,0,0", "2E8,0,0,0"];

            data = instr.LoadSavedData(3);

            testCase.verifyTrue(any(connection.QueriedCommands == "OPC?;RECAREG03;"));
            testCase.verifyEqual(connection.WrittenCommands(1), "HOLD;");
            testCase.verifyEqual(string(instr.MeasMode), "S21");
            testCase.verifyEqual(string(instr.MeasUnit), "Absolute");
            testCase.verifyEqual(instr.CollectMetaData().Channel, 2);
            testCase.verifyEqual(data, [5e7, 0.1; 1e8, 0.2; 2e8, 0.3]);
            testCase.verifyTrue(instr.CheckScanComplete(), "Nothing to wait for");
        end

        function EmptyRegisterIsAnErrorTest(testCase)
            %Error 55: the analyser keeps its state, so its current trace would be taken for the register's
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTPERRO;") = "55,NO VALID STATE IN REGISTER";

            testCase.verifyError(@() instr.RecallRegister(4), "HP_8722ES_NetworkAnalyser:EmptyRegister");
            testCase.verifyError(@() instr.RecallRegister(32), "MATLAB:validators:mustBeInRange");
        end

        function RunScanCanLoadARegisterTest(testCase)
            %How the VNA Control's Load button works: RunScan with LoadRegister recalls instead of sweeping, and is complete at once
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTPERRO;") = "0,NO ERROR";

            instr.RunScan(struct("LoadRegister", 5, "StartFrequency_Hz", 1e9, "StopFrequency_Hz", 2e9));

            testCase.verifyTrue(instr.CheckScanComplete());
            testCase.verifyFalse(any(startsWith(connection.WrittenCommands, "STAR")), "The settings are not sent");
            testCase.verifyTrue(any(connection.QueriedCommands == "OPC?;RECAREG05;"));
        end

        function ExtraScanControlsOfferTheChannelTest(testCase)
            instr = Palladium.Instruments.HP_8722ES_NetworkAnalyser();

            controls = instr.GetExtraScanControls();

            testCase.verifyEqual(string(controls.Name), "Channel");
            testCase.verifyEqual(string(controls.Items), ["1", "2", "3", "4"]);
        end

        function SimulatedChannelSelectionTest(testCase)
            instr = Palladium.Instruments.HP_8722ES_NetworkAnalyser();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("instr.Connect()");

            testCase.verifyEqual(instr.GetScanSettings().Channel, 1);
            testCase.verifyEqual(instr.GetScanSettings(struct("Channel", "3")).Channel, 3, "Reading another channel's settings switches to it");
            instr.RunScan(struct("Channel", 4));
            testCase.verifyEqual(instr.CollectMetaData().Channel, 4);
        end

        function RunMeasurementTakesNamedArgumentsTest(testCase)
            %From a script: no scanDetails struct, no GUI
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTPCHAN;") = "3";
            connection.QueryResponses("POIN?;") = "201";

            instr.RunMeasurement(Channel = 3, MeasMode = "S21", MeasUnit = "dB", StartFrequency_Hz = 1e9, StopFrequency_Hz = 2e9, ...
                NumPoints = 201, SweepTime_s = 0, SweepType = "Log");

            testCase.verifyEqual(connection.QueriedCommands(1), "OPC?;CHAN3;");
            testCase.verifyEqual(connection.WrittenCommands, ["STAR1000000000HZ;", "STOP2000000000HZ;", "POIN201;", ...
                "SWET0.000000S;", "LOGFREQ;", "S21;", "LOGM;", "OPC?;NUMG1;"]);
        end

        function RunMeasurementLeavesOutSettingsAsTheyAreTest(testCase)
            %Only what is asked for is sent; the units not given are the channel's own, so no display format command
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("POIN?;") = "201";
            connection.QueryResponses("LOGM?;") = "1";

            instr.RunMeasurement(NumPoints = 201, MeasMode = "S12");

            testCase.verifyEqual(connection.WrittenCommands, ["POIN201;", "S12;", "OPC?;NUMG1;"]);
            testCase.verifyEqual(string(instr.MeasMode), "S12");
            testCase.verifyEqual(string(instr.MeasUnit), "dB", "Taken from the analyser");
        end

        function RunMeasurementWithNothingGivenMeasuresWhatTheChannelShowsTest(testCase)
            %The S-parameter and units are the channel's: no S11/dB forced onto an S21 channel - and the data is labelled to match
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("S21?;") = "1";
            connection.QueryResponses("LINM?;") = "1";

            instr.RunMeasurement();

            testCase.verifyEqual(connection.WrittenCommands, "OPC?;NUMG1;", "Nothing is changed on the analyser");
            [headers, units] = instr.GetScanHeaders();
            testCase.verifyEqual(headers(2), instr.Name + " - S21 (Absolute)");
            testCase.verifyEqual(units, ["Hz", ""]);
        end

        function UnrecognisedDisplayFormatIsReplacedTest(testCase)
            %A phase display would give data that isn't what the column says - so the last measurement's format is set
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("S21?;") = "1";      %No LOGM?, LINM? or POLA? reply: some other format

            instr.RunMeasurement();

            testCase.verifyEqual(connection.WrittenCommands, ["LOGM;", "OPC?;NUMG1;"]);
        end

        function RunMeasurementCanWaitAndReturnTheDataTest(testCase)
            instr = Palladium.Instruments.HP_8722ES_NetworkAnalyser();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("instr.Connect()");

            data = instr.RunMeasurement(NumPoints = 51, MeasMode = "S21", Wait = true);

            testCase.verifySize(data, [51, 2]);
            testCase.verifyTrue(instr.CheckScanComplete());
        end

        function RunMeasurementWaitTimesOutTest(testCase)
            [instr, ~] = testCase.makeInstrument();     %Never replies to OPC?

            testCase.verifyError(@() instr.RunMeasurement(Wait = true, Timeout_s = 0.2), "HP_8722ES_NetworkAnalyser:Timeout");
        end

        function BadArgumentsAreRejectedBeforeTheAnalyserIsTouchedTest(testCase)
            [instr, connection] = testCase.makeInstrument();

            testCase.verifyError(@() instr.RunMeasurement(SweepType = "Spiral"), "HP_8722ES_NetworkAnalyser:UnsupportedSweepType");
            testCase.verifyError(@() instr.RunMeasurement(NumPoints = -1), "MATLAB:validators:mustBePositive");
            testCase.verifyError(@() instr.RunMeasurement(Channel = 7), "HP_8722ES_NetworkAnalyser:InvalidChannel");
            threw = false;
            try
                instr.RunMeasurement(MeasMode = "S33");
            catch
                threw = true;
            end
            testCase.verifyTrue(threw, "An unknown S-parameter is an error");
            testCase.verifyEqual(connection.ClearCount, 0, "Nothing was sent");
            testCase.verifyEmpty(connection.WrittenCommands);
        end

        function MeasModeAndUnitAreNotInstrumentSettingsTest(testCase)
            %They are chosen per measurement (RunMeasurement, the VNA Control), so a setting would only fight those
            instr = Palladium.Instruments.HP_8722ES_NetworkAnalyser();
            testCase.verifyEqual(string(instr.MeasMode), "S11");
            testCase.verifyEqual(string(instr.MeasUnit), "dB");
            properties = metaclass(instr).PropertyList;
            testCase.verifyFalse(properties(string({properties.Name}) == "MeasMode").SetObservable, "Not shown in the Instrument Settings");
            try
                instr.MeasMode = instr.MeasType("S22");
                threw = false;
            catch
                threw = true;
            end
            testCase.verifyTrue(threw);
        end

        function GetScanSettingsReadsTheAnalyserTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            replies = ["STAR?;", "5E7"; "STOP?;", "4E10"; "POIN?;", "401"; "SWET?;", "0.12"; "LOGFREQ?;", "0"; ...
                "S11?;", "0"; "S21?;", "0"; "S12?;", "1"; "S22?;", "0"; "LOGM?;", "0"; "LINM?;", "1"];
            for i = 1:height(replies)
                connection.QueryResponses(replies(i, 1)) = replies(i, 2);
            end

            settings = instr.GetScanSettings();

            testCase.verifyEqual(settings, struct("Channel", 1, "StartFrequency_Hz", 5e7, "StopFrequency_Hz", 4e10, "NumPoints", 401, ...
                "SweepTime_s", 0.12, "SweepType", "Linear", "MeasMode", "S12", "MeasUnit", "Absolute"));
            testCase.verifyEqual(string(instr.MeasMode), "S11", "Only reported - the driver's own setting is unchanged");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~)
            %The driver, given a fake connection as if connected
            instr = InstrumentTestingInstruments.RecordingHP8722ES();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
            connection.QueryResponses("OUTPCHAN;") = "1";
        end
    end
end
