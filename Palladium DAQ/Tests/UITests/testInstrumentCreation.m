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
            %Palladium writes its data files, sequences and logs to the
            %Data, Sequences and Logs folders in Testing Data Files (see
            %TestingConfig.json). The fixture removes them again afterwards.
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "Helpers")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
            testCase.ConfigPath = fullfile("Tests", "TestingConfig.json");   %Relative to the Palladium.m folder
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