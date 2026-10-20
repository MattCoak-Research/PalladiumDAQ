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

            cont.ScanRun();
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
            cont.ScanRun();
            testCase.waitForScan(cont);
            settings = instr.GetScanSettings();
            testCase.verifyEqual([settings.StartFrequency_Hz, settings.StopFrequency_Hz], [100e6, 200e6], RelTol=1e-12);
            testCase.verifyEqual(fields.StartFrequency.Value, 0.1, "Read back in the units chosen", RelTol=1e-12);
        end

        function StopBelowStartIsRefusedTest(testCase, InstrumentType)
            [~, cont] = testCase.addAnalyser(InstrumentType);
            testCase.startMeasurements();
            fields = struct(cont).Fields;
            fields.StartFrequency.Value = 300;
            fields.StopFrequency.Value = 200;

            testCase.verifyError(@() cont.ScanRun(), "VNAController:InvalidFrequencyRange");
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
