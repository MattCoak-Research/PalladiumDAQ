classdef test_Agilent53220A < matlab.unittest.TestCase
    %TEST_AGILENT53220A Tests the Agilent 53220A driver's frequency measurement command
    %The expected frequency and resolution are settings - they used to be
    %fixed at 20 MHz and 0.01 Hz. The driver is given a fake connection
    %(FakeDeviceHandle) that records its queries.

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function DefaultsTest(testCase)
            [~, connection] = testCase.measure();
            testCase.verifyEqual(connection.QueriedCommands, "MEAS:FREQ? 20000000,0.01,(@1)");
        end

        function SettingsAreUsedTest(testCase)
            [~, connection] = testCase.measure(ExpectedFrequency_Hz=60, Resolution_Hz=1e-3);
            testCase.verifyEqual(connection.QueriedCommands, "MEAS:FREQ? 60,0.001,(@1)");
        end

        function ReadingIsReturnedTest(testCase)
            dataRow = testCase.measure();
            testCase.verifyEqual(dataRow, 19999998.5);
        end

        function SettingsMustBePositiveTest(testCase)
            instr = Palladium.Instruments.Agilent_53220A_FreqCounter();
            testCase.verifyError(@() setResolution(0), "MATLAB:validators:mustBePositive");
            testCase.verifyError(@() setExpected(-1), "MATLAB:validators:mustBePositive");

            function setResolution(v); instr.Resolution_Hz = v; end
            function setExpected(v); instr.ExpectedFrequency_Hz = v; end
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [dataRow, connection] = measure(~, Settings)
            %Measure once with these settings, the counter replying 19999998.5 Hz
            arguments
                ~;
                Settings.ExpectedFrequency_Hz = [];
                Settings.Resolution_Hz = [];
            end
            instr = InstrumentTestingInstruments.RecordingAgilent53220A();
            if ~isempty(Settings.ExpectedFrequency_Hz); instr.ExpectedFrequency_Hz = Settings.ExpectedFrequency_Hz; end
            if ~isempty(Settings.Resolution_Hz); instr.Resolution_Hz = Settings.Resolution_Hz; end
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            connection.QueryResponse = "+1.99999985000000E+07";
            instr.SetDeviceHandleForTest(connection);
            dataRow = instr.Measure();
        end
    end
end
