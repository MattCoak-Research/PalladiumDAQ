classdef Logger < handle
    %Logger - Singleton static instance class for handling logging to
    %command line / file / GUI in Palladium
    %Create an instance of this from Controller initialisation

    %% Properties (Private)
    properties (Access = private)
        Controller;
    end

    %% Constructor
    methods
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
                "Controller", controller,...
                "LogFileDirectory", LogFileDirectory,...
                "LogFileFileName", LogFileFileName,...
                "CommandWindowMessageLevel", Settings.CommandWindowMessageLevel,...
                "GUIMessageLevel", Settings.GUIMessageLevel,...
                "LogFileMessageLevel", Settings.LogFileMessageLevel,...
                "PrintStackTraceInCommandWindow", Settings.PrintStackTraceInCommandWindow...
                );
        end
    end

    %% Methods (Static, Public)
    methods (Static, Access = public)
        
        function [Halt, suppressError] = HandleError(message, err, uiFigureHandle, Settings)
            %Show the error dialogue and return what the user chose.
            %By default (an error in the measurement loop or something that
            %could affect it) the options are Stop Measurements, Stop & Go to
            %Code, Suppress Error and Ignore. For a Standalone error - in a
            %window that does not interact with the measurement loop, e.g.
            %the Data Viewer - there is nothing to stop, so the options are
            %OK, Go to Code, Suppress Error and Ignore, and Halt is always
            %false.
            arguments
                message;
                err;
                uiFigureHandle;
                Settings.Standalone (1,1) logical = false;
            end

            Halt = false;
            suppressError = false;

            %Last error thrown; could be a MATLAB builtin.
            TopErrorFile = err.stack(1).file;
            TopErrorName = string(err.stack(1).name);
            TopErrorLine = err.stack(1).line;

            %Get last user error; this has an exist type of 0;
            for i = 1:length(err.stack)
                ExistsType(i,1) = exist(err.stack(i,1).name); %#ok<EXIST,AGROW>
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
            if(strcmp(UserErrorFile, TopErrorFile))
                ErrorString = string(sprintf("Error in " + TopErrorName + " - line " + num2str(TopErrorLine) + "\n\n")) + string(message);
            else
                ErrorString = string(sprintf("Error in Matlab function " + TopErrorName + " - line " + num2str(TopErrorLine) + ":\n\n")) + string(message) + string(sprintf("\n\nError in user function " + UserErrorName + " - line " + num2str(UserErrorLine) + "."));
            end

            %No logging here - the caller (Controller.HandleError) has
            %already logged the error, and doing it again here printed
            %every error twice and wrote it to the log file twice

            if Settings.Standalone
                suppressError = Palladium.Logging.Logger.ShowStandaloneErrorDialogue(ErrorString, err, uiFigureHandle, ...
                    [string(TopErrorFile), string(UserErrorFile)], [TopErrorLine, UserErrorLine], [string(TopErrorName), string(UserErrorName)]);
                return;
            end

            if isempty(uiFigureHandle)  %If we do not have a uiFigure GUI to create modal dialogue boses in..
                %Show a normal dialogue box asking the user what they want
                %to do
                msg = ErrorString;
                title = "Error";
                if isdeployed
                    ErrorQuestResult = questdlg(string(msg), title, ...
                        "Stop Measurements", "Ignore", "Ignore");
                else
                    ErrorQuestResult = questdlg(string(msg), title, ...
                        "Stop Measurements", "Stop & Go to Code", "Ignore", "Ignore");
                end
            else
                %Show a modal dialogue box asking the user what they want
                %to do
                fig = uiFigureHandle;
                msg = ErrorString;
                title = "Error";
                if isdeployed
                    ErrorQuestResult = uiconfirm(fig, Palladium.Utilities.GUIUtils.MessageToHTML(msg), title, ...
                        "Options", ["Stop Measurements", "Suppress Error", "Ignore"], ...
                        "Icon","warning", "Interpreter", "HTML",...
                        "DefaultOption", 1, "CancelOption", 3);
                else
                    ErrorQuestResult = uiconfirm(fig, Palladium.Utilities.GUIUtils.MessageToHTML(msg), title, ...
                        "Options", ["Stop Measurements", "Stop & Go to Code", "Suppress Error", "Ignore"], ...
                        "Icon","warning", "Interpreter", "HTML",...
                        "DefaultOption", 1, "CancelOption", 4);

                 end
            end

            %On error, either switch to the command window to view full
            %stack trace, open editor at mistake lines or just do nothing.
            if isdeployed
                switch(ErrorQuestResult)
                    case "Stop Measurements"
                        Halt = true;
                    case "Suppress Error"
                        suppressError = true;
                    case "Ignore"
                        %Do nothing
                    otherwise
                        error("HandleErrorError:UnsupportedErrorResponse", "Awful meta-error in the error handling");
                end
            else                
                switch(ErrorQuestResult)
                    case "Stop Measurements"
                        Halt = true;
                    case "Stop & Go to Code"
                        Halt = true;
                        fprintf(2, '%s\n', getReport(err, 'extended'));
                        Palladium.Logging.Logger.GoToCode(TopErrorFile, TopErrorLine, TopErrorName);
                        if ~strcmp(UserErrorFile, TopErrorFile) || UserErrorLine ~= TopErrorLine
                            Palladium.Logging.Logger.GoToCode(UserErrorFile, UserErrorLine, UserErrorName);
                        end
                    case "Suppress Error"
                        suppressError = true;
                    case "Ignore"
                        %Do nothing
                    otherwise
                        error("HandleErrorError:UnsupportedErrorResponse", "Awful meta-error in the error handling");
                end
            end
        end

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
                Settings.SkipGUI (1,1) logical = false;     %True to leave the message out of the GUI message area / status light, e.g. for an error in a window unrelated to the measurement loop
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
                Palladium.Logging.Logger.LogToCommandWindow(level, string(message), PrintStackTraceInCommandWindow, Palladium.Logging.Logger.HasGUIWindow(Controller));
            end

            %Logging to GUI
            if ~Settings.SkipGUI && Palladium.Logging.Logger.IsSeverityLevelAboveCutoff(level, GUIMessageLevel)
                Palladium.Logging.Logger.LogToGUI(level, string(message), Controller);
            end

            %Logging to File - note that this will use FullMessage, others
            %will not
            if Palladium.Logging.Logger.IsSeverityLevelAboveCutoff(level, LogFileMessageLevel)
                filePath = Palladium.Logging.Logger.ConstructFilePath(LogFileDirectory, LogFileFileName);
                Palladium.Logging.Logger.LogToFile(level, string(fullMessage), filePath);
            end

        end

        function LogError(err, message, Settings)
            %Log an error, with its full stack in the log file.
            %Pass SkipGUI = true to keep it out of the GUI status light and message area.
            arguments
                err;
                message = [];
                Settings.SkipGUI (1,1) logical = false;
            end
            try
                report = string(getReport(err, 'extended'));
                msg = string(err.message) + " : " + message;
                Palladium.Logging.Logger.Log("Error", msg, "FullMessage", report, "LogFileMessageLevel", "Error", "CommandWindowMessageLevel", "Error", "GUIMessageLevel", "Error", "SkipGUI", Settings.SkipGUI);
            catch err
                warning("LogErrorWarning:LoggingFailed", "Error thrown while attempting to log.. another error");
            end
        end

    end

    %% Methods (Static, Private)
    methods(Static, Access = private)

        function path = ConstructFilePath(logFileDirectory, logFileFileName)
            fileName = Palladium.Logging.Logger.ReplaceDateTag(logFileFileName);

            %Make the config folder if it doesn't exist already
            if ~exist(logFileDirectory, 'dir')
                mkdir(logFileDirectory);
            end

            %Construct the full path
            path = fullfile(logFileDirectory, fileName);
        end

        function suppressError = ShowStandaloneErrorDialogue(errorString, err, uiFigureHandle, files, lines, names)
            %Dialogue for an error in a window that does not interact with
            %the measurement loop: nothing to stop, so the options are OK,
            %Go to Code (not in a deployed app, which has no editor),
            %Suppress Error and Ignore. Returns true if the user chose to
            %suppress this error from now on.
            %files, lines and names hold the top stack frame, then the
            %first user-code frame, for Go to Code.
            suppressError = false;

            title = "Error";
            if isempty(uiFigureHandle)
                %questdlg only has room for three buttons, so there is no
                %Ignore here - it would do the same as OK anyway
                options = "OK";
                if ~isdeployed
                    options(end+1) = "Go to Code";
                end
                options(end+1) = "Suppress Error";
                result = string(questdlg(errorString, title, options(:)', "OK"));
            else
                options = "OK";
                if ~isdeployed
                    options(end+1) = "Go to Code";
                end
                options = [options, "Suppress Error", "Ignore"];
                result = string(uiconfirm(uiFigureHandle, Palladium.Utilities.GUIUtils.MessageToHTML(errorString), title, ...
                    "Options", options, "Icon", "warning", "Interpreter", "HTML", ...
                    "DefaultOption", 1, "CancelOption", numel(options)));
            end

            %OK, Ignore, or the dialogue being closed all just dismiss it
            if result == "Suppress Error"
                suppressError = true;
            elseif result == "Go to Code"
                fprintf(2, '%s\n', getReport(err, 'extended'));
                Palladium.Logging.Logger.GoToCode(files(1), lines(1), names(1));
                if files(2) ~= files(1) || lines(2) ~= lines(1)
                    Palladium.Logging.Logger.GoToCode(files(2), lines(2), names(2));
                end
            end
        end

        function GoToCode(file, line, functionName)
            %Open the editor at a line of code, for the Stop & Go to Code option of the error dialogue.
            %Ordinary code files open in the MATLAB editor at the line.
            %App Designer (.mlapp) files cannot be opened at a line by the
            %editor API, so they are opened in App Designer, and the
            %function and line number are printed to find the spot in Code
            %View - the line number matches the one shown there. Never
            %throws: failing to open the editor must not break error handling.
            try
                [~, ~, ext] = fileparts(file);
                if strcmpi(ext, ".mlapp")
                    %The editor functions are not available in a deployed app,
                    %and the compiler needs telling to leave them out
                    if ~isdeployed
                        %#exclude appdesigner
                        appdesigner(file);
                    end
                    fprintf(2, 'Error is in an App Designer file: %s\n    function %s, line %d (as numbered in Code View)\n', file, functionName, line);
                elseif ~isdeployed
                    %#exclude matlab.desktop.editor.openAndGoToLine
                    matlab.desktop.editor.openAndGoToLine(file, line);
                end
            catch e
                warning("GoToCodeWarning:OpenFailed", "%s", "Could not open " + string(file) + " at line " + string(line) + ": " + string(e.message));
            end
        end

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
                    error("GetLevelTextError:UnsupportedLevel", "%s", "Unsupported level in Logger: " + level);
            end
        end

        function str = GetTimeStamp()
            %Return the string that will be printed in front of logfile
            %entries to give the time
            d = datetime;
            format = 'HH:mm:ss';
            str = string(d, format);  %Today's date
        end

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
                    error("IsSeverityLevelAboveCutoffError:UnsupportedLevel", "%s", "Unsupported level in Logger: " + cutoff);
            end
        end

        function LogToCommandWindow(level, message, printStackTraceInCommandWindow, hasGUIWindow)
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
                        %Add where the message was logged from, leaving out
                        %the Logger's own functions
                        stack = dbstack("-completenames");
                        stack = stack(~endsWith({stack.file}, fullfile("+Logging", "Logger.m")));
                        for i = 1 : numel(stack)
                            fullMessage = fullMessage + newline + "    In " + stack(i).name + " (line " + stack(i).line + ")";
                        end
                    end

                    %Write to stderr, which shows in RED in the command
                    %window. But a compiled app without a console (the
                    %installed standalone application) shows anything
                    %written to stderr in a modal Windows "Error" box. That
                    %is only wanted for errors before Palladium's window
                    %exists - warnings are in the log file and status bar,
                    %and once the window is open it shows errors itself (status
                    %bar, and its own dialog boxes), so the Windows box would
                    %just pop up first. So write those to stdout there:
                    %discarded by that app, and still shown by the console
                    %debug build.
                    %Message is passed through %s so backslashes (eg file
                    %path separators) and % characters are printed literally
                    outputStream = 2;
                    if isdeployed && (level == "Warning" || hasGUIWindow)
                        outputStream = 1;
                    end
                    fprintf(outputStream, "\n%s\n\n", fullMessage);
                otherwise
                    error("LogToCommandWindowError:UnsupportedLevel", "%s", "Unsupported level in Logger: " + level);
            end
        end

        function tf = HasGUIWindow(controller)
            %True if Palladium's main window is open, to show messages in
            try
                tf = ~isempty(controller) && isvalid(controller) && controller.HasGUIWindow();
            catch
                tf = false;
            end
        end

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
                    error("LogToGUIError:UnsupportedLevel", "%s", "Unsupported level in Logger: " + level);
            end

            %Pass through the message and a colour to symbolise its
            %severity to the Palladium controller, to display however it
            %seems best. Skip a deleted Controller - the Logger keeps the
            %most recent one, which may have been closed already
            if ~isempty(controller) && isvalid(controller)
                controller.ShowMessageInGUI(colour, message);
            end
        end

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