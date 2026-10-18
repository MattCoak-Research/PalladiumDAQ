classdef test_SR830 < matlab.unittest.TestCase
    %TEST_SR830 Tests the SR830 lock-in driver's columns and readings, in simulation mode
    %Simulated readings: X 0.0705876 V and Y 0.00256349 V at the input,
    %and a 2 V rms sine output.

    %% Properties
    properties
        Instrument;     %The SR830_Lockin under test, connected in simulation mode
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function connect(testCase)
            testCase.Instrument = Palladium.Instruments.SR830_Lockin();
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("testCase.Instrument.Connect()");
        end
    end

    %% Methods (Test)
    methods (Test)
        function ResistanceUnitsAreOhmsTest(testCase)
            %As every other driver names them (it was "Ohm")
            [headers, units] = testCase.Instrument.GetHeaders();

            testCase.verifyEqual(headers(end), "SR830 - Resistance (Ohms)");
            testCase.verifyEqual(units, ["V", "V", "A", "Ohms"]);
        end

        function AmplifierGainDividesXAndYTest(testCase)
            %X and Y are the signal at the sample - divided by the gain of
            %any preamplifier before the input, as the resistance always was
            testCase.Instrument.AmplifierGain = 100;
            current = 200e-6 * 2;   %200 uA/V current source, 2 V sine output

            dataRow = testCase.Instrument.Measure();

            testCase.verifyEqual(dataRow, [0.0705876/100, 0.00256349/100, current, 0.0705876/100/current], RelTol=1e-12);
        end

        function NoCurrentSourceTest(testCase)
            %Without a current source: the output voltage, and no resistance
            testCase.Instrument.ConnectedCurrentSource = testCase.Instrument.CurrentSource("None");
            testCase.Instrument.AmplifierGain = 10;

            [~, units] = testCase.Instrument.GetHeaders();
            dataRow = testCase.Instrument.Measure();

            testCase.verifyEqual(units, ["V", "V", "V"]);
            testCase.verifyEqual(dataRow, [0.0705876/10, 0.00256349/10, 2], RelTol=1e-12);
        end

        function AmplifierGainCannotBeZeroTest(testCase)
            testCase.verifyError(@() testCase.setGain(0), "MATLAB:validators:mustBeNonzero");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function setGain(testCase, gain)
            testCase.Instrument.AmplifierGain = gain;
        end
    end
end
