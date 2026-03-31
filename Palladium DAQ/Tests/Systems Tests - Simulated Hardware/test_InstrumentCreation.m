classdef test_InstrumentCreation < matlab.unittest.TestCase
    % TEST_INSTRUMENTCREATION Tests for Palladium
    %
    %
    properties
        InstrumentNames = [];
        ConfigPath;
        Pd;
    end

    methods (TestClassSetup)
        function configPathSetup(testCase)
            % Set up shared state for all tests.
            testCase.ConfigPath = fullfile("..","TestingConfig.json");
        end
    end

    methods (TestMethodSetup)

        % Setup for each test
        function SetupPalladiumAndListOfInstrumentClasses(testCase)
            testCase.Pd = Palladium("ConfigFilePath",testCase.ConfigPath);
            testCase.InstrumentNames = testCase.Pd.GetAllInstrumentClassNames();
            drawnow();
        end

    end

    methods (TestMethodTeardown)
        % Remove folder created during test
        function TeardownFiles(testCase)
            path = fullfile( '..','Palladium DAQ - Testing');
            rmdir(path, 's')
        end
    end

    methods (Test)
        % Test methods
        function AddSingleInstrument(testCase)
            % Warning doesn't seem to generate identifier so can't test for
            % that
            testCase.Pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            drawnow();

            pause(0.5);
            testCase.Pd.Close();
        end

        function AddAllInstruments(testCase)
            % Warning doesn't seem to generate identifier so can't test for
            % that

            %Loop over all possible Instruments, and add them - in Debug
            %ConnectionType mode
            for i = 1 : length(testCase.InstrumentNames)
                testCase.Pd.AddInstrument(testCase.InstrumentNames{i}, ConnectionType="Debug");
                drawnow();
            end

            pause(0.5);
            testCase.Pd.Close();
        end

    end

end