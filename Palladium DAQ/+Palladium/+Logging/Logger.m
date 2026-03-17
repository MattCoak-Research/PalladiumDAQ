classdef Logger < handle
    %Logger - Singleton static instance class for handling logging to
    %command line / file / GUI in Palladium
    %Create an instance of this from Controller initialisation


    properties (Access = public)
    end

    properties (Access = private)
        Controller;
    end


    methods
        %% Constructor
        function this = Logger(controller, LogFileDirectory, LogFileFileName, Settings)
            arguments
                controller                                          (1,1) Palladium.Core.Controller;
                LogFileDirectory                                    {mustBeTextScalar};
                LogFileFileName                                     {mustBeTextScalar};
                Settings.CommandWindowMessageLevel                  {mustBeTextScalar, mustBeMember(Settings.CommandWindowMessageLevel, ["Off", "Debug", "Info", "Warning", "Error"])}  = "Debug";      %Messages at or above this severity level will be passed on to Command Window
                Settings.GUIMessageLevel                            {mustBeTextScalar, mustBeMember(Settings.GUIMessageLevel, ["Off", "Debug", "Info", "Warning", "Error"])}            = "Warning";    %Messages at or above this severity level will be passed on to GUI
                Settings.LogFileMessageLevel                        {mustBeTextScalar, mustBeMember(Settings.LogFileMessageLevel, ["Off", "Debug", "Info", "Warning", "Error"])}        = "Debug";
                Settings.PrintStackTraceInCommandWindow             (1,1) logical = false;
            end

            this.Controller = controller;

            %This slightly clumsy pass-through boilerplate allows choosing
            %Logger settings on constructing it, then those options
            Palladium.Logging.Logger.Log("Debug", "Logger created",...
                "LogFileDirectory", LogFileDirectory,...
                "LogFileFileName", LogFileFileName,...
                "CommandWindowMessageLevel", Settings.CommandWindowMessageLevel,...
                "GUIMessageLevel", Settings.GUIMessageLevel,...
                "LogFileMessageLevel", Settings.LogFileMessageLevel,...
                "PrintStackTraceInCommandWindow", Settings.PrintStackTraceInCommandWindow...
                );
        end

    end

    methods (Static)
        %% HandleError
        function [Halt, suppressError] = HandleError(message, err, uiFigureHandle)
            Halt = false;
            suppressError = false;

            %Last error thrown; could be a MATLAB builtin.
            TopErrorFile = err.stack(1).file;
            TopErrorName = string(err.stack(1).name);
            TopErrorLine = err.stack(1).line;

            %Get last user error; this has an exist type of 0;
            for i = 1:length(err.stack)
                ExistsType(i,1) = exist(err.stack(i,1).name);
            end

            %Get the details of the first function erroring which isn't a
            %builtin.
            IndexOfFirstUserFuncError = find(ExistsType(:,1) == 0, 1);
            UserErrorFile = err.stack(IndexOfFirstUserFuncError).file;
            UserErrorName = err.stack(IndexOfFirstUserFuncError).name;
            UserErrorLine = err.stack(IndexOfFirstUserFuncError).line;

            %If the first function is a user function, error string can be
            %simpler. Otherwise, show both the builtin's error and the
            %user's error.
            message = string(message) + ": " + string(err.message);
            if( strcmp(UserErrorFile, TopErrorFile))
                ErrorString = string(sprintf("Error in " + TopErrorName + " - line " + num2str(TopErrorLine) + "\n\n")) + string(message);
            else
                ErrorString = string(sprintf("Error in Matlab function " + TopErrorName + " - line " + num2str(TopErrorLine) + ":\n\n")) + string(message) + string(sprintf("\n\nError in user function " + UserErrorName + " - line " + num2str(UserErrorLine) + "."));
            end

            if isempty(uiFigureHandle)  %If we do not have a uiFigure GUI to create modal dialogue boses in..
                %Show a normal dialogue box asking the user what they want
                %to do
                msg = ErrorString;
                title = "Error";
                ErrorQuestResult = questdlg(string(msg), title, ...
                    "Stop Measurements", "Stop & Go to Code", "Ignore", "Ignore");
            else
                %Show a modal dialogue box asking the user what they want
                %to do
                fig = uiFigureHandle;
                msg = ErrorString;
                title = "Error";
                ErrorQuestResult = uiconfirm(fig, string(msg), title, ...
                    "Options", ["Stop Measurements", "Stop & Go to Code", "Suppress Error", "Ignore"], ...
                    "Icon","warning", "Interpreter", "HTML",...
                    "DefaultOption", 1, "CancelOption", 4);
            end

            %On error, either switch to the command window to view full
            %stack trace, open editor at mistake lines or just do nothing.
            switch(ErrorQuestResult)
                case "Stop Measurements"
                    Halt = true;
                case "Stop & Go to Code"
                    Halt = true;
                    fprintf(2, '%s\n', getReport(err, 'extended'));
                    matlab.desktop.editor.openAndGoToLine(TopErrorFile, TopErrorLine);
                    matlab.desktop.editor.openAndGoToLine(UserErrorFile, UserErrorLine);
                case "Suppress Error"
                    suppressError = true;
                case "Ignore"
                    %Do nothing
                otherwise
                    error("Awful meta-error in the error handling");
            end
        end

        %% Log
        function Log(level, message, Settings)
            %Print a message to a combination of command window, GUI and
            %log file on disk, depending on selected options and level of
            %severity of the message
            arguments
                level {mustBeTextScalar, mustBeMember(level, ["Debug", "Info", "Warning", "Error"])};
                message {mustBeTextScalar};
                Settings.FullMessage                = [];
                Settings.Controller                 = [];
                Settings.LogFileDirectory           = [];    %Will be set in the constructor call that passes through to this
                Settings.LogFileFileName                {mustBeTextScalar} = "";    %Will be set in the constructor call that passes through to this
                Settings.CommandWindowMessageLevel      {mustBeTextScalar, mustBeMember(Settings.CommandWindowMessageLevel, ["Off", "Debug", "Info", "Warning", "Error"])}  = "Debug";      %Messages at or above this severity level will be passed on to Command Window
                Settings.GUIMessageLevel                {mustBeTextScalar, mustBeMember(Settings.GUIMessageLevel, ["Off", "Debug", "Info", "Warning", "Error"])}            = "Warning";    %Messages at or above this severity level will be passed on to GUI
                Settings.LogFileMessageLevel            {mustBeTextScalar, mustBeMember(Settings.LogFileMessageLevel, ["Off", "Debug", "Info", "Warning", "Error"])}        = "Debug";
                Settings.PrintStackTraceInCommandWindow (1,1) logical = false;
            end

            %Option to have a full verbose message to log to e.g. file but
            %without cluttering up the GUI, if provided
            if isempty(Settings.FullMessage)
                fullMessage = message;
            else
                fullMessage = Settings.FullMessage;
            end

            %Annoying boilerplate to essentially hack in static properties,
            %which Matlab does not allow
            persistent Controller;
            if isempty(Controller) || ~isempty(Settings.Controller) %Second argument is basically a code for 'is this being called from the constructor?'
                Controller = Settings.Controller;
            end

            persistent LogFileDirectory;
            if isempty(LogFileDirectory) || ~isempty(Settings.Controller) %Second argument is basically a code for 'is this being called from the constructor?'
                LogFileDirectory = Settings.LogFileDirectory;
            end

            persistent LogFileFileName;
            if isempty(LogFileFileName) || ~isempty(Settings.Controller)
                LogFileFileName = Settings.LogFileFileName;
            end

            persistent CommandWindowMessageLevel;
            if isempty(CommandWindowMessageLevel) || ~isempty(Settings.Controller)
                CommandWindowMessageLevel = Settings.CommandWindowMessageLevel;
            end

            persistent GUIMessageLevel;
            if isempty(GUIMessageLevel) || ~isempty(Settings.Controller)
                GUIMessageLevel = Settings.GUIMessageLevel;
            end

            persistent LogFileMessageLevel;
            if isempty(LogFileMessageLevel) || ~isempty(Settings.Controller)
                LogFileMessageLevel = Settings.LogFileMessageLevel;
            end

            persistent PrintStackTraceInCommandWindow;
            if isempty(PrintStackTraceInCommandWindow) || ~isempty(Settings.Controller)
                PrintStackTraceInCommandWindow = Settings.PrintStackTraceInCommandWindow;
            end

            %Logging to CommandWindow
            if Palladium.Logging.Logger.IsSeverityLevelAboveCutoff(level, CommandWindowMessageLevel)
                Palladium.Logging.Logger.LogToCommandWindow(level, string(message), PrintStackTraceInCommandWindow);
            end

            %Logging to GUI
            if Palladium.Logging.Logger.IsSeverityLevelAboveCutoff(level, GUIMessageLevel)
                Palladium.Logging.Logger.LogToGUI(level, string(message), Controller);
            end

            %Logging to File - note that this will use FullMessage, others
            %will not
            if Palladium.Logging.Logger.IsSeverityLevelAboveCutoff(level, LogFileMessageLevel)
                filePath = Palladium.Logging.Logger.ConstructFilePath(LogFileDirectory, LogFileFileName);
                Palladium.Logging.Logger.LogToFile(level, string(fullMessage), filePath);
            end

        end

    end

    methods(Access = private, Static)

        %% ConstructFilePath
        function path = ConstructFilePath(logFileDirectory, logFileFileName)
            fileName = Palladium.Logging.Logger.ReplaceDateTag(logFileFileName);

            %Make the config folder if it doesn't exist already
            if ~exist(logFileDirectory, 'dir')
                mkdir(logFileDirectory);
            end

            %Construct the full path
            path = fullfile(logFileDirectory, fileName);
        end


        %% GetLevelText
        function str = GetLevelText(level)
            %Get a string to put on the front of the message to indicate
            %its severity
            switch(level)
                case("Debug")
                    str = "[DEBUG]   ";
                case("Info")
                    str = "[INFO]    ";
                case("Warning")
                    str = "[WARNING] ";
                case("Error")
                    str = "[ERROR]   ";
                otherwise
                    error("Unsupported level in Logger: " + level);
            end
        end

        %% GetTimeStamp
        function str = GetTimeStamp()
            %Return the string that will be printed in front of logfile
            %entries to give the time
            d = datetime;
            format = 'HH:mm:ss';
            str = string(d, format);  %Today's date
        end

        %% IsSeverityLevelAboveCutoff
        function tf = IsSeverityLevelAboveCutoff(level, cutoff)
            switch(cutoff)
                case("Off")
                    tf = false;
                case("Debug")
                    switch(level)
                        case{"Debug", "Info", "Warning", "Error"}
                            tf = true;
                        otherwise
                            tf = false;
                    end
                case("Info")
                    switch(level)
                        case{"Info", "Warning", "Error"}
                            tf = true;
                        otherwise
                            tf = false;
                    end
                case("Warning")
                    switch(level)
                        case{"Warning", "Error"}
                            tf = true;
                        otherwise
                            tf = false;
                    end
                case("Error")
                    switch(level)
                        case{"Error"}
                            tf = true;
                        otherwise
                            tf = false;
                    end
                otherwise
                    error("Unsupported level in Logger: " + cutoff);
            end
        end

        %% LogToCommandWindow
        function LogToCommandWindow(level, message, printStackTraceInCommandWindow)
            %Write the message to the command window - make it scary orange
            %warning text for warnings and errors

            switch(level)
                case{"Debug", "Info"}
                    disp(message);
                case{"Warning", "Error"}
                    %Add a bit of text before the message to indicate its severity
                    %ie [INFO] : "Here is some info"
                    %Only both doing this for warnings and errors
                    fullMessage = Palladium.Logging.Logger.GetLevelText(level) + message;
                    if(printStackTraceInCommandWindow)
                        warning(fullmessage, "backtrace", "on", "verbose", "on");
                    else
                        fprintf(2, "\n" + strrep(fullMessage, '\', '\\') + "\n\n");    %fprintf with red text writes to command window in RED. Replace any '\' with '\\, assuming them to be file path separators
                    end
                otherwise
                    error("Unsupported level in Logger: " + level);
            end
        end

        %% LogToGUI
        function LogToGUI(level, message, controller)
            %Write the message to the main GUI
            switch(level)
                case("Debug")
                    colour = "Green";
                case("Info")
                    colour = "Green";
                case("Warning")
                    colour = "Yellow";
                case("Error")
                    colour = "Red";
                otherwise
                    error("Unsupported level in Logger: " + level);
            end

            %Pass through the message and a colour to symbolise its
            %severity to the Palladium controller, to display however it
            %seems best
            if ~isempty(controller)
                controller.ShowMessageInGUI(colour, message);
            end
        end

        %% LogToFile
        function LogToFile(level, message, path)
            %Write the message to the log file .txt on disk

            %Add a bit of text before the message to indicate its severity
            %ie [INFO] : "Here is some info"
            fullMessage = Palladium.Logging.Logger.GetLevelText(level) + "(" + Palladium.Logging.Logger.GetTimeStamp() + ") : " + string(message);

            for i = 1 : 3   %try 3 times to open the file
                try
                    %Write the message string to file
                    writelines(fullMessage, path, WriteMode = "append");

                    %Write an empty line below it to give some spacing and increase readability
                    writelines("", path, WriteMode = "append");
                    success = true;
                catch
                    success = false;
                end

                if success
                    break;
                else
                    pause(0.2);
                end
            end
        end

        %% ReplaceDateTag
        function outstr = ReplaceDateTag(str)
            %If a string has '<DATE>' in it, let's replace that with today's
            %date for convenience
            d = datetime;
            format = 'yyyy-MM-dd';
            dateStr = string(d, format);  %Today's date

            outstr = strrep(str, '<DATE>', dateStr);
        end
    end
end