classdef test_InstrumentCreation < matlab.unittest.TestCase
    % TEST_INSTRUMENTCREATION Tests for Palladium
    %
    %
    properties
        InstrumentNames = [];
    end

    methods (TestClassSetup)
        % Shared setup for the entire test class
    end

    methods (TestMethodSetup)

        % Setup for each test
        function SetupListOfInstrumentClasses(testCase)
            pd = Palladium();
            testCase.InstrumentNames = pd.GetAllInstrumentClassNames();
        end

    end

    methods (Test)
        % Test methods

        function AddAllInstruments(testCase)
            % Warning doesn't seem to generate identifier so can't test for
            % that
            pd = Palladium();

            %Loop over all possible Instruments, and add them - in Debug
            %ConnectionType mode
            for i = 1 : length(testCase.InstrumentNames)
                pd.AddInstrument(testCase.InstrumentNames{i}, ConnectionType="Debug");
            end

            pause(2);
            pd.Close();
        end

    end

end