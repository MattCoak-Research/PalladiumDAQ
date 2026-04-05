classdef testInstrumentCreation < matlab.unittest.TestCase
    % TEST_INSTRUMENTCREATION Tests for Palladium
    %
    %
    properties
        InstrumentNames = ["AH2550_Bridge","Keithley2000", "Lakeshore331"];
        ConfigPath;
    end

     methods (TestClassSetup)
        function configPathSetup(testCase)
            % Set up shared state for all tests.
            testCase.ConfigPath = fullfile('..','Palladium DAQ - Testing');
        end
     end

    methods (TestClassTeardown)
        % Remove folder created during test
        function TeardownFiles(testCase)
            path = fullfile( '..','Palladium DAQ - Testing');
            rmdir(path, 's');
        end
    end

    methods (TestMethodSetup)

    end

    methods (Test)
        % Test methods

        function AddAllInstruments(testCase)
           
            pd = Palladium(ConfigFilePath=testCase.ConfigPath);

            %Loop over all instruments in InstrumentNames, and add them - in Debug
            %ConnectionType mode
            for i = 1 : length(testCase.InstrumentNames)
                pd.AddInstrument(testCase.InstrumentNames{i}, ConnectionType="Debug");
            end
            actSelected = pd.Controller.InstrumentController.SelectedInstrumentNames;
            verifyEqual(testCase, 3, length(actSelected));
            verifyEqual(testCase, testCase.InstrumentNames, actSelected);
            pause(0.5);
            pd.Close();
        end

    end

end