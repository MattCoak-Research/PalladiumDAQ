classdef test_Keithley2450 < matlab.unittest.TestCase
    %TEST_KEITHLEY2450 Tests the Keithley 2450 driver's Sweep Control limits and default VISA address
    %The voltage limit is the most the instrument will output: 210 V, the
    %overvoltage protection level, or 42 V without the interlock. The
    %driver is given a fake connection (FakeDeviceHandle) with set replies,
    %through the RecordingKeithley2450 test subclass.

    %% Properties (TestParameter)
    properties (TestParameter)
        %The queries and replies for each command set: protection level, then interlock (engaged, not engaged)
        Language = struct( ...
            "SCPI", struct("Name", "SCPI", "OVPQuery", "SOUR:VOLT:PROT?", "OVP40", "PROT40", "OVPNone", "NONE", ...
                "InterlockQuery", "OUTP:INT:TRIP?", "Engaged", "1", "NotEngaged", "0"), ...
            "TSP", struct("Name", "TSP", "OVPQuery", "print(smu.source.getattribute(smu.FUNC_DC_VOLTAGE, smu.ATTR_SRC_PROTECT_LEVEL))", ...
                "OVP40", "smu.PROTECT_40V", "OVPNone", "smu.PROTECT_NONE", ...
                "InterlockQuery", "print(smu.interlock.tripped)", "Engaged", "smu.ON", "NotEngaged", "smu.OFF"));
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function VoltageLimitTest(testCase, Language)
            %They used to be fixed at 50 V, whatever the instrument allowed
            limit = @(ovp, interlock) testCase.voltageLimit(Language, ovp, interlock);

            testCase.verifyEqual(limit(Language.OVPNone, Language.Engaged), 210, "The 2450's maximum");
            testCase.verifyEqual(limit(Language.OVP40, Language.Engaged), 40, "The protection level");
            testCase.verifyEqual(limit(Language.OVPNone, Language.NotEngaged), 42, "Limited without the interlock");
            testCase.verifyEqual(limit(Language.OVP40, Language.NotEngaged), 40, "The lower of the two");
        end

        function SweepLimitsTest(testCase)
            %Voltage from GetSourceVoltageLimit, current the 2450's 1.05 A.
            %Connected in Debug mode, which sets the source and measure modes
            instr = InstrumentTestingInstruments.RecordingKeithley2450();
            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("instr.Connect()");
            instr.SetSourceModeForTest("Current");
            [units, limits] = instr.GetSweepUnitsString();
            testCase.verifyEqual(units, "A");
            testCase.verifyEqual(limits, [-1.05, 1.05]);

            %In Debug mode, as when not connected: the most it can source
            instr.SetSourceModeForTest("Voltage");
            [units, limits] = instr.GetSweepUnitsString();
            testCase.verifyEqual(units, "V");
            testCase.verifyEqual(limits, [-210, 210]);
        end

        function UnreadableLimitFallsBackTest(testCase)
            %A reply that can't be read gives the 2450's maximum, with a warning
            instr = InstrumentTestingInstruments.RecordingKeithley2450();
            instr.Language = instr.LanguageType("SCPI");
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            connection.QueryResponses("SOUR:VOLT:PROT?") = "garbled";
            instr.SetDeviceHandleForTest(connection);

            evalc("limit = instr.GetSourceVoltageLimit();");

            testCase.verifyEqual(limit, 210);
        end

        function DefaultVISAAddressIsAPatternTest(testCase)
            %Not one particular instrument's address, as it was
            instr = Palladium.Instruments.Keithley2450();
            testCase.verifyEqual(string(instr.VISA_Address), "USB0::0x05E6::0x2450::SERIALNUMBER::0::INSTR");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function limit = voltageLimit(~, language, ovpReply, interlockReply)
            %GetSourceVoltageLimit, with the instrument giving these replies
            instr = InstrumentTestingInstruments.RecordingKeithley2450();
            instr.Language = instr.LanguageType(language.Name);
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            connection.QueryResponses(language.OVPQuery) = ovpReply;
            connection.QueryResponses(language.InterlockQuery) = interlockReply;
            instr.SetDeviceHandleForTest(connection);
            limit = instr.GetSourceVoltageLimit();
        end
    end
end
