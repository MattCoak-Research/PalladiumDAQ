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
            %Palladium writes its data files, sequences and logs to the
            %Data, Sequences and Logs folders in Testing Data Files (see
            %TestingConfig.json). The fixture removes them again afterwards.
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "Helpers")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
            testCase.ConfigPath = fullfile("Tests", "TestingConfig.json");   %Relative to the Palladium.m folder
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
        % Close Palladium
        function ClosePalladium(testCase)
           testCase.Pd.Close();
        end
    end

    methods (Test)
        % Test methods
        function AddSingleInstrument(testCase)
           
            testCase.Pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            drawnow();

            pause(0.5);
        end

        function AddAllInstruments(testCase)
            %Loop over all possible Instruments, and add them - in Debug
            %ConnectionType mode
            for i = 1 : length(testCase.InstrumentNames)
                testCase.Pd.AddInstrument(testCase.InstrumentNames{i}, ConnectionType="Debug");
                drawnow();
            end

            pause(0.5);
        end

    end

end