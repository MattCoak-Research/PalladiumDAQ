classdef ConfigIO < handle
    %ConfigIO - Class to handling reading and writing of local Config
    %settings to and from (XML) files.
    
    properties(Access = public)
        ConfigDirectory = "\..\..\..\..\..\CoakViewSettings\";
        Config;
    end
    
    properties(Access = private)
        config;
    end
    
    %% Gets and Sets
    methods
        function con = get.Config(this)
            if(isempty(this.config))
                this.config = this.LoadConfig();
            end
            
            con = this.config;
        end
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
                configPath = confDir + "\Config.json";

                if ~exist(configPath, 'file')
                    %Show a warning in the command window - note that we do
                    %not have a Logger yet and so cannot use that
                    fprintf("\n");
                    disp("[INFO] - Config file not found at " + CoakView.Utilities.FileLoading.PathUtils.CleanPath(configPath));
                    disp("Creating default, saving to file.");
                    fprintf("\n");
                    this.SaveDefaultConfig();
                end
                con = readstruct(configPath);
            catch e
                error("Error loading Config file in ConfigIO: " + e.message);
            end
        end
        
        %% SaveConfig
        function SaveConfig(this)
            try
                confDir = this.GetConfigDirPath();
                
                %Make the config folder if it doesn't exist already
                if ~exist(confDir, 'dir')
                    mkdir(confDir);
                end
                
                configPath = [confDir 'Config.json'];
                writestruct(this.config, configPath, "FileType", "json");
            catch e
                error("Error saving Config file in ConfigIO: " + e.message);
            end
        end
        
        %% SaveDefaultConfig
        function SaveDefaultConfig(this)
            try
                
                %% ------- Edit default config values / add new ones here ----
                s.LogSettings.LogFileDirectory = "..\CoakViewTesting\Logs";
                s.LogSettings.LogFileFileName = "<DATE>_Log.txt";
                s.LogSettings.LogFileDirectoryIsRelativePath = true;
                s.LogSettings.CommandWindowMessageLevel = "Debug";
                s.LogSettings.PrintStackTraceInCommandWindow = false;
                s.LogSettings.GUIMessageLevel = "Warning";
                s.LogSettings.LogFileMessageLevel = "Debug";
                s.LogSettings.ErrorOnAllInstrumentErrors = false;
               
                s.PathSettings.DefaultPath = "<DATE>_Filename";
                s.PathSettings.DefaultDirectory = "..\CoakViewTesting";
                s.PathSettings.DefaultSequenceDirectory = "..\CoakViewTesting";
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
                
                this.config = s;
                this.SaveConfig();
            catch e
                error("Error saving new default Config file in ConfigIO: " + e.message);
            end
        end     
                
    end
    
    methods(Access = private)
        
        %% GetConfigDirPath
        function dirPath = GetConfigDirPath(this)            
            functionPath = mfilename('fullpath');
            [directoryOfThisFunction, ~, ~] = fileparts(functionPath);
            dirPath = fullfile(directoryOfThisFunction, char(this.ConfigDirectory));
        end        

    end
end