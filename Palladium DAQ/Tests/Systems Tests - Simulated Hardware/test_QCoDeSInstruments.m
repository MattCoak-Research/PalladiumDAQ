classdef test_QCoDeSInstruments < matlab.unittest.TestCase
    %TEST_QCODESINSTRUMENTS Tests adding QCoDeS drivers from the instruments list, choosing their parameters, and saving them in Presets
    %Runs the whole programme, with its GUI, and needs qcodes installed in
    %the Python MATLAB uses - it skips otherwise. No hardware: the
    %instruments are in Debug mode, which runs the real QCoDeS driver
    %against a fake instrument.

    %% Properties
    properties
        ConfigPath;     %Test config, relative to the Palladium.m folder
        Folder;         %Fresh folder in Testing Data Files for each test's preset files
        Programme;      %The Palladium instance under test, with its GUI
    end

    %% Properties (Constant)
    properties (Constant)
        K2450 = "QCoDeS: Keithley2450";     %The entry in the instruments list of the Keithley 2450 driver
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function fixturesSetup(testCase)
            hasQcodes = false;
            try %#ok<TRYNC>
                hasQcodes = logical(pyrun("import importlib.util; found = importlib.util.find_spec('qcodes') is not None", "found"));
            end
            testCase.assumeTrue(hasQcodes, "qcodes isn't installed in the Python MATLAB uses");

            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "Helpers")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
            testCase.ConfigPath = fullfile("Tests", "TestingConfig.json");
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function setup(testCase)
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            testCase.Folder = string(fixture.Folder);
            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            testCase.Programme = pd;
        end
    end

    %% Methods (Test)
    methods (Test)

        function QCoDeSDriversAreInTheInstrumentListTest(testCase)
            names = string(testCase.instrumentController().ListOfAvailableInstrumentClassNameStrings);

            testCase.verifyTrue(ismember(testCase.K2450, names));
            testCase.verifyGreaterThan(sum(startsWith(names, "QCoDeS: ")), 100);
        end

        function DriversDroppedInTheFolderAreListedTest(testCase)
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            fid = fopen(fullfile(folder.Folder, "MyDevice.py"), "w");
            fprintf(fid, "%s\n", "from qcodes.instrument import VisaInstrument", "class MyDevice(VisaInstrument): pass");
            fclose(fid);
            ic = testCase.instrumentController();

            ic.PythonInstrumentController.LoadQCoDeSDrivers(folder.Folder);
            ic.LoadInstrumentClasses();

            testCase.verifyTrue(ismember("QCoDeS: MyDevice", string(ic.ListOfAvailableInstrumentClassNameStrings)));
        end

        function AddingGivesAConfiguredInstrumentWithAParametersTabTest(testCase)
            instr = testCase.instrumentController().AddInstrument(testCase.K2450);

            testCase.verifyClass(instr, "Palladium.PythonInstruments.QCoDeSInstrument");
            testCase.verifyEqual(instr.Type, testCase.K2450);
            testCase.verifyTrue(startsWith(instr.Name, "Keithley2450"));
            testCase.verifyTrue(ismember("QCoDeS Parameters", instr.GetRegisteredControlNames()));
        end

        function DebugModeRecordsTheChosenParametersTest(testCase)
            instr = testCase.instrumentController().AddInstrument(testCase.K2450, ConnectionType="Debug");
            instr.RecordedParameters = ["line_frequency", "timeout"];
            instr.ParameterSettings = '{"source_function": "voltage"}';

            evalc("instr.Connect()");
            testCase.addTeardown(@() testCase.disconnectQuietly(instr));
            headers = instr.GetHeaders();
            row = instr.Measure();
            metadata = instr.CollectMetaData();

            testCase.verifyEqual(headers, instr.Name + " - " + ["line_frequency_Hz", "timeout_s"]);
            testCase.verifySize(row, [1 2]);
            testCase.verifyEqual(string(metadata.source_function), "voltage");
        end

        function PresetKeepsTheDriverAndTheParameterChoicesTest(testCase)
            ic = testCase.instrumentController();
            instr = ic.AddInstrument(testCase.K2450, ConnectionType="Debug");
            instr.RecordedParameters = ["line_frequency", "timeout"];
            instr.ParameterSettings = '{"source_function": "voltage"}';
            path = fullfile(testCase.Folder, "QCoDeS.json");
            ctrl = testCase.Programme.Controller;
            Palladium.Utilities.PluginLoading.SavePresetToJson(ctrl, ic, testCase.Programme.View, path);
            saved = jsondecode(fileread(path));
            testCase.verifyEqual(string(saved.Instruments.Type), testCase.K2450);

            ic.RemoveInstrument(instr);
            Palladium.Utilities.PluginLoading.ApplyPresetFromJson(ctrl, testCase.Programme.View, path);

            loaded = ic.GetInstruments();
            testCase.verifyNumElements(loaded, 1);
            testCase.verifyEqual(loaded{1}.RecordedParameters, ["line_frequency", "timeout"]);
            testCase.verifyEqual(jsondecode(char(loaded{1}.ParameterSettings)), struct("source_function", 'voltage'));
        end

        function ParametersTabWritesRecordingsAndSettingsToTheInstrumentTest(testCase)
            instr = testCase.instrumentController().AddInstrument(testCase.K2450, ConnectionType="Debug");
            table = testCase.parametersTable();

            testCase.editCell(table, "line_frequency", 1, true);
            testCase.editCell(table, "source_function", 4, "voltage");

            testCase.verifyEqual(instr.RecordedParameters, "line_frequency");
            testCase.verifyEqual(jsondecode(char(instr.ParameterSettings)), struct("source_function", 'voltage'));

            testCase.editCell(table, "line_frequency", 1, false);
            testCase.editCell(table, "source_function", 4, "");

            testCase.verifyEmpty(instr.RecordedParameters);
            testCase.verifyEqual(jsondecode(char(instr.ParameterSettings)), struct());
        end

        function ParametersTabRefusesASettingThatCannotBeSetTest(testCase)
            instr = testCase.instrumentController().AddInstrument(testCase.K2450, ConnectionType="Debug");
            table = testCase.parametersTable();

            testCase.editCell(table, "line_frequency", 4, "50");    %Read-only on the instrument

            testCase.verifyEqual(jsondecode(char(instr.ParameterSettings)), struct());
            isRow = string(table.Data(:, 2)) == "line_frequency";
            testCase.verifyEqual(string(table.Data{isRow, 4}), "");
        end

        function ParametersTabShowsChangesMadeToTheInstrumentTest(testCase)
            %For instance, loading a Preset
            instr = testCase.instrumentController().AddInstrument(testCase.K2450, ConnectionType="Debug");
            table = testCase.parametersTable();

            instr.RecordedParameters = "timeout";
            instr.ParameterSettings = '{"source_function": "current"}';

            data = table.Data;
            testCase.verifyTrue(data{string(data(:, 2)) == "timeout", 1});
            testCase.verifyFalse(data{string(data(:, 2)) == "line_frequency", 1});
            testCase.verifyEqual(string(data{string(data(:, 2)) == "source_function", 4}), "current");
        end

    end

    %% Methods (Private)
    methods (Access = private)
        function ic = instrumentController(testCase)
            ic = testCase.Programme.Controller.InstrumentController;
        end

        function disconnectQuietly(~, instr) %#ok<INUSD>
            %Disconnect, keeping its messages out of the test output
            evalc("instr.Disconnect()");
        end

        function table = parametersTable(~)
            %The Parameters tab's table of the instrument added last
            tables = findall(groot, "Type", "uitable");
            isParameters = arrayfun(@(t) iscell(t.ColumnName) && any(strcmp(t.ColumnName, "Record")) || (isstring(t.ColumnName) && any(t.ColumnName == "Record")), tables);
            assert(any(isParameters), "No Parameters table found");
            table = tables(find(isParameters, 1));
        end

        function editCell(~, table, parameter, column, newValue)
            %Edit a cell as a user does: change the data, then call the table's edit callback with the edit's details
            row = find(string(table.Data(:, 2)) == parameter);
            assert(isscalar(row), "Parameter " + parameter + " not in the table");
            previous = table.Data{row, column};
            if isstring(newValue)
                newValue = char(newValue);      %A table's text cells are char
            end
            table.Data{row, column} = newValue;
            table.CellEditCallback(table, struct("Indices", [row column], "NewData", newValue, "PreviousData", previous));
        end
    end
end
