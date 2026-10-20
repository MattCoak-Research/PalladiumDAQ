classdef test_Lakeshore350 < matlab.unittest.TestCase
    %TEST_LAKESHORE350 Tests the Lakeshore 350 driver: the inputs logged and their units, heater power, control modes, power-up enable and applying the Heater Control settings
    %Commands from the Model 350 User's Manual, chapter 6. The driver is
    %given a fake connection (FakeDeviceHandle), through the
    %RecordingLakeshore350 test subclass.

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function EachInputLoggedAsSetTest(testCase)
            %Ch_A_Reading to Ch_D_Reading did nothing - every input was
            %logged in K and sensor units
            [instr, connection] = testCase.makeInstrument();
            instr.Ch_A_Reading = instr.MeasType("Both");
            instr.Ch_B_Reading = instr.MeasType("Temperature");
            instr.Ch_C_Reading = instr.MeasType("Sensor Units");
            instr.Ch_D_Reading = instr.MeasType("Disabled");
            connection.QueryResponses("KRDG? 0") = "+1.000,+2.000,+3.000,+4.000";
            connection.QueryResponses("SRDG? 0") = "+10.00,+20.00,+30.00,+40.00";

            [headers, units] = instr.GetHeaders();
            row = instr.Measure();

            testCase.verifyEqual(headers, ["Channel A Temperature (K)", "Ls350 - Ch A Sensor (Ω)", "Channel B Temperature (K)", ...
                "Ls350 - Ch C Sensor (Ω)", "Ls350 Heater Power (W)"]);
            testCase.verifyEqual(units, ["K", "Ω", "K", "Ω", "W"]);
            testCase.verifyEqual(row(1:4), [1, 10, 2, 30]);
            testCase.verifyNumElements(row, numel(headers));
        end

        function NoSensorUnitsNoQueryTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            for letter = ["A", "B", "C", "D"]
                instr.("Ch_" + letter + "_Reading") = instr.MeasType("Temperature");
            end
            connection.QueryResponses("KRDG? 0") = "+1,+2,+3,+4";
            instr.Measure();
            testCase.verifyFalse(any(startsWith(connection.QueriedCommands, "SRDG?")));
        end

        function SensorUnitsFollowTheSensorTypeTest(testCase)
            %They were always Ω - a diode reads in V, a thermocouple in mV
            [instr, ~] = testCase.makeInstrument(InputTypes=["1", "2", "4", "5"]);
            [headers, units] = instr.GetHeaders();
            testCase.verifyEqual(units(2:2:8), ["V", "Ω", "mV", "nF"]);
            testCase.verifyEqual(headers(2), "Ls350 - Ch A Sensor (V)");
        end

        function AllInputsOneAtATimeIfNeededTest(testCase)
            %Some 350s answer KRDG? 0 with fewer than four values
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("KRDG? 0") = "+1.000";
            letters = ["A", "B", "C", "D"];
            for i = 1:4
                connection.QueryResponses("KRDG? " + letters(i)) = string(i + 0.5);
            end
            [a, b, c, d] = instr.GetTemperatureAllChannels();
            testCase.verifyEqual([a, b, c, d], [1.5, 2.5, 3.5, 4.5]);
        end

        function InputByChannelOrLetterTest(testCase)
            %It took only text, not the driver's own Channel
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("KRDG? B") = "+77.35";
            testCase.verifyEqual(instr.GetTemperature(instr.Channel("B")), 77.35);
            testCase.verifyEqual(instr.GetTemperature("b"), 77.35);
            testCase.verifyError(@() instr.GetTemperature("E"), "Lakeshore350:InvalidInput");
        end

        function OnlyHeaterControlModesTest(testCase)
            %Monitor Out and Warmup Supply are only for analog outputs 3 and 4
            instr = Palladium.Instruments.Lakeshore350();
            testCase.verifyEqual(string(categories(instr.ControlMode("Off")))', ["Off", "Closed Loop PID", "Zone", "Open Loop"]);
        end

        function PowerUpEnableIsKeptTest(testCase)
            %It was always set on (1)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTMODE? 1") = "1,1,0";
            instr.SetControlMode(instr.OutputChannel("Ch1"), instr.Channel("B"), instr.ControlMode("Zone"));
            testCase.verifyEqual(connection.WrittenCommands, "OUTMODE 1,2,2,0");
        end

        function HeaterPowerTest(testCase)
            %Range 5 is the output's max current (HTRSET?), each lower range a
            %decade lower in power; HTRSET? is read on connecting, not each tick
            [instr, connection] = testCase.makeInstrument(HTRSET1="1,2,+0.000,2");
            instr.HeaterResistance = 25;
            connection.QueryResponses("HTR? 1") = "+50.0";
            connection.QueryResponses("RANGE? 1") = "4";

            power = instr.GetHeaterPower(instr.OutputChannel("Ch1"));

            testCase.verifyEqual(power, 25 * 1^2 * 0.1 * 0.5, RelTol=1e-12);
            testCase.verifyEqual(nnz(startsWith(connection.QueriedCommands, "HTRSET?")), 2, "Only on connecting (both outputs)");
        end

        function SettingsAreAppliedOnceHeaterRangeLastTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("OUTMODE? 1") = "1,1,1";
            settings = struct("ControlMode", instr.ControlMode("Open Loop"), "HeaterRange", instr.HeaterRange("Range 3"), ...
                "SetPoint", 25.4, "RampEnabled", true, "RampRate", 1.5, "ManualOutput", 40, ...
                "PID_Settings", struct("P", 50, "I", 10, "D", 5));

            instr.ApplySettingsForTest(settings);

            testCase.verifyEqual(connection.WrittenCommands, ["OUTMODE 1,3,1,1", "PID 1,50,10,5", "RAMP 1,1,1.5", "SETP 1,25.4", ...
                "MOUT 1,40", "RANGE 1,3"]);
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~, Settings)
            %The driver, given a fake connection as if connected - reading the input types and heater set-up as on connecting
            arguments
                ~;
                Settings.InputTypes (1,4) string = ["2", "2", "2", "2"];
                Settings.HTRSET1 (1,1) string = "1,2,+0.000,1";
            end
            instr = InstrumentTestingInstruments.RecordingLakeshore350();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
            letters = ["A", "B", "C", "D"];
            for i = 1:4
                connection.QueryResponses("INTYPE? " + letters(i)) = Settings.InputTypes(i) + ",1,0,1,1,0";
            end
            connection.QueryResponses("HTRSET? 1") = Settings.HTRSET1;
            connection.QueryResponses("HTRSET? 2") = "0,0,+0.000,1";
            connection.QueryResponses("HTR? 1") = "+0.0";
            connection.QueryResponses("RANGE? 1") = "0";
            instr.OnConnectedForTest();
        end
    end
end
