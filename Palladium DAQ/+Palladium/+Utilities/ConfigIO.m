classdef ConfigIO < handle
    %ConfigIO - Reads and writes Palladium DAQ's Config.json settings file.
    %The Controller loads the config at start-up with `LoadConfig`, which
    %finds the file (`GetConfigPath`), creates it from the **Config Entry**
    %window or the defaults if there is none, and adds any settings it is
    %missing. `SetConfigValue` changes one setting, e.g. when the user
    %turns off a warning. The settings and their defaults are listed in
    %`GenerateDefaultConfigStruct`, and on the [Presets and config](../presets-and-config.md) page.

    %% Properties (Constant, Public)
    properties(Constant, Access = public)
        ConfigDirectoryName = "";               %Folder of the config file in a source checkout, relative to the application folder (the source root)
        ConfigFileName = "Config.json";         %Name of the config file
        UserConfigFolderName = "Palladium DAQ"; %Folder of the config file in the user's application settings folder, for installed copies
        ProjectFileName = "PalladiumDAQ.prj";   %MATLAB Project file, found only in a source checkout, in the folder above the source root
    end

    %% Properties (Public)
    properties(Access = public)
        ConfigDirectory = fullfile(Palladium.Utilities.ConfigIO.ConfigDirectoryName);  %Folder of the config file in a source checkout, relative to the application folder
        PromptForGUIEntryOfSettings = true;     %True to ask for the settings in the Config Entry window when there is no config file; false to use the defaults (e.g. in tests)
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
            %The path of the default config file, which depends on whether this is a source checkout.
            %In a source checkout (with the MATLAB Project) it is in the
            %source root, as it always was. An installed copy - toolbox or
            %compiled application - can't keep it in its installation folder:
            %the compiled application's (e.g. in Program Files) can't be
            %written to, and the toolbox's is replaced by each update. So it
            %goes in the user's application settings folder
            %(`PathUtils.GetAppDataDirectory`), in a `Palladium DAQ` folder
            %
            %Inputs (name-value):
            %   ApplicationDir - the folder Palladium.m is in
            %
            %Outputs:
            %   configPath - full path of Config.json

            arguments
                this;
                Settings.ApplicationDir;
            end

            if this.IsSourceCheckout(Settings.ApplicationDir)
                configPath = this.GetLegacyConfigPath(Settings.ApplicationDir);
            else
                configPath = fullfile(Palladium.Utilities.PathUtils.GetAppDataDirectory(), this.UserConfigFolderName, this.ConfigFileName);
            end
        end

        function con = LoadConfig(this, Settings)
            %Load the config file as a struct, creating it first if there is none.
            %A new file is made from the settings entered in the Config Entry
            %window, or from the defaults if PromptForGUIEntryOfSettings is
            %false. Settings an older file is missing are added with default
            %values, and ones no longer used are removed (with a message), and
            %the file is saved again. An installed copy's config file from
            %before it moved to the user's settings folder is copied there
            %(`CopyLegacyConfig`)
            %
            %Inputs (name-value):
            %   ApplicationDir - the folder Palladium.m is in, to find the default config file
            %   ConfigFilePath - full path of a config file to use instead. Default []
            %
            %Outputs:
            %   con - the config, a struct of sections (LogSettings, PathSettings, ...)

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
                        warndlg("Missing lines or obsolete settings found in Config file. Corrupted file or config version needs updating. Adding default values and saving new version of file.", "Config file verification");
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
            %Write a config struct to a JSON file, creating its folder if needed.
            %
            %Inputs:
            %   config         - the config struct
            %   ConfigFilePath - (name-value) full path of the file, including .json

            arguments
                this;
                config;
                Settings.ConfigFilePath;
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
            %Change one setting in a config file, leaving the rest of the file as it is.

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
            %Write a config file with the default settings (GenerateDefaultConfigStruct).
            %
            %Inputs:
            %   configPath - full path of the file, including .json

            try
                s = this.GenerateDefaultConfigStruct();
                this.SaveConfig(s, ConfigFilePath=configPath);
            catch e
                error("SaveDefaultConfigError:SaveFailed", "%s", "Error saving new default Config file in ConfigIO: " + e.message);
            end
        end

        function s = GenerateDefaultConfigStruct(~)
            %The default config settings, as a struct - used for a new config file, and to add missing settings to an old one.
            %By default the data, log, sequence and user files folders are in
            %Documents/Palladium DAQ, as full paths
            %
            %Outputs:
            %   s - the config struct, with LogSettings, PathSettings etc. sections

            %% ------- Edit default config values / add new ones here ----
            %By default everything goes in a Palladium DAQ folder in the
            %user's Documents folder (on Windows, Mac and Linux)
            rootDir = fullfile(Palladium.Utilities.PathUtils.GetDocumentsDirectory(), "Palladium DAQ");

            s.LogSettings.LogFileFileName = "<DATE>_Log.txt";
            s.LogSettings.LogFileDirectory = fullfile(rootDir, "Logs");

            s.LogSettings.CommandWindowMessageLevel = "Debug";
            s.LogSettings.PrintStackTraceInCommandWindow = false;
            s.LogSettings.GUIMessageLevel = "Warning";
            s.LogSettings.LogFileMessageLevel = "Debug";
            s.LogSettings.ErrorOnAllInstrumentErrors = false;

            s.PathSettings.UserFilesDirectory = rootDir;
            s.PathSettings.DefaultFileName = "<DATE>_Filename";
            s.PathSettings.DefaultDirectory = fullfile(rootDir, "Data");
            s.PathSettings.DefaultSequenceDirectory = fullfile(rootDir, "Sequences");

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

        function isSource = IsSourceCheckout(this, applicationDir)
            %Whether Palladium DAQ is running from a source checkout, rather than an installed copy.
            %A source checkout has the MATLAB Project in the folder above
            %applicationDir. An installed toolbox or compiled application
            %doesn't
            %
            %Inputs:
            %   applicationDir - the folder Palladium.m is in
            %
            %Outputs:
            %   isSource - true for a source checkout

            isSource = ~isdeployed && isfile(fullfile(fileparts(applicationDir), this.ProjectFileName));
        end

    end

    %% Methods (Private)
    methods(Access = {?Palladium.Utilities.ConfigIO, ?matlab.unittest.TestCase})    %Permission is Private, but also allow unit tests to see it

        function CopyLegacyConfig(this, configPath, applicationDir)
            %Copy an installed copy's old config file from its installation folder to the user's settings folder.
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
            %The config file's path in the application folder.
            %Used by a source checkout, and by installed copies before they
            %used the user's settings folder

            legacyPath = fullfile(applicationDir, this.ConfigDirectory, this.ConfigFileName);
        end

        function ConfigEntryComplete(this, ~, eventData)
            %Keep the settings entered in the Config Entry window, when its Done button is pressed.

            settingsStruct = eventData.Value;
            this.EnteredSettingsStruct = settingsStruct;
        end

        function con = ShowConfigEntryGUI(this, initialConfig, applicationDir)
            %Show the Config Entry window, wait for it to close, and return the config with the settings entered.
            %If the window is closed without pressing Done, initialConfig is
            %returned unchanged
            %
            %Inputs:
            %   initialConfig  - the config to start from, normally the defaults
            %   applicationDir - the folder Palladium.m is in, for relative paths
            %
            %Outputs:
            %   con - the config to save

            con = initialConfig;
            c = Palladium.Components.ConfigInputWindow();

            c.SetInitialValues(...
                "DefaultDataDirectory", initialConfig.PathSettings.DefaultDirectory,...
                "DefaultDataDirectoryIsRelativePath", ~Palladium.Utilities.PathUtils.IsAbsolutePath(initialConfig.PathSettings.DefaultDirectory),...
                "DefaultLogFileDirectory", initialConfig.LogSettings.LogFileDirectory,...
                "DefaultLogFileDirectoryIsRelativePath", ~Palladium.Utilities.PathUtils.IsAbsolutePath(initialConfig.LogSettings.LogFileDirectory),...
                "DefaultSequenceDirectory", initialConfig.PathSettings.DefaultSequenceDirectory,...
                "DefaultSequenceDirectoryIsRelativePath", ~Palladium.Utilities.PathUtils.IsAbsolutePath(initialConfig.PathSettings.DefaultSequenceDirectory),...
                "DefaultFileName", initialConfig.PathSettings.DefaultFileName,...
                "UserFilesDirectory", initialConfig.PathSettings.UserFilesDirectory,...
                "UserFilesDirectoryIsRelativePath", ~Palladium.Utilities.PathUtils.IsAbsolutePath(initialConfig.PathSettings.UserFilesDirectory),...
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
                con.PathSettings.DefaultFileName = s.DefaultFileName;
                con.PathSettings.UserFilesDirectory = s.UserFilesDirectory;
                con.WindowSettings.DefaultSize = s.DefaultSize;
                con.WindowSettings.Maximised = s.WindowStartsMaximised;

                %Store each folder relative to applicationDir if its "relative"
                %box was ticked, and absolute if not. The boxes are only used
                %here - whether a stored path is relative is seen from the
                %path itself (PathUtils.IsAbsolutePath)
                con.PathSettings.DefaultDirectory = this.ApplyRelativeChoice(con.PathSettings.DefaultDirectory, s.DataDirectoryIsRelativePath, applicationDir);
                con.LogSettings.LogFileDirectory = this.ApplyRelativeChoice(con.LogSettings.LogFileDirectory, s.LogFileDirectoryIsRelativePath, applicationDir);
                con.PathSettings.DefaultSequenceDirectory = this.ApplyRelativeChoice(con.PathSettings.DefaultSequenceDirectory, s.SequenceDirectoryIsRelativePath, applicationDir);
                con.PathSettings.UserFilesDirectory = this.ApplyRelativeChoice(con.PathSettings.UserFilesDirectory, s.UserFilesDirectoryIsRelativePath, applicationDir);
            end
        end

        function path = ApplyRelativeChoice(~, path, makeRelative, applicationDir)
            %Store a folder path relative to applicationDir, or absolute, as chosen in the Config Entry window.
            %A folder that can't be made relative (e.g. on another drive)
            %stays absolute
            %
            %Inputs:
            %   path           - the folder, absolute or relative to applicationDir
            %   makeRelative   - true to store it relative to applicationDir
            %   applicationDir - the folder Palladium.m (or the app) is in
            %
            %Outputs:
            %   path - the folder to store, tidied (PathUtils.CleanPath)

            path = Palladium.Utilities.PathUtils.CleanPath(path);
            isAbsolute = Palladium.Utilities.PathUtils.IsAbsolutePath(path);
            if makeRelative && isAbsolute
                [relativePath, success] = Palladium.Utilities.PathUtils.MakeFilePathRelative(path, RefDir=applicationDir);
                if success
                    path = relativePath;
                end
            elseif ~makeRelative && ~isAbsolute
                path = Palladium.Utilities.PathUtils.CleanPath(fullfile(applicationDir, path));
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
            %must be obsolete)
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
                % - Check for obsolete or new fields
                [changesDetected, newStrct, removed] = Palladium.Utilities.ConfigIO.AdjustStructsToMatch(con.(cfName), df.(cfName), changesDetected);
                fieldsRemoved = fieldsRemoved || removed;
                con.(cfName) = newStrct;
            end

        end

    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function [changesDetected, configStruct, fieldsRemoved] = AdjustStructsToMatch(configStruct, defaultStructToCompareTo, changesDetectedAlready)
            %Add the fields a struct is missing, from the default one, and remove the fields the default doesn't have.
            %changesDetected is changesDetectedAlready, or true if anything
            %changed; fieldsRemoved is true if anything was removed

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

            %Remove obsolete fields
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