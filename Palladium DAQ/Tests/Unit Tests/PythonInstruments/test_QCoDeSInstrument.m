classdef test_QCoDeSInstrument < matlab.unittest.TestCase
    %TEST_QCODESINSTRUMENT Tests using QCoDeS drivers as Palladium instruments (PalladiumPythonCore/QCoDeSInstrument.py)
    %Needs qcodes installed in the Python MATLAB uses, and skips otherwise.
    %No hardware: Debug mode runs the real driver against a fake instrument
    %(QCoDeSOffline), and the connecting tests fake the VISA connection.

    %% Properties
    properties
        Instruments;    %The qcodes_test_instruments Python module
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function importInstruments(testCase)
            here = fileparts(mfilename("fullpath"));
            sourceRoot = fileparts(fileparts(fileparts(here)));     %Holds PalladiumPythonCore
            dataDir = fullfile(fileparts(here), "data", "Python Testing");

            hasQcodes = false;
            try %#ok<TRYNC>
                hasQcodes = logical(pyrun("import importlib.util; found = importlib.util.find_spec('qcodes') is not None", "found"));
            end
            testCase.assumeTrue(hasQcodes, "qcodes isn't installed in the Python MATLAB uses");

            %Don't let Python write __pycache__ folders into the source or test data folders
            oldSetting = pyrun("import sys; old = sys.dont_write_bytecode; sys.dont_write_bytecode = True", "old");
            testCase.addTeardown(@() pyrun("import sys; sys.dont_write_bytecode = setting", setting=oldSetting));

            for folder = [string(sourceRoot), string(dataDir)]
                py.sys.path().insert(int32(0), folder);
                testCase.addTeardown(@() py.sys.path().remove(folder));
            end

            %Import afresh, so the current files are tested
            for moduleName = ["PalladiumPythonCore.Instrument", "PalladiumPythonCore.QCoDeSOffline", "PalladiumPythonCore.QCoDeSInstrument"]
                py.importlib.reload(py.importlib.import_module(moduleName));
            end
            testCase.Instruments = py.importlib.reload(py.importlib.import_module("qcodes_test_instruments"));
        end
    end

    %% Methods (Test)
    methods (Test)

        function DebugModeGivesNumericHeadersAndReadingsTest(testCase)
            instr = testCase.wrapped(testCase.Instruments.Lakeshore336Test());
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            testCase.connect(instr);

            [headers, units] = instr.GetHeaders();
            row = instr.Measure();

            testCase.verifyEqual(headers, instr.Name + " - " + ["A_temperature_K", "B_temperature_K"]);
            testCase.verifyEqual(units, ["K", "K"]);
            testCase.verifySize(row, [1 2]);
            testCase.verifyTrue(isnumeric(row) && all(isfinite(row)));
        end

        function SimulatedReadingsVaryTest(testCase)
            instr = testCase.wrapped(testCase.Instruments.K2450Test());
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            testCase.connect(instr);

            rows = [instr.Measure(); instr.Measure(); instr.Measure()];

            testCase.verifyGreaterThan(numel(unique(rows(:, 2))), 1, "Simulated data should not be constant");
        end

        function SettingsAreAppliedAndRecordedInMetadataTest(testCase)
            instr = testCase.wrapped(testCase.Instruments.K2450Test());
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            testCase.connect(instr);

            metadata = instr.CollectMetaData();

            testCase.verifyEqual(string(metadata.source_function), "voltage");
            testCase.verifyEqual(string(metadata.Driver), "Keithley2450");
            testCase.verifyEqual(string(metadata.Model), "MODEL 2450");
        end

        function DriverValidatorRejectsABadSettingTest(testCase)
            instr = testCase.wrapped(testCase.Instruments.K2450BadSettingTest());
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;

            err = testCase.capturedError(@() testCase.connect(instr));

            testCase.verifySubstring(string(err.message), "bogus");
            testCase.verifyFalse(instr.IsConnected);
        end

        function UnknownParameterErrorListsTheParametersTest(testCase)
            instr = testCase.wrapped(testCase.Instruments.K2450UnknownParameterTest());
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;

            err = testCase.capturedError(@() testCase.connect(instr));

            testCase.verifySubstring(string(err.message), "not_a_parameter");
            testCase.verifySubstring(string(err.message), "line_frequency");
        end

        function NonNumericParameterGivesAClearErrorTest(testCase)
            instr = testCase.wrapped(testCase.Instruments.K2450NonNumericTest());
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            testCase.connect(instr);

            err = testCase.capturedError(@() instr.Measure());

            testCase.verifySubstring(string(err.message), "isn't a number");
        end

        function DebugIsOfferedOnlyForDriversThatCanBeSimulatedTest(testCase)
            simulatable = testCase.wrapped(testCase.Instruments.K2450Test());
            notSimulatable = testCase.wrapped(testCase.Instruments.Keithley2601BTest());

            testCase.verifyTrue(ismember(Palladium.Enums.ConnectionType.Debug, simulatable.GetSupportedConnectionTypes()));
            testCase.verifyFalse(ismember(Palladium.Enums.ConnectionType.Debug, notSimulatable.GetSupportedConnectionTypes()));
            testCase.verifyNotEmpty(string(notSimulatable.PyInstr.SimulationProblem));
        end

        function GPIBConnectionUsesTheAddressAndTimeoutTest(testCase)
            pyInstr = testCase.Instruments.K2450NoSettingsTest();
            handle = testCase.Instruments.connect_gpib_with_fake_visa(pyInstr, int32(0), int32(18), 7.5);
            testCase.addTeardown(@() pyInstr.close());

            testCase.verifyEqual(string(handle.resource_name), "GPIB0::18::INSTR");
            testCase.verifyEqual(double(pyInstr.parameter("timeout").get()), 7.5);
            headerAndUnits = pyInstr.GetHeaders();     %A Python tuple: (headers, units)
            headers = cell(headerAndUnits{1});
            testCase.verifyEqual(string(cellfun(@char, headers, UniformOutput=false)), ["timeout_s", "line_frequency_Hz"]);
        end

        function DisconnectFreesTheDriverSoItCanConnectAgainTest(testCase)
            instr = testCase.wrapped(testCase.Instruments.K2450Test());
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;

            for i = 1 : 2
                testCase.connect(instr);
                evalc("instr.Disconnect()");
            end

            testCase.verifyFalse(instr.IsConnected);
        end

    end

    %% Methods (Private)
    methods (Access = private)
        function instr = wrapped(testCase, pyInstr)
            %A PythonInstrument wrapping a Python instrument
            instr = Palladium.PythonInstruments.PythonInstrument(pyInstr);
            testCase.addTeardown(@() testCase.cleanUp(instr));
        end

        function cleanUp(~, instr)
            %Close the driver if a test left it open, so its QCoDeS name is freed
            try
                if instr.IsConnected
                    evalc("instr.Disconnect()");
                end
            catch
                %Closing is best effort
            end
            delete(instr);
        end

        function err = capturedError(testCase, fcn)
            %The error a function throws - the test stops here if it doesn't throw one
            err = [];
            try
                fcn();
            catch caught
                err = caught;
            end
            testCase.assertNotEmpty(err, "Expected an error to be thrown");
        end

        function connect(~, instr) %#ok<INUSD>
            %Connect, keeping its messages out of the test output
            evalc("instr.Connect()");
        end
    end
end
