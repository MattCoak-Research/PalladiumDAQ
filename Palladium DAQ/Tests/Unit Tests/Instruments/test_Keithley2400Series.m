classdef test_Keithley2400Series < matlab.unittest.TestCase
    %TEST_KEITHLEY2400SERIES Tests the Keithley 2410 and 6430 drivers: offset compensation, readings and the 6430's limits
    %The 6430 driver is the 2410's with the 6430's name and limits. The
    %drivers are given a fake connection (FakeDeviceHandle) that records
    %what they send and gives set replies.

    %% Properties (TestParameter)
    properties (TestParameter)
        Model = struct("K2410", "RecordingKeithley2410", "K6430", "RecordingKeithley6430");
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function OffsetCompUsesTheInstrumentsTest(testCase, Model)
            %The instrument's own offset-compensated ohms, set on connecting -
            %the driver used to step the source to 0 and back itself
            [instr, connection] = testCase.makeInstrument(Model);
            instr.OffsetComp = true;

            instr.ConfigureReadingsForTest();

            testCase.verifyEqual(connection.WrittenCommands, [":FORM:ELEM VOLT,CURR,RES", ":SENS:RES:OCOM ON"]);
        end

        function OffsetCompOffTurnsItOffTest(testCase, Model)
            %Sent either way, so turning OffsetComp off also turns it off on the instrument
            [instr, connection] = testCase.makeInstrument(Model);

            instr.ConfigureReadingsForTest();

            testCase.verifyEqual(connection.WrittenCommands(end), ":SENS:RES:OCOM OFF");
        end

        function OffsetCompOnlyInResistanceModeTest(testCase, Model)
            %Outside Resistance MeasMode: no offset compensation command
            [instr, connection] = testCase.makeInstrument(Model);
            instr.MeasMode = instr.MeasType("Voltage");

            instr.ConfigureReadingsForTest();

            testCase.verifyEqual(connection.WrittenCommands, ":FORM:ELEM VOLT,CURR,RES");
        end

        function MeasureTakesOneReadingTest(testCase, Model)
            %With OffsetComp, Measure no longer sets the source level itself
            [instr, connection] = testCase.makeInstrument(Model);
            instr.OffsetComp = true;
            connection.QueryResponses("OUTP?") = "1";
            connection.QueryResponses("SOUR:CURR:LEV:AMPL?") = "1.0E-05";
            connection.QueryResponses("READ?") = "+1.839736E+00,+9.999968E-06,+1.839742E+05";
            connection.QueryResponses("SENS:VOLT:PROT:TRIP?") = "0";

            dataRow = instr.Measure();

            testCase.verifyEmpty(connection.WrittenCommands, "No source level or output commands");
            testCase.verifyEqual(dataRow, [1.839742e5, 9.999968e-6, 1.839736, 1e-5, 0], RelTol=1e-12);
        end

        function K6430NameAndLimitsTest(testCase)
            %The 6430 sources up to 210 V or 105 mA
            instr = Palladium.Instruments.Keithley6430();
            testCase.verifyEqual(instr.FullName, "Keithley 6430 Src Meter");

            [~, limits] = instr.GetSweepUnitsString();
            testCase.verifyEqual(limits, [-0.105, 0.105], "Sourcing current (the default)");

            instr.SourceMode = instr.SourceType("Voltage");
            [~, limits] = instr.GetSweepUnitsString();
            testCase.verifyEqual(limits, [-210, 210], "Sourcing voltage, not connected");
        end

        function K6430ColumnsMatchThe2410Test(testCase)
            %The measured quantity first, then the source level and compliance flag, as on the 2410
            k6430 = Palladium.Instruments.Keithley6430();
            k2410 = Palladium.Instruments.Keithley2410();

            headers6430 = k6430.GetHeaders();
            headers2410 = k2410.GetHeaders();

            testCase.verifyEqual(extractAfter(headers6430, " - "), extractAfter(headers2410, " - "));
            testCase.verifyEqual(headers6430(1), "SrcMtr - Resistance (Ohms)");
        end

        function K6430HasASweepControlTest(testCase)
            instr = Palladium.Instruments.Keithley6430();
            testCase.verifyTrue(any(string({instr.GetAvailableControlOptions().Name}) == "Sweep Control"));
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~, className)
            %The driver, given a fake connection as if connected
            instr = InstrumentTestingInstruments.(className)();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
        end
    end
end
