classdef test_Lakeshore372 < matlab.unittest.TestCase
    %TEST_LAKESHORE372 Tests the Lakeshore 372 driver: native sample heater commands, emulation mode check, channel, heater power and applying the Heater Control settings
    %Commands from the Model 372 User's Manual, chapter 6. The driver is
    %given a fake connection (FakeDeviceHandle), through the
    %RecordingLakeshore372 test subclass.

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function ApplySettingsIsOnePassWithRangeLastTest(testCase)
            %Native commands for the sample heater (output 0), sent once,
            %the heater range last. OUTMODE keeps the instrument's other
            %output settings
            [instr, connection] = testCase.makeInstrument();

            instr.ApplySettingsForTest(testCase.settings(instr));

            testCase.verifyEqual(connection.WrittenCommands, ["OUTMODE 0,2,1,0,0,1,5", "PID 0,50,10,5", "RAMP 0,1,1.5", ...
                "SETP 0,0.025", "MOUT 0,40", "RANGE 0,3"]);
        end

        function EmulationModeStopsConnectingTest(testCase)
            %370 emulation would misread the 372's own commands
            testCase.verifyError(@() testCase.makeInstrument(EMUL="1"), "Lakeshore372:EmulationMode");
        end

        function ChannelIsReadTest(testCase)
            %Was always channel 1
            [instr, connection] = testCase.makeInstrument();
            instr.Channel = instr.InputChannel("A");
            connection.QueryResponses("RDGK? A") = "+1.20000E-01";
            connection.QueryResponses("RDGR? A") = "+2.50000E+03";
            connection.QueryResponses("HTR?") = "+0.0";
            connection.QueryResponses("RANGE? 0") = "0";

            testCase.verifyEqual(instr.Measure(), [0.12 2500 0]);
            testCase.verifyEqual(instr.Channel, instr.InputChannel("A"));
            testCase.verifyEqual(InstrumentTestingInstruments.RecordingLakeshore372().Channel, instr.InputChannel("1"), "Default channel");
        end

        function NoCurveReadsNaNTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("RDGK? 1") = "+0.00000E+00";
            testCase.verifyEqual(instr.GetTemperature(), NaN);
        end

        function HeaterPowerInCurrentModeTest(testCase)
            %Resistance from HTRSET? 0 (was a driver setting)
            [instr, connection] = testCase.makeInstrument(HTRSET="+120.0,0,+0.000,1");
            connection.QueryResponses("HTR?") = "+50.0";
            connection.QueryResponses("RANGE? 0") = "4";

            testCase.verifyEqual(instr.GetHeaterPower(), 120 * (0.5e-3)^2, RelTol=1e-12);
            testCase.verifyFalse(isprop(instr, "HeaterResistance"), "Set on the instrument instead");
        end

        function HeaterPowerInPowerModeTest(testCase)
            %HTR? and MOUT are in W with the Power display
            [instr, connection] = testCase.makeInstrument(HTRSET="+100.0,0,+0.000,2");
            connection.QueryResponses("HTR?") = "+2.5E-05";
            connection.QueryResponses("RANGE? 0") = "4";

            [level, enabled] = instr.GetHeaterLevel();
            testCase.verifyEqual(instr.GetHeaterPower(), 2.5e-5);
            testCase.verifyEqual(level, 50, "Percent of full-scale current", RelTol=1e-12);
            testCase.verifyTrue(enabled);

            instr.SetManualOutputPercent(50, instr.HeaterRange("  1 mA (4)"));
            testCase.verifyEqual(connection.WrittenCommands(end), "MOUT 0,2.5E-05");
        end

        function NamedHeaterRangeTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("RANGE? 0") = "6";
            testCase.verifyEqual(instr.GetHeaterRange(), instr.HeaterRange(" 10 mA (6)"));
        end

        function RepliesParsedWhereverTheNumbersAreTest(testCase)
            %I was once seen as "E20.000"
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("PID? 0") = "+10.000,E20.000,+0.000";
            connection.QueryResponses("RAMP? 0") = "1,+0.500";
            connection.QueryResponses("OUTMODE? 0") = "5,1,0,0,1,5";

            [P, I, D] = instr.GetPIDValues();
            [enabled, rate] = instr.GetRamp();

            testCase.verifyEqual([P I D], [10 20 0]);
            testCase.verifyEqual([enabled rate], [true 0.5]);
            testCase.verifyEqual(instr.GetControlMode(), instr.ControlMode("Closed Loop PID"));
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~, Settings)
            %The driver, given a fake connection as if connected - checking emulation mode and reading the heater set-up as on connecting
            arguments
                ~;
                Settings.EMUL (1,1) string = "0";
                Settings.HTRSET (1,1) string = "+100.0,0,+0.000,1";
            end
            instr = InstrumentTestingInstruments.RecordingLakeshore372();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
            connection.QueryResponses("EMUL?") = Settings.EMUL;
            connection.QueryResponses("HTRSET? 0") = Settings.HTRSET;
            connection.QueryResponses("OUTMODE? 0") = "3,1,0,0,1,5";
            instr.OnConnectedForTest();
        end

        function settings = settings(~, instr)
            %Heater Control tab settings, in Open Loop so every one is sent
            settings = struct("ControlMode", instr.ControlMode("Open Loop"), "HeaterRange", instr.HeaterRange("316 muA (3)"), ...
                "SetPoint", 0.025, "RampEnabled", true, "RampRate", 1.5, "ManualOutput", 40, ...
                "PID_Settings", struct("P", 50, "I", 10, "D", 5));
        end
    end
end
