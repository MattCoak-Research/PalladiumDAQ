classdef ConfigIO < handle
    %ConfigIO - Class to handling reading and writing of local Config
    %settings to and from (XML) files.

    %% Properties (Public)
    properties(Access = public)
        ConfigDirectory = filesep + ".." + filesep + ".." + filesep + "Palladium DAQ - Settings" + filesep;
        PromptForGUIEntryOfSettings = true;
    end

    %% Properties (Private)
    properties (Access = private)
        EnteredSettingsStruct = []; %Hold enetered details (fired from event) in temp property that code can then access when execution resumes
    end

    %% Constructor
    methods
        function this = ConfigIO()
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function con = LoadConfig(this, Settings)
            arguments
                this;
                Settings.ApplicationDir = [];
                Settings.ConfigFilePath = [];                  % Default is blank ([]) - enter a filepath instead to override default Config json file loading and pass in the path for another settings file to be loaded from
            end

            try
                %Load the default path if no override given
                if isempty(Settings.ConfigFilePath)
                    confDir = this.GetConfigDirPath();
                    configPath = confDir + "Config.json";
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
                        this.SaveConfig(enteredConfig, configPath);
                    else
                        disp("Creating default, saving to file.");
                        fprintf("\n");
                        this.SaveDefaultConfig(configPath);
                    end
                end

                %Load config struct from file
                con = readstruct(configPath);

                %Verfication - check all expected fields are present. This
                %is mainly for if the software updates and there is an old
                %config file on disk that doesn't have a newly added field.
                %If so, add that in and re-save the config to upgrade it.
                [con, changesDetected] = this.VerifyConfigStruct(con);
                if changesDetected
                    warndlg("Missing lines or obseleted properties found in Config file. Corrupted file or config version needs updating. Adding default values and saving new version of file.", "Config file verification");
                    this.SaveConfig(con, configPath);
                end
            catch e
                error("Error loading Config file in ConfigIO: " + e.message);
            end
        end

        function SaveConfig(~, config, configPath)
            try
                %Extract file parts
                [confDir, ~, ~] = fileparts(configPath);

                %Make the config folder if it doesn't exist already
                if ~exist(confDir, 'dir')
                    mkdir(confDir);
                end

                writestruct(config, configPath, "FileType", "json");
            catch e
                error("Error saving Config file in ConfigIO: " + e.message);
            end
        end

        function SaveDefaultConfig(this, configPath)
            try
                s = this.GenerateDefaultConfigStruct();
                this.SaveConfig(s, configPath);
            catch e
                error("Error saving new default Config file in ConfigIO: " + e.message);
            end
        end
        
    end

    %% Methods (Private)
    methods(Access = {?Palladium.Utilities.ConfigIO, ?matlab.unittest.TestCase})    %Permission is Private, but also allow unit tests to see it

        function ConfigEntryComplete(this, ~, eventData)
            settingsStruct = eventData.Value;
            this.EnteredSettingsStruct = settingsStruct;
        end

        function s = GenerateDefaultConfigStruct(~)

            %% ------- Edit default config values / add new ones here ----
            s.LogSettings.LogFileDirectory = ".." + filesep + "Palladium DAQ - Testing" + filesep + "Logs";
            s.LogSettings.LogFileFileName = "<DATE>_Log.txt";
            s.LogSettings.LogFileDirectoryIsRelativePath = true;
            s.LogSettings.CommandWindowMessageLevel = "Debug";
            s.LogSettings.PrintStackTraceInCommandWindow = false;
            s.LogSettings.GUIMessageLevel = "Warning";
            s.LogSettings.LogFileMessageLevel = "Debug";
            s.LogSettings.ErrorOnAllInstrumentErrors = false;
 
            s.PathSettings.UserFilesDirectory = Palladium.Utilities.PathUtils.GetUserDirectory();
            s.PathSettings.UserFilesDirectoryIsRelativePath = false;
            s.PathSettings.DefaultFileName = "<DATE>_Filename";
            s.PathSettings.DefaultDirectory = ".." + filesep + "Palladium DAQ - Testing";
            s.PathSettings.DefaultSequenceDirectory = ".." + filesep + "Palladium DAQ - Testing";
            s.PathSettings.DataDirectoryIsRelativePath = true;
            s.PathSettings.SequenceDirectoryIsRelativePath = true;
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
            % ------------------------------------------------------------
        end

        function dirPath = GetConfigDirPath(this)
            functionPath = mfilename('fullpath');
            [directoryOfThisFunction, ~, ~] = fileparts(functionPath);
            dirPath = fullfile(directoryOfThisFunction, char(this.ConfigDirectory));
        end

        function con = ShowConfigEntryGUI(this, initialConfig, applicationDir)
            con = initialConfig;
            c = Palladium.Components.ConfigInputWindow();

            c.SetInitialValues(...
                "DefaultDataDirectory", initialConfig.PathSettings.DefaultDirectory,...
                "DefaultDataDirectoryIsRelativePath", initialConfig.PathSettings.DataDirectoryIsRelativePath,...
                "DefaultLogFileDirectory", initialConfig.LogSettings.LogFileDirectory,...
                "DefaultLogFileDirectoryIsRelativePath", initialConfig.LogSettings.LogFileDirectoryIsRelativePath,...
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

        function [con, changesDetected] = VerifyConfigStruct(this, con)
            changesDetected = false;

            df = this.GenerateDefaultConfigStruct();

            %Get top level fields - in our config struct layout, these are
            %all themselves structs (PathSettings etc). Add any missing in
            %the config struct that appear in the default reference one,
            %and remove any that are not found in the ref (and therefore
            %must be obseleted)
            [changesDetected, con] = Palladium.Utilities.ConfigIO.AdjustStructsToMatch(con, df, changesDetected);

            %Grab these again, as they may have changed above (but should
            %now match)
            conFlds = fields(con);
            dfFlds = fields(df);
            assert(isequal(conFlds, dfFlds), "Something has gone wrong in Config verification - these lists of fields really should be equal");

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
                [changesDetected, newStrct] = Palladium.Utilities.ConfigIO.AdjustStructsToMatch(con.(cfName), df.(cfName), changesDetected);
                con.(cfName) = newStrct;
            end

        end

    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function [changesDetected, configStruct] = AdjustStructsToMatch(configStruct, defaultStructToCompareTo, changesDetectedAlready)
            changesDetected = changesDetectedAlready;

            conFlds = fields(configStruct);
            dfFlds = fields(defaultStructToCompareTo);

            %Make sure these are all there in the loaded one..
            difference = setdiff(dfFlds, conFlds);%This returns cell array of elements in df that are not in con

            %Add these in
            if ~isempty(difference)
                changesDetected = true;

                for i = 1 : length(difference)
                    fieldToAdd = difference{i};
                    warning("Adding missing config field " + fieldToAdd);
                    configStruct.(fieldToAdd) = defaultStructToCompareTo.(fieldToAdd);
                end
            end

            %And do the reverse - remove any structures NOT found in the
            %default
            difference = setdiff(conFlds, dfFlds);%This returns cell array of elements in con that are not in df

            %Remove obselete fields
            if ~isempty(difference)
                changesDetected = true;

                for i = 1 : length(difference)
                    fieldToRemove = difference{i};
                    warning("Removing deprecated config field " + fieldToRemove);
                    configStruct = rmfield(configStruct, fieldToRemove);
                end
            end
        end
    end
end