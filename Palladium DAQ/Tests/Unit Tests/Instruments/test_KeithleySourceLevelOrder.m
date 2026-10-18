classdef test_KeithleySourceLevelOrder < matlab.unittest.TestCase
    %TEST_KEITHLEYSOURCELEVELORDER Tests the order SetSourceLevel sends its commands in, on the Keithley 2450, 2410 and 6430
    %Turning the output on, the level must be set first - the output used
    %to come on at the old level, then jump. Turning it off, the output
    %must go off first - otherwise the new level is briefly sourced. The
    %drivers are given a fake connection that records what they send.

    %% Properties (TestParameter)
    properties (TestParameter)
        %Driver (a recording subclass), command language, and the commands expected for level 2.5 sourcing voltage
        Driver = struct( ...
            "K2450_SCPI", struct("Class", "RecordingKeithley2450", "Language", "SCPI", "Level", "SOUR:VOLT:LEV 2.5", "On", "OUTP ON", "Off", "OUTP OFF"), ...
            "K2450_TSP", struct("Class", "RecordingKeithley2450", "Language", "TSP", "Level", "smu.source.level = 2.5", "On", "smu.source.output = smu.ON", "Off", "smu.source.output = smu.OFF"), ...
            "K2410", struct("Class", "RecordingKeithley2410", "Language", "", "Level", "SOUR:VOLT:LEV 2.5", "On", "OUTP ON", "Off", "OUTP OFF"), ...
            "K6430", struct("Class", "RecordingKeithley6430", "Language", "", "Level", "SOUR:VOLT:LEV 2.5", "On", "OUTP ON", "Off", "OUTP OFF"));
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function TurningOnSetsTheLevelFirstTest(testCase, Driver)
            [instr, connection] = testCase.makeInstrument(Driver);

            instr.SetSourceLevel(2.5, true);

            testCase.verifyEqual(connection.WrittenCommands, [Driver.Level, Driver.On]);
        end

        function TurningOffTurnsOffFirstTest(testCase, Driver)
            [instr, connection] = testCase.makeInstrument(Driver);

            instr.SetSourceLevel(2.5, false);

            testCase.verifyEqual(connection.WrittenCommands, [Driver.Off, Driver.Level]);
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~, driver)
            %The driver, sourcing voltage, given a fake connection as if connected to the instrument
            instr = InstrumentTestingInstruments.(driver.Class)();
            if strlength(driver.Language) > 0
                instr.Language = instr.LanguageType(driver.Language);
            end
            instr.SetSourceModeForTest("Voltage");
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
        end
    end
end
