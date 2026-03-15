classdef ConfigIO < handle
    %ConfigIO - Class to handling reading and writing of local Config
    %settings to and from (XML) files.
    
    properties(Access = public)
        ConfigDirectory = filesep + ".." + filesep + ".." + filesep + ".." + filesep + ".." + filesep + ".." + filesep + "CoakViewSettings" + filesep;
        PromptForGUIEntryOfSettings = true;
    end

    properties (Access = private)
        EnteredSettingsStruct = []; %Hold enetered details (fired from event) in temp property that code can then access when execution resumes
    end
        
    %% Methods
    methods(Access = public)

        %% Constructor
        function this = ConfigIO()
        end        
        
        %% LoadConfig
        function con = LoadConfig(this)
            try
                confDir = this.GetConfigDirPath();
                configPath = confDir + "Config.json";

                if ~exist(configPath, 'file')
                    %Show a warning in the command window - note that we do
                    %not have a Logger yet and so cannot use that
                    fprintf("\n");
                    disp("[INFO] - Config file not found at " + CoakView.Utilities.FileLoading.PathUtils.CleanPath(configPath));
                    
                    if this.PromptForGUIEntryOfSettings
                        disp("Opening GUI window for config settings entry.");
                        defaultConfig = this.GenerateDefaultConfigStruct();                        
                        enteredConfig = this.ShowConfigEntryGUI(defaultConfig);
                        this.SaveConfig(enteredConfig);
                    else
                        disp("Creating default, saving to file.");
                        fprintf("\n");
                        this.SaveDefaultConfig();
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
                    this.SaveConfig(con);
                end
            catch e
                error("Error loading Config file in ConfigIO: " + e.message);
            end
        end
        
        %% SaveConfig
        function SaveConfig(this, config)
            try
                confDir = this.GetConfigDirPath();
                
                %Make the config folder if it doesn't exist already
                if ~exist(confDir, 'dir')
                    mkdir(confDir);
                end
                
                configPath = [confDir 'Config.json'];
                writestruct(config, configPath, "FileType", "json");
            catch e
                error("Error saving Config file in ConfigIO: " + e.message);
            end
        end
        
        %% SaveDefaultConfig
        function SaveDefaultConfig(this)
            try                
                s = this.GenerateDefaultConfigStruct();                
                this.SaveConfig(s);
            catch e
                error("Error saving new default Config file in ConfigIO: " + e.message);
            end
        end     

        
                
    end
    
    methods(Access = private)
        
        %% ConfigEntryComplete
        function ConfigEntryComplete(this, ~, eventData)
            settingsStruct = eventData.Value;
            this.EnteredSettingsStruct = settingsStruct;
        end

        %% GenerateDefaultConfigStruct
        function s = GenerateDefaultConfigStruct(this)

             %% ------- Edit default config values / add new ones here ----
                s.LogSettings.LogFileDirectory = filesep + ".." + filesep + ".." + filesep + "CoakViewTesting" + filesep + "Logs";
                s.LogSettings.LogFileFileName = "<DATE>_Log.txt";
                s.LogSettings.LogFileDirectoryIsRelativePath = true;
                s.LogSettings.CommandWindowMessageLevel = "Debug";
                s.LogSettings.PrintStackTraceInCommandWindow = false;
                s.LogSettings.GUIMessageLevel = "Warning";
                s.LogSettings.LogFileMessageLevel = "Debug";
                s.LogSettings.ErrorOnAllInstrumentErrors = false;
               
                s.PathSettings.DefaultFileName = "<DATE>_Filename";
                s.PathSettings.DefaultDirectory = filesep + ".." + filesep + ".." + filesep + "CoakViewTesting";
                s.PathSettings.DefaultSequenceDirectory = filesep + ".." + filesep + ".." + filesep + "CoakViewTesting";
                s.PathSettings.DataDirectoryIsRelativePath = true;
                s.PathSettings.SequenceDirectoryIsRelativePath = true;
                s.PathSettings.DataFileExtension = ".dat";
                s.PathSettings.SequenceFileExtension = ".seq";
                s.PathSettings.SaveFile = true;
                s.PathSettings.FileWriteMode = "Increment File No.";
                s.PathSettings.DefaultDescription = "";

                s.WindowSettings.DefaultSize = [1000, 700];
                s.WindowSettings.DefaultPosition = [];  %If empty, window will be centred
                s.WindowSettings.Maximised = true;

                s.PlotterSettings.Colours = [1 0 0, 0 0 1, 0 0.6 0, 1 0 1];
                s.PlotterSettings.FontSize = 20;
                s.PlotterSettings.LineStyles = ["None", "None", "None", "None"];
                s.PlotterSettings.LineWidth = 1;
                s.PlotterSettings.MarkerSize = 6;
                s.PlotterSettings.Markers = ["o"; "o"; "+"; "*"];
                s.PlotterSettings.ShowLegends = true;
                % ------------------------------------------------------------
        end

        %% GetConfigDirPath
        function dirPath = GetConfigDirPath(this)            
            functionPath = mfilename('fullpath');
            [directoryOfThisFunction, ~, ~] = fileparts(functionPath);
            dirPath = fullfile(directoryOfThisFunction, char(this.ConfigDirectory));
        end  

        %% ShowConfigEntryGUI
        function con = ShowConfigEntryGUI(this, initialConfig)  
            con = initialConfig;
            c = CoakView.Components.ConfigInputWindow();

            c.SetInitialValues(...
                "DefaultDataDirectory", initialConfig.PathSettings.DefaultDirectory,...
                "DefaultDataDirectoryIsRelativePath", initialConfig.PathSettings.DataDirectoryIsRelativePath,...
                "DefaultLogFileDirectory", initialConfig.LogSettings.LogFileDirectory,...
                "DefaultLogFileDirectoryIsRelativePath", initialConfig.LogSettings.LogFileDirectoryIsRelativePath,...
                "DefaultFileName", initialConfig.PathSettings.DefaultFileName,...
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
                con.WindowSettings.DefaultSize = s.DefaultSize;
                con.WindowSettings.Maximised = s.WindowStartsMaximised;

                %Clean up file paths and make desired ones relative instead
                %of absolute
                con.PathSettings.DefaultDirectory = CoakView.Utilities.FileLoading.PathUtils.CleanPath(con.PathSettings.DefaultDirectory);
                con.LogSettings.LogFileDirectory = CoakView.Utilities.FileLoading.PathUtils.CleanPath(con.LogSettings.LogFileDirectory);

                if con.PathSettings.DataDirectoryIsRelativePath
                    [p, success] = CoakView.Utilities.FileLoading.PathUtils.MakeFilePathRelative(con.PathSettings.DefaultDirectory);
                    if success
                        con.PathSettings.DefaultDirectory = p;
                    else %Handle case of failing to find a relative path to extract - if the folder given was on a different drive for instance. Path remains absolute, and disable the relative toggle
                        con.PathSettings.DataDirectoryIsRelativePath = false;
                    end
                end

                if con.LogSettings.LogFileDirectoryIsRelativePath
                    [p, success] = CoakView.Utilities.FileLoading.PathUtils.MakeFilePathRelative(con.LogSettings.LogFileDirectory);
                    if success
                        con.LogSettings.LogFileDirectory = p;
                    else
                        con.LogSettings.LogFileDirectoryIsRelativePath = false;
                    end
                end
            end
        end

        %% VerifyConfigStruct
        function [con, changesDetected] = VerifyConfigStruct(this, con)
            changesDetected = false;

            df = this.GenerateDefaultConfigStruct();

            %Get top level fields - in our config struct layout, these are
            %all themselves structs (PathSettings etc). Add any missing in
            %the config struct that appear in the default reference one,
            %and remove any that are not found in the ref (and therefore
            %must be obseleted)
            [changesDetected, con] = CoakView.Utilities.FileLoading.ConfigIO.AdjustStructsToMatch(con, df, changesDetected);

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
                [changesDetected, newStrct] = CoakView.Utilities.FileLoading.ConfigIO.AdjustStructsToMatch(con.(cfName), df.(cfName), changesDetected);
                con.(cfName) = newStrct;
            end
            
        end

    end

    methods (Static, Access = private)

        %% AdjustStructsToMatch
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