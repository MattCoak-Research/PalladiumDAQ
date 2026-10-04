classdef test_ConfigIO < matlab.unittest.TestCase
    % TEST_CONFIGIO Tests for Palladium utilities functions - ConfigIO class

    %% Properties
    properties
        TestingDir;   %Fresh folder for each test, inside Testing Data Files
        TestConfigDirName = "Test Config Dir";
        TestConfigDir;
        TestConfigDir_2;
        TestConfigPath;
        ConfigIOInstance;  
        ApplicationDir;
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function DirectorySetup(testCase)% Shared setup for the entire test class
            applicationPath = mfilename('fullpath');
            [testCase.ApplicationDir, ~, ~] = fileparts(applicationPath);
            testCase.TestConfigPath = fullfile(testCase.ApplicationDir, fullfile("..", "..", "TestingConfig.json"));
            testCase.TestConfigPath = Palladium.Utilities.PathUtils.CleanPath(testCase.TestConfigPath);

            %Test helpers, which keep everything the tests write inside Testing Data Files
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testCase.ApplicationDir, "..", "..", "Helpers")));
        end
    end

    %% Methods(TestMethodSetup)
    methods(TestMethodSetup)
        function createTestingFolders(testCase)
            %A new folder in Testing Data Files for each test, removed by the fixture afterwards
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            testCase.TestingDir = string(fixture.Folder);
            testCase.TestConfigDir = fullfile(testCase.TestingDir, testCase.TestConfigDirName);   %Exists when the tests run
            testCase.TestConfigDir_2 = fullfile(testCase.TestingDir, testCase.TestConfigDirName + "_2");   %Does not exist when the tests run
            mkdir(testCase.TestConfigDir);
        end

        function createConfigIOInstance(testCase)
            testCase.ConfigIOInstance = Palladium.Utilities.ConfigIO();
            testCase.ConfigIOInstance.PromptForGUIEntryOfSettings = false;
        end
    end


    %% Tests
    methods (Test)
       

        %% LoadConfig
        %This test currently fails on linux..
%         function test_LoadConfig_WithDefaultPath(testCase)
%             % Test loading config with default path
%             applicationDir = []; % Use current directory
%             configFilePath = []; % Default path
% 
%             %Point the CIO to the ConfigIO Testing/Test Config Dir, which
%             %doesn't yet exist
%             fullPathToTestConfigDir = Palladium.Utilities.PathUtils.CleanPath(fullfile(testCase.ApplicationDir, testCase.TestConfigDir));
%             palladiumRootDir = Palladium.Utilities.PathUtils.CleanPath(fullfile(testCase.ApplicationDir, "..", "..", ".."));
%             configIODir = fullfile(palladiumRootDir, "+Palladium", "+Utilities");
% 
% 
%             % Verify that the ConfigIO.m file exists where we expect it
%             testCase.verifyTrue(exist(fullfile(configIODir, "ConfigIO.m"), "file")==2);
% 
%             pathFromCIOClassLoc = Palladium.Utilities.PathUtils.MakeFilePathRelative(fullPathToTestConfigDir, RefDir=configIODir);
% 
%             testCase.ConfigIOInstance.ConfigDirectory = pathFromCIOClassLoc;
% 
%             % Create a default config
%             defaultConfig = testCase.ConfigIOInstance.GenerateDefaultConfigStruct();
% disp("Default config created")
%             % Load the config - file will not be found, so this will build
%             % a new one from the default and load it back. This is
%             % therefore a full test of read/write preserving a config
%             % struct
%             loadedConfig = testCase.ConfigIOInstance.LoadConfig(ApplicationDir=applicationDir, ConfigFilePath=configFilePath);
%             testCase.verifyEqual(loadedConfig, defaultConfig);
%         end

        function test_LoadConfig_WithCustomPath(testCase)
            % Test loading config with a custom path - DONE
            applicationDir = []; 
            configFilePath = testCase.TestConfigPath;

            loadedConfig = testCase.ConfigIOInstance.LoadConfig(ApplicationDir=applicationDir, ConfigFilePath=configFilePath);
            testCase.verifyEqual(loadedConfig.PathSettings.DefaultDirectory, "Tests/Testing Data Files/Data");
        end

        %% GetConfigPath
        function test_GetConfigPath_SourceCheckout(testCase)
            % In a source checkout (MATLAB Project in the folder above the source root), the config file is in the source root
            sourceRoot = fileparts(fileparts(fileparts(testCase.ApplicationDir)));   %Tests/Unit Tests/Utilities -> source root
            configPath = testCase.ConfigIOInstance.GetConfigPath(ApplicationDir=sourceRoot);
            testCase.verifyEqual(configPath, fullfile(sourceRoot, "Config.json"));
        end

        function test_GetConfigPath_Installed(testCase)
            % Without the MATLAB Project (an installed toolbox or application), the config file is in the user's settings folder
            configPath = testCase.ConfigIOInstance.GetConfigPath(ApplicationDir=testCase.TestingDir);
            expectedPath = fullfile(Palladium.Utilities.PathUtils.GetAppDataDirectory(), "Palladium DAQ", "Config.json");
            testCase.verifyEqual(configPath, expectedPath);
        end

        %% CopyLegacyConfig (private)
        function test_CopyLegacyConfig_CopiesOldConfig(testCase)
            % A config file in the application folder is copied to the new place, if there is none there yet
            appDir = testCase.TestConfigDir;
            testCase.ConfigIOInstance.SaveDefaultConfig(fullfile(appDir, "Config.json"));
            newPath = fullfile(testCase.TestConfigDir_2, "Config.json");

            testCase.ConfigIOInstance.CopyLegacyConfig(newPath, appDir);
            testCase.verifyTrue(isfile(newPath));
            testCase.verifyEqual(fileread(newPath), fileread(fullfile(appDir, "Config.json")));
        end

        function test_CopyLegacyConfig_KeepsExistingConfig(testCase)
            % An existing config file in the new place is not overwritten
            appDir = testCase.TestConfigDir;
            testCase.ConfigIOInstance.SaveDefaultConfig(fullfile(appDir, "Config.json"));
            newPath = fullfile(testCase.TestConfigDir_2, "Config.json");
            mkdir(testCase.TestConfigDir_2);
            writelines("existing", newPath);

            testCase.ConfigIOInstance.CopyLegacyConfig(newPath, appDir);
            testCase.verifyEqual(strtrim(string(fileread(newPath))), "existing");
        end

        function test_CopyLegacyConfig_NoOldConfig(testCase)
            % Nothing is created if there is no config file in the application folder
            newPath = fullfile(testCase.TestConfigDir_2, "Config.json");
            testCase.ConfigIOInstance.CopyLegacyConfig(newPath, testCase.TestConfigDir);
            testCase.verifyFalse(isfile(newPath));
        end

        %% SaveConfig
        function test_SaveConfig_CreatesDirectory(testCase)
            % Test that SaveConfig creates the directory if it does not exist
            testDir = testCase.TestConfigDir_2; %This directory will not exist when this is run
            testFile = fullfile(testDir, "SaveConfigTest.json");
            configData = testCase.ConfigIOInstance.GenerateDefaultConfigStruct();

            % Save the config
            testCase.ConfigIOInstance.SaveConfig(configData, ConfigFilePath=testFile);

            % Verify that the directory was created
            testCase.verifyTrue(exist(testDir, 'dir') == 7);

            % Verify that the config file exists
            testCase.verifyTrue(exist(testFile, "file")==2);
        end

        %% SetConfigValue
        function test_SetConfigValue(testCase)
            % Test that SetConfigValue changes one setting, and leaves the rest of the file as it was
            testFile = fullfile(testCase.TestConfigDir, "SetConfigValueTest.json");
            testCase.ConfigIOInstance.SaveDefaultConfig(testFile);
            before = readstruct(testFile);

            testCase.ConfigIOInstance.SetConfigValue("WarningSettings", "SuppressPythonSetupWarning", true, ConfigFilePath=testFile);

            after = readstruct(testFile);
            testCase.verifyTrue(after.WarningSettings.SuppressPythonSetupWarning);
            after.WarningSettings.SuppressPythonSetupWarning = before.WarningSettings.SuppressPythonSetupWarning;
            testCase.verifyEqual(after, before);
        end

        function test_SetConfigValue_MissingFile(testCase)
            % Test that SetConfigValue errors for a config file that doesn't exist
            testFile = fullfile(testCase.TestConfigDir_2, "Missing.json");
            testCase.verifyError(@() testCase.ConfigIOInstance.SetConfigValue("WarningSettings", "SuppressPythonSetupWarning", true, ConfigFilePath=testFile), "SetConfigValueError:SetFailed");
        end

        %% SaveDefaultConfig
        function test_SaveDefaultConfig(testCase)
             % Test that SaveConfig creates the directory if it does not exist
            testDir = testCase.TestConfigDir; %This directory will already exist when this is run - adds some more testing to the previous ones where it had to be created, different scenario
            testFile = fullfile(testDir, "SaveDefaultConfigTest.json");

            % Save the config
            testCase.ConfigIOInstance.SaveDefaultConfig(testFile);

            % Verify that the config file exists
            testCase.verifyTrue(exist(testFile, "file")==2);

            % Save the config again so we can confirm overwriting is ok
            testCase.ConfigIOInstance.SaveDefaultConfig(testFile);

            % Verify that the config file exists
            testCase.verifyTrue(exist(testFile, "file")==2);
        end

        %% VerifyConfigStruct (private)
        function test_VerifyConfigStruct_AddMissingFields(testCase)
            % Test that VerifyConfigStruct detects changes
            %Note - removal of a whole sub-struct ie PathSettings does
            %crash everything, this is not handled by the code or tested
            %for. That would be a massive overhaul of settings rather than
            %the planned gradual upgrading of configs
            modifiedConfig = testCase.ConfigIOInstance.GenerateDefaultConfigStruct();
            logSettingsFields = fields(modifiedConfig.LogSettings);
            modifiedConfig.LogSettings = rmfield(modifiedConfig.LogSettings, logSettingsFields{1}); %Remove the first field from the LogSettings struct
            expectedWarningID = "ConfigVerificationWarning:AddedMissingField";

            %Verify that a warning is shown for a deprecated field being removed
            %Note this actually stops the warning being printed in the console, which
            %is nice - it means when we see a warning while testing it is unexpected
            [verifiedConfig, changesDetected, fieldsRemoved] = testCase.verifyWarning(@() testCase.ConfigIOInstance.VerifyConfigStruct(modifiedConfig), expectedWarningID);
  
            testCase.verifyTrue(changesDetected);
            testCase.verifyFalse(fieldsRemoved);    %Only added - LoadConfig then doesn't show a dialog
            testCase.verifyTrue(isfield(verifiedConfig, "PathSettings"));
            testCase.verifyTrue(isfield(verifiedConfig.LogSettings, logSettingsFields{1}));
        end

        function test_VerifyConfigStruct_RemoveDeprecatedFields(testCase)
            % Test that VerifyConfigStruct detects changes
            modifiedConfig = testCase.ConfigIOInstance.GenerateDefaultConfigStruct();
            modifiedConfig.NewField = "NewValue"; % Add a new field
            modifiedConfig.LogSettings.NonsenseField = 'NewLogSettingsValue'; % Add a new field
            expectedWarningID = "ConfigVerificationWarning:RemovedDeprecatedField";

            %Verify that a warning is shown for a deprecated field being removed
            %Note this actually stops the warning being printed in the console, which
            %is nice - it means when we see a warning while testing it is unexpected
            [verifiedConfig, changesDetected, fieldsRemoved] = testCase.verifyWarning(@() testCase.ConfigIOInstance.VerifyConfigStruct(modifiedConfig), expectedWarningID);
  
            testCase.verifyTrue(changesDetected);
            testCase.verifyTrue(fieldsRemoved);
            testCase.verifyTrue(isfield(verifiedConfig, "LogSettings"));
            testCase.verifyFalse(isfield(verifiedConfig, "NewField"));
            testCase.verifyFalse(isfield(verifiedConfig.LogSettings, "NonsenseField"));
        end

    end

end