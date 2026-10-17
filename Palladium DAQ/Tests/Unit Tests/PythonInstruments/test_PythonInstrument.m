classdef test_PythonInstrument < matlab.unittest.TestCase
    %TEST_PYTHONINSTRUMENT Tests the MATLAB side of Python instruments: PythonInstrument (which wraps one) and PythonInstrumentController
    %Connecting uses the stand-in pyvisa and serial packages in
    %data/Python Testing/instrument_core_fakes.py - no hardware, pyvisa or
    %pyserial needed - so the real connect code runs on both sides.

    %% Properties
    properties
        Fakes;          %The instrument_core_fakes Python module
        SourceRoot;     %The folder Palladium.m is in
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function importFakes(testCase)
            here = fileparts(mfilename("fullpath"));
            testCase.SourceRoot = fileparts(fileparts(fileparts(here)));     %Holds PalladiumPythonCore
            fakesDir = fullfile(fileparts(here), "data", "Python Testing");

            %Don't let Python write __pycache__ folders into the source or
            %test data folders while these tests run
            oldSetting = pyrun("import sys; old = sys.dont_write_bytecode; sys.dont_write_bytecode = True", "old");
            testCase.addTeardown(@() pyrun("import sys; sys.dont_write_bytecode = setting", setting=oldSetting));

            %Put the folders first on Python's path, for these tests only
            for folder = [string(testCase.SourceRoot), string(fakesDir)]
                py.sys.path().insert(int32(0), folder);
                testCase.addTeardown(@() py.sys.path().remove(folder));
            end

            %Import afresh, so that the current Instrument.py is tested
            py.importlib.reload(py.importlib.import_module("PalladiumPythonCore.Instrument"));
            testCase.Fakes = py.importlib.reload(py.importlib.import_module("instrument_core_fakes"));
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function useFakePackages(testCase)
            testCase.Fakes.install_fake_packages();
            testCase.addTeardown(@() testCase.Fakes.restore_packages());
        end
    end

    %% Methods (Test)
    methods (Test)

        %% PythonInstrument
        function USBConnectsWithTheVISAAddressTest(testCase)
            %A USB instrument is opened by the VISA address set in MATLAB (and
            %shown in the GUI) - it used to fail, as no address reached Python
            instr = testCase.wrappedInstrument(testCase.Fakes.instrument());
            instr.Connection_Type = Palladium.Enums.ConnectionType.USB;
            instr.VISA_Address = "USB0::0x05E6::0x2450::SN1::INSTR";

            testCase.connect(instr);

            testCase.verifyEqual(string(instr.PyInstr.DeviceHandle.resource_name), "USB0::0x05E6::0x2450::SN1::INSTR");
        end

        function DriversSerialSettingsAreUsedTest(testCase)
            %The Python driver owns its connection settings - connecting from
            %MATLAB leaves them as the driver set them
            instr = testCase.wrappedInstrument(testCase.Fakes.instrument_with_serial_settings(115200));
            instr.Connection_Type = Palladium.Enums.ConnectionType.Serial;
            instr.Serial_Address = 'COM99';

            testCase.connect(instr);

            settings = struct(instr.PyInstr.DeviceHandle.settings);
            testCase.verifyEqual(string(settings.port), "COM99");
            testCase.verifyEqual(double(settings.baudrate), 115200);
            testCase.verifyEqual(string(settings.parity), "E");
            testCase.verifyEqual(double(settings.stopbits), 2);
        end

        function DisconnectClosesThePythonConnectionTest(testCase)
            instr = testCase.wrappedInstrument(testCase.Fakes.instrument());
            instr.Connection_Type = Palladium.Enums.ConnectionType.VISA;
            instr.VISA_Address = "TCPIP0::1.2.3.4::inst0::INSTR";
            testCase.connect(instr);
            handle = instr.PyInstr.DeviceHandle;

            evalc("instr.Disconnect()");

            testCase.verifyTrue(logical(handle.closed));
            testCase.verifyFalse(instr.IsConnected);
        end

        %% PythonInstrumentController
        function CreatingWithNoInstrumentsLoadedErrorsClearlyTest(testCase)
            %One clear error - it used to be a MATLAB warning, then a
            %not-found error anyway
            controller = Palladium.PythonInstruments.PythonInstrumentController("PythonInstruments", testCase.SourceRoot);

            testCase.verifyWarningFree(@() testCase.verifyError(@() controller.CreateInstrument("Anything"), "InstantiateInstrumentError:NoInstrumentsLoaded"));
        end

    end

    %% Methods (Private)
    methods (Access = private)
        function instr = wrappedInstrument(testCase, pyInstr)
            %A PythonInstrument wrapping a Python instrument from the fakes
            instr = Palladium.PythonInstruments.PythonInstrument(pyInstr);
            testCase.addTeardown(@() delete(instr));
        end

        function connect(~, instr)
            %Connect, keeping its messages out of the test output
            evalc("instr.Connect()");
        end
    end
end
