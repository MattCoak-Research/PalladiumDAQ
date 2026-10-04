classdef ConfigIO < handle
    %ConfigIO - Class to handling reading and writing of local Config
    %settings to and from (XML) files.

    %% Properties (Constant, Public)
    properties(Constant, Access = public)
        ConfigDirectoryName = "";               %Folder of the config file in a source checkout, relative to the application folder (the source root)
        ConfigFileName = "Config.json";
        UserConfigFolderName = "Palladium DAQ"; %Folder of the config file in the user's application settings folder, for installed copies
        ProjectFileName = "PalladiumDAQ.prj";   %MATLAB Project file, found only in a source checkout, in the folder above the source root
    end

    %% Properties (Public)
    properties(Access = public)
        ConfigDirectory = fullfile(Palladium.Utilities.ConfigIO.ConfigDirectoryName);
        PromptForGUIEntryOfSettings = true;
    end

    %% Properties (Private)
    properties (Access = private)
        EnteredSettingsStruct = []; %Hold entered details (fired from event) in temp property that code can then access when execution resumes
    end

    %% Constructor
    methods
        function this = ConfigIO()
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function configPath = GetConfigPath(this, Settings)
            arguments
                this;
                Settings.ApplicationDir;   
            end

            %Path of the default config file. In a source checkout (with the
            %MATLAB Project) it is in the source root, as it always was. An
            %installed copy - toolbox or compiled application - can't keep it
            %in its installation folder: the compiled application's (e.g. in
            %Program Files) can't be written to, and the toolbox's is replaced
            %by each update. So it goes in the user's application settings
            %folder (see PathUtils.GetAppDataDirectory)

            if this.IsSourceCheckout(Settings.ApplicationDir)
                configPath = this.GetLegacyConfigPath(Settings.ApplicationDir);
            else
                configPath = fullfile(Palladium.Utilities.PathUtils.GetAppDataDirectory(), this.UserConfigFolderName, this.ConfigFileName);
            end
        end

        function con = LoadConfig(this, Settings)
            arguments
                this;
                Settings.ApplicationDir = [];
                Settings.ConfigFilePath = [];                  % Default is blank ([]) - enter a filepath instead to override default Config json file loading and pass in the path for another settings file to be loaded from
            end

            try
                %Load the default path if no override given
                if isempty(Settings.ConfigFilePath)
                    configPath = this.GetConfigPath(ApplicationDir=Settings.ApplicationDir);
                    this.CopyLegacyConfig(configPath, Settings.ApplicationDir);
                else
                    configPath = Settings.ConfigFilePath;
                end
                
                if ~exist(configPath, 'file')
                    %Show a warning in the command window - note that we do
                    %not have a Logger yet and so cannot use that
                    fprintf("\n");
                    disp("[INFO] - Config file not found at " + Palladium.Utilities.PathUtils.CleanPath(configPath));

                    if this.PromptForGUIEntryOfSettings
                        disp("Opening GUI window for config settings entry.");
                        defaultConfig = this.GenerateDefaultConfigStruct();
                        enteredConfig = this.ShowConfigEntryGUI(defaultConfig, Settings.ApplicationDir);
                        this.SaveConfig(enteredConfig, ConfigFilePath=configPath);
                    else
                        disp("Creating default, saving to file.");
                        fprintf("\n");
                        this.SaveDefaultConfig(configPath);
                    end
                end

                %Load config struct from file
                con = readstruct(configPath);

                %Verification - check all expected fields are present. This
                %is mainly for if the software updates and there is an old
                %config file on disk that doesn't have a newly added field.
                %If so, add that in and re-save the config to upgrade it.
                [con, changesDetected, fieldsRemoved] = this.VerifyConfigStruct(con);
                if changesDetected
                    if fieldsRemoved
                        warndlg("Missing lines or obseleted properties found in Config file. Corrupted file or config version needs updating. Adding default values and saving new version of file.", "Config file verification");
                    else
                        %Only new settings added (e.g. after an update) - routine,
                        %so just say so in the command window
                        disp("[INFO] - Added new settings to the Config file at " + Palladium.Utilities.PathUtils.CleanPath(configPath) + ", with default values");
                    end
                    this.SaveConfig(con, ConfigFilePath=configPath);
                end
            catch e
                error("LoadConfigError:LoadFailed", "%s", "Error loading Config file in ConfigIO: " + e.message);
            end
        end

        function SaveConfig(this, config, Settings)
            arguments
                this;
                config;
                Settings.ConfigFilePath;                  % Default is blank ([]) - enter a filepath instead to override default Config json file loading and pass in the path for another settings file to be loaded from
            end

            configPath = Settings.ConfigFilePath;

            try
                %Extract file parts
                [confDir, ~, ext] = fileparts(configPath);
                assert(length(char(ext))>1, "SaveConfigError:MissingExtension", "%s", "File Extension must be included when specifying file path in SaveConfig. filepath was: " + string(configPath));

                %Make the config folder if it doesn't exist already
                if ~exist(confDir, 'dir')
                    mkdir(confDir);
                end

                writestruct(config, configPath, "FileType", "json");
            catch e
                error("SaveConfigError:SaveFailed", "%s", "Error saving Config file in ConfigIO: " + e.message);
            end
        end

        function SetConfigValue(this, sectionName, settingName, value, Settings)
            %Change one setting in a config file, leaving the rest of the file as it is
            arguments
                this;
                sectionName {mustBeTextScalar};     %Section of the config, e.g. "WarningSettings"
                settingName {mustBeTextScalar};     %Setting in that section, e.g. "SuppressPythonSetupWarning"
                value;                              %New value of the setting
                Settings.ApplicationDir = [];       %Application folder, to find the default config file
                Settings.ConfigFilePath = [];       %Path of the config file to change, instead of the default one
            end

            if isempty(Settings.ConfigFilePath)
                configPath = this.GetConfigPath(ApplicationDir=Settings.ApplicationDir);
            else
                configPath = Settings.ConfigFilePath;
            end

            try
                con = readstruct(configPath);
                con.(sectionName).(settingName) = value;
            catch e
                error("SetConfigValueError:SetFailed", "%s", "Error setting " + string(sectionName) + "." + string(settingName) + " in Config file " + string(configPath) + ": " + e.message);
            end
            this.SaveConfig(con, ConfigFilePath=configPath);
        end

        function SaveDefaultConfig(this, configPath)
            try
                s = this.GenerateDefaultConfigStruct();
                this.SaveConfig(s, ConfigFilePath=configPath);
            catch e
                error("SaveDefaultConfigError:SaveFailed", "%s", "Error saving new default Config file in ConfigIO: " + e.message);
            end
        end
        
    end

    %% Methods (Private)
    methods(Access = {?Palladium.Utilities.ConfigIO, ?matlab.unittest.TestCase})    %Permission is Private, but also allow unit tests to see it

        function CopyLegacyConfig(this, configPath, applicationDir)
            %Before the move to the user's settings folder, installed copies
            %kept their config file in the installation folder. If there is
            %one there, and none in the new place yet, carry it over (copied:
            %the installation folder may not be writable, to delete it)
            legacyPath = this.GetLegacyConfigPath(applicationDir);
            if isfile(configPath) || ~isfile(legacyPath) || strcmp(Palladium.Utilities.PathUtils.CleanPath(legacyPath), Palladium.Utilities.PathUtils.CleanPath(configPath))
                return
            end
            Palladium.Utilities.PathUtils.EnsureDirectoryExists(fileparts(configPath));
            copyfile(legacyPath, configPath);
            disp("[INFO] - Copied Config file from " + Palladium.Utilities.PathUtils.CleanPath(legacyPath) + " to " + Palladium.Utilities.PathUtils.CleanPath(configPath));
        end

        function legacyPath = GetLegacyConfigPath(this, applicationDir)
            %Config file path in the application folder - used by a source
            %checkout, and by installed copies before they used the user's
            %settings folder
            legacyPath = fullfile(applicationDir, this.ConfigDirectory, this.ConfigFileName);
        end

        function isSource = IsSourceCheckout(this, applicationDir)
            %True if running from a source checkout (with the MATLAB Project),
            %rather than an installed toolbox or compiled application
            isSource = ~isdeployed && isfile(fullfile(fileparts(applicationDir), this.ProjectFileName));
        end

        function ConfigEntryComplete(this, ~, eventData)
            settingsStruct = eventData.Value;
            this.EnteredSettingsStruct = settingsStruct;
        end

        function s = GenerateDefaultConfigStruct(~)

            %% ------- Edit default config values / add new ones here ----
            %By default everything goes in a Palladium DAQ folder in the
            %user's Documents folder (on Windows, Mac and Linux)
            rootDir = fullfile(Palladium.Utilities.PathUtils.GetDocumentsDirectory(), "Palladium DAQ");

            s.LogSettings.LogFileFileName = "<DATE>_Log.txt";
            s.LogSettings.LogFileDirectory = fullfile(rootDir, "Logs");
            s.LogSettings.LogFileDirectoryIsRelativePath = false;

            s.LogSettings.CommandWindowMessageLevel = "Debug";
            s.LogSettings.PrintStackTraceInCommandWindow = false;
            s.LogSettings.GUIMessageLevel = "Warning";
            s.LogSettings.LogFileMessageLevel = "Debug";
            s.LogSettings.ErrorOnAllInstrumentErrors = false;
 
            s.PathSettings.UserFilesDirectory = rootDir;
            s.PathSettings.UserFilesDirectoryIsRelativePath = false;
            s.PathSettings.DefaultFileName = "<DATE>_Filename";
            s.PathSettings.DefaultDirectory = fullfile(rootDir, "Data");
            s.PathSettings.DefaultSequenceDirectory = fullfile(rootDir, "Sequences");
            s.PathSettings.DataDirectoryIsRelativePath = false;
            s.PathSettings.SequenceDirectoryIsRelativePath = false;

            s.PathSettings.DataFileExtension = ".dat";
            s.PathSettings.SequenceFileExtension = ".seq";
            s.PathSettings.SaveFile = true;
            s.PathSettings.FileWriteMode = "Increment File No.";
            s.PathSettings.DefaultDescription = "";

            s.WindowSettings.DefaultSize = [1200, 900];
            s.WindowSettings.DefaultPosition = [];  %If empty, window will be centred
            s.WindowSettings.Maximised = true;

            s.PlotterSettings.Colours = [1 0 0, 0 0 1, 0 0.6 0, 1 0 1];
            s.PlotterSettings.FontSize = 20;
            s.PlotterSettings.LineStyles = ["None", "None", "None", "None"];
            s.PlotterSettings.LineWidth = 1;
            s.PlotterSettings.MarkerSize = 6;
            s.PlotterSettings.Markers = ["o", "o", "+", "*"];
            s.PlotterSettings.ShowLegends = true;

            s.PythonSettings.PythonExecutable = "";     %Python to use for Python instruments. Blank: the one bundled with the standalone application, or else the one MATLAB finds (see pyenv)

            s.WarningSettings.SuppressPythonSetupWarning = false;   %True to stop warning at startup that Python instruments are unavailable
            % ------------------------------------------------------------
        end

        function con = ShowConfigEntryGUI(this, initialConfig, applicationDir)
            con = initialConfig;
            c = Palladium.Components.ConfigInputWindow();

            c.SetInitialValues(...
                "DefaultDataDirectory", initialConfig.PathSettings.DefaultDirectory,...
                "DefaultDataDirectoryIsRelativePath", initialConfig.PathSettings.DataDirectoryIsRelativePath,...
                "DefaultLogFileDirectory", initialConfig.LogSettings.LogFileDirectory,...
                "DefaultLogFileDirectoryIsRelativePath", initialConfig.LogSettings.LogFileDirectoryIsRelativePath,...
                "DefaultSequenceDirectory", initialConfig.PathSettings.DefaultSequenceDirectory,...
                "DefaultSequenceDirectoryIsRelativePath", initialConfig.PathSettings.SequenceDirectoryIsRelativePath,...
                "DefaultFileName", initialConfig.PathSettings.DefaultFileName,...
                "UserFilesDirectory", initialConfig.PathSettings.UserFilesDirectory,...
                "UserFilesDirectoryIsRelativePath", initialConfig.PathSettings.UserFilesDirectoryIsRelativePath,...
                "WindowWidth", initialConfig.WindowSettings.DefaultSize(1),...
                "WindowHeight", initialConfig.WindowSettings.DefaultSize(2),...
                "WindowStartsMaximised", initialConfig.WindowSettings.Maximised);

            %Subscribe to event when Done button pressed on the Config entry
            addlistener(c, "ConfigEntryComplete", @(src,evnt)this.ConfigEntryComplete(src,evnt));

            waitfor(c);

            if ~isempty(this.EnteredSettingsStruct)
                s = this.EnteredSettingsStruct;
                con.PathSettings.DefaultDirectory = s.DefaultDirectory;
                con.LogSettings.LogFileDirectory = s.LogFileDirectory;
                con.PathSettings.DefaultSequenceDirectory = s.DefaultSequenceDirectory;
                con.PathSettings.SequenceDirectoryIsRelativePath = s.SequenceDirectoryIsRelativePath;
                con.PathSettings.DataDirectoryIsRelativePath = s.DataDirectoryIsRelativePath;
                con.LogSettings.LogFileDirectoryIsRelativePath = s.LogFileDirectoryIsRelativePath;
                con.PathSettings.DefaultFileName = s.DefaultFileName;
                con.PathSettings.UserFilesDirectory = s.UserFilesDirectory;
                con.PathSettings.UserFilesDirectoryIsRelativePath = s.UserFilesDirectoryIsRelativePath;
                con.WindowSettings.DefaultSize = s.DefaultSize;
                con.WindowSettings.Maximised = s.WindowStartsMaximised;

                %Clean up file paths and make desired ones relative instead
                %of absolute
                con.PathSettings.DefaultDirectory = Palladium.Utilities.PathUtils.CleanPath(con.PathSettings.DefaultDirectory);
                con.PathSettings.DefaultSequenceDirectory = Palladium.Utilities.PathUtils.CleanPath(con.PathSettings.DefaultSequenceDirectory);
                con.LogSettings.LogFileDirectory = Palladium.Utilities.PathUtils.CleanPath(con.LogSettings.LogFileDirectory);
                con.PathSettings.UserFilesDirectory = Palladium.Utilities.PathUtils.CleanPath(con.PathSettings.UserFilesDirectory);

                if con.PathSettings.DataDirectoryIsRelativePath
                    [p, success] = Palladium.Utilities.PathUtils.MakeFilePathRelative(con.PathSettings.DefaultDirectory, RefDir=applicationDir);
                    if success
                        con.PathSettings.DefaultDirectory = p;
                    else %Handle case of failing to find a relative path to extract - if the folder given was on a different drive for instance. Path remains absolute, and disable the relative toggle
                        con.PathSettings.DataDirectoryIsRelativePath = false;
                    end
                end

                if con.LogSettings.LogFileDirectoryIsRelativePath
                    [p, success] = Palladium.Utilities.PathUtils.MakeFilePathRelative(con.LogSettings.LogFileDirectory, RefDir=applicationDir);
                    if success
                        con.LogSettings.LogFileDirectory = p;
                    else
                        con.LogSettings.LogFileDirectoryIsRelativePath = false;
                    end
                end

                if con.PathSettings.SequenceDirectoryIsRelativePath
                    [p, success] = Palladium.Utilities.PathUtils.MakeFilePathRelative(con.PathSettings.DefaultSequenceDirectory, RefDir=applicationDir);
                    if success
                        con.PathSettings.DefaultSequenceDirectory = p;
                    else
                        con.PathSettings.SequenceDirectoryIsRelativePath = false;
                    end
                end

                if con.PathSettings.UserFilesDirectoryIsRelativePath
                    [p, success] = Palladium.Utilities.PathUtils.MakeFilePathRelative(con.PathSettings.UserFilesDirectory, RefDir=applicationDir);
                    if success
                        con.PathSettings.UserFilesDirectory = p;
                    else %Handle case of failing to find a relative path to extract - if the folder given was on a different drive for instance. Path remains absolute, and disable the relative toggle
                        con.PathSettings.UserFilesDirectoryIsRelativePath = false;
                    end
                end
            end
        end

        function [con, changesDetected, fieldsRemoved] = VerifyConfigStruct(this, con)
            %Add any settings missing from a loaded config, with default values, and remove any no longer used.
            %changesDetected is true if anything was added or removed,
            %fieldsRemoved if anything was removed
            changesDetected = false;

            df = this.GenerateDefaultConfigStruct();

            %Get top level fields - in our config struct layout, these are
            %all themselves structs (PathSettings etc). Add any missing in
            %the config struct that appear in the default reference one,
            %and remove any that are not found in the ref (and therefore
            %must be obseleted)
            [changesDetected, con, fieldsRemoved] = Palladium.Utilities.ConfigIO.AdjustStructsToMatch(con, df, changesDetected);

            %Grab these again, as they may have changed above (but should
            %now match)
            conFlds = fields(con);
            dfFlds = fields(df);
            assert(isequal(conFlds, dfFlds), "VerifyConfigStructError:FieldListMismatch", "Something has gone wrong in Config verification - these lists of fields really should be equal");

            %Go through each of those container structs in turn and repeat
            %same process
            for i = 1 : length(conFlds)
                cfName = conFlds{i};

                %Clean up this sub-struct
                % - set any empty values in the fields of this field (con is a struct of structs) to [] (instead of e.g. 1x0 empty
                % double row vector)
                subFields = fields(con.(cfName));
                for j = 1 : length(subFields)
                    subF = subFields{j};
                    if isempty(con.(cfName).(subF))
                        con.(cfName).(subF) = [];
                    end
                end
                % - Check for obseleted or new fields
                [changesDetected, newStrct, removed] = Palladium.Utilities.ConfigIO.AdjustStructsToMatch(con.(cfName), df.(cfName), changesDetected);
                fieldsRemoved = fieldsRemoved || removed;
                con.(cfName) = newStrct;
            end

        end

    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function [changesDetected, configStruct, fieldsRemoved] = AdjustStructsToMatch(configStruct, defaultStructToCompareTo, changesDetectedAlready)
            changesDetected = changesDetectedAlready;
            fieldsRemoved = false;

            conFlds = fields(configStruct);
            dfFlds = fields(defaultStructToCompareTo);

            %Make sure these are all there in the loaded one..
            difference = setdiff(dfFlds, conFlds);%This returns cell array of elements in df that are not in con

            %Add these in
            if ~isempty(difference)
                changesDetected = true;

                for i = 1 : length(difference)
                    fieldToAdd = difference{i};
                    warning("ConfigVerificationWarning:AddedMissingField", "%s", "Adding missing config field " + fieldToAdd);
                    configStruct.(fieldToAdd) = defaultStructToCompareTo.(fieldToAdd);
                end
            end

            %And do the reverse - remove any structures NOT found in the
            %default
            difference = setdiff(conFlds, dfFlds);%This returns cell array of elements in con that are not in df

            %Remove obselete fields
            if ~isempty(difference)
                changesDetected = true;
                fieldsRemoved = true;

                for i = 1 : length(difference)
                    fieldToRemove = difference{i};
                    warning("ConfigVerificationWarning:RemovedDeprecatedField", "%s", "Removing deprecated config field " + fieldToRemove);
                    configStruct = rmfield(configStruct, fieldToRemove);
                end
            end
        end
    end
end