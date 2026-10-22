classdef ComServerProcess < handle
    %ComServerProcess - Runs a Windows COM object in a separate (32-bit) PowerShell process, so its calls can run in the background.
    %MATLAB's own COM calls block until the function returns - and a vendor
    %library's slow functions (e.g. the PicoVNA's `Measure`, which can take
    %minutes) freeze the whole of Palladium meanwhile. Here the object
    %lives in a hidden PowerShell process instead, and MATLAB sends it
    %requests: `Call` waits for the reply, as a normal COM call would, while
    %`CallAsync` returns at once and the caller checks `IsBusy` each tick
    %and takes the reply with `GetAsyncReply` when it is done. (Windows
    %PowerShell runs in a single-threaded apartment, which libraries with
    %their own dialogues, such as VB6 ones, expect.) 32-bit
    %PowerShell is used by default, which also lets a 64-bit MATLAB use a
    %32-bit COM library.
    %
    %Requests and replies are JSON files in a temporary folder, written
    %under a temporary name and then renamed, so they are never read half
    %written. The process handles one request at a time: a new request
    %waits for the one before it (e.g. a sweep nobody wanted any more) to
    %finish. The process is stopped when the object is deleted. Windows only.
    %
    %Used by the PicoVNA 3 support of PicoVNA_NetworkAnalyser.

    %% Properties (Public, Private Set)
    properties(GetAccess = public, SetAccess = private)
        ProgId = "";                %The COM object's programmatic ID, e.g. "PicoControl3.PicoVNA_3"
    end

    %% Properties (Private)
    properties(Access = private)
        Process = [];               %The PowerShell process (System.Diagnostics.Process)
        Folder = "";                %Temporary folder the requests and replies pass through
        NextId = 1;                 %Id of the next request
        PendingId = [];             %Id of the background call in progress, or empty for none
        AsyncResult = [];           %Reply (or error) of the last background call once finished: a struct with fields id, reply and error
    end

    %% Constructor
    methods
        function this = ComServerProcess(progId, Settings)
            %Start the PowerShell process and create the COM object in it, waiting for it to be ready.
            %Errors with ComServerProcess:StartFailed if PowerShell can't
            %be started or the object can't be created (e.g. its library
            %isn't installed), giving the reason
            %
            %Inputs:
            %   progId             - programmatic ID of the COM object, e.g. "PicoControl3.PicoVNA_3"
            %   Use32Bit           - (name-value) true to run it in 32-bit PowerShell, if there is one. Default true
            %   CreateObjectScript - (name-value) PowerShell that makes the object, in place of
            %                        creating one from progId - for testing without a COM library.
            %                        Default ""
            %   StartupTimeout_s   - (name-value) how long to wait for the object to be ready. Default 30

            arguments
                progId (1,1) string;
                Settings.Use32Bit (1,1) logical = true;
                Settings.CreateObjectScript (1,1) string = "";
                Settings.StartupTimeout_s (1,1) double = 30;
            end

            assert(ispc, "ComServerProcess:WindowsOnly", "%s", "COM objects are only available on Windows.");

            this.ProgId = progId;
            this.Folder = string(tempname());
            mkdir(this.Folder);

            %Run as an encoded command, which (unlike a script file) the
            %PowerShell execution policy does not block
            script = Palladium.Utilities.ComServerProcess.BuildScript(this.Folder, progId, Settings.CreateObjectScript);
            encoded = matlab.net.base64encode(unicode2native(char(script), "UTF-16LE"));
            arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand " + string(encoded);

            try
                startInfo = System.Diagnostics.ProcessStartInfo(char(Palladium.Utilities.ComServerProcess.PowerShellPath(Settings.Use32Bit)), char(arguments));
                startInfo.CreateNoWindow = true;
                startInfo.UseShellExecute = false;
                this.Process = System.Diagnostics.Process.Start(startInfo);
            catch err
                this.Cleanup();
                error("ComServerProcess:StartFailed", "%s", "Could not start PowerShell for " + progId + ": " + err.message);
            end

            %It replies (as request 0) once the object exists, or with why not
            try
                reply = this.WaitForReply(0, Settings.StartupTimeout_s);
            catch err
                this.Cleanup();
                error("ComServerProcess:StartFailed", "%s", "Could not create the COM object " + progId + ": " + err.message);
            end
            if strlength(reply.error) > 0
                this.Cleanup();
                error("ComServerProcess:StartFailed", "%s", "Could not create the COM object " + progId + ": " + reply.error);
            end
        end

        function delete(this)
            %Stop the PowerShell process and delete its temporary folder.
            this.Cleanup();
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function reply = Call(this, functionName, varargin)
            %Call one of the COM object's methods and wait for its reply - as an ordinary COM call.
            %Waits first for any background call still running. Errors with
            %ComServerProcess:CallFailed if the method fails
            %
            %Inputs:
            %   functionName - name of the method, e.g. "SetFreqPlan"
            %   varargin     - its arguments: numbers and text (the object receives
            %                  them as numbers and strings)
            %
            %Outputs:
            %   reply - what the method returned (text as char, or a number, [] for none)

            id = this.SendRequest(functionName, varargin);
            result = this.WaitForReply(id, Inf);
            reply = Palladium.Utilities.ComServerProcess.ReplyOrError(result, functionName);
        end

        function CallAsync(this, functionName, varargin)
            %Start one of the COM object's methods in the background, returning at once - check IsBusy, then GetAsyncReply.
            %Waits first for any background call still running
            %
            %Inputs:
            %   functionName - name of the method, e.g. "Measure"
            %   varargin     - its arguments, as for Call

            this.PendingId = this.SendRequest(functionName, varargin);
            this.AsyncResult = [];
        end

        function reply = GetAsyncReply(this)
            %The reply of the background call, once IsBusy is false.
            %Errors with ComServerProcess:CallFailed if the method failed,
            %and with ComServerProcess:NoCall if there was no background call
            %
            %Outputs:
            %   reply - what the method returned

            assert(~isempty(this.AsyncResult), "ComServerProcess:NoCall", "%s", "There is no finished background call to take the reply of.");
            result = this.AsyncResult;
            this.AsyncResult = [];
            reply = Palladium.Utilities.ComServerProcess.ReplyOrError(result, "the background call");
        end

        function busy = IsBusy(this)
            %True while the background call is still running - checked without waiting.
            %False when there is none, or it has finished (take its reply
            %with GetAsyncReply). Errors if the process has died
            %
            %Outputs:
            %   busy - true if a background call is running

            busy = false;
            if isempty(this.PendingId)
                return;
            end

            result = this.ReadReply(this.PendingId);
            if isempty(result)
                this.AssertProcessRunning();
                busy = true;
                return;
            end
            this.AsyncResult = result;
            this.PendingId = [];
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function AssertProcessRunning(this)
            %Error if the PowerShell process has exited, saying how and what it was doing - a crash in the COM library ends the process, not MATLAB.
            %The exit code is a Windows status code (0xC0000005 is a
            %memory access violation, 0xC0000409 a security check failure),
            %and the last request is the call that was being made

            if ~this.Process.HasExited
                return;
            end

            code = int32(this.Process.ExitCode);
            description = "exit code " + code + " (0x" + string(dec2hex(typecast(code, "uint32"), 8)) + ")";
            traceFile = fullfile(this.Folder, "trace.txt");
            if isfile(traceFile)
                requests = strip(splitlines(string(fileread(traceFile))));
                requests = requests(strlength(requests) > 0);
                if ~isempty(requests)
                    description = description + ", while handling request " + requests(end);
                end
            end
            error("ComServerProcess:ProcessExited", "%s", "The PowerShell process running " + this.ProgId + " has exited unexpectedly: " + description + ".");
        end

        function Cleanup(this)
            %Ask the process to stop, kill it if it doesn't, and delete the folder.

            if ~isempty(this.Process)
                try
                    if ~this.Process.HasExited
                        this.WriteRequest(this.NextId, "__quit", {});
                        if ~this.Process.WaitForExit(int32(3000))
                            this.Process.Kill();
                        end
                    end
                    this.Process.Dispose();
                catch
                    %Nothing more can be done
                end
                this.Process = [];
            end
            if strlength(this.Folder) > 0 && isfolder(this.Folder)
                try
                    rmdir(this.Folder, "s");
                catch
                    %Left in the temp folder
                end
            end
        end

        function result = ReadReply(this, id)
            %The reply file, as a struct with fields id, reply and error - or [] if there isn't one (yet) for this request.

            result = [];
            file = fullfile(this.Folder, "resp.json");
            if ~isfile(file)
                return;
            end

            decoded = jsondecode(fileread(file, Encoding = "UTF-8"));
            if decoded.id ~= id
                return;
            end
            delete(file);

            result = struct("id", id, "reply", [], "error", "");
            if isfield(decoded, "reply");   result.reply = decoded.reply;   end
            if isfield(decoded, "error");   result.error = string(decoded.error);   end
        end

        function id = SendRequest(this, functionName, args)
            %Write a request for the process, after the one before it has finished.

            %A background call nobody collected (e.g. an aborted sweep) is
            %waited for here, as the process only does one thing at a time
            if ~isempty(this.PendingId)
                this.AsyncResult = this.WaitForReply(this.PendingId, Inf);
                this.PendingId = [];
            end
            this.AssertProcessRunning();

            id = this.NextId;
            this.NextId = id + 1;
            this.WriteRequest(id, functionName, args);
        end

        function result = WaitForReply(this, id, timeout_s)
            %Wait for the reply to a request, polling every 10 ms. Errors if the process exits or the time runs out.

            timer = tic();
            result = this.ReadReply(id);
            while isempty(result)
                this.AssertProcessRunning();
                assert(toc(timer) < timeout_s, "ComServerProcess:Timeout", "%s", "No reply from " + this.ProgId + " within " + timeout_s + " s.");
                pause(0.01);
                result = this.ReadReply(id);
            end
        end

        function WriteRequest(this, id, functionName, args)
            %Write the request file - under another name first, so the process never reads it half written.

            request = struct("id", id, "fn", functionName, "args", {args});
            temporary = fullfile(this.Folder, "req.tmp");
            writelines(string(jsonencode(request)), temporary, Encoding = "UTF-8");
            movefile(temporary, fullfile(this.Folder, "req.json"), "f");
        end

    end

    %% Methods (Static, Private)
    methods(Static, Access = private)

        function script = BuildScript(folder, progId, createObjectScript)
            %The PowerShell the process runs: create the object, then answer requests until told to quit.

            quote = @(text) "'" + replace(string(text), "'", "''") + "'";
            if strlength(createObjectScript) == 0
                createObjectScript = "New-Object -ComObject $progId";
            end

            lines = [
                "$ErrorActionPreference = 'Stop'"
                "$dir = " + quote(folder)
                "$progId = " + quote(progId)
                "$utf8 = New-Object System.Text.UTF8Encoding $false"
                "function Send($obj) {"
                "    $tmp = Join-Path $dir 'resp.tmp'"
                "    [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Compress -Depth 4), $utf8)"
                "    Move-Item -LiteralPath $tmp -Destination (Join-Path $dir 'resp.json') -Force"
                "}"
                "try {"
                "    $com = & { " + createObjectScript + " }"
                "    Send @{ id = 0; reply = 'ready' }"
                "} catch {"
                "    Send @{ id = 0; error = $_.Exception.Message }"
                "    exit 1"
                "}"
                "$reqFile = Join-Path $dir 'req.json'"
                "while ($true) {"
                "    if (-not (Test-Path -LiteralPath $reqFile)) { Start-Sleep -Milliseconds 10; continue }"
                "    $req = [IO.File]::ReadAllText($reqFile, $utf8) | ConvertFrom-Json"
                "    Remove-Item -LiteralPath $reqFile -Force"
                "    if ($req.fn -eq '__quit') { break }"
                "    [IO.File]::AppendAllText((Join-Path $dir 'trace.txt'), ([string]$req.id + ' ' + $req.fn + [Environment]::NewLine))"
                "    try {"
                "        if ($null -eq $req.args) { $callArgs = [object[]]@() } else { $callArgs = [object[]]@($req.args) }"
                "        if ($com -is [System.__ComObject]) {"
                "            $result = [System.__ComObject].InvokeMember($req.fn, [Reflection.BindingFlags]::InvokeMethod, $null, $com, $callArgs)"
                "        } else {"
                "            $result = $com.PSObject.Methods[$req.fn].Invoke($callArgs)"
                "        }"
                "        if ($null -eq $result) { $result = $null }"
                "        Send @{ id = $req.id; reply = $result }"
                "    } catch {"
                "        Send @{ id = $req.id; error = $_.Exception.Message }"
                "    }"
                "}"
                ];
            script = strjoin(lines, newline);
        end

        function path = PowerShellPath(use32Bit)
            %The PowerShell to run: the 32-bit one if asked for and there is one (a 32-bit COM library needs it), else the 64-bit one.

            windowsDir = string(getenv("SystemRoot"));
            path32 = fullfile(windowsDir, "SysWOW64", "WindowsPowerShell", "v1.0", "powershell.exe");
            path64 = fullfile(windowsDir, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            if use32Bit && isfile(path32)
                path = path32;
            else
                path = path64;
            end
        end

        function reply = ReplyOrError(result, description)
            %The reply of a finished request, or the error it ended in.

            if strlength(result.error) > 0
                error("ComServerProcess:CallFailed", "%s", description + " failed: " + result.error);
            end
            reply = result.reply;
        end

    end
end
