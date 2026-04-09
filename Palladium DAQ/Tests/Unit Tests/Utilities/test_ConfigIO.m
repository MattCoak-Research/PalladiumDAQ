classdef test_ConfigIO < matlab.unittest.TestCase
    % TEST_CONFIGIO Tests for Palladium utilities functions - ConfigIO class

    %% Properties
    properties
        TestingDir = fullfile("..", "data", "ConfigIO Testing");
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
            testCase.TestConfigDir = fullfile(testCase.TestingDir, testCase.TestConfigDirName);     testCase.TestConfigDir = fullfile(testCase.TestingDir, testCase.TestConfigDirName);
            testCase.TestConfigDir_2 = fullfile(testCase.TestingDir, testCase.TestConfigDirName + "_2");      
        end
    end

    %% Methods (TestClassTeardown)
    methods (TestClassTeardown)
        % Remove folder created during test
        function TeardownFiles(testCase)
            if isfolder(testCase.TestConfigDir)
                rmdir(testCase.TestConfigDir, 's')
            end

             if isfolder(testCase.TestConfigDir_2)
                rmdir(testCase.TestConfigDir_2, 's')
            end
        end
    end

    %% Methods(TestMethodSetup)
    methods(TestMethodSetup)
        function createConfigIOInstance(testCase)
            testCase.ConfigIOInstance = Palladium.Utilities.ConfigIO();
            testCase.ConfigIOInstance.PromptForGUIEntryOfSettings = false;
        end
    end


    %% Tests
    methods (Test)

        %% General Tests
        function test_RelativePath(testCase)
            configPath = testCase.ConfigIOInstance.GetConfigDirPath();
            configRelPath = testCase.ConfigIOInstance.ConfigDirectory;  %The path from the ConfigIO class file to the main Palladium directory, where Palladium.m sits
            palladiumRootDir = Palladium.Utilities.PathUtils.CleanPath(fullfile(testCase.ApplicationDir, "..", "..", ".."));
            
            %Check that we are indeed in the right directory, that
            %Palladium.m is there, and we haven't moved a load of files
            %around or changed the folder heirachy
            testCase.verifyEqual(exist(fullfile(palladiumRootDir, "Palladium.m"), "File"), 2);

            %And check that ConfigIO.m is where we expect it (it has hard
            %coded relative paths in it so it had better be)
            configIOFileLocation = fullfile(palladiumRootDir, "+Palladium", "+Utilities");
            testCase.verifyEqual(exist(fullfile(configIOFileLocation, "ConfigIO.m"), "File"), 2);

            %And check the config path matches when grabbed in various ways
            otherConfigPath = fullfile(configIOFileLocation, configRelPath);
            otherConfigPath = Palladium.Utilities.PathUtils.CleanPath(otherConfigPath);
            configPathFromRoot = Palladium.Utilities.PathUtils.CleanPath(fullfile(palladiumRootDir, Palladium.Utilities.ConfigIO.ConfigDirectoryName));
            testCase.verifyEqual(configPath, otherConfigPath);
            testCase.verifyEqual(configPath, configPathFromRoot);
        end

        %% LoadConfig
        function test_LoadConfig_WithDefaultPath(testCase)
            % Test loading config with default path
            applicationDir = []; % Use current directory
            configFilePath = []; % Default path

            %Point the CIO to the ConfigIO Testing/Test Config Dir, which
            %doesn't yet exist
            testCase.ConfigIOInstance.ConfigDirectory = testCase.TestConfigDir;

            % Create a default config
            defaultConfig = testCase.ConfigIOInstance.GenerateDefaultConfigStruct();

            % Load the config - file will not be found, so this will build
            % a new one from the default and load it back. This is
            % therefore a full test of read/write preserving a config
            % struct
            loadedConfig = testCase.ConfigIOInstance.LoadConfig(ApplicationDir=applicationDir, ConfigFilePath=configFilePath);
            testCase.verifyEqual(loadedConfig, defaultConfig);
        end

        function test_LoadConfig_WithCustomPath(testCase)
            % Test loading config with a custom path - DONE
            applicationDir = []; 
            configFilePath = testCase.TestConfigPath;

            loadedConfig = testCase.ConfigIOInstance.LoadConfig(ApplicationDir=applicationDir, ConfigFilePath=configFilePath);
            testCase.verifyEqual(loadedConfig.PathSettings.DefaultDirectory, "../Palladium DAQ/Tests/Palladium DAQ - Testing");
        end

        %% SaveConfig
        function test_SaveConfig_CreatesDirectory(testCase)
            % Test that SaveConfig creates the directory if it does not exist
            testDir = testCase.TestConfigDir_2; %This directory will not exist when this is run
            testFile = fullfile(testDir, "SaveConfigTest.json");
            configData = testCase.ConfigIOInstance.GenerateDefaultConfigStruct();

            % Save the config
            testCase.ConfigIOInstance.SaveConfig(configData, testFile);

            % Verify that the directory was created
            testCase.verifyTrue(exist(testDir, 'dir') == 7);

            % Verify that the config file exists
            testCase.verifyTrue(exist(testFile, "file")==2);
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
            [verifiedConfig, changesDetected] = testCase.verifyWarning(@() testCase.ConfigIOInstance.VerifyConfigStruct(modifiedConfig), expectedWarningID);
  
            testCase.verifyTrue(changesDetected);
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
            [verifiedConfig, changesDetected] = testCase.verifyWarning(@() testCase.ConfigIOInstance.VerifyConfigStruct(modifiedConfig), expectedWarningID);
  
            testCase.verifyTrue(changesDetected);
            testCase.verifyTrue(isfield(verifiedConfig, "LogSettings"));
            testCase.verifyFalse(isfield(verifiedConfig, "NewField"));
            testCase.verifyFalse(isfield(verifiedConfig.LogSettings, "NonsenseField"));
        end

    end

end