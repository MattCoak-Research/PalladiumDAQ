classdef test_PythonInstrumentCore < matlab.unittest.TestCase
    %TEST_PYTHONINSTRUMENTCORE Tests the communication helpers of the Python instrument base class (PalladiumPythonCore/Instrument.py)
    %Uses the stand-in connections and scenarios in
    %data/Python Testing/instrument_core_fakes.py - no hardware, pyvisa or
    %pyserial needed.

    %% Properties
    properties
        Fakes;      %The instrument_core_fakes Python module
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function importFakes(testCase)
            here = fileparts(mfilename("fullpath"));
            sourceRoot = fileparts(fileparts(fileparts(here)));     %Holds PalladiumPythonCore
            fakesDir = fullfile(fileparts(here), "data", "Python Testing");
            templateDir = fullfile(sourceRoot, "ExamplesAndTemplates", "PythonInstruments");     %The template Python instrument

            %Don't let Python write __pycache__ folders into the source or
            %test data folders while these tests run
            oldSetting = pyrun("import sys; old = sys.dont_write_bytecode; sys.dont_write_bytecode = True", "old");
            testCase.addTeardown(@() pyrun("import sys; sys.dont_write_bytecode = setting", setting=oldSetting));

            %Put the folders first on Python's path, for these tests only
            for folder = [string(sourceRoot), string(fakesDir), string(templateDir)]
                py.sys.path().insert(int32(0), folder);
                testCase.addTeardown(@() py.sys.path().remove(folder));
            end

            %Import afresh, so that the current Instrument.py is tested
            py.importlib.reload(py.importlib.import_module("PalladiumPythonCore.Instrument"));
            testCase.Fakes = py.importlib.reload(py.importlib.import_module("instrument_core_fakes"));
        end
    end

    %% Methods (Test)
    methods (Test)
        function SocketQueryDouble(testCase)
            %Ethernet: the query is sent with a \n terminator, and the reply read up to one
            r = struct(testCase.Fakes.socket_query_double(sprintf("1.25\n")));
            testCase.verifyEqual(double(r.value), 1.25);
            testCase.verifyEqual(string(r.received), sprintf("MEAS?\n"));
        end

        function SocketCustomTerminators(testCase)
            %Ethernet, with WriteTermination and ReadTermination set to \r\n
            r = struct(testCase.Fakes.socket_custom_terminators(sprintf("Ready\r\n")));
            testCase.verifyEqual(string(r.read), "Ready");
            testCase.verifyEqual(string(r.received), sprintf("OUTP ON\r\n"));
        end

        function VisaHelpers(testCase)
            %pyvisa: commands sent as given (pyvisa adds its own terminator), replies stripped
            r = struct(testCase.Fakes.visa_scenario(py.list({sprintf("  ACME,DMM \n"), sprintf("3.5\n")})));
            testCase.verifyEqual(string(r.text), "ACME,DMM");
            testCase.verifyEqual(double(r.value), 3.5);
            testCase.verifyEqual(string(r.written), "*RST | *IDN? | MEAS?");
        end

        function SerialHelpers(testCase)
            %Serial: commands sent with a \n terminator, replies read up to \n and stripped (including any \r)
            r = struct(testCase.Fakes.serial_scenario(py.list({sprintf("ACME,DMM\r\n"), sprintf("-2e-3\r\n")})));
            testCase.verifyEqual(string(r.text), "ACME,DMM");
            testCase.verifyEqual(double(r.value), -2e-3);
            testCase.verifyEqual(string(r.written), sprintf("*RST\n | *IDN?\n | MEAS?\n"));
        end

        function SimulationMode(testCase)
            %No connection needed: "null" for text, a number near 100 for query_double
            r = struct(testCase.Fakes.simulation_scenario());
            testCase.verifyEqual(string(r.text), "null");
            testCase.verifyEqual(string(r.read), "null");
            testCase.verifyGreaterThanOrEqual(double(r.value), 100);
            testCase.verifyLessThan(double(r.value), 101);
        end

        function QueryDoubleNonNumberErrors(testCase)
            testCase.verifyPythonError(@() testCase.Fakes.query_double_non_number(), "ValueError", "is not a number: 'OVERLOAD'");
        end

        function NotConnectedErrors(testCase)
            testCase.verifyPythonError(@() testCase.Fakes.not_connected(), "AssertionError", "not connected");
        end

        function UnsupportedConnectionErrors(testCase)
            testCase.verifyPythonError(@() testCase.Fakes.unsupported_connection(), "RuntimeError", "Unsupported connection type");
        end

        function TemplateWorksInSimulation(testCase)
            %The template Python instrument (ExamplesAndTemplates/PythonInstruments):
            %Measure returns one number per header, and it has the members Palladium uses
            module = py.importlib.reload(py.importlib.import_module("TemplatePythonInstrument"));
            instr = module.TemplatePythonInstrument();
            instr.SimulationMode = true;

            headersAndUnits = cell(instr.GetHeaders());
            headers = string(cell(headersAndUnits{1}));
            units = string(cell(headersAndUnits{2}));
            values = cellfun(@double, cell(py.list(instr.Measure())));

            testCase.verifyNotEmpty(headers);
            testCase.verifyNumElements(units, numel(headers));
            testCase.verifyNumElements(values, numel(headers));
            testCase.verifyNotEqual(string(instr.Name), "");
            testCase.verifyNotEqual(string(instr.FullName), "");
            testCase.verifyClass(instr.collect_metadata(), "py.dict");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function verifyPythonError(testCase, fn, errorType, messagePart)
            %Verify that a call raises a Python exception of the given type,
            %with a message containing the given text
            try
                fn();
                testCase.verifyFail("Expected a Python " + errorType);
            catch err
                testCase.verifySubstring(err.message, errorType);
                testCase.verifySubstring(err.message, messagePart);
            end
        end
    end
end
