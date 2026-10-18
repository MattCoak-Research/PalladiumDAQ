classdef test_AH2550 < matlab.unittest.TestCase
    %TEST_AH2550 Tests the AH 2550A bridge driver: loss units, reading the newest continuous result, and RS-232 set-up
    %Behaviour is from the AH 2500A manual (no 2550A manual was
    %available). The driver is given a fake connection (FakeDeviceHandle),
    %through the RecordingAH2550 test subclass.

    %% Properties (TestParameter)
    properties (TestParameter)
        %Each Loss_Units setting: the loss column's units, and the bridge's label for them on a result line
        Units = struct( ...
            "TanDelta", struct("Name", "TanDelta", "Unit", "", "Label", "DS"), ...
            "kOhm", struct("Name", "kOhm", "Unit", "kOhm", "Label", "KO"), ...
            "nS", struct("Name", "nS", "Unit", "nS", "Label", "NS"), ...
            "GOhm", struct("Name", "GOhm", "Unit", "GOhm", "Label", "GO"), ...
            "jpF", struct("Name", "jpF", "Unit", "jpF", "Label", "GW"));
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function LossColumnUnitsTest(testCase, Units)
            %All five of the bridge's UNITS settings - only two were offered
            instr = Palladium.Instruments.AH2550_Bridge();
            instr.Loss_Units = instr.LossUnitsType(Units.Name);

            [headers, units] = instr.GetHeaders();

            testCase.verifyEqual(headers(2), "AH_Br - Loss (" + Units.Unit + ")");
            testCase.verifyEqual(units(2), Units.Unit);
        end

        function MatchingUnitsAreReadTest(testCase, Units)
            [instr, connection] = testCase.makeInstrument();
            instr.Loss_Units = instr.LossUnitsType(Units.Name);
            connection.ReadResponse = "C= 454.688993 PF L= 0.01744 " + Units.Label + " V= 15.0 V";

            dataRow = instr.Measure();

            testCase.verifyEqual(dataRow, [454.688993, 0.01744, 15.0]);
        end

        function MismatchedUnitsStopWithAMessageTest(testCase)
            %Loss_Units only names the column - so a bridge reporting other
            %units would have been recorded under the wrong ones
            [instr, connection] = testCase.makeInstrument();
            instr.Loss_Units = instr.LossUnitsType("TanDelta");
            connection.ReadResponse = "C= 454.688993 PF L= 0.01744 NS V= 15.0 V";

            testCase.verifyError(@() instr.Measure(), "AH2550_Bridge:LossUnitsMismatch");
            try
                instr.OnConnectedForTest();
                instr.Measure();
            catch err
                testCase.verifySubstring(err.message, "reports loss in nS");
            end
        end

        function UnitsAreCheckedOnceAfterConnectingTest(testCase)
            %Only the first result after connecting is checked
            [instr, connection] = testCase.makeInstrument();
            instr.Loss_Units = instr.LossUnitsType("nS");
            connection.ReadResponse = "C= 1.0 PF L= 0.5 NS V= 15.0 V";
            instr.Measure();

            connection.ReadResponse = "C= 1.0 PF L= 0.5 DS V= 15.0 V";
            testCase.verifyWarningFree(@() instr.Measure());

            instr.OnConnectedForTest();
            testCase.verifyError(@() instr.Measure(), "AH2550_Bridge:LossUnitsMismatch");
        end

        function SerialReadsTheNewestResultTest(testCase)
            %Over RS-232 every result queues up in the port's buffer -
            %reading one at a time fell further and further behind
            [instr, connection] = testCase.makeInstrument(Serial=true);
            instr.Loss_Units = instr.LossUnitsType("nS");
            connection.ReadQueue = ["C= 1.0 PF L= 0.1 NS V= 15.0 V", "C= 2.0 PF L= 0.2 NS V= 15.0 V", ">", "C= 3.0 PF L= 0.3 NS V= 15.0 V"];

            dataRow = instr.Measure();

            testCase.verifyEqual(dataRow, [3.0, 0.3, 15.0], "The newest result");
            testCase.verifyEmpty(connection.ReadQueue, "The older ones are read past");
        end

        function SerialWaitsWhenNothingIsWaitingTest(testCase)
            [instr, connection] = testCase.makeInstrument(Serial=true);
            instr.Loss_Units = instr.LossUnitsType("nS");
            connection.ReadResponse = "C= 4.0 PF L= 0.4 NS V= 15.0 V";

            dataRow = instr.Measure();

            testCase.verifyEqual(dataRow, [4.0, 0.4, 15.0]);
        end

        function SerialConnectingTurnsEchoOffTest(testCase)
            %Echo (on by default on the bridge) would be read as part of
            %the replies. Commands end CR, replies CR LF
            [instr, connection] = testCase.makeInstrument(Serial=true);

            instr.OnConnectedForTest();

            testCase.verifyEqual(connection.WrittenCommands, "BAUD ......0");
            testCase.verifyEqual(connection.Terminators, ["CR/LF", "CR"]);
            testCase.verifyEqual(connection.FlushCount, 1, "The echo and prompt are discarded");
        end

        function GPIBConnectingSendsNothingTest(testCase)
            [instr, connection] = testCase.makeInstrument();

            instr.OnConnectedForTest();

            testCase.verifyEmpty(connection.WrittenCommands);
        end

        function SingleMeasurementTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            instr.Continuous_Mode = false;
            instr.Loss_Units = instr.LossUnitsType("nS");
            connection.QueryResponse = "C= 5.0 PF L= 0.5 NS V= 15.0 V";

            dataRow = instr.Measure();

            testCase.verifyEqual(connection.QueriedCommands, "SI");
            testCase.verifyEqual(dataRow, [5.0, 0.5, 15.0]);
        end

        function SerialDefaultsMatchTheBridgeTest(testCase)
            %9600 baud, 8 data bits, no parity, 1 stop bit (2500A manual, BAUD)
            instr = InstrumentTestingInstruments.RecordingAH2550();
            settings = instr.GetConnectionSettingsForTest().SerialSettings;
            testCase.verifyEqual([settings.BaudRate, settings.DataBits, settings.StopBits], [9600, 8, 1]);
            testCase.verifyEqual(string(settings.Parity), "none");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~, Settings)
            %The driver, given a fake connection as if connected (GPIB, or Serial)
            arguments
                ~;
                Settings.Serial (1,1) logical = false;
            end
            instr = InstrumentTestingInstruments.RecordingAH2550();
            if Settings.Serial
                instr.Connection_Type = Palladium.Enums.ConnectionType.Serial;
            end
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
        end
    end
end
