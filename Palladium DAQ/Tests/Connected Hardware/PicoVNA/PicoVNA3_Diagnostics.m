function reportFile = PicoVNA3_Diagnostics(Settings)
    %PicoVNA3_Diagnostics - Step-by-step check of the PicoVNA 3 route of the PicoVNA driver on a PC with the PicoVNA 3 (or 2) software installed - and writes what the library says to a text file.
    %NOT run by the build or CI: it needs the PicoVNA software installed (the
    %analyser itself only for steps 4 and 5). Run it from MATLAB with
    %Palladium DAQ on the path:
    %
    %   PicoVNA3_Diagnostics                          - steps 1 to 3, no analyser needed
    %   PicoVNA3_Diagnostics(Sweep = true)            - plus steps 4 and 5, with the analyser plugged in
    %   PicoVNA3_Diagnostics(Sweep = true, CalibrationFile = "C:\cals\my.pcal")
    %   PicoVNA3_Diagnostics(Sweep = true, Calibrate = true)   - calibrate first, in the library's own dialogue
    %
    %Close the PicoVNA 3 application first: the library takes the analyser
    %over, and two programs can't share it. Nothing is sent that changes the
    %analyser's setup beyond a frequency plan (1 MHz to 100 MHz, 51 points)
    %in step 4, and no calibration dialogue is opened.
    %
    %Steps
    %-----
    % 1. The helper process works: Palladium starts a 32-bit PowerShell
    %    process and talks to a stand-in object through it (no PicoVNA software
    %    involved). Fails if PowerShell can't be started on this PC.
    % 2. The PicoVNA library is registered on this PC (PicoControl3, and
    %    PicoControl2 from PicoVNA 2).
    % 3. The library can be started through the helper process, and what it
    %    says to DLLVer, FND (finds the analyser; 0 if there is none) and
    %    GetInfo is recorded. Stops here if no analyser is found.
    % 4. (Sweep = true) A sweep through the library's own calls: SetFreqPlan,
    %    then Measure, GetData - the timings, the text of every reply, and
    %    the first values of the data. With no calibration loaded Measure
    %    probably says "Error" - which is recorded too (give CalibrationFile
    %    to load one made with SaveCalibration).
    % 5. (Sweep = true) A scan through the driver itself, as the VNA Control
    %    runs it: whether RunScan returns at once while the sweep goes on in
    %    the background, and what data comes out.
    %
    %Send the text file it writes (its name is printed at the end) back for
    %checking - it holds the library's raw replies, which is what is needed
    %to confirm the driver reads them correctly.
    %
    %Inputs:
    %   Sweep           - (name-value) true to run steps 4 and 5 too (needs the analyser). Default false
    %   CalibrationFile - (name-value) full path of a calibration file saved with the driver's SaveCalibration, to load before sweeping. Default none
    %   AppCalibrationFile - (name-value) full path of a calibration saved by the PicoVNA application (a .cal file), to see whether the
    %                     library can use it: the guide says files saved through the library and by the application are not compatible,
    %                     so this checks (LoadCal, then SelectCal with the file name) and records what the library replies, and
    %                     whether it can then measure. Default none
    %   Calibrate       - (name-value) true to open the library's calibration dialogue (SelectCal) at the start of step 4, so a real
    %                     calibration is there to measure with. You do the calibration in the dialogue - it needs the analyser
    %                     and your calibration standards - and it is saved to a file in Folder, which step 5 then loads. If no
    %                     dialogue appears, press Ctrl+C and say so. Default false
    %   Folder          - (name-value) folder to write the text file in. Default the current folder
    %
    %Outputs:
    %   reportFile - full path of the text file written

    arguments
        Settings.Sweep (1,1) logical = false;
        Settings.CalibrationFile (1,1) string = "";
        Settings.Folder (1,1) string = string(pwd);
        Settings.ProgIds (1,:) string = ["PicoControl3.PicoVNA_3", "PicoControl2.PicoVNA_2"];     %For testing this script: the COM classes to look for
        Settings.StandInScript (1,1) string = "";           %For testing this script: PowerShell making a stand-in object to use in place of the library
        Settings.SkipDriverScan (1,1) logical = false;      %For testing this script: skip step 5, which needs the real library
        Settings.Calibrate (1,1) logical = false;
        Settings.AppCalibrationFile (1,1) string = "";
    end

    reportFile = fullfile(Settings.Folder, "PicoVNA3_diagnostics_" + string(datetime("now", Format = "yyyyMMdd_HHmmss")) + ".txt");
    report = strings(0, 1);
    server = [];
    function say(text)
        %Print a line, and keep it for the file.
        text = string(text);
        fprintf("%s\n", text);
        report(end + 1, 1) = text; %#ok<AGROW>
        writelines(report, reportFile);
    end
    function stopServer()
        %Stop the library's process, if there is one.
        if ~isempty(server) && isvalid(server)
            delete(server);
        end
        server = [];
    end

    say("PicoVNA 3 diagnostics, " + string(datetime("now")));
    say("MATLAB " + version + " on " + computer("arch") + ", Windows " + string(ispc));
    say("");

    %% Step 1 - the helper process
    say("STEP 1: helper process (32-bit PowerShell) with a stand-in object");
    try
        stand_in = "$o = New-Object PSObject; $o | Add-Member ScriptMethod Echo { param($x) $x }; $o";
        timer = tic();
        server = Palladium.Utilities.ComServerProcess("StandIn", CreateObjectScript = stand_in);
        say("  started in " + sprintf("%.1f", toc(timer)) + " s");
        reply = server.Call("Echo", "hello");
        say("  Echo(""hello"") -> """ + string(reply) + """  " + ternary(string(reply) == "hello", "OK", "UNEXPECTED"));
        delete(server);
    catch err
        say("  FAILED: " + err.message);
        say("The helper process doesn't work on this PC, so nothing further can be checked.");
        return;
    end
    say("");

    %% Step 2 - registration
    say("STEP 2: is the PicoVNA library registered?");
    found = strings(1, 0);
    locations = ["HKEY_CLASSES_ROOT", ""; "HKEY_LOCAL_MACHINE", "SOFTWARE\Classes\"; "HKEY_LOCAL_MACHINE", "SOFTWARE\Classes\WOW6432Node\"; ...
        "HKEY_CURRENT_USER", "SOFTWARE\Classes\"];
    for progId = Settings.ProgIds
        for k = 1:height(locations)
            registered = false;
            try
                winqueryreg("name", char(locations(k, 1)), char(locations(k, 2) + progId + "\CLSID"));
                registered = true;
            catch
            end
            say("  " + progId + "  " + locations(k, 1) + "\" + locations(k, 2) + ": " + ternary(registered, "registered", "not registered"));
            if registered && ~any(found == progId)
                found(end + 1) = progId; %#ok<AGROW>
            end
        end
    end
    if strlength(Settings.StandInScript) > 0
        found = "StandIn";
        say("  (using a stand-in object, as asked)");
    end
    if isempty(found)
        say("Neither library is registered: the PicoVNA 3 (or 2) software isn't installed on this PC, or didn't register its library.");
        return;
    end
    say("");

    %% Step 3 - the library
    say("STEP 3: start the library, find the analyser");
    say("  - what else might be holding the analyser:");
    try
        names = string(arrayfun(@(p) string(p.ProcessName), System.Diagnostics.Process.GetProcesses()));
    catch
        names = strings(0, 1);
    end
    names = sort(unique(names(contains(names, ["pico", "vna", "ftdi"], IgnoreCase = true))));
    say("    programs running with pico/vna in their name: " + ternary(isempty(names), "none", strjoin(names, ", ")));
    try
        say("    COM ports: " + strjoin(serialportlist("all"), ", "));
    catch
        say("    COM ports: could not be listed");
    end
    [~, devices] = system('powershell -NoProfile -Command "Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match ''Pico|VNA|FTDI|USB Serial'' } | ForEach-Object { $_.Status + ''  '' + $_.FriendlyName } | Out-String -Width 200"');
    say("    USB/serial devices matching Pico, VNA, FTDI or USB Serial:");
    say("      " + strjoin(strip(splitlines(string(devices))), newline + "      "));
    try
    %Every registered library is tried: PicoVNA 2's PicoControl2 is the one for the
    %PicoVNA 106 in Pico's programmer's guide, PicoVNA 3's PicoControl3 for the 108
    serial = 0;
    foundId = "";
    for progId = found
        say("  ----- library " + progId);
        if ~startServer(progId)
            continue;
        end
        serial = examineLibrary();
        if serial > 0
            foundId = progId;
            break;      %This library finds the analyser: use it for the sweep
        end
        stopServer();
    end
    if serial <= 0
        say("  -> NO library found the analyser (FND returned 0 for each).");
        if ~Settings.Sweep
            say("  Run PicoVNA3_Diagnostics(Sweep = true) to try a sweep anyway - it shows whether a library can use the analyser regardless.");
            say("");
            say("Wrote " + reportFile);
            return;
        end
        say("  (carrying on to the sweep anyway with " + found(1) + ", to see whether the library can use the analyser regardless)");
        say("  ----- library " + found(1));
        if ~startServer(found(1))
            say("Wrote " + reportFile);
            return;
        end
    else
        say("  -> " + foundId + " found the analyser (serial number " + serial + ") - it is the library used below.");
    end
    say("");

    if ~Settings.Sweep
        stopServer();
        say("Steps 4 and 5 (a sweep) were not requested. Run PicoVNA3_Diagnostics(Sweep = true) with the analyser to do them.");
        say("");
        say("Wrote " + reportFile);
        return;
    end

    %% Step 4 - a sweep through the library
    say("STEP 4: a sweep through the library's own calls");
    calibrationFile = Settings.CalibrationFile;
    if Settings.Calibrate
        say("  Opening the library's calibration dialogue (SelectCal). It should appear on screen: calibrate in it, then finish. This waits for you.");
        timer = tic();
        probe("SelectCal", "?");
        say("  (the dialogue took " + sprintf("%.0f", toc(timer)) + " s)");
        calibrationFile = fullfile(Settings.Folder, "PicoVNA_diagnostic_calibration.pcal");
        probe("SaveCal", char(calibrationFile));
        say("  calibration saved as " + calibrationFile);
        probe("GetInfo", "CalType");
        probe("GetInfo", "FreqPlan");
    elseif strlength(Settings.AppCalibrationFile) > 0
        say("  Trying a calibration saved by the PicoVNA application, " + Settings.AppCalibrationFile + ":");
        probe("LoadCal", char(Settings.AppCalibrationFile));
        probe("GetInfo", "CalType");
        probe("SelectCal", char(Settings.AppCalibrationFile));
        probe("GetInfo", "CalType");
        probe("GetInfo", "FreqPlan");
    else
        if strlength(calibrationFile) > 0
            probe("LoadCal", char(calibrationFile));
            probe("GetInfo", "CalType");
        end
        probe("SetFreqPlan", 1, 1.98, 51, 0, 1000);
        probe("GetInfo", "FreqPlan");
    end
    for sParameter = ["S11", "S21"]
        timer = tic();
        measureReply = probe("Measure", sParameter);
        say("  Measure took " + sprintf("%.2f", toc(timer)) + " s");
        if strip(string(measureReply)) == "OK"
            raw = probe("GetData", sParameter, "logmag", 0, 400);
            numbers = str2double(split(strip(string(raw)), ","))';
            say("  GetData " + sParameter + " logmag: " + numel(numbers) + " numbers (the plan's points, twice if each has a frequency and a value)");
            say("  first six numbers: " + strjoin(string(numbers(1:min(6, end))), ", "));
            probe("GetData", sParameter, "real", 0, 200);
            probe("GetData", sParameter, "imag", 0, 200);
        else
            say("  Measure(" + sParameter + ") didn't say OK, so there is nothing to read - the library needs a calibration covering it (use Calibrate = true or CalibrationFile).");
        end
    end
    timer = tic();
    measureReply = probe("Measure", "All");
    say("  Measure(All) took " + sprintf("%.2f", toc(timer)) + " s");
    if strip(string(measureReply)) == "OK"
        probe("GetData", "S12", "logmag", 0, 200);
        probe("GetData", "S22", "logmag", 0, 200);
    end
    say("");

    %% Step 5 - a scan through the driver
    stopServer();
    if Settings.SkipDriverScan
        say("Step 5 skipped, as asked.");
        say("Wrote " + reportFile);
        return;
    end
    say("STEP 5: a scan through the driver, as the VNA Control runs it");
    pause(1);
    instr = Palladium.Instruments.PicoVNA_NetworkAnalyser();
    instr.Software = instr.SoftwareType("PicoVNA 3");
    if strlength(calibrationFile) > 0
        instr.CalibrationFile = calibrationFile;
    end
    try
        instr.Connect();
        say("  connected: " + instr.GetActiveSoftware());
        say("  settings: " + jsonencode(instr.GetScanSettings()));
        for scan = [struct("MeasMode", "S11", "MeasUnit", "dB"), struct("MeasMode", "S21", "MeasUnit", "Absolute")]
            say("  - scan of " + scan.MeasMode + " in " + scan.MeasUnit + ":");
            try
                timer = tic();
                instr.RunScan(scan);
                say("    RunScan returned after " + sprintf("%.2f", toc(timer)) + " s (the sweep goes on in the background)");
                polls = 0;
                timer = tic();
                while ~instr.CheckScanComplete() && toc(timer) < 120
                    pause(0.05);
                    polls = polls + 1;
                end
                say("    sweep finished after " + sprintf("%.2f", toc(timer)) + " s more (" + polls + " checks)");
                data = instr.GetCompletedScanData();
                say("    data: " + mat2str(size(data)) + ", first rows:");
                say("      " + strjoin(compose("%g  %g", data(1:min(3, end), 1), data(1:min(3, end), 2)), newline + "      "));
                say("    metadata: " + jsonencode(instr.CollectMetaData()));
            catch err
                say("    FAILED: " + err.message);
            end
        end
    catch err
        say("  FAILED: " + err.message);
    end
    try
        instr.Disconnect();
    catch
    end

    say("");
    say("Wrote " + reportFile);
    catch crash
        if crash.identifier ~= "PicoVNA3Diag:Crashed"
            rethrow(crash);
        end
        stopServer();
        say("");
        say("The library's process died, so the diagnostic stops here. Please send this file back.");
        say("Wrote " + reportFile);
    end

    function serial = serialFrom(reply)
        %The serial number in a FND or FNDSN reply - 0 for none, or if the call failed.
        serial = str2double(string(reply));
        if isnan(serial)
            serial = 0;
        end
    end

    function ok = startServer(progId)
        %Start the library's process - true if it started, saying why if not.
        ok = false;
        try
            if strlength(Settings.StandInScript) > 0
                server = Palladium.Utilities.ComServerProcess(progId, CreateObjectScript = Settings.StandInScript);
            else
                server = Palladium.Utilities.ComServerProcess(progId);
            end
            say("  started " + progId);
            ok = true;
        catch err
            say("  " + progId + " FAILED to start: " + err.message);
        end
    end

    function serial = examineLibrary()
        %What the library says to DLLVer and FND (a few times, then by hardware serial number), and its other settings - returns the serial number FND found, 0 for none.
        probe("DLLVer");

        %FND comes first, before any GetInfo: in an earlier run, asking the
        %library for information before it had searched for the analyser
        %ended its process
        serial = 0;
        for attempt = 1:3
            say("  - FND, attempt " + attempt + ":");
            timer = tic();
            reply = probe("FND");
            say("    (took " + sprintf("%.1f", toc(timer)) + " s)");
            probe("GetInfo", "SN");
            probe("GetInfo", "Model");
            serial = serialFrom(reply);
            if serial > 0
                break;
            end
            pause(3);
        end

        %By hardware serial number, if the library knows one
        hardwareSerial = strip(string(probeQuietly("GetInfo", "HWSN")));
        if strlength(hardwareSerial) > 0 && serial <= 0
            say("  - FNDSN(""" + hardwareSerial + """):");
            reply = probe("FNDSN", char(hardwareSerial));
            serial = serialFrom(reply);
            probe("GetInfo", "SN");
            probe("GetInfo", "Model");
        end

        say("  - the library's other settings:");
        for item = ["Stat", "ErrFlag", "CalType", "CalPower", "FreqPlan", "BWSet", "AverSet", "CFreqPlan", "CWMode"]
            probe("GetInfo", item);
        end
    end

    function reportCrash()
        %Say what Windows logged about a program crashing in the last ten minutes.
        say("  The helper process running the library ended, which is a crash in the library. What Windows logged just now:");
        [~, events] = system('powershell -NoProfile -Command "Get-WinEvent -FilterHashtable @{LogName=''Application''; Id=1000,1001; StartTime=(Get-Date).AddMinutes(-10)} -MaxEvents 4 -ErrorAction SilentlyContinue | ForEach-Object { $_.TimeCreated.ToString() + '' '' + $_.Message.Substring(0, [Math]::Min(500, $_.Message.Length)) } | Out-String -Width 220"');
        say("    " + strjoin(strip(splitlines(string(events))), newline + "    "));
    end

    function reply = probe(functionName, varargin)
        %Call a library function through the helper process, saying what was sent and replied (replies cut to maxChars if the last argument is a number after the data ones).
        maxChars = 300;
        args = varargin;
        if strcmp(functionName, "GetData") && numel(args) == 4
            maxChars = args{4};
            args(4) = [];
        end
        text = strjoin(string(cellfun(@(a) string(a), args)), ", ");
        try
            reply = server.Call(functionName, args{:});
            shown = string(reply);
            if strlength(shown) > maxChars
                shown = extractBefore(shown, maxChars + 1) + "... (" + strlength(string(reply)) + " characters)";
            end
            say("  " + functionName + "(" + text + ") -> " + class(reply) + " """ + shown + """");
        catch err
            reply = "";
            say("  " + functionName + "(" + text + ") FAILED: " + err.message);
            if contains(err.message, "exited unexpectedly")
                reportCrash();
                error("PicoVNA3Diag:Crashed", "The library's process died.");
            end
        end
    end

    function reply = probeQuietly(functionName, varargin)
        %Call a library function through the helper process without saying anything - "" if it fails.
        try
            reply = server.Call(functionName, varargin{:});
        catch
            reply = "";
        end
    end

    function out = ternary(condition, yes, no)
        if condition;   out = yes;
        else;           out = no;
        end
    end
end
