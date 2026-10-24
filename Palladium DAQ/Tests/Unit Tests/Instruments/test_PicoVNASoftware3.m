classdef test_PicoVNASoftware3 < matlab.unittest.TestCase
    %TEST_PICOVNASOFTWARE3 Tests the PicoVNA driver working through the PicoVNA 3 software's COM library: sweeps run in the background, calibration and settings
    %Functions from the PicoVNA Programmer's Guide. The driver is given a
    %Software3 backend with a fake connection to the library
    %(FakeComServer), through the RecordingPicoVNA test subclass, which
    %records the library calls and answers them - so no library or analyser
    %is needed. Two tests (Windows only) use a real helper process with a
    %PowerShell stand-in for the library, to check a sweep really runs in
    %the background.

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function RunScanSetsThePlanThenStartsTheSweepInTheBackgroundTest(testCase)
            %The library takes start and step in MHz. The plan and calibration are read back first, for the
            %metadata, as the library can't be asked anything once it is sweeping
            [instr, server] = testCase.makeInstrument();
            settings = struct("StartFrequency_Hz", 1e7, "StopFrequency_Hz", 1e9, "NumPoints", 101, ...
                "SweepTime_s", 0, "SweepType", "Linear", "MeasMode", "S21", "MeasUnit", "dB", ...
                "SaveSweepFile", true, "FileName", "x");

            instr.RunScan(settings);

            testCase.verifyEqual(server.Calls, ["GetInfo(FreqPlan)", "SetFreqPlan(10, 9.9, 101, 0, 1000)", ...
                "GetInfo(FreqPlan)", "GetInfo(FreqPlan)", "GetInfo(BWSet)", "GetInfo(CalType)", "GetInfo(CalType)", "Measure(S21) [background]"]);
            testCase.verifyEqual(string(instr.MeasMode), "S21");
        end

        function PowerAndBandwidthAreSentWithThePlanTest(testCase)
            %The application can't be used to set them, so they are the driver's settings
            [instr, server] = testCase.makeInstrument();
            instr.Power_dBm = -10;
            instr.Bandwidth_Hz = 100;

            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11));

            testCase.verifyTrue(any(server.Calls == "SetFreqPlan(1, 0.1, 11, -10, 100)"));
        end

        function SettingsNotGivenStayAsTheLibraryHasThemTest(testCase)
            [instr, server] = testCase.makeInstrument();
            server.Replies("GetInfo|FreqPlan") = "3E5,2E9,1E7,201,0";

            instr.RunScan(struct("StopFrequency_Hz", 1e9));

            testCase.verifyEqual(server.Calls(2), "SetFreqPlan(0.3, " + string((1e9 - 3e5) / 200 / 1e6) + ", 201, 0, 1000)");
        end

        function ReverseParametersNeedAFullMeasurementTest(testCase)
            %S12 and S22 only come with Measure("All") - and a two-port calibration
            for sParameter = ["S12", "S22"]
                [instr, server] = testCase.makeInstrument();
                server.Replies("GetInfo|CalType") = "12 Term";
                instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11, "MeasMode", sParameter));
                testCase.verifyEqual(server.Calls(end), "Measure(All) [background]", sParameter);
            end
        end

        function TheCalibrationDecidesWhatCanBeMeasuredTest(testCase)
            %A one-port calibration measures S11 only. With "All" the library says OK even then, and gives placeholder
            %values (-200 dB for S12, -120 dB for S22) that would be recorded as if measured
            covered = struct("UnCal", strings(1, 0), "S11", "S11", "S21", "S21", "S11_S21", ["S11", "S21"], "TwoPort", ["S11", "S21", "S12", "S22"]);
            calTypes = struct("UnCal", "UnCal", "S11", "S11", "S21", "S21", "S11_S21", "S11+S21", "TwoPort", "12 Term");
            for name = string(fieldnames(covered))'
                for sParameter = ["S11", "S21", "S12", "S22"]
                    [instr, server] = testCase.makeInstrument();
                    server.Replies("GetInfo|CalType") = calTypes.(name);
                    scan = @() instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11, "MeasMode", sParameter));
                    label = calTypes.(name) + " calibration, " + sParameter;
                    if any(covered.(name) == sParameter)
                        scan();
                        testCase.verifyTrue(any(contains(server.Calls, "Measure(")), label + " is measured");
                    else
                        testCase.verifyError(scan, "PicoVNA_NetworkAnalyser:CalibrationDoesNotCover", label);
                        testCase.verifyFalse(any(contains(server.Calls, "Measure(")), label + " is not measured");
                    end
                end
            end
        end

        function CalibrationErrorSaysWhatIsNeededTest(testCase)
            [instr, server] = testCase.makeInstrument();
            server.Replies("GetInfo|CalType") = "S11";

            try
                instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11, "MeasMode", "S22"));
                message = "";
            catch err
                message = string(err.message);
            end

            testCase.verifyTrue(contains(message, "two-port") && contains(message, "S22") && contains(message, """S11"""), message);
        end

        function ACalibrationTypeNotKnownIsLeftToTheLibraryTest(testCase)
            [instr, server] = testCase.makeInstrument();
            server.Replies("GetInfo|CalType") = "Alln";

            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11, "MeasMode", "S22"));

            testCase.verifyEqual(server.Calls(end), "Measure(All) [background]");
        end

        function LogSweepIsRefusedTest(testCase)
            [instr, server] = testCase.makeInstrument();
            testCase.verifyError(@() instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11, "SweepType", "Log")), ...
                "PicoVNA_NetworkAnalyser:UnsupportedSweepType");
            testCase.verifyEmpty(server.Calls, "Nothing sent");
        end

        function FailedPlanErrorsBeforeMeasuringTest(testCase)
            [instr, server] = testCase.makeInstrument();
            server.Replies("SetFreqPlan") = "Error";

            testCase.verifyError(@() instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11)), ...
                "PicoVNA_NetworkAnalyser:CommandFailed");
            testCase.verifyFalse(any(contains(server.Calls, "Measure")), "No sweep");
        end

        function ScanIsCompleteWhenTheBackgroundSweepFinishesTest(testCase)
            %RunScan returns at once, and the Scan Control checks each tick
            [instr, server] = testCase.makeInstrument();
            server.BusyChecks = 2;
            testCase.setUpSweepData(server, 3);
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 3e6, "NumPoints", 3));

            testCase.verifyFalse(instr.CheckScanComplete(), "Sweeping");
            testCase.verifyFalse(instr.CheckScanComplete(), "Still sweeping");
            testCase.verifyTrue(instr.CheckScanComplete(), "Done");
            testCase.verifyTrue(instr.CheckScanComplete(), "Stays done");
        end

        function ScanDataIsFrequencyAndLogMagnitudeTest(testCase)
            %The library gives the frequency of each point as well as its value
            [instr, server] = testCase.makeInstrument();
            testCase.setUpSweepData(server, 3);
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 3e6, "NumPoints", 3));
            instr.CheckScanComplete();

            data = instr.GetCompletedScanData();

            testCase.verifyEqual(data, [1e6, -1.5; 2e6, -2.5; 3e6, -3.5]);
        end

        function RealImaginaryScanDataIsBothPartsTest(testCase)
            %Three columns: frequency, real part, imaginary part - for a Smith chart
            [instr, server] = testCase.makeInstrument();
            testCase.setUpSweepData(server, 2);
            server.Replies("GetData|S21|real|0") = "1000000,0.5,2000000,0.25";
            server.Replies("GetData|S21|imag|0") = "1000000,-0.1,2000000,-0.2";
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 2, "MeasMode", "S21", "MeasUnit", "Real/Imaginary"));
            instr.CheckScanComplete();

            data = instr.GetCompletedScanData();

            testCase.verifyEqual(data, [1e6, 0.5, -0.1; 2e6, 0.25, -0.2]);
        end

        function AbsoluteScanDataIsMagnitudeFromRealAndImaginaryTest(testCase)
            %The library has no linear magnitude format
            [instr, server] = testCase.makeInstrument();
            testCase.setUpSweepData(server, 2);
            server.Replies("GetData|S21|real|0") = "1000000,0.3,2000000,0";
            server.Replies("GetData|S21|imag|0") = "1000000,0.4,2000000,1";
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 2, "MeasMode", "S21", "MeasUnit", "Absolute"));
            instr.CheckScanComplete();

            data = instr.GetCompletedScanData();

            testCase.verifyEqual(data, [1e6, 0.5; 2e6, 1], AbsTol = 1e-12);
        end

        function FailedMeasureRaisesWhenTheDataIsCollectedTest(testCase)
            %The library says only "Error" when the calibration doesn't cover the measurement
            [instr, server] = testCase.makeInstrument();
            server.Replies("Measure") = "Error";
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11));

            testCase.verifyTrue(instr.CheckScanComplete(), "A failed sweep ends the scan");
            testCase.verifyError(@() instr.GetCompletedScanData(), "PicoVNA_NetworkAnalyser:MeasureFailed");

            testCase.setUpSweepData(server, 2);
            server.Replies("Measure") = "OK";
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 2));
            instr.CheckScanComplete();
            testCase.verifyEqual(instr.GetCompletedScanData(), [1e6, -1.5; 2e6, -2.5], "The next scan is not affected");
        end

        function UnpairedScanDataErrorsTest(testCase)
            [instr, server] = testCase.makeInstrument();
            server.Replies("GetInfo|FreqPlan") = "1E6,3E6,1E6,3,0";
            server.Replies("GetData|S11|logmag|0") = "1000000,-1.5,2000000";
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 3e6, "NumPoints", 3));
            instr.CheckScanComplete();
            testCase.verifyError(@() instr.GetCompletedScanData(), "PicoVNA_NetworkAnalyser:DataSizeMismatch");

            server.Replies("GetData|S11|logmag|0") = "Error";
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 3e6, "NumPoints", 3));
            instr.CheckScanComplete();
            testCase.verifyError(@() instr.GetCompletedScanData(), "PicoVNA_NetworkAnalyser:DataSizeMismatch", "Not numbers at all");
        end

        function NothingIsAskedWhileSweepingTest(testCase)
            %The library can't answer during a sweep: the settings and metadata come from before it started
            [instr, server] = testCase.makeInstrument();
            server.BusyChecks = 5;
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11));
            callsAtStart = numel(server.Calls);

            settings = instr.GetScanSettings();
            metadata = instr.CollectMetaData();

            testCase.verifyEqual(numel(server.Calls), callsAtStart, "No calls to the library");
            testCase.verifyEqual(settings.NumPoints, 201, "As read back before the sweep (the fake's plan)");
            testCase.verifyEqual(metadata.CalType, "S11+S21");
        end

        function GetScanSettingsReadsTheFrequencyPlanTest(testCase)
            [instr, server] = testCase.makeInstrument();
            server.Replies("GetInfo|FreqPlan") = "3E5,2E9,1E7,201,0";
            instr.MeasMode = instr.MeasType("S21");

            settings = instr.GetScanSettings();

            testCase.verifyEqual(settings, struct("StartFrequency_Hz", 3e5, "StopFrequency_Hz", 2e9, "NumPoints", 201, ...
                "SweepTime_s", 0, "SweepType", "Linear", "MeasMode", "S21", "MeasUnit", "dB"));
        end

        function CWSweepIsNotAFrequencyPlanTest(testCase)
            %A CW (time) sweep's plan has four values: <CW freq>, <points>, <level>, <time between points>
            [instr, server] = testCase.makeInstrument();
            server.Replies("GetInfo|FreqPlan") = "1E9,101,0,5";
            testCase.verifyError(@() instr.GetScanSettings(), "PicoVNA_NetworkAnalyser:NotAFrequencySweep");
        end

        function MetadataTest(testCase)
            [instr, server] = testCase.makeInstrument();
            server.Replies("GetInfo|FreqPlan") = "3E5,2E9,1E7,201,-5";
            server.Replies("GetInfo|BWSet") = "100";

            metadata = instr.CollectMetaData();

            testCase.verifyEqual(metadata, struct("Freq_Start_Hz", 3e5, "Freq_Stop_Hz", 2e9, "NumPoints", 201, ...
                "Power_dBm", -5, "Bandwidth_Hz", 100, "CalType", "S11+S21"));
        end

        function CalibrationFilesTest(testCase)
            [instr, server] = testCase.makeInstrument();
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            file = fullfile(folder, "cal.pcal");

            testCase.verifyError(@() instr.LoadCalibration(file), "PicoVNA_NetworkAnalyser:CalibrationFileMissing");
            testCase.verifyEmpty(server.Calls);

            fclose(fopen(file, "w"));
            instr.LoadCalibration(file);
            testCase.verifyEqual(server.Calls, "LoadCal(" + string(file) + ")");

            server.Replies("LoadCal") = "Error reading file";
            testCase.verifyError(@() instr.LoadCalibration(file), "PicoVNA_NetworkAnalyser:CommandFailed");

            instr.SaveCalibration("C:\cal.pcal");
            testCase.verifyEqual(server.Calls(end), "SaveCal(C:\cal.pcal)");
        end

        function CalibrateOpensTheLibrarysDialogueTest(testCase)
            [instr, server] = testCase.makeInstrument();
            instr.Calibrate();
            testCase.verifyEqual(server.Calls, "SelectCal(?)");
        end

        function ScansAreRecordedOnlyThroughTheControlTest(testCase)
            [instr, server] = testCase.makeInstrument();
            [headers, units] = instr.GetHeaders();
            testCase.verifyEmpty(headers);
            testCase.verifyEmpty(units);
            testCase.verifyEmpty(instr.Measure());
            testCase.verifyEmpty(server.Calls, "Measure makes no call to the library");
        end

        function DisconnectingCutsOffASweepTest(testCase)
            %CloseVNA would wait for the sweep, so it is skipped and the process stopped
            [instr, server] = testCase.makeInstrument();
            server.BusyChecks = 100;
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11));
            callsBefore = numel(server.Calls);
            shared = server.Shared;

            instr.CloseForTest();

            testCase.verifyEqual(numel(shared("Calls")), callsBefore, "No CloseVNA");
            testCase.verifyTrue(shared("Deleted"));
        end

        function DisconnectingWhenIdleClosesTheAnalyserTest(testCase)
            [instr, server] = testCase.makeInstrument();
            shared = server.Shared;

            instr.CloseForTest();

            calls = shared("Calls");
            testCase.verifyEqual(calls(end), "CloseVNA()");
            testCase.verifyTrue(shared("Deleted"));
        end

        function OpeningFindsTheAnalyserTest(testCase)
            server = InstrumentTestingInstruments.FakeComServer();
            server.Replies("FND") = "1234";
            server.Replies("GetInfo|Model") = "PicoVNA 106";
            backend = Palladium.Instruments.PicoVNA.Software3(Server = server);

            backend.Open();

            testCase.verifyEqual(server.Calls, ["FND()", "GetInfo(Model)"]);
            testCase.verifyTrue(contains(backend.Description, "PicoVNA 106") && contains(backend.Description, "1234"));
        end

        function NoAnalyserOnUSBErrorsAndReleasesTheLibraryTest(testCase)
            %FND returns 0 when it finds nothing
            server = InstrumentTestingInstruments.FakeComServer();
            server.Replies("FND") = "0";
            shared = server.Shared;
            backend = Palladium.Instruments.PicoVNA.Software3(Server = server);

            testCase.verifyError(@() backend.Open(), "PicoVNA_NetworkAnalyser:PicoVNA3NoAnalyser");
            testCase.verifyTrue(shared("Deleted"), "The process is stopped");
        end

        function MessageBoxDuringARequestIsLoggedTest(testCase)
            %The library comments on a request in a box (closed for the user) - what it said is logged, and the request carries on
            Palladium.Logging.Logger.ResetForTest();      %Other tests may have changed where messages go
            testCase.addTeardown(@() Palladium.Logging.Logger.ResetForTest());
            [instr, server] = testCase.makeInstrument();
            server.DialogsDismissed = "PicoControl2: Start frequency outside existing calibration span. Calibration values will be restored";

            output = evalc("instr.RunScan(struct(""StartFrequency_Hz"", 1e6, ""StopFrequency_Hz"", 2e6, ""NumPoints"", 11));");

            testCase.verifySubstring(output, "Start frequency outside existing calibration span");
            testCase.verifyTrue(any(startsWith(server.Calls, "SetFreqPlan")), "The request was still made");
        end

        function MessageTheLibraryShowedIsReportedTest(testCase)
            %A library that dislikes the analyser can show a message box (closed by the process) - what it said helps explain the failure
            server = InstrumentTestingInstruments.FakeComServer();
            server.Replies("FND") = "0";
            server.DialogsDismissed = "Warning: Wrong instrument";
            backend = Palladium.Instruments.PicoVNA.Software3(Server = server);

            message = "";
            try
                backend.Open();
            catch err
                testCase.verifyEqual(err.identifier, 'PicoVNA_NetworkAnalyser:PicoVNA3NoAnalyser');
                message = string(err.message);
            end
            testCase.verifySubstring(message, "Warning: Wrong instrument");
        end

        function AnalyserNotFoundByOneLibraryIsLookedForByTheNextTest(testCase)
            %Both PicoVNA 3's and PicoVNA 2's libraries can be installed, and only one may find a given analyser
            first = testCase.fakeLibrary("0", "");
            second = testCase.fakeLibrary("9905", "PicoVNA 106");
            servers = containers.Map(["PicoControl3.PicoVNA_3", "PicoControl2.PicoVNA_2"], {first, second});
            firstShared = first.Shared;
            backend = Palladium.Instruments.PicoVNA.Software3(ServerFactory = @(progId) servers(progId));

            backend.Open();

            testCase.verifyTrue(firstShared("Deleted"), "The library that found nothing is let go");
            testCase.verifyTrue(contains(backend.Description, "9905") && contains(backend.Description, "PicoVNA 106"));
        end

        function NoLibraryFindingTheAnalyserNamesEachTest(testCase)
            servers = containers.Map(["PicoControl3.PicoVNA_3", "PicoControl2.PicoVNA_2"], {testCase.fakeLibrary("0", ""), testCase.fakeLibrary("0", "")});
            backend = Palladium.Instruments.PicoVNA.Software3(ServerFactory = @(progId) servers(progId));

            testCase.verifyError(@() backend.Open(), "PicoVNA_NetworkAnalyser:PicoVNA3NoAnalyser");
            try
                backend.Open();
            catch err
                testCase.verifyTrue(contains(err.message, "PicoControl3.PicoVNA_3") && contains(err.message, "PicoControl2.PicoVNA_2"));
            end
        end

        function MissingLibraryErrorsNamingEachClassTriedTest(testCase)
            backend = Palladium.Instruments.PicoVNA.Software3(ProgIds = ["No.Such.ComClassA", "No.Such.ComClassB"]);

            testCase.verifyError(@() backend.Open(), "PicoVNA_NetworkAnalyser:PicoVNA3NotFound");

            try
                backend.Open();
            catch err
                testCase.verifyTrue(contains(err.message, "No.Such.ComClassA") && contains(err.message, "No.Such.ComClassB"));
            end
        end

        function SweepRunsInTheBackgroundThroughTheRealProcessTest(testCase)
            %End to end, with a stand-in library in a real PowerShell process whose sweep takes 2 s (Windows only):
            %starting the scan returns at once, and the data is there once it finishes
            testCase.assumeTrue(ispc, "COM objects are only available on Windows");
            instr = testCase.connectToSlowStandIn(2);

            timer = tic();
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 2));
            started_s = toc(timer);

            testCase.verifyLessThan(started_s, 1.5, "RunScan doesn't wait for the 2 s sweep");
            testCase.verifyFalse(instr.CheckScanComplete(), "Still sweeping");
            timer = tic();
            while ~instr.CheckScanComplete() && toc(timer) < 20
                pause(0.05);
            end
            testCase.verifyTrue(instr.CheckScanComplete(), "Finished");
            testCase.verifyEqual(instr.GetCompletedScanData(), [1e6, -1.5; 2e6, -2.5]);
        end

        function DisconnectingDuringASweepReturnsPromptlyThroughTheRealProcessTest(testCase)
            %The sweep is cut off with its process, not waited for (Windows only)
            testCase.assumeTrue(ispc, "COM objects are only available on Windows");
            instr = testCase.connectToSlowStandIn(30);
            instr.RunScan(struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 2));

            timer = tic();
            instr.CloseForTest();

            testCase.verifyLessThan(toc(timer), 10, "Doesn't wait for the 30 s sweep");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, server] = makeInstrument(~)
            %The driver, given a fake connection to the library as if connected - with a frequency plan, bandwidth and calibration to read back
            instr = InstrumentTestingInstruments.RecordingPicoVNA();
            server = InstrumentTestingInstruments.FakeComServer();
            server.Replies("GetInfo|FreqPlan") = "3E5,2E9,1E7,201,0";
            server.Replies("GetInfo|BWSet") = "1000";
            server.Replies("GetInfo|CalType") = "S11+S21";
            instr.SetBackendForTest(Palladium.Instruments.PicoVNA.Software3(Server = server));
        end

        function server = fakeLibrary(~, fndReply, model)
            %A fake library that answers FND with a serial number (or 0 for none) and GetInfo("Model") with a model.
            server = InstrumentTestingInstruments.FakeComServer();
            server.Replies("FND") = fndReply;
            server.Replies("GetInfo|Model") = model;
        end

        function setUpSweepData(~, server, numPoints)
            %The plan read back, and the data of the next sweep, for numPoints points (-1.5, -2.5... dB) from 1 MHz in 1 MHz steps.
            server.Replies("GetInfo|FreqPlan") = "1E6," + numPoints * 1e6 + ",1E6," + numPoints + ",0";
            frequency = (1:numPoints)' * 1e6;
            values = -(1:numPoints)' - 0.5;
            server.Replies("GetData|S11|logmag|0") = strjoin(compose("%.15g,%.15g", frequency, values), ",");
            server.Replies("GetData|S21|logmag|0") = server.Replies("GetData|S11|logmag|0");
        end

        function instr = connectToSlowStandIn(testCase, sweepTime_s)
            %The driver connected to a stand-in library in a real PowerShell process, whose Measure takes sweepTime_s.
            script = strjoin([
                "$o = New-Object PSObject"
                "$o | Add-Member ScriptMethod FND { 1234 }"
                "$o | Add-Member ScriptMethod CloseVNA { 'OK' }"
                "$o | Add-Member ScriptMethod SetFreqPlan { param($a, $b, $c, $d, $e) 'OK' }"
                "$o | Add-Member ScriptMethod Measure { param($p) Start-Sleep -Seconds " + sweepTime_s + "; 'OK' }"
                "$o | Add-Member ScriptMethod GetData { param($p, $f, $n) '1000000,-1.5,2000000,-2.5' }"
                "$o | Add-Member ScriptMethod GetInfo { param($p) switch ($p) { 'Model' { 'PicoVNA 106' } 'FreqPlan' { '1000000,2000000,1000000,2,0' } 'BWSet' { '1000' } 'CalType' { 'S11+S21' } default { 'Error' } } }"
                "$o"
                ], newline);
            server = Palladium.Utilities.ComServerProcess("Fake", CreateObjectScript = script);
            backend = Palladium.Instruments.PicoVNA.Software3(Server = server);
            backend.Open();
            instr = InstrumentTestingInstruments.RecordingPicoVNA();
            instr.SetBackendForTest(backend);
            testCase.addTeardown(@() backend.Close());
        end
    end
end
