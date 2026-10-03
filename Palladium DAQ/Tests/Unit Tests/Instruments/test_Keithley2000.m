classdef test_Keithley2000 < matlab.unittest.TestCase
    properties
        instrument
        currentRNG
        defaults = struct('dataTypes', categorical(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]),...
            'Address', 22, 'ConnectionSettings', ["LF" "LF"], 'MeasMode', categorical("Resistance"),...
            'SourceMode', categorical("Current"));
    end

    properties (TestParameter)
        % Meas and source types, 2 header strings, 2 units strings
        dataArray = { ["Resistance","Current"," - Resistance_Ohms"," - Current_A", "Ohms", "A"], ...
            ["Resistance","Voltage", " - Resistance_Ohms"," - Voltage_V","Ohms", "V"], ...
            ["Voltage","Voltage"," - Current_A"," - Voltage_V","A", "V"], ...
            ["Current","Current"," - Voltage_V"," - Current_A","V","A"]}
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
           verifyEqual(testCase, testCase.instrument.MeasMode, testCase.defaults.MeasMode);
           verifyEqual(testCase, testCase.instrument.SourceMode, testCase.defaults.SourceMode);
        end
        
        % GetHeader() tests
        function testGetHeadersCorrectInput(testCase, dataArray)
            % Tests for voltage measurement mode
            testCase.instrument.MeasMode = testCase.instrument.MeasType(dataArray(1));
            testCase.instrument.SourceMode = testCase.instrument.SourceType(dataArray(2));
            [headers, units] = testCase.instrument.GetHeaders();

            expectedHeaders = ["K2000" + dataArray(3), "K2000" + dataArray(4)];
            expectedUnits = [dataArray(5), dataArray(6)];

            testCase.verifyEqual(headers, expectedHeaders);
            testCase.verifyEqual(units, expectedUnits);
        end

        function testGetHeadersInvalidSourceMode(testCase)
            % Invalid source type
            testCase.instrument.MeasMode = testCase.instrument.MeasType("Resistance");
            testCase.instrument.SourceMode = categorical("None");
            verifyError(testCase, @() testCase.instrument.GetHeaders(), 'Keithley2000:InvalidSourceType')
        end
        
        function testGetHeadersInvalidMeasMode(testCase)
            testCase.instrument.MeasMode = categorical("None");
            verifyError(testCase, @() testCase.instrument.GetHeaders(), 'MATLAB:noSuchMethodOrField')
        end
        
        % Measure() test
        function testMeasureReturnsDataRow(testCase)
            testCase.instrument.Connection_Type = Palladium.Enums.ConnectionType.Debug; % Simulate mode
            testCase.instrument.Connect();

            dataRow = testCase.instrument.Measure();
            testCase.verifySize(dataRow, [1, 2]);

            %Simulated reading is random, scattered about 17 with a
            %standard deviation of 0.1 (see Keithley2000.Measure), so check
            %it falls within 6 standard deviations rather than for an exact
            %value. GenerateSimulatedData clamps to 5 standard deviations,
            %so this can never fail by chance. Second column is the source
            %level, which defaults to 0
            testCase.verifyEqual(dataRow(1), 17, "AbsTol", 6 * 0.1);
            testCase.verifyEqual(dataRow(2), 0);
        end
    end
end