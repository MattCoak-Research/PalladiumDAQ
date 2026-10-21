classdef test_Lakeshore340 < matlab.unittest.TestCase
    %TEST_LAKESHORE340 Tests the Lakeshore 340 driver: control loop and input, heater power, sensor units and applying the Heater Control settings
    %Commands from the Model 340 User's Manual, chapter 9. The driver is
    %given a fake connection (FakeDeviceHandle), through the
    %RecordingLakeshore340 test subclass.

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "..", "Helpers")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function Loop1RegulatingOnInputBTest(testCase)
            %ControlChannel B used to mean loop 2 (Analog Output 2) - it is
            %now the input the loop regulates on. Heater range last
            [instr, connection] = testCase.makeInstrument();
            instr.ControlChannel = instr.Channel("B");

            instr.ApplySettingsForTest(testCase.settings(instr));

            testCase.verifyEqual(connection.WrittenCommands, ["CSET 1,B", "CMODE 1,3", "PID 1,50,10,5", "RAMP 1,1,1.5", ...
                "SETP 1,25.4", "MOUT 1,40", "RANGE 3"]);
        end

        function NoControlInputChangesNothingTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            instr.ControlChannel = instr.Channel("None");
            instr.ApplySettingsForTest(testCase.settings(instr));
            testCase.verifyFalse(any(startsWith(connection.WrittenCommands, "CSET")));
        end

        function Loop2Test(testCase)
            %Kept as an option (the user's choice): Analog Output 2, with no
            %heater range - and a warning if that output isn't in Loop mode
            [instr, connection] = testCase.makeInstrument();
            instr.ControlLoop = instr.LoopType("Loop 2 (Analog Output 2)");
            connection.QueryResponses("ANALOG? 2") = "0,3,A,1,+100.000,+0.000,+0.00";

            instr.ApplySettingsForTest(testCase.settings(instr));

            testCase.verifyEqual(connection.WrittenCommands, ["CSET 2,A", "CMODE 2,3", "PID 2,50,10,5", "RAMP 2,1,1.5", ...
                "SETP 2,25.4", "MOUT 2,40"]);
        end

        function Loop2NotInLoopModeWarnsTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            instr.ControlLoop = instr.LoopType("Loop 2 (Analog Output 2)");
            connection.QueryResponses("ANALOG? 2") = "0,2,A,1,+100.000,+0.000,+0.00";

            %Record the warnings that reach the GUI (warnings to the Command
            %Window go to stderr, which evalc can't capture)
            gui = TestHelpers.RecordingController();
            Palladium.Logging.Logger.Log("Debug", "Logger set up for test", "Controller", gui, "CommandWindowMessageLevel", "Off", ...
                "GUIMessageLevel", "Warning", "LogFileMessageLevel", "Off");
            testCase.addTeardown(@() Palladium.Logging.Logger.ResetForTest());

            instr.ApplySettingsForTest(testCase.settings(instr));

            testCase.verifyTrue(any(contains(gui.Messages, "Analog Output 2 is not in Loop mode")), join(gui.Messages, " | "));
        end

        function Loop2OutputInTheTabTest(testCase)
            %Loop 2's output is Analog Output 2's (AOUT? 2) - not the heater's
            [instr, connection] = testCase.makeInstrument();
            instr.ControlLoop = instr.LoopType("Loop 2 (Analog Output 2)");
            replies = ["CMODE? 2", "1"; "RANGE?", "0"; "SETP? 2", "+4.2"; "RAMP? 2", "0,+1.0"; "MOUT? 2", "+0.00"; ...
                "PID? 2", "+50.0,+20.0,+0.0"; "AOUT? 2", "+35.5"];
            for i = 1:height(replies)
                connection.QueryResponses(replies(i, 1)) = replies(i, 2);
            end

            [settings, level, enabled, power] = instr.CollectHeaterControlSettings();

            testCase.verifyEqual(level, 35.5);
            testCase.verifyTrue(enabled);
            testCase.verifyEqual(power, NaN);
            testCase.verifyEqual(settings.SetPoint, 4.2);
        end

        function OldChannelArgumentIsALoopTest(testCase)
            %These methods took Channel A/B for loop 1/2 - still accepted
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("CMODE? 2") = "3";
            testCase.verifyEqual(instr.GetControlMode(instr.Channel("B")), instr.ControlMode("Open Loop"));
            testCase.verifyEqual(instr.GetControlMode(2), instr.ControlMode("Open Loop"));
        end

        function HeaterPowerFromTheInstrumentsSetupTest(testCase)
            %Resistance from CDISP? (the driver had its own setting), max
            %current from CLIMI? when CLIMIT? says User (was recorded as NaN)
            [instr, connection] = testCase.makeInstrument(CLIMIT="+325.0,+10.0,+0.0,5,5", CDISP="1,50,2,0");
            connection.QueryResponses("HTR?") = "50.0";
            connection.QueryResponses("RANGE?") = "5";

            power = instr.GetHeaterPower();

            %1 A user maximum into 50 Ohms (within the 50 V compliance), 50% of full-scale power
            testCase.verifyEqual(power, 50 * 1^2 * 0.5, RelTol=1e-12);
            testCase.verifyFalse(isprop(instr, "HeaterResistance"), "Set on the instrument instead");
        end

        function SensorUnitsFollowTheSensorTypeTest(testCase)
            %Diodes read in V - they were always labelled Ω
            [instr, ~] = testCase.makeInstrument(INTYPE_A="1,1,1,0,0", INTYPE_B="8,2,1,7,0");
            instr.Ch_A_Reading = instr.MeasType("Sensor Units");
            instr.Ch_B_Reading = instr.MeasType("Sensor Units");

            [headers, units] = instr.GetHeaders();

            testCase.verifyEqual(headers, ["Ls340 - Ch A Sensor (V)", "Ls340 - Ch B Sensor (Ω)", "Ls340 Heater Power (W)"]);
            testCase.verifyEqual(units, ["V", "Ω", "W"]);
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~, Settings)
            %The driver, given a fake connection as if connected - reading the inputs' types and the heater set-up as on connecting
            arguments
                ~;
                Settings.INTYPE_A (1,1) string = "8,2,1,7,0";
                Settings.INTYPE_B (1,1) string = "8,2,1,7,0";
                Settings.CLIMIT (1,1) string = "+325.0,+10.0,+0.0,3,5";
                Settings.CDISP (1,1) string = "1,25,2,0";
            end
            instr = InstrumentTestingInstruments.RecordingLakeshore340();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
            connection.QueryResponses("INTYPE? A") = Settings.INTYPE_A;
            connection.QueryResponses("INTYPE? B") = Settings.INTYPE_B;
            connection.QueryResponses("CLIMIT? 1") = Settings.CLIMIT;
            connection.QueryResponses("CLIMI?") = "1.000";
            connection.QueryResponses("CDISP? 1") = Settings.CDISP;
            instr.OnConnectedForTest();
        end

        function settings = settings(~, instr)
            %Heater Control tab settings, in Open Loop so every one is sent
            settings = struct("ControlMode", instr.ControlMode("Open Loop"), "HeaterRange", instr.HeaterRange("Range 3"), ...
                "SetPoint", 25.4, "RampEnabled", true, "RampRate", 1.5, "ManualOutput", 40, ...
                "PID_Settings", struct("P", 50, "I", 10, "D", 5));
        end
    end
end
