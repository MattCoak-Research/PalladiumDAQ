classdef test_MercuryITC < matlab.unittest.TestCase
    %TEST_MERCURYITC Tests the Mercury iTC driver's reading of replies (values and their units), setpoints, device catalogue and GPIB settings
    %From the Mercury iTC User Manual (MAN-NS-0014), chapter 10. The driver
    %is given a fake connection (FakeDeviceHandle), through the
    %RecordingMercuryITC test subclass.

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function ValueAndUnitsAsSeparateTokensTest(testCase)
            %As in the manual's example (10.3.13)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("READ:DEV:MB1.T1:TEMP:SIG:VOLT") = "STAT:DEV:MB1.T1:TEMP:SIG:VOLT:12.345:mV:VALID";
            testCase.verifyEqual(instr.GetSignal("DEV:MB1.T1:TEMP", "VOLT"), 12.345e-3, RelTol=1e-12);
        end

        function ValueJoinedToUnitsTest(testCase)
            replies = ["4.2310K", "12.5mV", "250uA", "1.5kOhm", "1234.5Ohm", "-3.2E-2W"];
            values = [4.231, 12.5e-3, 250e-6, 1500, 1234.5, -0.032];
            for i = 1:numel(replies)
                [instr, connection] = testCase.makeInstrument();
                connection.QueryResponses("READ:DEV:DB1.X1:TEMP:SIG:X") = "STAT:DEV:DB1.X1:TEMP:SIG:X:" + replies(i);
                testCase.verifyEqual(instr.GetSignal("DEV:DB1.X1:TEMP", "X"), values(i), replies(i), RelTol=1e-12);
            end
        end

        function OhmSignTest(testCase)
            %The front panel shows resistance in ohms with the ohm sign
            [instr, connection] = testCase.makeInstrument();
            for ohm = [string(char(937)), string(char(8486))]
                connection.QueryResponses("READ:DEV:MB1.T1:TEMP:SIG:RES") = "STAT:DEV:MB1.T1:TEMP:SIG:RES:2.5k" + ohm;
                testCase.verifyEqual(instr.GetSignal("DEV:MB1.T1:TEMP", "RES"), 2500, RelTol=1e-12);
            end
        end

        function PressureInMbarIsNotScaledTest(testCase)
            %"mB" (mbar) used to be read as milli-B, making pressure 1000x too small
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("READ:DEV:DB5.P1:PRES:SIG:PRES") = "STAT:DEV:DB5.P1:PRES:SIG:PRES:12.34mB";
            testCase.verifyEqual(instr.GetSignal("DEV:DB5.P1:PRES", "PRES"), 12.34, RelTol=1e-12);

            connection.QueryResponses("READ:DEV:DB5.P1:PRES:SIG:PRES") = "STAT:DEV:DB5.P1:PRES:SIG:PRES:12.34:mB:VALID";
            testCase.verifyEqual(instr.GetSignal("DEV:DB5.P1:PRES", "PRES"), 12.34, "As separate tokens", RelTol=1e-12);
        end

        function UnknownUnitsAreLeftUnscaledTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("READ:DEV:DB1.X1:TEMP:SIG:X") = "STAT:DEV:DB1.X1:TEMP:SIG:X:7.5Furlong";
            evalc("value = instr.GetSignal(""DEV:DB1.X1:TEMP"", ""X"")");
            testCase.verifyEqual(value, 7.5);
        end

        function SetpointMatchesWithin1mKTest(testCase)
            %The reply's value may be rounded - it used to need to match exactly
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("SET:DEV:MB1.T1:TEMP:LOOP:TSET:4.32104") = "STAT:SET:DEV:MB1.T1:TEMP:LOOP:TSET:4.321:VALID";
            instr.SetTemperatureSetpoint("DEV:MB1.T1:TEMP", 4.32104);

            connection.QueryResponses("SET:DEV:MB1.T1:TEMP:LOOP:TSET:4.5") = "STAT:SET:DEV:MB1.T1:TEMP:LOOP:TSET:4.4:VALID";
            testCase.verifyError(@() instr.SetTemperatureSetpoint("DEV:MB1.T1:TEMP", 4.5), "MercuryITC:SetpointNotSet");
        end

        function CatalogueWithSpacesTest(testCase)
            %The manual's examples show spaces in the catalogue reply
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("READ:SYS:CAT") = "STAT:SYS:CAT:DEV:MB1.T1 :TEMP:DEV:DB5.P1 :PRES";

            addresses = instr.GetDeviceCatalogue();

            testCase.verifyEqual(addresses, ["DEV:MB1.T1:TEMP", "DEV:DB5.P1:PRES"]);
        end

        function GPIBUsesSecondaryAddress1Test(testCase)
            %SCPI over GPIB needs secondary address 1 (manual 9.2.1)
            instr = InstrumentTestingInstruments.RecordingMercuryITC();
            settings = instr.GetConnectionSettingsForTest();

            testCase.verifyTrue(any(instr.GetSupportedConnectionTypes() == Palladium.Enums.ConnectionType.GPIB));
            testCase.verifyEqual(Palladium.Core.Instrument.GPIBResourceName(settings.GPIB_BoardIndex, 5, settings.GPIB_SecondaryAddress), "GPIB0::5::1::INSTR");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~)
            %The driver, given a fake connection as if connected
            instr = InstrumentTestingInstruments.RecordingMercuryITC();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
        end
    end
end
