classdef testPythonSetupWarning < matlab.uitest.TestCase
    %TESTPYTHONSETUPWARNING Tests that Palladium DAQ starts without a usable Python, warns about it, and can be told not to warn again

    %% Properties
    properties
        ConfigPath;         %Test config file, relative to the Palladium.m folder (as Palladium's ConfigFilePath takes it)
        ConfigFullPath;     %The same, as an absolute path
        Config;             %The config written to it
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function fixturesSetup(testCase)
            %Palladium writes its data files, sequences and logs to the
            %Data, Sequences and Logs folders in Testing Data Files (see
            %TestingConfig.json). The fixture removes them again afterwards.
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "Helpers")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function configSetup(testCase)
            %A copy of TestingConfig.json, in a new folder in Testing Data
            %Files, set to use a Python that doesn't exist - so Python
            %can't be used, whatever is installed
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            appDir = string(fileparts(which("Palladium")));
            testCase.Config = readstruct(fullfile(appDir, "Tests", "TestingConfig.json"));
            testCase.Config.PythonSettings.PythonExecutable = fullfile(string(fixture.Folder), "NoSuchPython", "python.exe");
            testCase.ConfigFullPath = fullfile(string(fixture.Folder), "PythonTestConfig.json");
            testCase.ConfigPath = extractAfter(testCase.ConfigFullPath, appDir + filesep);
        end
    end

    %% Methods (Test)
    methods (Test)
        function WarningCanBeTurnedOff(testCase)
            %The warning is shown, and "Don't show this again" saves that
            %in the config file, changing nothing else
            testCase.Config.WarningSettings.SuppressPythonSetupWarning = false;
            writestruct(testCase.Config, testCase.ConfigFullPath, FileType="json");

            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            drawnow();

            fig = findall(groot, "Type", "figure", "Name", "Palladium Data Acquisition");
            testCase.chooseDialog("uiconfirm", fig(1), "Don't show this again");
            drawnow();

            saved = readstruct(testCase.ConfigFullPath);
            testCase.verifyTrue(saved.WarningSettings.SuppressPythonSetupWarning);
            testCase.verifyEqual(saved.PathSettings, testCase.Config.PathSettings);
            testCase.verifyEqual(saved.LogSettings, testCase.Config.LogSettings);
        end

        function StartsWithoutPython(testCase)
            %With the warning turned off, Palladium DAQ starts, with the
            %MATLAB instruments available
            testCase.Config.WarningSettings.SuppressPythonSetupWarning = true;
            writestruct(testCase.Config, testCase.ConfigFullPath, FileType="json");

            pd = Palladium(ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            drawnow();

            testCase.verifyNotEmpty(pd.View);
            testCase.verifyTrue(ismember("Keithley2000", pd.GetAllInstrumentClassNames()));
            testCase.verifyEmpty(pd.Controller.InstrumentController.PythonInstrumentController);
        end
    end
end
