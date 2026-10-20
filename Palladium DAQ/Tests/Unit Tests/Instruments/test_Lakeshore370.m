classdef test_Lakeshore370 < matlab.unittest.TestCase
    %TEST_LAKESHORE370 Tests the Lakeshore 370 driver: channel readings, heater output in either display mode, reply parsing and applying the Heater Control settings
    %Commands from the Model 370 User's Manual, chapter 6. The driver is
    %given a fake connection (FakeDeviceHandle), through the
    %RecordingLakeshore370 test subclass.

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function ReadingsAreOfTheChannelTest(testCase)
            %RDGK? and RDGR? take a channel (1-16) - they were sent without one
            [instr, connection] = testCase.makeInstrument();
            instr.Channel = 5;
            connection.QueryResponses("RDGK? 5") = "+4.2000E+00";
            connection.QueryResponses("RDGR? 5") = "+1.0240E+03";

            testCase.verifyEqual(instr.GetTemperature(), 4.2);
            testCase.verifyEqual(instr.GetResistance(), 1024);
        end

        function NoCurveIsNaNTest(testCase)
            %With no calibration curve the instrument reads 0 K
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("RDGK? 1") = "+0.0000E+00";
            testCase.verifyEqual(instr.GetTemperature(), NaN);
        end

        function HeaterRangeIsNamedTest(testCase)
            %It was the range number, so the Heater Control tab showed "1"
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("HTRRNG?") = "2";
            testCase.verifyEqual(instr.GetHeaterRange(), instr.HeaterRange("100 muA (2)"));
        end

        function HeaterOutputInCurrentModeTest(testCase)
            %HTR? in % of full-scale current: power = R x I^2, with R from CSET?
            [instr, connection] = testCase.makeInstrument(CSET="1,0,1,30,1,8,+100.000");
            connection.QueryResponses("HTR?") = "+50.000E+00";
            connection.QueryResponses("HTRRNG?") = "8";

            [level, enabled] = instr.GetHeaterLevel();

            testCase.verifyEqual(level, 50);
            testCase.verifyTrue(enabled);
            testCase.verifyEqual(instr.GetHeaterPower(), 100 * (0.05)^2, "50% of 100 mA into 100 Ohms", RelTol=1e-12);
        end

        function HeaterOutputInPowerModeTest(testCase)
            %HTR? in W when the heater output display is Power - it used to
            %be taken as a percentage whatever the display
            [instr, connection] = testCase.makeInstrument(CSET="1,0,1,30,2,8,+100.000");
            connection.QueryResponses("HTR?") = "+2.5000E-01";
            connection.QueryResponses("HTRRNG?") = "8";

            testCase.verifyEqual(instr.GetHeaterPower(), 0.25, RelTol=1e-12);
            testCase.verifyEqual(instr.GetHeaterLevel(), 50, "Shown as % of full-scale current", RelTol=1e-12);
        end

        function ManualOutputInPowerModeTest(testCase)
            %MOUT is in W in Power display - 50% would have been sent as 50 W
            [instr, connection] = testCase.makeInstrument(CSET="1,0,1,30,2,8,+100.000");
            connection.QueryResponses("HTRRNG?") = "8";
            connection.QueryResponses("MOUT?") = "+2.5000E-01";

            instr.SetManualOutputPercent(50);

            testCase.verifyEqual(connection.WrittenCommands, "MOUT 0.25");
            testCase.verifyEqual(instr.GetManualOutputPercent(), 50, RelTol=1e-12);
        end

        function ManualOutputInCurrentModeTest(testCase)
            [instr, connection] = testCase.makeInstrument(CSET="1,0,1,30,1,8,+100.000");
            instr.SetManualOutputPercent(22.45);
            testCase.verifyEqual(connection.WrittenCommands, "MOUT 22.45", "As the manual's example");
        end

        function PIDAndRampRepliesTest(testCase)
            %The manual's format, and an I once seen as "E20.000" - which used
            %to be parsed by dropping the first character, so "+20.000"
            %worked only by luck and "20.000" gave 0
            replies = ["+10.000,+20.000,+5.000", "+10.000,E20.000,+5.000", "10,20,5"];
            for reply = replies
                [instr, connection] = testCase.makeInstrument();
                connection.QueryResponses("PID?") = reply;
                [P, I, D] = instr.GetPIDValues();
                testCase.verifyEqual([P, I, D], [10, 20, 5], reply);
            end

            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("RAMP?") = "1,+1.500";
            [enabled, rate] = instr.GetRamp();
            testCase.verifyTrue(enabled);
            testCase.verifyEqual(rate, 1.5);
        end

        function UnexpectedReplyErrorsTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("PID?") = "+10.000,+20.000";
            testCase.verifyError(@() instr.GetPIDValues(), "Lakeshore370:UnexpectedReply");
        end

        function SettingsAreAppliedOnceHeaterRangeLastTest(testCase)
            %They were all sent twice; the heater range is now sent last, so
            %the heater only switches on once everything else is set
            [instr, connection] = testCase.makeInstrument(CSET="1,0,1,30,1,8,+100.000");
            settings = struct("ControlMode", instr.ControlMode("Open Loop"), "HeaterRange", instr.HeaterRange("100 mA (8)"), ...
                "SetPoint", 1.5, "RampEnabled", true, "RampRate", 1.5, "ManualOutput", 50, ...
                "PID_Settings", struct("P", 10, "I", 20, "D", 5));

            instr.ApplySettingsForTest(settings);

            testCase.verifyEqual(connection.WrittenCommands, ["CMODE 3", "PID 10,20,5", "RAMP 1,1.5", "SETP 1.5", "MOUT 50", "HTRRNG 8"]);
        end

        function NoSensorReadingQueryTest(testCase)
            %SRDG? is a Model 372 query, not a 370 one
            testCase.verifyFalse(ismethod(Palladium.Instruments.Lakeshore370(), "GetSensorReading"));
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~, Settings)
            %The driver, given a fake connection as if connected - reading CSET? (Control Setup) as on connecting
            arguments
                ~;
                Settings.CSET (1,1) string = "1,0,1,30,1,8,+100.000";
            end
            instr = InstrumentTestingInstruments.RecordingLakeshore370();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
            connection.QueryResponses("CSET?") = Settings.CSET;
            instr.OnConnectedForTest();
        end
    end
end
