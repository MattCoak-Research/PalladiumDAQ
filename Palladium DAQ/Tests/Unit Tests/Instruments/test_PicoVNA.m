classdef test_PicoVNA < matlab.unittest.TestCase
    %TEST_PICOVNA Tests the PicoVNA driver: how it finds the PicoVNA software, and its sweep, as the Scan Control runs it, with PicoVNA 5
    %Commands from the PicoVNA 5 User Guide (SCPI). The driver is given a
    %PicoVNA 5 backend with a fake connection (FakeDeviceHandle), through
    %the RecordingPicoVNA test subclass. PicoVNA 3 is tested in
    %test_PicoVNASoftware3. The last test runs against a real PicoVNA 5
    %software in demo mode, if one is running on this PC with SCPI on port
    %5025 - otherwise it is skipped.

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function SetupControlsShowTheCalibrationFileTest(testCase)
            instr = Palladium.Instruments.PicoVNA_NetworkAnalyser();
            fig = uifigure("Visible", "off");
            testCase.addTeardown(@() delete(fig));
            panel = uipanel(fig);

            height = instr.CreateSetupControls(panel);

            testCase.verifyGreaterThan(height, 0, "Asks for an area");
            buttons = findall(panel, "Type", "uibutton");
            testCase.verifyEqual(sort(string({buttons.Text})), sort(["Browse", "Run Calibration"]));
            field = findall(panel, "Type", "uieditfield");
            testCase.verifySubstring(string(field.Value), "none", "No file set");

            delete(panel.Children);
            instr.CalibrationFile = fullfile("cals", "mine.pcal");
            instr.CreateSetupControls(panel);
            field = findall(panel, "Type", "uieditfield");
            testCase.verifyEqual(string(field.Value), fullfile("cals", "mine.pcal"));
        end

        function CalibrationFileIsNotInTheSettingsListTest(testCase)
            %It has its own buttons in the setup controls area, so isn't also a setting - but is still saved in presets (SetObservable)
            instr = Palladium.Instruments.PicoVNA_NetworkAnalyser();

            settings = Palladium.Utilities.GUIUtils.ComputePropertyList(instr, true);

            testCase.verifyFalse(any(settings == "CalibrationFile"));
            testCase.verifyTrue(any(settings == "MeasMode"), "The others are still there");
            names = string({metaclass(instr).PropertyList.Name});
            testCase.verifyEqual(sum(names == "CalibrationFile"), 1, "Defined once");
            testCase.verifyTrue(findprop(instr, "CalibrationFile").SetObservable);
        end

        function RunCalibrationIsRefusedInDebugTest(testCase)
            instr = InstrumentTestingInstruments.RecordingPicoVNA();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;

            evalc("instr.RunCalibrationFromGUI([])");

            testCase.verifyFalse(instr.IsConnected, "Nothing to calibrate, so not connected");
        end

        function RunCalibrationIsRefusedWhileConnectedTest(testCase)
            [instr, five] = testCase.instrumentWithFakeSoftware();
            evalc("instr.Connect()");

            evalc("instr.RunCalibrationFromGUI([])");

            testCase.verifyTrue(instr.IsConnected, "Left as it was");
            testCase.verifyFalse(five.Closed);
        end

        function FailedCalibrationDisconnectsAndKeepsTheFileTest(testCase)
            %The fake can't calibrate from here (like PicoVNA 5): the error is shown, the analyser let go, CalibrationFile untouched and not loaded
            [instr, five] = testCase.instrumentWithFakeSoftware();
            oldFile = fullfile("cals", "old.pcal");
            instr.CalibrationFile = oldFile;

            evalc("instr.RunCalibrationFromGUI([])");

            testCase.verifyFalse(instr.IsConnected, "Disconnected afterwards");
            testCase.verifyTrue(five.Closed);
            testCase.verifyEqual(string(instr.CalibrationFile), oldFile);
            testCase.verifyEmpty(five.LoadedCalibrations, "The old file isn't loaded just to calibrate");

            evalc("instr.Connect()");
            testCase.verifyEqual(five.LoadedCalibrations, oldFile, "But it is when connecting for measurements");
        end

        function ConnectionTypesTest(testCase)
            %The software's SCPI port (Ethernet) - not USB, which the software owns
            instr = Palladium.Instruments.PicoVNA_NetworkAnalyser();
            testCase.verifyEqual(sort(string(instr.GetSupportedConnectionTypes()))', sort(["Debug", "Ethernet"]));
            testCase.verifyEqual(string(instr.IP_Address), "127.0.0.1");
            testCase.verifyEqual(string(instr.Software), "Auto");
        end

        function AutoUsesPicoVNA5WhenItIsThereTest(testCase)
            [instr, five, three] = testCase.instrumentWithFakeSoftware();

            evalc("instr.Connect()");

            testCase.verifyEqual(instr.BackendsRequested, "PicoVNA 5", "PicoVNA 3 is not even looked for");
            testCase.verifyTrue(five.Opened);
            testCase.verifyFalse(three.Opened);
            testCase.verifyEqual(instr.GetActiveSoftware(), "fake 5");
        end

        function AutoFallsBackToPicoVNA3Test(testCase)
            [instr, five, three] = testCase.instrumentWithFakeSoftware();
            five.OpenError = "nothing listening on port 5025";

            evalc("instr.Connect()");

            testCase.verifyEqual(instr.BackendsRequested, ["PicoVNA 5", "PicoVNA 3"]);
            testCase.verifyTrue(three.Opened);
            testCase.verifyEqual(instr.GetActiveSoftware(), "fake 3");
        end

        function NeitherSoftwareFoundExplainsWhatIsExpectedTest(testCase)
            [instr, five, three] = testCase.instrumentWithFakeSoftware();
            five.OpenError = "nothing listening on port 5025";
            three.OpenError = "library not registered";

            testCase.verifyError(@() instr.Connect(), "PicoVNA_NetworkAnalyser:SoftwareNotFound");
            message = testCase.errorMessage(@() instr.Connect());
            testCase.verifyTrue(contains(message, "https://www.picotech.com/downloads#t9"), "Where to get them");
            testCase.verifyTrue(contains(message, "PicoVNA 5") && contains(message, "PicoVNA 3"), "What is expected");
            testCase.verifyTrue(contains(message, "nothing listening on port 5025") && contains(message, "library not registered"), "What happened");
            testCase.verifyFalse(instr.IsConnected);
        end

        function ChosenSoftwareIsTheOnlyOneTriedTest(testCase)
            [instr, five, three] = testCase.instrumentWithFakeSoftware();
            five.OpenError = "nothing listening on port 5025";
            instr.Software = instr.SoftwareType("PicoVNA 5");

            testCase.verifyError(@() instr.Connect(), "PicoVNA_NetworkAnalyser:SoftwareNotFound");
            testCase.verifyEqual(instr.BackendsRequested, "PicoVNA 5");

            instr.Software = instr.SoftwareType("PicoVNA 3");
            instr.BackendsRequested = strings(1, 0);
            evalc("instr.Connect()");
            testCase.verifyEqual(instr.BackendsRequested, "PicoVNA 3");
            testCase.verifyTrue(three.Opened);
        end

        function PicoVNA3IsNotTriedForAnotherComputerTest(testCase)
            %Its library only exists on this PC
            [instr, five, ~] = testCase.instrumentWithFakeSoftware();
            five.OpenError = "no route to host";
            instr.IP_Address = '192.168.1.50';

            testCase.verifyError(@() instr.Connect(), "PicoVNA_NetworkAnalyser:SoftwareNotFound");

            testCase.verifyEqual(instr.BackendsRequested, "PicoVNA 5");
            testCase.verifyFalse(contains(testCase.errorMessage(@() instr.Connect()), "PicoVNA 3 software installed"));
        end

        function DisconnectReleasesTheSoftwareTest(testCase)
            [instr, five, ~] = testCase.instrumentWithFakeSoftware();
            evalc("instr.Connect()");

            evalc("instr.Disconnect()");

            testCase.verifyTrue(five.Closed);
            testCase.verifyEqual(instr.GetActiveSoftware(), "");
        end

        function RunScanAppliesTheSettingsThenStartsTheSweepTest(testCase)
            %The plan is read first (for what the tab leaves out), set, read back for the metadata, then the
            %sweep is started and its data asked for - which is not read until the sweep is done
            [instr, fake] = testCase.makeInstrument();
            settings = struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 1e9, "NumPoints", 101, ...
                "SweepTime_s", 0, "SweepType", "Linear", "MeasMode", "S21", "MeasUnit", "dB", ...
                "SaveSweepFile", true, "FileName", "x");

            instr.RunScan(settings);

            planQueries = ["SENSe:FREQuency:STARt?", "SENSe:FREQuency:STOP?", "SENSe:SWEep:POINts?"];
            testCase.verifyEqual(fake.QueriedCommands, [planQueries, "SENSe:FREQuency:STOP?", ...
                "SENSe:FREQuency:STARt 1000000", "SENSe:FREQuency:STOP 1000000000", "SENSe:SWEep:POINts 101", ...
                planQueries, "SENSe:LEVel?", "SENSe:BANDwidth?", "MMEMory:CALibration:INFO:TYPe?", "FORMat ASCii", "INITiate"]);
            testCase.verifyEqual(fake.WrittenCommands, "CALCulate:DATa S21,LOGMAG");
            testCase.verifyEqual(string(instr.MeasMode), "S21");
            testCase.verifyFalse(instr.CheckScanComplete(), "No reply yet: the sweep is under way");
        end

        function MovingTheSweepUpSetsTheStopFirstTest(testCase)
            %The software refuses a start above the current stop (8.5 GHz here)
            [instr, fake] = testCase.makeInstrument();

            instr.RunScan(struct("StartFrequency_Hz", 9e9, "StopFrequency_Hz", 10e9, "NumPoints", 11));

            commands = fake.QueriedCommands(startsWith(fake.QueriedCommands, ["SENSe:FREQuency:STARt ", "SENSe:FREQuency:STOP "]));
            testCase.verifyEqual(commands, ["SENSe:FREQuency:STOP 10000000000", "SENSe:FREQuency:STARt 9000000000"]);
        end

        function PowerAndBandwidthAreLeftToTheSoftwareTest(testCase)
            %Set in the PicoVNA 5 software, as for the other analysers - only read, for the header
            [instr, fake] = testCase.makeInstrument();
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11));
            testCase.verifyFalse(any(startsWith(fake.QueriedCommands, ["SENSe:LEVel ", "SENSe:BANDwidth "])));
            testCase.verifyTrue(all(ismember(["SENSe:LEVel?", "SENSe:BANDwidth?"], fake.QueriedCommands)));
        end

        function MeasUnitAndModeChooseTheDataRequestTest(testCase)
            [instr, fake] = testCase.makeInstrument();
            instr.RunScan(struct("MeasMode", "S12", "MeasUnit", "Absolute"));
            testCase.verifyEqual(fake.WrittenCommands, "CALCulate:DATa S12,MAG");
        end

        function LogSweepIsRefusedTest(testCase)
            [instr, fake] = testCase.makeInstrument();
            testCase.verifyError(@() instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11, "SweepType", "Log")), ...
                "PicoVNA_NetworkAnalyser:UnsupportedSweepType");
            testCase.verifyEmpty(fake.QueriedCommands, "Nothing sent");
        end

        function FailedSettingNamesTheActionAndTheSoftwaresMessageTest(testCase)
            [instr, fake] = testCase.makeInstrument();
            fake.QueryResponses("SENSe:FREQuency:STOP 99000000000") = "Cannot sweep frequency 99000000000 Hz because it is too high.";

            testCase.verifyError(@() instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 99e9, "NumPoints", 11)), ...
                "PicoVNA_NetworkAnalyser:CommandFailed");
            testCase.verifyEmpty(fake.WrittenCommands, "No sweep started");
        end

        function StopBelowStartIsRefusedTest(testCase)
            [instr, ~] = testCase.makeInstrument();
            testCase.verifyError(@() instr.SetFrequencyPlan(2e6, 1e6, 11), "PicoVNA_NetworkAnalyser:FrequencyOutOfRange");
        end

        function ScanIsCompleteWhenTheReplyArrivesTest(testCase)
            %Checked each tick without waiting: the software holds the data back until the sweep is done
            [instr, fake] = testCase.makeInstrument();
            testCase.startSweep(instr, fake, 3);

            testCase.verifyFalse(instr.CheckScanComplete(), "Sweeping");
            testCase.verifyFalse(instr.CheckScanComplete(), "Still sweeping");
            fake.ReadQueue = "-1.5,-2.5,-3.5";
            testCase.verifyTrue(instr.CheckScanComplete(), "Reply arrived");
            testCase.verifyTrue(instr.CheckScanComplete(), "Stays complete");
        end

        function ScanDataIsFrequencyAndValueTest(testCase)
            [instr, fake] = testCase.makeInstrument();
            testCase.startSweep(instr, fake, 3);
            fake.ReadQueue = "-1.5,-2.5,-3.5";
            instr.CheckScanComplete();

            data = instr.GetCompletedScanData();

            testCase.verifyEqual(data, [1e6, -1.5; 2e6, -2.5; 3e6, -3.5]);
        end

        function FailedSweepRaisesWhenTheDataIsCollectedTest(testCase)
            %E.g. the software is sweeping continuously: it answers the data request with a message
            [instr, fake] = testCase.makeInstrument();
            testCase.startSweep(instr, fake, 3);
            fake.ReadQueue = "No device connected";

            testCase.verifyTrue(instr.CheckScanComplete(), "A failed sweep ends the scan");
            testCase.verifyError(@() instr.GetCompletedScanData(), "PicoVNA_NetworkAnalyser:MeasureFailed");
        end

        function MissingOrEmptyDataErrorsTest(testCase)
            [instr, fake] = testCase.makeInstrument();
            testCase.startSweep(instr, fake, 3);
            fake.ReadQueue = "-1.5,-2.5";
            instr.CheckScanComplete();
            testCase.verifyError(@() instr.GetCompletedScanData(), "PicoVNA_NetworkAnalyser:DataSizeMismatch");

            testCase.startSweep(instr, fake, 3);
            fake.ReadQueue = "nan,nan,nan";
            instr.CheckScanComplete();
            testCase.verifyError(@() instr.GetCompletedScanData(), "PicoVNA_NetworkAnalyser:NoData", "Not measurable with this calibration");
        end

        function SettingsAreNotAskedForWhileSweepingTest(testCase)
            %The software can't answer while the data request waits for the sweep: the tab and metadata use the read-back from before
            [instr, fake] = testCase.makeInstrument();
            testCase.startSweep(instr, fake, 3);
            queriesAtStart = numel(fake.QueriedCommands);

            settings = instr.GetScanSettings();
            metadata = instr.CollectMetaData();

            testCase.verifyEqual(numel(fake.QueriedCommands), queriesAtStart, "Nothing asked");
            testCase.verifyEqual(settings.NumPoints, 3);
            testCase.verifyEqual(metadata.CalType, "2-port non-insertable DUT (SOLU)");
        end

        function AbandonedSweepIsAbortedAtTheNextScanTest(testCase)
            %Abort on the screen leaves the sweep and its data request going: ABORt makes the software answer it, then OK
            [instr, fake] = testCase.makeInstrument();
            testCase.startSweep(instr, fake, 3);
            fake.ReadQueue = ["nan,nan,nan", "OK"];

            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 3e6, "NumPoints", 3));

            testCase.verifyEqual(fake.WrittenCommands, ["CALCulate:DATa S11,LOGMAG", "ABORt", "CALCulate:DATa S11,LOGMAG"]);
            testCase.verifyEqual(fake.NumBytesAvailable, 0, "The old reply was thrown away");
            testCase.verifyFalse(instr.CheckScanComplete(), "The new sweep is under way");
        end

        function CompletedScanNeedsNoAbortTest(testCase)
            [instr, fake] = testCase.makeInstrument();
            testCase.startSweep(instr, fake, 3);
            fake.ReadQueue = "-1.5,-2.5,-3.5";
            instr.CheckScanComplete();

            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 3e6, "NumPoints", 3));

            testCase.verifyFalse(any(fake.WrittenCommands == "ABORt"));
        end

        function DisconnectingStopsASweepTest(testCase)
            [instr, fake] = testCase.makeInstrument();
            testCase.startSweep(instr, fake, 3);
            fake.ReadQueue = ["nan,nan,nan", "OK"];

            instr.CloseForTest();

            testCase.verifyEqual(fake.WrittenCommands(end), "ABORt");
        end

        function ReplyUnitsAreConvertedToHzTest(testCase)
            %The software puts units after its numbers
            [instr, fake] = testCase.makeInstrument();
            fake.QueryResponses("SENSe:FREQuency:STARt?") = "0.300000 MHz";
            fake.QueryResponses("SENSe:FREQuency:STOP?") = "8.5 GHz";
            fake.QueryResponses("SENSe:SWEep:POINts?") = "51";

            settings = instr.GetScanSettings();

            testCase.verifyEqual(settings, struct("StartFrequency_Hz", 3e5, "StopFrequency_Hz", 8.5e9, "NumPoints", 51, ...
                "SweepTime_s", 0, "SweepType", "Linear", "MeasMode", "S11", "MeasUnit", "dB"));
        end

        function MetadataTest(testCase)
            [instr, ~] = testCase.makeInstrument();

            metadata = instr.CollectMetaData();

            testCase.verifyEqual(metadata, struct("Freq_Start_Hz", 3e5, "Freq_Stop_Hz", 8.5e9, "NumPoints", 201, ...
                "Power_dBm", 3, "Bandwidth_Hz", 1000, "CalType", "2-port non-insertable DUT (SOLU)"));
        end

        function ScanHeadersTest(testCase)
            [instr, ~] = testCase.makeInstrument();
            [headers, units] = instr.GetScanHeaders();
            testCase.verifyEqual(headers, "PicoVNA - " + ["Frequency_Hz", "S11 (dB)"]);
            testCase.verifyEqual(units, ["Hz", "dB"]);

            instr.MeasUnit = instr.MeasUnitType("Absolute");
            instr.MeasMode = instr.MeasType("S22");
            [headers, units] = instr.GetScanHeaders();
            testCase.verifyEqual(headers, "PicoVNA - " + ["Frequency_Hz", "S22 (Absolute)"]);
            testCase.verifyEqual(units, ["Hz", ""]);
        end

        function MeasureAndHeadersAddNoColumnsTest(testCase)
            %Scans are saved only through the Scan Control
            [instr, fake] = testCase.makeInstrument();
            [headers, units] = instr.GetHeaders();
            testCase.verifyEmpty(headers);
            testCase.verifyEmpty(units);
            testCase.verifyEmpty(instr.Measure());
            testCase.verifyEmpty(fake.QueriedCommands, "Measure asks nothing of the analyser");
        end

        function LoadCalibrationQuotesThePathTest(testCase)
            [instr, fake] = testCase.makeInstrument();

            instr.LoadCalibration("C:\Cals\my cal.pvcal");
            testCase.verifyEqual(fake.QueriedCommands, "MMEMory:APPLY:CALibration 'C:\Cals\my cal.pvcal'");

            fake.QueryResponses("MMEMory:APPLY:CALibration 'C:\Cals\my cal.pvcal'") = "File not found";
            testCase.verifyError(@() instr.LoadCalibration("C:\Cals\my cal.pvcal"), "PicoVNA_NetworkAnalyser:CommandFailed");
        end

        function SimulatedScanFollowsTheSettingsTest(testCase)
            %In Debug mode no software is needed: the settings are kept, and the scan follows them
            instr = Palladium.Instruments.PicoVNA_NetworkAnalyser();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("instr.Connect()");

            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11, "SweepType", "Linear", "MeasMode", "S12"));
            data = instr.GetCompletedScanData();
            settings = instr.GetScanSettings();

            testCase.verifyTrue(instr.CheckScanComplete());
            testCase.verifySize(data, [11, 2]);
            testCase.verifyEqual(data(:, 1)', linspace(1e6, 2e6, 11));
            testCase.verifyEqual([settings.StartFrequency_Hz, settings.StopFrequency_Hz, settings.NumPoints], [1e6, 2e6, 11]);
            testCase.verifyEqual(settings.MeasMode, "S12");
        end

        function SimulatedAbsoluteScanIsPositiveTest(testCase)
            instr = Palladium.Instruments.PicoVNA_NetworkAnalyser();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("instr.Connect()");

            instr.RunScan(struct("MeasUnit", "Absolute"));
            data = instr.GetCompletedScanData();

            testCase.verifyTrue(all(data(:, 2) > 0));
        end

        function DemoModeSoftwareTest(testCase)
            %Against a real PicoVNA 5 in demo mode, if one is running: a scan starts without waiting for its sweep,
            %and one abandoned part way is cleared by the next
            testCase.assumeTrue(testCase.demoSoftwareIsRunning(), "No PicoVNA 5 in demo mode listening on port 5025");
            instr = Palladium.Instruments.PicoVNA_NetworkAnalyser();
            evalc("instr.Connect()");
            testCase.addTeardown(@() instr.Disconnect());
            original = instr.GetScanSettings();
            testCase.addTeardown(@() instr.SetFrequencyPlan(original.StartFrequency_Hz, original.StopFrequency_Hz, original.NumPoints));

            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 1e9, "NumPoints", 51, "MeasMode", "S21", "MeasUnit", "dB"));
            testCase.waitForScan(instr);
            data = instr.GetCompletedScanData();
            testCase.verifySize(data, [51, 2]);
            testCase.verifyEqual(data([1 end], 1)', [1e6, 1e9]);
            testCase.verifyTrue(all(isfinite(data(:, 2))));

            instr.RunScan(struct("StartFrequency_Hz", 3e5, "StopFrequency_Hz", 8.5e9, "NumPoints", 10001));   %About 2 s in demo mode
            pause(0.3);
            testCase.verifyFalse(instr.CheckScanComplete(), "Still sweeping, and not waited for");
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e9, "NumPoints", 51, "MeasUnit", "Absolute"));
            testCase.waitForScan(instr);
            data = instr.GetCompletedScanData();
            testCase.verifySize(data, [51, 2], "The abandoned sweep's data is not mixed in");
            testCase.verifyEqual(data(1, 1), 1e6);
            testCase.verifyTrue(all(data(:, 2) >= 0), "Linear magnitude");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, fake] = makeInstrument(~)
            %The driver, given a fake connection as if connected - the software's replies for a default setup
            instr = InstrumentTestingInstruments.RecordingPicoVNA();
            fake = InstrumentTestingInstruments.FakeDeviceHandle();
            fake.QueryResponse = "OK";
            replies = ["SENSe:FREQuency:STARt?", "300000.000000 Hz"; "SENSe:FREQuency:STOP?", "8500000000.000000 Hz"; ...
                "SENSe:SWEep:POINts?", "201"; "SENSe:LEVel?", "3.000000 dBm"; "SENSe:BANDwidth?", "1000.000000 Hz"; ...
                "MMEMory:CALibration:INFO:TYPe?", "2-port non-insertable DUT (SOLU)"];
            for i = 1:height(replies)
                fake.QueryResponses(replies(i, 1)) = replies(i, 2);
            end
            instr.SetBackendForTest(Palladium.Instruments.PicoVNA.Software5(Handle = fake));
        end

        function message = errorMessage(~, fcn)
            %The message of the error a function throws.
            message = "";
            try
                fcn();
            catch err
                message = string(err.message);
            end
        end

        function [instr, five, three] = instrumentWithFakeSoftware(~)
            %An instrument whose search for the software finds the two fake backends, rather than any real software
            instr = InstrumentTestingInstruments.RecordingPicoVNA();
            five = InstrumentTestingInstruments.FakeBackend();
            five.FakeDescription = "fake 5";
            three = InstrumentTestingInstruments.FakeBackend();
            three.FakeDescription = "fake 3";
            instr.FakeBackends = dictionary(["PicoVNA 5", "PicoVNA 3"], {five, three});
        end

        function startSweep(~, instr, fake, numPoints)
            %Start a scan of numPoints points from 1 MHz in 1 MHz steps - the fake's read-back of the plan matches - leaving the data request waiting
            fake.QueryResponses("SENSe:FREQuency:STARt?") = "1000000.000000 Hz";
            fake.QueryResponses("SENSe:FREQuency:STOP?") = numPoints * 1e6 + " Hz";
            fake.QueryResponses("SENSe:SWEep:POINts?") = string(numPoints);
            fake.ReadQueue = strings(1, 0);
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", numPoints * 1e6, "NumPoints", numPoints));
        end

        function running = demoSoftwareIsRunning(~)
            %True if a PicoVNA 5 in demo mode answers on port 5025.
            running = false;
            try
                connection = tcpclient("127.0.0.1", 5025, ConnectTimeout = 1, Timeout = 3);
                running = contains(string(writeread(connection, "*IDN?")), "DEMO");
            catch
                %Not running, or SCPI is off
            end
        end

        function waitForScan(testCase, instr)
            %Until the sweep has finished - up to 30 s.
            timer = tic();
            while ~instr.CheckScanComplete() && toc(timer) < 30
                pause(0.02);
            end
            testCase.assertTrue(instr.CheckScanComplete(), "The sweep didn't finish");
        end
    end
end
