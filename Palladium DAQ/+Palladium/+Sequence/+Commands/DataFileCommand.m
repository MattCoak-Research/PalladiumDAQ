classdef DataFileCommand < Palladium.Sequence.Commands.Command
    %WAITCOMMAND 

    %% Properties (Public)
    properties(Access = public)
        WriteToFile;
        DataFilePath;
    end

    %% Properties (Private)
    properties (Access = private)
        Timer;
    end    

    %% Constructor
    methods
        function this = DataFileCommand(writeToFile, Settings)
            arguments
                writeToFile (1,1) logical;
                Settings.FunctionOnComplete = [];
                Settings.DataFilePath {mustBeTextScalar} = "";     %New data file. Empty: keep the current file, and just switch writing on or off
            end
            
            this.FunctionOnComplete = Settings.FunctionOnComplete;

            this.WriteToFile = writeToFile;
            this.DataFilePath = string(Settings.DataFilePath);
        end
    end

    %% Methods (Public)
    methods(Access = public)
        
        function str = GetDescription(this)
            if this.WriteToFile && strlength(this.DataFilePath) > 0
                str = "Write to: " + string(this.DataFilePath);
            elseif this.WriteToFile
                str = "Write Enable (current file name)";
            else
                str = "Write Disable";
            end
        end
    end

end