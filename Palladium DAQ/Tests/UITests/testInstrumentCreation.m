classdef testInstrumentCreation < matlab.unittest.TestCase
    % TEST_INSTRUMENTCREATION Tests for Palladium
    %
    %
    properties
        InstrumentNames = ["AH2550_Bridge","Keithley2000", "Lakeshore331"];
    end

    methods (TestClassSetup)
        % Shared setup for the entire test class
    end

    methods (TestMethodSetup)

    end

    methods (Test)
        % Test methods

        function AddAllInstruments(testCase)
           
            pd = Palladium();

            %Loop over all instruments in InstrumentNames, and add them - in Debug
            %ConnectionType mode
            for i = 1 : length(testCase.InstrumentNames)
                pd.AddInstrument(testCase.InstrumentNames{i}, ConnectionType="Debug");
            end
            actSelected = pd.Controller.InstrumentController.SelectedInstrumentNames;
            verifyEqual(testCase, 3, length(actSelected));
            verifyEqual(testCase, testCase.InstrumentNames, actSelected);
            pause(2);
            pd.Close();
        end

    end

end