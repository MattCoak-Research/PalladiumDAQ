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
                Settings.DataFilePath {mustBeTextScalar} = string.empty;
            end
            
            this.FunctionOnComplete = Settings.FunctionOnComplete;

            this.WriteToFile = writeToFile;
            this.DataFilePath = string(Settings.DataFilePath);
        end
    end

    %% Methods (Public)
    methods(Access = public)
        
        function str = GetDescription(this)
            if this.WriteToFile
                str = "Write to: " + string(this.DataFilePath);
            else
                str = "Write Disable";
            end
        end
    end

end