classdef Logger < handle
    %Logger - Sends Palladium DAQ's messages to the Command Window, the GUI's status bar and a log file.
    %Use it through its static methods: `Logger.Log(level, message)` from
    %anywhere, with level "Debug", "Info", "Warning" or "Error". Each
    %place has its own level, from the config's LogSettings (see
    %[Presets and config](../presets-and-config.md)), and shows a message
    %only if it is at least that serious; "Off" shows nothing.
    %
    %The Controller creates the one Logger at start-up, which sets those
    %levels and the log file. MATLAB has no static properties, so the
    %settings are kept as persistent variables in `Log`, and the object
    %itself is not needed afterwards. Before that - e.g. an instrument used
    %on its own from the Command Window - messages go to the Command Window
    %only.
    %
    %`LogError` logs an error with its full stack in the log file, and
    %`HandleError` shows the dialogue that asks the user what to do about
    %an error (see `Controller.HandleError`).

    %% Properties (Private)
    properties (Access = private)
        Controller;     %The Palladium.Core.Controller, which shows messages in the GUI
    end

    %% Constructor
    methods
        function this = Logger(controller, LogFileDirectory, LogFileFileName, Settings)
            %Set up logging for a Palladium DAQ session - called by Controller.Initialise.
            %Replaces any earlier settings. Levels are "Off", "Debug",
            %"Info", "Warning" or "Error"
            %
            %Inputs:
            %   controller       - the Palladium.Core.Controller, for messages in the GUI
            %   LogFileDirectory - folder for log files
            %   LogFileFileName  - log file name; <DATE> is replaced with today's date
            %   CommandWindowMessageLevel, GUIMessageLevel, LogFileMessageLevel
            %                    - (name-value) the least serious message each place shows
            %   PrintStackTraceInCommandWindow - (name-value) true to show where warnings and errors were logged from

            arguments
                controller                                          (1,1) Palladium.Core.Controller;
                LogFileDirectory                                    {mustBeTextScalar};
                LogFileFileName                                     {mustBeTextScalar};
                Settings.CommandWindowMessageLevel                  {mustBeTextScalar, mustBeMember(Settings.CommandWindowMessageLevel, ["Off", "Debug", "Info", "Warning", "Error"])}  = "Debug";      %Messages at or above this severity level will be passed on to Command Window
                Settings.GUIMessageLevel                            {mustBeTextScalar, mustBeMember(Settings.GUIMessageLevel, ["Off", "Debug", "Info", "Warning", "Error"])}            = "Warning";    %Messages at or above this severity level will be passed on to GUI
                Settings.LogFileMessageLevel                        {mustBeTextScalar, mustBeMember(Settings.LogFileMessageLevel, ["Off", "Debug", "Info", "Warning", "Error"])}        = "Debug";      %Messages at or above this severity level will be written to the log file
                Settings.PrintStackTraceInCommandWindow             (1,1) logical = false;  %True to show where warnings and errors were logged from
            end

            this.Controller = controller;

            %This slightly clumsy pass-through boilerplate allows choosing
            %Logger settings on constructing it, then those options are
            %kept by Log for every later call
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
            %false. Go to Code options are left out of a compiled app, which
            %has no editor. Doesn't log the error - the caller does
            %
            %Inputs:
            %   message        - what was happening, e.g. "Error in main measurement loop"
            %   err            - the MException
            %   uiFigureHandle - window to show the dialogue in, or [] for a separate dialogue
            %   Standalone     - (name-value) true for an error in a window that doesn't affect measuring. Default false
            %
            %Outputs:
            %   Halt          - true if the user chose to stop measurements
            %   suppressError - true if the user chose not to be shown this error again

            arguments
                message;
                err;
                uiFigureHandle;
                Settings.Standalone (1,1) logical = false;
            end

            Halt = false;
            suppressError = false;

            %An error that was created but never thrown has no stack - say
            %so, rather than fail on err.stack(1) (it used to crash with
            %"Index exceeds array bounds")
            stack = err.stack;
            if isempty(stack)
                stack = struct("file", "", "name", "(not known - the error was never thrown)", "line", 0);
            end

            %Last error thrown; could be a MATLAB builtin.
            TopErrorFile = stack(1).file;
            TopErrorName = string(stack(1).name);
            TopErrorLine = stack(1).line;

            %Get last user error; this has an exist type of 0;
            ExistsType = zeros(numel(stack), 1);
            for i = 1:numel(stack)
                ExistsType(i) = exist(stack(i).name); %#ok<EXIST>
            end

            %Get the details of the first function erroring which isn't a
            %builtin - or the top one, if they all are
            IndexOfFirstUserFuncError = find(ExistsType == 0, 1);
            if isempty(IndexOfFirstUserFuncError)
                IndexOfFirstUserFuncError = 1;
            end
            UserErrorFile = stack(IndexOfFirstUserFuncError).file;
            UserErrorName = stack(IndexOfFirstUserFuncError).name;
            UserErrorLine = stack(IndexOfFirstUserFuncError).line;

            %If the first function is a user function, error string can be
            %simpler. Otherwise, show both the builtin's error and the
            %user's error. (Built by joining, not sprintf, so a % or \ in a
            %name is shown as it is)
            message = string(message) + ": " + string(err.message);
            if(strcmp(UserErrorFile, TopErrorFile))
                ErrorString = "Error in " + TopErrorName + " - line " + TopErrorLine + newline + newline + message;
            else
                ErrorString = "Error in Matlab function " + TopErrorName + " - line " + TopErrorLine + ":" + newline + newline + message + newline + newline + "Error in user function " + UserErrorName + " - line " + UserErrorLine + ".";
            end

            %No logging here - the caller (Controller.HandleError) has
            %already logged the error, and doing it again here printed
            %every error twice and wrote it to the log file twice

            if Settings.Standalone
                suppressError = Palladium.Logging.Logger.ShowStandaloneErrorDialogue(ErrorString, err, uiFigureHandle, ...
                    [string(TopErrorFile), string(UserErrorFile)], [TopErrorLine, UserErrorLine], [string(TopErrorName), string(UserErrorName)]);
                return;
            end

            testResponse = Palladium.Logging.Logger.TestDialogResponse("use");
            if testResponse ~= ""
                %A test is answering the dialogue (it is modal, so would
                %block the test) - see TestDialogResponse
                ErrorQuestResult = testResponse;
            elseif isempty(uiFigureHandle)  %If we do not have a uiFigure GUI to create modal dialogue boses in..
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
            %Show a message in the Command Window, GUI and log file, as far as each place's level allows.
            %Warnings and errors are shown in red in the Command Window, and
            %log file lines are timestamped. The Controller, log file and
            %level name-value arguments are only used when the Logger is
            %created (and by tests): the settings are then kept for every
            %later call
            %
            %Inputs:
            %   level       - "Debug", "Info", "Warning" or "Error"
            %   message     - the message
            %   FullMessage - (name-value) a longer version for the log file only, e.g. with a stack trace
            %   SkipGUI     - (name-value) true to leave it out of the GUI, e.g. for an error in a window
            %                 that doesn't affect measuring

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

            %MATLAB has no static properties, so the settings are kept by
            %Store. Passing a Controller (the constructor does) sets them;
            %any other call uses them as they are - or the defaults, if the
            %Logger hasn't been created. (Every call's arguments used to be
            %kept by the very first call, so a LogError before Palladium
            %started hid all later messages below Error)
            if ~isempty(Settings.Controller)
                state = Palladium.Logging.Logger.Store("get");
                state.Controller = Settings.Controller;
                state.LogFileDirectory = Settings.LogFileDirectory;
                state.LogFileFileName = Settings.LogFileFileName;
                state.CommandWindowMessageLevel = Settings.CommandWindowMessageLevel;
                state.GUIMessageLevel = Settings.GUIMessageLevel;
                state.LogFileMessageLevel = Settings.LogFileMessageLevel;
                state.PrintStackTraceInCommandWindow = Settings.PrintStackTraceInCommandWindow;
                state.LogFileFailureReported = false;
                Palladium.Logging.Logger.Store("set", state);
            else
                state = Palladium.Logging.Logger.Store("get");
            end

            %Logging to CommandWindow
            if Palladium.Logging.Logger.IsSeverityLevelAboveCutoff(level, state.CommandWindowMessageLevel)
                Palladium.Logging.Logger.LogToCommandWindow(level, string(message), state.PrintStackTraceInCommandWindow, Palladium.Logging.Logger.HasGUIWindow(state.Controller));
            end

            %Logging to GUI
            if ~Settings.SkipGUI && Palladium.Logging.Logger.IsSeverityLevelAboveCutoff(level, state.GUIMessageLevel)
                Palladium.Logging.Logger.LogToGUI(level, string(message), state.Controller);
            end

            %Logging to File - note that this will use FullMessage, others
            %will not. There is no log file until Palladium has set one up -
            %e.g. for an instrument used from the Command Window on its own
            hasLogFile = ~isempty(state.LogFileDirectory) && strlength(string(state.LogFileDirectory)) > 0;
            if hasLogFile && Palladium.Logging.Logger.IsSeverityLevelAboveCutoff(level, state.LogFileMessageLevel)
                %Never throw from here: logging is used while handling errors,
                %and a log folder that can't be made (e.g. a drive gone
                %mid-run) used to make every Log call throw
                failure = "";
                try
                    filePath = Palladium.Logging.Logger.ConstructFilePath(state.LogFileDirectory, state.LogFileFileName);
                    if ~Palladium.Logging.Logger.LogToFile(level, string(fullMessage), filePath)
                        failure = "could not write to " + filePath;
                    end
                catch e
                    failure = string(e.message);
                end
                if failure ~= ""
                    Palladium.Logging.Logger.ReportLogFileFailure(failure, state);
                end
            end

        end

        function LogError(err, message, Settings)
            %Log an error, with its full stack in the log file.
            %
            %Inputs:
            %   err     - the MException
            %   message - (optional) what was happening, added after the error's own message
            %   SkipGUI - (name-value) true to keep it out of the GUI status light and message area

            arguments
                err;
                message = "";
                Settings.SkipGUI (1,1) logical = false;
            end
            try
                report = string(getReport(err, 'extended'));

                %The message is optional - with none given, nothing used to
                %be logged at all ("text" + [] is an empty string array)
                msg = string(err.message);
                if strlength(string(message)) > 0
                    msg = msg + " : " + string(message);
                end
                %The log file gets the message as well as the full report -
                %it used to get only the report, without what was happening
                Palladium.Logging.Logger.Log("Error", msg, "FullMessage", msg + newline + report, "SkipGUI", Settings.SkipGUI);
            catch err
                warning("LogErrorWarning:LoggingFailed", "%s", "Error thrown while attempting to log another error: " + string(err.message));
            end
        end

    end

    %% Methods (Static, Public, Hidden) - for tests
    methods (Static, Access = public, Hidden)

        function ResetForTest()
            %Forget the settings, as if the Logger had never been created - for tests.
            %(clear doesn't reset them)

            Palladium.Logging.Logger.Store("reset");
        end

        function out = TestDialogResponse(action, response)
            %Answer the error dialogue in place of a person, for tests - it is modal, so would block them.
            %   TestDialogResponse("set", "Stop Measurements") - answer every
            %       error dialogue with this choice from now on
            %   TestDialogResponse("set", "") - show the dialogues again (do
            %       this in the test's teardown)
            %   TestDialogResponse("count") - how many dialogues have been
            %       answered since the last "set"
            %HandleError calls TestDialogResponse("use"), which returns the
            %choice to use ("" for none) and counts it

            arguments
                action {mustBeMember(action, ["set", "use", "count"])}
                response (1,1) string = ""
            end

            persistent storedResponse timesUsed
            if isempty(storedResponse)
                storedResponse = "";
                timesUsed = 0;
            end

            switch action
                case "set";     storedResponse = response;  timesUsed = 0;  out = storedResponse;
                case "count";   out = timesUsed;
                case "use"
                    out = storedResponse;
                    if out ~= ""
                        timesUsed = timesUsed + 1;
                    end
            end
        end

    end

    %% Methods (Static, Private)
    methods(Static, Access = private)

        function state = Store(action, newState)
            %Keep the Logger's settings between calls, as MATLAB has no static properties.
            %"get" returns them - the defaults until the Logger is created;
            %"set" replaces them; "reset" goes back to the defaults

            arguments
                action {mustBeMember(action, ["get", "set", "reset"])}
                newState = []
            end

            persistent stored
            if isempty(stored) || action == "reset"
                %Before Palladium sets the Logger up: Command Window only
                stored = struct("Controller", [], "LogFileDirectory", "", "LogFileFileName", "", ...
                    "CommandWindowMessageLevel", "Debug", "GUIMessageLevel", "Warning", "LogFileMessageLevel", "Debug", ...
                    "PrintStackTraceInCommandWindow", false, "LogFileFailureReported", false);
            end
            if action == "set"
                stored = newState;
            end
            state = stored;
        end

        function ReportLogFileFailure(reason, state)
            %Say - once, until the Logger is set up again - that messages can't be written to the log file.
            %Shown in the Command Window and the GUI directly, not through
            %Log, which would try the file again

            if state.LogFileFailureReported
                return;
            end
            state.LogFileFailureReported = true;
            Palladium.Logging.Logger.Store("set", state);

            msg = "Messages can't be written to the log file (" + reason + "). They are still shown here; check the log folder in the config (LogSettings.LogFileDirectory).";
            try
                Palladium.Logging.Logger.LogToCommandWindow("Warning", msg, false, Palladium.Logging.Logger.HasGUIWindow(state.Controller));
                if Palladium.Logging.Logger.IsSeverityLevelAboveCutoff("Warning", state.GUIMessageLevel)
                    Palladium.Logging.Logger.LogToGUI("Warning", msg, state.Controller);
                end
            catch
                %Nowhere left to report it
            end
        end

        function path = ConstructFilePath(logFileDirectory, logFileFileName)
            %The log file's path, with <DATE> in its name replaced by today's date, creating the folder if needed.

            fileName = Palladium.Utilities.PathUtils.ReplaceDateTag(logFileFileName);

            %Make the log folder if it doesn't exist already
            if ~exist(logFileDirectory, 'dir')
                mkdir(logFileDirectory);
            end

            %Construct the full path
            path = fullfile(logFileDirectory, fileName);
        end

        function suppressError = ShowStandaloneErrorDialogue(errorString, err, uiFigureHandle, files, lines, names)
            %Show the error dialogue for an error in a window that doesn't affect measuring, and return whether to suppress it.
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
            if strlength(string(file)) == 0
                return;     %No file to go to - the error was never thrown
            end
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
            %The tag put in front of a message to show its severity, e.g. "[WARNING] ".

            switch(level)
                case("Debug");     str = "[DEBUG]   ";
                case("Info");      str = "[INFO]    ";
                case("Warning");   str = "[WARNING] ";
                case("Error");     str = "[ERROR]   ";
                otherwise
                    error("GetLevelTextError:UnsupportedLevel", "%s", "Unsupported level in Logger: " + level);
            end
        end

        function str = GetTimeStamp()
            %The time put in front of log file entries, as HH:mm:ss.

            d = datetime;
            format = 'HH:mm:ss';
            str = string(d, format);  %The time now
        end

        function tf = IsSeverityLevelAboveCutoff(level, cutoff)
            %Whether a message of this level is serious enough to show where the cutoff level is set; never for "Off".
            %Errors for an unknown cutoff

            levels = ["Debug", "Info", "Warning", "Error"];     %Least to most serious
            if cutoff == "Off"
                tf = false;
            elseif any(levels == cutoff)
                tf = find(levels == level, 1) >= find(levels == cutoff, 1);
            else
                error("IsSeverityLevelAboveCutoffError:UnsupportedLevel", "%s", "Unsupported level in Logger: " + cutoff);
            end
        end

        function LogToCommandWindow(level, message, printStackTraceInCommandWindow, hasGUIWindow)
            %Show the message in the Command Window - warnings and errors in red, with a severity tag.

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
            %Whether Palladium's main window is open, to show messages in.

            try
                tf = ~isempty(controller) && isvalid(controller) && controller.HasGUIWindow();
            catch
                tf = false;
            end
        end

        function LogToGUI(level, message, controller)
            %Show the message in the main GUI's status bar, coloured by severity.

            switch(level)
                case("Debug");     colour = "Green";
                case("Info");      colour = "Green";
                case("Warning");   colour = "Yellow";
                case("Error");     colour = "Red";
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

        function success = LogToFile(level, message, path)
            %Add the message to the log file, tagged with its severity and the time, trying up to 3 times.
            %Returns false if every attempt failed

            %Add a bit of text before the message to indicate its severity
            %ie [INFO] : "Here is some info"
            fullMessage = Palladium.Logging.Logger.GetLevelText(level) + "(" + Palladium.Logging.Logger.GetTimeStamp() + ") : " + string(message);

            success = false;
            for i = 1 : 3   %try 3 times to open the file
                try
                    %The message and an empty line below it (for
                    %readability) in one write - written separately, a
                    %failure of the second wrote the message again on retry
                    writelines([fullMessage; ""], path, WriteMode = "append");
                    success = true;
                    break;
                catch
                    pause(0.2);
                end
            end
        end

    end
end