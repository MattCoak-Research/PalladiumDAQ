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

        function GPIBTimeoutAppliedWithoutSettingsTest(testCase)
            %connectGPIB applies the timeout it is given (in ms for pyvisa)
            %even with no ConnectionSettings - it used to be skipped then
            r = struct(testCase.Fakes.gpib_connect_without_settings(3.5));
            testCase.verifyEqual(string(r.resource), "GPIB0::7::INSTR");
            testCase.verifyEqual(double(r.timeout), 3500);
        end

        function SerialUsesTheDriversSettingsTest(testCase)
            %A driver sets its serial settings in ConnectionSettings; any it
            %leaves out take the defaults
            settings = py.dict(pyargs("SerialSettings", py.dict(pyargs("BaudRate", int32(115200), "Parity", "E", "StopBits", 2)), "GPIB_Timeout", 3));
            r = struct(testCase.Fakes.serial_connect(settings));
            testCase.verifyEqual(string(r.port), "COM9");
            testCase.verifyEqual(double(r.baudrate), 115200);
            testCase.verifyEqual(string(r.parity), "E");
            testCase.verifyEqual(double(r.stopbits), 2);
            testCase.verifyEqual(double(r.bytesize), 8, "Not set by the driver - the default");
            testCase.verifyEqual(double(r.timeout), 3);
        end

        function SerialDefaultsWithoutSettingsTest(testCase)
            r = struct(testCase.Fakes.serial_connect());
            testCase.verifyEqual([double(r.baudrate), double(r.bytesize), double(r.stopbits), double(r.timeout)], [9600, 8, 1, 10]);
            testCase.verifyEqual(string(r.parity), "N");
        end

        function GPIBUsesTheDriversTerminatorsAndTimeoutTest(testCase)
            %The driver's own timeout wins over the one Palladium passes
            r = struct(testCase.Fakes.gpib_connect_with_driver_settings());
            testCase.verifyEqual(string(r.read), string([char(13) newline]));
            testCase.verifyEqual(string(r.write), string(newline));
            testCase.verifyEqual(double(r.timeout), 2000);
        end

        function USBConnectsWithTheAddressGivenTest(testCase)
            %connectUSB opens the VISA address it is given - it used to look
            %for a VISA_Address attribute that nothing set, and always fail
            resource = testCase.Fakes.usb_connect("USB0::0x05E6::0x2450::SN1::INSTR");
            testCase.verifyEqual(string(resource), "USB0::0x05E6::0x2450::SN1::INSTR");
        end

        function NameDefaultsToTheClassNameTest(testCase)
            %An instrument that doesn't set Name is named after its class -
            %reading Name used to fail until a subclass set it
            testCase.verifyEqual(string(testCase.Fakes.default_name()), "CoreTestInstrument");
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
