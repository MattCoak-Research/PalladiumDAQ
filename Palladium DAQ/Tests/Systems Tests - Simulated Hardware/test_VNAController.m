classdef test_VNAController < matlab.unittest.TestCase
    %TEST_VNACONTROLLER Tests the VNA Control in a running Palladium: its settings panel, filled from the analyser, sent with each Run
    %For each analyser that uses it, in simulation (Debug). The control
    %doesn't know the instruments' methods: it passes a struct of settings
    %to RunScan, and fills the panel from GetScanSettings.

    %% Properties
    properties
        ConfigPath;     %Test config, relative to the Palladium.m folder
        Programme;      %The Palladium instance under test, with its GUI
        DataDir;        %Where the programme writes its data files (from TestingConfig.json)
    end

    %% Properties (TestParameter)
    properties (TestParameter)
        InstrumentType = {"PNA_L_NetworkAnalyser", "HP_8722ES_NetworkAnalyser", "PicoVNA_NetworkAnalyser"};
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function fixturesSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "Helpers")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
            testCase.ConfigPath = fullfile("Tests", "TestingConfig.json");
            testCase.DataDir = fullfile(string(fileparts(which("Palladium"))), "Tests", "Testing Data Files", "Data");

            %The tests reach the control's private components (struct of an object)
            warning("off", "MATLAB:structOnObject");
            testCase.addTeardown(@() warning("on", "MATLAB:structOnObject"));
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function setup(testCase)
            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            testCase.Programme = pd;
        end
    end

    %% Methods (Test)
    methods (Test)
        function ChangingAnInstrumentSettingTest(testCase, InstrumentType)
            %The Scan Control's listener called a method it didn't have, so
            %changing an instrument setting errored; the panel follows it
            [instr, cont] = testCase.addAnalyser(InstrumentType);

            testCase.verifyWarningFree(@() setMeasMode(instr));
            fields = struct(cont).Fields;
            testCase.verifyEqual(string(fields.MeasMode.Value), "S22");

            function setMeasMode(instr)
                instr.MeasMode = instr.MeasType("S22");
            end
        end

        function PanelStartsFromTheAnalyserTest(testCase, InstrumentType)
            %Filled in from GetScanSettings once measurements start (connected)
            [instr, cont] = testCase.addAnalyser(InstrumentType);
            fields = struct(cont).Fields;
            fields.NumPoints.Value = 2;     %Not the analyser's

            testCase.startMeasurements();

            settings = instr.GetScanSettings();
            testCase.verifyEqual(fields.NumPoints.Value, settings.NumPoints);
            testCase.verifyEqual(fields.StartFrequency.Value, settings.StartFrequency_Hz / 1e6, RelTol=1e-12);
        end

        function RunSendsTheSettingsTest(testCase, InstrumentType)
            %The panel's settings reach the analyser, the scan follows them,
            %and the data file records them
            [instr, cont] = testCase.addAnalyser(InstrumentType);
            testCase.startMeasurements();
            fields = struct(cont).Fields;
            fields.StartFrequency.Value = 100;
            fields.StopFrequency.Value = 200;
            fields.NumPoints.Value = 51;
            fields.MeasMode.Value = "S21";
            gui = struct(cont).GUIView;
            saveBox = struct(gui).SavetonewfileCheckBox;
            saveBox.Value = true;
            gui.SetNewSweepName(" - VNA " + InstrumentType);
            before = string({dir(fullfile(testCase.DataDir, "*.dat")).name});

            cont.Run();
            testCase.waitForScan(cont);

            testCase.verifyEqual(string(instr.MeasMode), "S21");
            files = dir(fullfile(testCase.DataDir, "*.dat"));
            files = files(~ismember(string({files.name}), before));
            testCase.assertNumElements(files, 1, "The scan writes one file");
            [metadata, headers, data] = Palladium.DataWriting.DataReader().ReadFile(fullfile(files(1).folder, files(1).name));
            testCase.verifySize(data, [51, 2]);
            testCase.verifyEqual(data([1 end], 1)', [100e6, 200e6], RelTol=1e-9);
            testCase.verifyTrue(contains(headers(2), "S21"));
            testCase.verifyTrue(any(contains(metadata, "NumPoints = 51")), "Settings in the metadata");
        end

        function FrequencyUnitsTest(testCase, InstrumentType)
            %Changing a frequency's units converts the value shown, keeping
            %the frequency; Run sends it in Hz
            [instr, cont] = testCase.addAnalyser(InstrumentType);
            testCase.startMeasurements();
            fields = struct(cont).Fields;
            fields.StartFrequency.Value = 100;
            fields.StopFrequency.Value = 200;

            testCase.chooseUnit(fields.StartFrequencyUnit, "GHz");
            testCase.chooseUnit(fields.StopFrequencyUnit, "kHz");

            testCase.verifyEqual(fields.StartFrequency.Value, 0.1, "100 MHz is 0.1 GHz", RelTol=1e-12);
            testCase.verifyEqual(fields.StopFrequency.Value, 2e5, "200 MHz is 200000 kHz", RelTol=1e-12);
            cont.Run();
            testCase.waitForScan(cont);
            settings = instr.GetScanSettings();
            testCase.verifyEqual([settings.StartFrequency_Hz, settings.StopFrequency_Hz], [100e6, 200e6], RelTol=1e-12);
            testCase.verifyEqual(fields.StartFrequency.Value, 0.1, "Read back in the units chosen", RelTol=1e-12);
        end

        function SmithChartScansRealAndImaginaryTest(testCase, InstrumentType)
            %Choosing the Smith chart sets (and locks) the units to Real/Imaginary, the scan has real and imaginary columns,
            %the plotter shows a Smith chart - and choosing the trace again puts the units back
            testCase.assumeTrue(Palladium.Utilities.GUIUtils.IsSmithPlotAvailable(), "Needs RF Toolbox");
            [~, cont] = testCase.addAnalyser(InstrumentType);
            testCase.startMeasurements();
            fields = struct(cont).Fields;
            testCase.verifyEqual(string(fields.PlotType.Items), ["Trace against frequency", "Smith chart"], "Smith offered: the analyser can give complex data");
            unitsBefore = string(fields.MeasUnit.Value);

            testCase.choosePlot(fields.PlotType, "Smith chart");

            testCase.verifyEqual(string(fields.MeasUnit.Value), "Real/Imaginary");
            testCase.verifyEqual(string(fields.MeasUnit.Enable), "off", "Locked while the Smith chart needs it");
            testCase.verifyEqual(struct(cont).Plotter.PlotKind, "Smith");

            fields.NumPoints.Value = 21;
            saveBox = struct(struct(cont).GUIView).SavetonewfileCheckBox;
            saveBox.Value = true;
            struct(cont).GUIView.SetNewSweepName(" - Smith " + InstrumentType);
            before = string({dir(fullfile(testCase.DataDir, "*.dat")).name});
            cont.Run();
            testCase.waitForScan(cont);

            files = dir(fullfile(testCase.DataDir, "*.dat"));
            files = files(~ismember(string({files.name}), before));
            testCase.assertNumElements(files, 1);
            [~, headers, data] = Palladium.DataWriting.DataReader().ReadFile(fullfile(files(1).folder, files(1).name));
            testCase.verifySize(data, [21, 3]);
            testCase.verifyTrue(contains(headers(2), "Real") && contains(headers(3), "Imaginary"));
            testCase.verifyEqual(string(fields.MeasUnit.Enable), "off", "Still locked after the scan");

            testCase.choosePlot(fields.PlotType, "Trace against frequency");

            testCase.verifyEqual(string(fields.MeasUnit.Value), unitsBefore);
            testCase.verifyEqual(string(fields.MeasUnit.Enable), "on");
            testCase.verifyEqual(struct(cont).Plotter.PlotKind, "Scatter");
        end

        function SmithChartAfterAScanWithoutComplexDataIsQuietTest(testCase, InstrumentType)
            %The last scan was in dB, so has nothing to show on a Smith chart: choosing it just leaves the chart empty
            %until the next scan (which will be Real/Imaginary) - no warning
            testCase.assumeTrue(Palladium.Utilities.GUIUtils.IsSmithPlotAvailable(), "Needs RF Toolbox");
            [~, cont] = testCase.addAnalyser(InstrumentType);
            testCase.startMeasurements();
            fields = struct(cont).Fields;
            fields.NumPoints.Value = 21;
            cont.Run();
            testCase.waitForScan(cont);

            output = evalc('testCase.choosePlot(fields.PlotType, "Smith chart")');

            testCase.verifyFalse(contains(output, "Smith chart needs"), "No warning");
            testCase.verifyEqual(struct(cont).Plotter.PlotKind, "Smith");
            testCase.verifyEqual(string(fields.MeasUnit.Value), "Real/Imaginary");
        end

        function SmithChartWithoutRFToolboxGoesBackToTheTraceTest(testCase, InstrumentType)
            %Palladium runs without RF Toolbox: choosing the Smith chart warns and leaves everything as it was
            testCase.assumeTrue(Palladium.Utilities.GUIUtils.IsSmithPlotAvailable(), "Needs RF Toolbox, to take away");
            folder = fileparts(which("smithplot"));
            rmpath(folder);
            testCase.addTeardown(@() addpath(folder));
            [~, cont] = testCase.addAnalyser(InstrumentType);
            testCase.startMeasurements();
            fields = struct(cont).Fields;
            unitsBefore = string(fields.MeasUnit.Value);

            testCase.choosePlot(fields.PlotType, "Smith chart");

            testCase.verifyEqual(string(fields.PlotType.Value), "Trace against frequency", "Back to the trace");
            testCase.verifyEqual(string(fields.MeasUnit.Value), unitsBefore, "Units untouched");
            testCase.verifyEqual(string(fields.MeasUnit.Enable), "on");
            testCase.verifyEqual(struct(cont).Plotter.PlotKind, "Scatter");
        end

        function SettersChangeThePanelLikeTypingTest(testCase, InstrumentType)
            %The Set... methods a sequence uses put the values in the panel's fields
            [instr, cont] = testCase.addAnalyser(InstrumentType);
            fields = struct(cont).Fields;

            cont.SetFrequencyRange(100e6, 2e9);
            cont.SetNumberOfPoints(51);
            cont.SetSweepTime(0.5);
            cont.SetSweepType("log");
            cont.SetSParameter("s21");
            cont.SetUnits("absolute");

            testCase.verifyEqual(fields.StartFrequency.Value, 100, RelTol = 1e-12);
            testCase.verifyEqual(fields.StopFrequency.Value, 2000, RelTol = 1e-12);
            testCase.verifyEqual(fields.NumPoints.Value, 51);
            testCase.verifyEqual(fields.SweepTime.Value, 0.5);
            testCase.verifyEqual(string(fields.SweepType.Value), "Log", "Case is ignored");
            testCase.verifyEqual(string(fields.MeasMode.Value), "S21");
            testCase.verifyEqual(string(fields.MeasUnit.Value), "Absolute");

            %In whatever units the panel shows
            testCase.chooseUnit(fields.StartFrequencyUnit, "GHz");
            cont.SetStartFrequency(300e6);
            testCase.verifyEqual(fields.StartFrequency.Value, 0.3, RelTol = 1e-12);
            testCase.verifyEqual(instr.MeasUnit, instr.MeasUnitType("dB"), "The instrument is only told on Run");
        end

        function SettersRefuseWhatThePanelWouldNotTakeTest(testCase, InstrumentType)
            [~, cont] = testCase.addAnalyser(InstrumentType);

            testCase.verifyError(@() cont.SetSParameter("S99"), "VNAController:UnknownChoice");
            testCase.verifyError(@() cont.SetSweepType("Exponential"), "VNAController:UnknownChoice");
            testCase.verifyError(@() cont.SetFrequencyRange(2e9, 1e9), "VNAController:InvalidFrequencyRange");
            testCase.verifyError(@() cont.SetNumberOfPoints(10.5), "MATLAB:validators:mustBeInteger");
            testCase.verifyError(@() cont.SetStartFrequency(-1), "MATLAB:validators:mustBePositive");
            message = testCase.errorMessage(@() cont.SetUnits("furlongs"));
            testCase.verifyTrue(contains(message, "dB") && contains(message, "Absolute"), "The choices are listed");
        end

        function SmithChartPlotTypeSetsTheUnitsLikeTheDropDownTest(testCase, InstrumentType)
            testCase.assumeTrue(Palladium.Utilities.GUIUtils.IsSmithPlotAvailable(), "Needs RF Toolbox");
            [~, cont] = testCase.addAnalyser(InstrumentType);
            fields = struct(cont).Fields;

            cont.SetPlotType("Smith");

            testCase.verifyEqual(string(fields.PlotType.Value), "Smith chart");
            testCase.verifyEqual(string(fields.MeasUnit.Value), "Real/Imaginary");
            testCase.verifyError(@() cont.SetUnits("dB"), "VNAController:UnitsLocked");

            cont.SetPlotType("Trace");

            testCase.verifyEqual(string(fields.PlotType.Value), "Trace against frequency");
            testCase.verifyEqual(string(fields.MeasUnit.Value), "dB", "The units come back");
            cont.SetUnits("Absolute");
        end

        function RunAndAbortUpdateThePanelLikeTheButtonTest(testCase, InstrumentType)
            %Run and Abort, as a sequence calls them: the button, the fields and the plot are told just as for a press
            [~, cont] = testCase.addAnalyser(InstrumentType);
            testCase.startMeasurements();
            fields = struct(cont).Fields;
            runButton = struct(struct(cont).GUIView).RunButton;
            cont.SetSaveSweepFile(false);
            cont.SetNumberOfPoints(21);
            testCase.verifyEqual(string(runButton.Text), "Run");

            cont.Run();

            testCase.verifyTrue(cont.Running);
            testCase.verifyEqual(string(runButton.Text), "Abort", "The button changes as for a press");
            testCase.verifyEqual(string(fields.NumPoints.Enable), "off", "The settings are locked");
            testCase.verifyError(@() cont.Run(), "ScanController:AlreadyRunning");
            testCase.verifyError(@() cont.SetNumberOfPoints(11), "VNAController:ScanRunning");

            cont.Abort();

            testCase.verifyFalse(cont.Running);
            testCase.verifyEqual(string(runButton.Text), "Run");
            testCase.verifyEqual(string(fields.NumPoints.Enable), "on");
            cont.Abort();       %Nothing running: nothing to do

            cont.Run();         %And a scan can be run to its end
            testCase.waitForScan(cont);
            testCase.verifyEqual(string(runButton.Text), "Run");
            testCase.verifyEqual(string(fields.NumPoints.Enable), "on");
        end

        function SequencesCanDriveTheControlTest(testCase, InstrumentType)
            %The commands a sequence is offered, and that Run waits for the scan to end
            [instr, cont] = testCase.addAnalyser(InstrumentType);
            methods = Palladium.Utilities.PluginLoading.GetInstrumentControlMethods(instr, "VNA Control");
            methods = string(methods(:))';

            testCase.verifyTrue(all(ismember(["Run", "Abort", "SetNumberOfPoints(numPoints)", "SetFrequencyRange(start_Hz, stop_Hz)", "SetSweepName(name)"], methods)));
            testCase.verifyFalse(any(ismember(["ScanRun", "ScanAbort", "OnScanRun", "OnScanAbort", "ScanDataChanged(~, eventData)", "UpdateData"], methods)), "Internals are not offered");

            testCase.startMeasurements();
            cont.SetSaveSweepFile(false);
            cont.SetNumberOfPoints(11);
            cont.Run();
            completeFn = cont.GetCommandCompleteFn("Run()");
            testCase.verifyFalse(completeFn(), "Not complete while scanning");
            testCase.waitForScan(cont);
            testCase.verifyTrue(completeFn(), "Complete once the scan has finished");
        end

        function QueuedCommandsRunAScanLikeASequenceTest(testCase, InstrumentType)
            %The commands a sequence makes, queued one per tick: set up a scan, run it (waiting for it to end), and the file is written
            [instr, ~] = testCase.addAnalyser(InstrumentType);
            before = string({dir(fullfile(testCase.DataDir, "*.dat")).name});
            commands = ["SetFrequencyRange(100e6, 200e6)", "SetNumberOfPoints(21)", "SetSaveSweepFile(true)", ...
                "SetSweepName(' - queued " + InstrumentType + "')", "Run()"];
            for command = commands
                testCase.Programme.CacheInstrumentCommand(instr, command, "VNA Control");
            end

            testCase.startMeasurements();
            timer = tic;
            files = [];
            while isempty(files) && toc(timer) < 30
                pause(0.2);
                files = dir(fullfile(testCase.DataDir, "*queued " + InstrumentType + "*.dat"));
                files = files(~ismember(string({files.name}), before));
            end

            testCase.assertNumElements(files, 1, "The queued scan wrote its file");
            pause(1);
            [~, ~, data] = Palladium.DataWriting.DataReader().ReadFile(fullfile(files(1).folder, files(1).name));
            testCase.verifySize(data, [21, 2]);
            testCase.verifyEqual(data([1 end], 1)', [100e6, 200e6], RelTol = 1e-9);
        end

        function StopBelowStartIsRefusedTest(testCase, InstrumentType)
            [~, cont] = testCase.addAnalyser(InstrumentType);
            testCase.startMeasurements();
            fields = struct(cont).Fields;
            fields.StartFrequency.Value = 300;
            fields.StopFrequency.Value = 200;

            %Run goes through the panel like the button, whose error dialogue is answered for the test
            Palladium.Logging.Logger.TestDialogResponse("set", "Ignore");
            testCase.addTeardown(@() Palladium.Logging.Logger.TestDialogResponse("set", ""));

            testCase.verifyError(@() cont.Run(), "ScanController:ScanNotStarted");
            testCase.verifyFalse(cont.Running);
            testCase.verifyEqual(string(fields.NumPoints.Enable), "on", "Settings usable again");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, cont] = addAnalyser(testCase, instrumentType)
            %An analyser in simulation, with its VNA Control (added by default)
            instr = testCase.Programme.AddInstrument(instrumentType, ConnectionType="Debug");
            cont = instr.GetRegisteredControlObjectsFromName("VNA Control");
            testCase.assertClass(cont, "Palladium.Instruments.Controls.VNAController");
        end

        function startMeasurements(testCase)
            pd = testCase.Programme;
            pd.Start();
            testCase.addTeardown(@() pd.Stop());
            pause(1);
        end

        function message = errorMessage(~, fcn)
            %The message of the error fcn throws.
            message = "";
            try
                fcn();
            catch err
                message = string(err.message);
            end
        end

        function choosePlot(~, dropDown, plotType)
            %Choose a plot type as the user would - setting Value alone doesn't run the drop-down's callback
            previous = dropDown.Value;
            dropDown.Value = plotType;
            dropDown.ValueChangedFcn(dropDown, struct("PreviousValue", previous, "Value", plotType));
        end

        function chooseUnit(~, dropDown, unit)
            %Choose a unit as the user would - setting Value alone doesn't run the drop-down's callback
            previous = dropDown.Value;
            dropDown.Value = unit;
            dropDown.ValueChangedFcn(dropDown, struct("PreviousValue", previous, "Value", unit));
        end

        function waitForScan(testCase, cont)
            %Until the scan has been saved - the measurement loop checks it each tick
            timer = tic;
            while cont.Running && toc(timer) < 30
                pause(0.2);
            end
            testCase.assertFalse(cont.Running, "The scan didn't finish");
        end
    end
end
