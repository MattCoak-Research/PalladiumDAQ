classdef test_Keysight4284A < matlab.unittest.TestCase
    %TEST_KEYSIGHT4284A Tests the Keysight 4284A driver: the trigger set on connecting, and columns named from the measurement function
    %From the 4284A Operation Manual. The driver is given a fake
    %connection (FakeDeviceHandle), through the RecordingKeysight4284A test
    %subclass.

    %% Properties (TestParameter)
    properties (TestParameter)
        %Some measurement functions (FUNC:IMP? replies) and the result columns they give
        Func = struct( ...
            "CPD", struct("Reply", "CPD", "Headers", ["LCR_Mtr - Cp (F)", "LCR_Mtr - D"], "Units", ["F", ""]), ...
            "CSRS", struct("Reply", "CSRS", "Headers", ["LCR_Mtr - Cs (F)", "LCR_Mtr - Rs (Ohms)"], "Units", ["F", "Ohms"]), ...
            "LSD", struct("Reply", "LSD", "Headers", ["LCR_Mtr - Ls (H)", "LCR_Mtr - D"], "Units", ["H", ""]), ...
            "RX", struct("Reply", "RX", "Headers", ["LCR_Mtr - R (Ohms)", "LCR_Mtr - X (Ohms)"], "Units", ["Ohms", "Ohms"]), ...
            "ZTD", struct("Reply", "ZTD", "Headers", ["LCR_Mtr - Z (Ohms)", "LCR_Mtr - Theta (deg)"], "Units", ["Ohms", "deg"]), ...
            "YTR", struct("Reply", "YTR", "Headers", ["LCR_Mtr - Y (S)", "LCR_Mtr - Theta (rad)"], "Units", ["S", "rad"]), ...
            "GB", struct("Reply", "GB", "Headers", ["LCR_Mtr - G (S)", "LCR_Mtr - B (S)"], "Units", ["S", "S"]));
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "data", "Instrument Testing")));
        end
    end

    %% Methods (Test)
    methods (Test)
        function ConnectingSetsInternalContinuousTriggerTest(testCase)
            %Left on bus or hold trigger, FETC? returned the same old result
            %every time - the driver never set the trigger
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("FUNC:IMP?") = "CPD";

            instr.OnConnectedForTest();

            testCase.verifyEqual(connection.WrittenCommands, ["TRIG:SOUR INT", "INIT:CONT ON"]);
        end

        function ColumnsNamedFromTheFunctionTest(testCase, Func)
            %They were always "Cap (F)" and "Loss ()", whatever the function
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("FUNC:IMP?") = Func.Reply;

            instr.OnConnectedForTest();
            [headers, units] = instr.GetHeaders();

            testCase.verifyEqual(headers(1:2), Func.Headers);
            testCase.verifyEqual(units(1:2), Func.Units);
            testCase.verifyEqual(headers(3:5), "LCR_Mtr - " + ["Frequency (Hz)", "Voltage (V)", "Status"]);
        end

        function DefaultIsCpDTest(testCase)
            %Before connecting, and in Debug mode: the 4284A's default function
            instr = Palladium.Instruments.Keysight4284A_LCR_Meter();
            headers = instr.GetHeaders();
            testCase.verifyEqual(headers(1:2), ["LCR_Mtr - Cp (F)", "LCR_Mtr - D"]);
        end

        function UnknownFunctionStopsConnectingTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("FUNC:IMP?") = "XYZ";

            testCase.verifyError(@() instr.OnConnectedForTest(), "Keysight4284A_LCR_Meter:UnknownFunction");
        end

        function MeasureReadsTheLatestResultTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("FETC?") = "+1.23450E-11,+2.00000E-03,+0";
            connection.QueryResponses("FREQ?") = "1000";
            connection.QueryResponses("VOLT?") = "0.5";

            dataRow = instr.Measure();

            testCase.verifyEqual(dataRow, [1.2345e-11, 2e-3, 1000, 0.5, 0], RelTol=1e-12);
        end

        function BadStatusGivesNaNTest(testCase)
            [instr, connection] = testCase.makeInstrument();
            connection.QueryResponses("FETC?") = "+9.90000E+37,+9.90000E+37,+1";
            connection.QueryResponses("FREQ?") = "1000";
            connection.QueryResponses("VOLT?") = "0.5";

            dataRow = instr.Measure();

            testCase.verifyEqual(dataRow(1:2), [NaN, NaN]);
            testCase.verifyEqual(dataRow(5), 1);
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function [instr, connection] = makeInstrument(~)
            %The driver, given a fake connection as if connected
            instr = InstrumentTestingInstruments.RecordingKeysight4284A();
            connection = InstrumentTestingInstruments.FakeDeviceHandle();
            instr.SetDeviceHandleForTest(connection);
        end
    end
end
