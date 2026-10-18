classdef test_SR7265 < matlab.unittest.TestCase
    %TEST_SR7265 Tests the SR7265 lock-in driver: the input mode read when connecting, the column units, and auto-sensitivity
    %The driver is given a fake connection (FakeDeviceHandle), with set
    %replies to each query, through the RecordingSR7265 test subclass.

    %% Properties
    properties
        Instrument;     %A RecordingSR7265
        Connection;     %Its FakeDeviceHandle
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function makeInstrument(testCase)
            testCase.Instrument = InstrumentTestingInstruments.RecordingSR7265();
            testCase.Connection = InstrumentTestingInstruments.FakeDeviceHandle();
            testCase.Instrument.SetDeviceHandleForTest(testCase.Connection);
        end
    end

    %% Methods (Test)
    methods (Test)
        function DefaultsToGPIBTest(testCase)
            %Like the other drivers - it used to default to Debug
            instr = Palladium.Instruments.SR7265_Lockin();
            testCase.verifyEqual(instr.Connection_Type, Palladium.Enums.ConnectionType.GPIB);
        end

        function VoltageModeColumnsTest(testCase)
            testCase.connectInMode("0");

            [headers, units] = testCase.Instrument.GetHeaders();

            testCase.verifyEqual(string(testCase.Instrument.InputMode), "Voltage");
            testCase.verifyEqual(headers, ["SR7265 - Vx (V)", "SR7265 - Vy (V)"]);
            testCase.verifyEqual(units, ["V", "V"]);
        end

        function CurrentModeColumnsAreInAmpsTest(testCase)
            %XY. replies in amps in either current mode - the headers used
            %to say V regardless
            for mode = ["1", "2"]
                testCase.connectInMode(mode);

                [headers, units] = testCase.Instrument.GetHeaders();

                testCase.verifyEqual(headers, ["SR7265 - Ix (A)", "SR7265 - Iy (A)"], "IMODE " + mode);
                testCase.verifyEqual(units, ["A", "A"], "IMODE " + mode);
            end
        end

        function UnreadableRepliesStopConnectingTest(testCase)
            %Over RS-232 with echo or the prompt on, the replies aren't just
            %the number: connecting stops, saying which settings to change
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.Serial;
            testCase.Connection.QueryResponses("IMODE") = "IMODE";

            testCase.verifyError(@() testCase.Instrument.OnConnectedForTest(), "SR7265_Lockin:UnexpectedReply");
            try
                testCase.Instrument.OnConnectedForTest();
            catch err
                testCase.verifySubstring(err.message, "turn off Echo and Prompt");
            end
        end

        function LowNoiseCurrentModeBottomRangeTest(testCase)
            %In low-noise current mode the ranges start at index 7 (2 fA):
            %a small signal on that range stays there - it used to step down
            %to the invalid index 6
            testCase.connectInMode("2");
            testCase.setReadings(Magnitude="100", Sensitivity="7");

            testCase.Instrument.Measure();

            testCase.verifyEmpty(testCase.Connection.WrittenCommands, "No range change");
        end

        function SmallSignalStepsDownTest(testCase)
            %In voltage mode the same signal on range 7 steps down a range
            testCase.connectInMode("0");
            testCase.setReadings(Magnitude="100", Sensitivity="7");

            testCase.Instrument.Measure();

            testCase.verifyEqual(testCase.Connection.WrittenCommands, "SEN 6");
        end

        function LargeSignalOnTopRangeStaysTest(testCase)
            %On the top range there is nowhere to step up to
            testCase.connectInMode("0");
            testCase.setReadings(Magnitude="25000", Sensitivity="27");

            testCase.Instrument.Measure();

            testCase.verifyEmpty(testCase.Connection.WrittenCommands);
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function connectInMode(testCase, imode)
            %Do what connecting does, with the instrument replying imode ("0", "1" or "2") to IMODE
            testCase.Connection.QueryResponses("IMODE") = imode;
            testCase.Instrument.OnConnectedForTest();
        end

        function setReadings(testCase, Settings)
            %Set the replies to the queries Measure sends
            arguments
                testCase;
                Settings.Magnitude (1,1) string;
                Settings.Sensitivity (1,1) string;
            end
            testCase.Connection.QueryResponses("XY.") = "1.0E-06,2.0E-06";
            testCase.Connection.QueryResponses("MAG") = Settings.Magnitude;
            testCase.Connection.QueryResponses("SEN") = Settings.Sensitivity;
        end
    end
end
