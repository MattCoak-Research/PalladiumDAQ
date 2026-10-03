classdef test_Keithley2000 < matlab.unittest.TestCase
    properties
        instrument
        currentRNG
        defaults = struct('Address', 16, 'ConnectionSettings', ["LF" "LF"], 'MeasMode', categorical("Resistance"), 'MeasUnit', "Ohms");
    end

    properties (TestParameter)
        % Measurement mode, its units, and the expected header suffix
        dataArray = { ["DC Voltage", "V", " - Voltage_DC_V"], ...
            ["AC Voltage", "dBm", " - Voltage_AC_dBm"], ...
            ["DC Current", "A", " - Current_DC_A"], ...
            ["AC Current", "A", " - Current_AC_A"], ...
            ["Resistance", "Ohms", " - Resistance_Ohms"], ...
            ["4-Wire Resistance", "Ohms", " - Resistance_4W_Ohms"], ...
            ["Frequency", "Hz", " - Frequency_Hz"], ...
            ["Period", "s", " - Period_s"], ...
            ["Temperature", "K", " - Temperature_K"]}
    end

    methods (TestClassSetup)
        function classSetup(testCase)
            % Set up shared state for all tests.
            testCase.currentRNG = rng;
            % Tear down with testCase.addTeardown.
            testCase.addTeardown(@rng, testCase.currentRNG);
            rng(1)
        end
    end

    methods(TestMethodSetup)
        function createInstrument(testCase)
            testCase.instrument = Palladium.Instruments.Keithley2000();
        end
    end

    methods(Test)
        % Test constructor
        function testConstructor(testCase)
           % Just tests for public properties at the moment
           verifyEqual(testCase, testCase.instrument.GPIB_Address, testCase.defaults.Address);
           verifyEqual(testCase, string(testCase.instrument.MeasMode), string(testCase.defaults.MeasMode));
           verifyEqual(testCase, testCase.instrument.MeasUnit, testCase.defaults.MeasUnit);
        end

        function testSupportedConnectionTypes(testCase)
            % The Model 2000 has GPIB and RS-232 ports only - no Ethernet or USB
            types = string(testCase.instrument.GetSupportedConnectionTypes());
            testCase.verifyEqual(sort(types(:)), sort(["Debug"; "GPIB"; "Serial"; "VISA"]));
        end

        % GetHeader() tests
        function testGetHeadersCorrectInput(testCase, dataArray)
            testCase.instrument.MeasMode = testCase.instrument.MeasType(dataArray(1));
            testCase.instrument.MeasUnit = dataArray(2);
            [headers, units] = testCase.instrument.GetHeaders();

            testCase.verifyEqual(headers, "K2000" + dataArray(3));
            testCase.verifyEqual(units, dataArray(2));
        end

        function testGetHeadersInvalidMeasMode(testCase)
            testCase.instrument.MeasMode = categorical("None");
            verifyError(testCase, @() testCase.instrument.GetHeaders(), 'Keithley2000:InvalidMeasureMode')
        end

        % Measure() test
        function testMeasureReturnsDataRow(testCase)
            testCase.instrument.Connection_Type = Palladium.Enums.ConnectionType.Debug; % Simulate mode
            testCase.instrument.Connect();

            dataRow = testCase.instrument.Measure();
            testCase.verifySize(dataRow, [1, 1]);

            %Simulated reading is random, scattered about 17 with a
            %standard deviation of 0.1 (see Keithley2000.Measure), so check
            %it falls within 6 standard deviations rather than for an exact
            %value. GenerateSimulatedData clamps to 5 standard deviations,
            %so this can never fail by chance
            testCase.verifyEqual(dataRow, 17, "AbsTol", 6 * 0.1);

            %One reading, one header
            testCase.verifySize(testCase.instrument.GetHeaders(), size(dataRow));
        end

        function testConnectKeepsModeInSimulation(testCase)
            % In Debug mode there is no instrument to read the function
            % from, so the constructor's default mode is kept
            testCase.instrument.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            testCase.instrument.Connect();
            testCase.verifyEqual(string(testCase.instrument.MeasMode), "Resistance");
            testCase.verifyEqual(testCase.instrument.MeasUnit, "Ohms");
        end
    end
end
