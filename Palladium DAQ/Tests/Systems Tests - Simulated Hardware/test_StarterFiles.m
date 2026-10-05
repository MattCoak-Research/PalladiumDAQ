classdef test_StarterFiles < matlab.unittest.TestCase
    %TEST_STARTERFILES Tests that starting Palladium DAQ puts the starter files in the user files folder, and keeps the driver templates out of the Instruments list

    %% Properties
    properties
        Programme;      %The Palladium instance under test, headless
        UserFilesDir;   %The test user files folder ("Palladium DAQ - User Files" in Tests/Testing User Files)
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function setup(testCase)
            %Palladium writes its data files, sequences and logs to the
            %Data, Sequences and Logs folders in Testing Data Files (see
            %TestingConfig.json). The fixture removes them again afterwards.
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "Helpers")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
            testCase.UserFilesDir = fullfile(TestHelpers.TestingPaths.UserFilesDir(), "Palladium DAQ - User Files");

            pd = Palladium(View=[], ConfigFilePath=fullfile("Tests", "TestingConfig.json"));
            testCase.addTeardown(@() pd.Close());
            testCase.Programme = pd;
        end
    end

    %% Methods (Test)
    methods (Test)
        function StarterFilesCopied(testCase)
            %The example Preset, the driver templates and the PPMS
            %interface DLL are in the user files folder
            expected = ["Presets/Example.json", ...
                "+Palladium/+Instruments/TemplateInstrumentClass.m", ...
                "PythonInstruments/TemplatePythonInstrument.py", ...
                "Instrument Drivers/Quantum Design/PPMS Communication/QDInterface.dll"];
            for f = expected
                testCase.verifyTrue(isfile(fullfile(testCase.UserFilesDir, f)), f + " should be in the user files folder");
            end
        end

        function TemplatesNotListedAsInstruments(testCase)
            %Neither template is offered as an instrument, though both are
            %in the user files folder
            names = string(testCase.Programme.GetAllInstrumentClassNames());
            testCase.verifyFalse(any(names == "TemplateInstrumentClass"));
            testCase.verifyFalse(any(names == "TemplatePythonInstrument"));
            testCase.verifyTrue(any(names == "Keithley2000"), "Built-in drivers should still be listed");
        end

        function PythonTemplateImportedButFiltered(testCase)
            %Python loads the template (so it is the filter, not a failed
            %import, that keeps it out of the list) - needs a usable Python
            pyc = testCase.Programme.Controller.InstrumentController.PythonInstrumentController;
            testCase.assumeNotEmpty(pyc, "Python isn't usable here, so Python instruments aren't loaded");
            testCase.verifyTrue(any(string(pyc.AvaialableInstrNames) == "TemplatePythonInstrument"));
        end

        function CopiedPythonTemplateRunsAsInstrument(testCase)
            %A user's copy of the template Python instrument (renamed file
            %and class) is listed, can be added in Debug mode, and writes
            %its columns and metadata to the data file. Uses its own user
            %files and data folders, in a new folder in Testing Data Files
            pyc = testCase.Programme.Controller.InstrumentController.PythonInstrumentController;
            testCase.assumeNotEmpty(pyc, "Python isn't usable here, so Python instruments aren't loaded");

            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            root = string(fixture.Folder);
            appDir = string(fileparts(which("Palladium")));
            pyDir = fullfile(root, "UserFiles", "Palladium DAQ - User Files", "PythonInstruments");
            mkdir(pyDir);

            %The user's copy: MyTemplateCopy.py, containing class MyTemplateCopy
            code = fileread(fullfile(appDir, "ExamplesAndTemplates", "PythonInstruments", "TemplatePythonInstrument.py"));
            writelines(replace(code, "class TemplatePythonInstrument(", "class MyTemplateCopy("), fullfile(pyDir, "MyTemplateCopy.py"));

            %A config pointing the user files, data and sequences at that folder.
            %Logs stay in Testing Data Files/Logs: the Logger is shared, and the
            %class's own Palladium logs its closing to the newest instance's log
            %folder, after this folder has gone
            cfg = readstruct(fullfile(appDir, "Tests", "TestingConfig.json"));
            cfg.PathSettings.UserFilesDirectory = fullfile(root, "UserFiles");
            cfg.PathSettings.UserFilesDirectoryIsRelativePath = false;
            cfg.PathSettings.DefaultDirectory = fullfile(root, "Data");
            cfg.PathSettings.DataDirectoryIsRelativePath = false;
            cfg.PathSettings.DefaultSequenceDirectory = fullfile(root, "Sequences");
            cfg.PathSettings.SequenceDirectoryIsRelativePath = false;
            configPath = fullfile(root, "Config.json");
            writestruct(cfg, configPath, FileType="json");

            pd = Palladium(View=[], ConfigFilePath=extractAfter(configPath, appDir + filesep));
            testCase.addTeardown(@() pd.Close());   %Runs before the fixture removes the folder

            testCase.verifyTrue(any(string(pd.GetAllInstrumentClassNames()) == "MyTemplateCopy"), "The copy should be listed as an instrument");
            instr = pd.AddInstrument("MyTemplateCopy", ConnectionType="Debug");
            pd.SetFileName("PyTemplate");
            pd.SetUpdateTime(0.2);
            pd.Start();
            pause(1.5);
            pd.Stop();

            files = dir(fullfile(root, "Data", "*.dat"));
            testCase.assertNumElements(files, 1);
            lines = readlines(fullfile(files(1).folder, files(1).name));
            testCase.verifyTrue(any(contains(lines, instr.Name + " Settings: ExampleSetting = Auto range")), "The template's metadata should be in the header");
            endIdx = find(lines == Palladium.DataWriting.DataWriter.END_METADATA_LINES_STRING);
            headers = split(strtrim(lines(endIdx + 2)), sprintf("\t"));
            testCase.verifyEqual(headers', ["Time (mins)", instr.Name + " - Resistance_Ohms", instr.Name + " - Current_A"]);
            rows = lines(endIdx + 3 : end);
            rows = rows(rows ~= "");
            testCase.verifyNotEmpty(rows, "Data should be written");
            testCase.verifyNumElements(split(strtrim(rows(1)), sprintf("\t")), 3, "Each row: time and the template's two values");
        end
    end
end
