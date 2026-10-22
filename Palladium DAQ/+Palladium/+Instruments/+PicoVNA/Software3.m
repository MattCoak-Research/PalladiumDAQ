classdef Software3 < Palladium.Instruments.PicoVNA.Backend
    %Software3 - PicoVNA_NetworkAnalyser's connection to a PicoVNA 106 or 108 through the COM library installed with the PicoVNA 3 (or PicoVNA 2) software.
    %The PicoVNA 3 installer registers both libraries, and each analyser works
    %with only one: on a PicoVNA 106 only PicoControl2 found the analyser
    %(PicoControl3's FND returned 0), as the programmer's guide says -
    %PicoControl2 for the 106, PicoControl3 for the 108. So each is tried.
    %Unlike PicoVNA 5, these have no remote control through the running
    %application: the library (PicoControl3.dll, or PicoControl2.dll from
    %PicoVNA 2) takes control of the analyser itself, so the PicoVNA 3
    %application must be CLOSED. Installing the software registers the
    %library; it is found without the application running. (Functions from
    %the PicoVNA Programmer's Guide, pvpg-4.)
    %
    %The library's `Measure` returns only when the sweep is done, which can
    %take minutes - and a COM call made from MATLAB would freeze Palladium
    %until then. So the library runs in a hidden 32-bit PowerShell process
    %(`Palladium.Utilities.ComServerProcess`): quick calls wait for their
    %reply, and the sweep runs in the background, checked for each tick. This
    %also lets a 64-bit MATLAB use the 32-bit library. The library cannot
    %stop a sweep under way: the next call waits for it, and closing cuts it
    %off.
    %
    %Power and bandwidth are set by the driver (`SetSweepOptions`), as
    %the application can't be used to set them. A calibration must be made
    %with the library (`Calibrate` opens its dialogue) and kept with
    %`SaveCalibration`: files saved by the PicoVNA application cannot be
    %used - "Calibration and status files saved using the remote control DLL
    %are not compatible" with it.

    %% Properties (Private)
    properties(Access = private)
        ProgIds = ["PicoControl3.PicoVNA_3", "PicoControl2.PicoVNA_2"];     %The library's COM classes to try, in order: PicoVNA 3's, then PicoVNA 2's
        Server = [];                %The ComServerProcess running the library - or a stand-in for one in tests
        ServerFactory = @(progId) Palladium.Utilities.ComServerProcess(progId);     %Starts the process for a COM class - replaced in tests
        Power_dBm = 0;              %Test signal power, sent with the frequency plan (from SetSweepOptions)
        Bandwidth_Hz = 1000;        %Measurement bandwidth, sent with the frequency plan (from SetSweepOptions)
        SParameter = "S11";         %The S-parameter of the sweep started
        Unit = "dB";                %Its unit
        Outstanding = false;        %True while a sweep has been started and not collected
    end

    %% Constructor
    methods
        function this = Software3(Settings)
            %Prepare to connect (see Open) to the library.
            %
            %Inputs:
            %   Server        - (name-value) a stand-in for the ComServerProcess to use in place of starting one - for tests
            %   ServerFactory - (name-value) function handle that starts the process (or a stand-in) for a COM class name, in place of ComServerProcess - for tests
            %   ProgIds       - (name-value) the COM classes to try, in order. Default PicoVNA 3's then PicoVNA 2's

            arguments
                Settings.Server = [];
                Settings.ServerFactory = [];
                Settings.ProgIds (1,:) string = ["PicoControl3.PicoVNA_3", "PicoControl2.PicoVNA_2"];
            end

            this.Server = Settings.Server;
            this.ProgIds = Settings.ProgIds;
            if ~isempty(Settings.ServerFactory)
                this.ServerFactory = Settings.ServerFactory;
            end
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function Open(this)
            %Start the library's process and find the analyser on USB, trying each of the libraries in turn - errors with the reason for each if none works.
            %A library that starts but doesn't find the analyser is let go and
            %the next tried: Pico's guide says PicoVNA 2's library is the
            %one for the PicoVNA 106 and PicoVNA 3's for the 108, and both
            %can be installed

            failures = strings(1, 0);
            anyStarted = false;
            if isempty(this.Server)
                attempts = this.ProgIds;
            else
                attempts = "the library";       %Given one to use
            end

            for attempt = attempts
                try
                    if isempty(this.Server)
                        this.Server = this.ServerFactory(attempt);
                    end
                    anyStarted = true;
                    this.FindAnalyser(attempt);
                    return;
                catch err
                    this.ReleaseServer();
                    failures(end + 1) = attempt + ": " + err.message; %#ok<AGROW>
                end
            end

            if anyStarted
                error("PicoVNA_NetworkAnalyser:PicoVNA3NoAnalyser", "%s", "PicoVNA 3 software's library found, but no PicoVNA on USB. Check it is plugged in and powered, and that the PicoVNA application is closed (it uses the analyser exclusively)." + ...
                    newline + strjoin(failures, newline));
            end
            error("PicoVNA_NetworkAnalyser:PicoVNA3NotFound", "%s", "PicoVNA 3 software's library not found - " + strjoin(failures, newline));
        end

        function Close(this)
            %Close the analyser's USB port and stop the library's process - cutting off a sweep still going.

            if isempty(this.Server)
                return;
            end
            try
                %A sweep still under way is cut off with the process, not waited for
                if ~this.Server.IsBusy()
                    this.Server.Call("CloseVNA");
                end
            catch
                %Stop the process anyway
            end
            this.ReleaseServer();
        end

        function plan = ReadPlan(this)
            %The frequency plan, from the library (GetInfo "FreqPlan").
            %It replies <start Hz>, <stop Hz>, <step Hz>, <points>, <test
            %level> - or four values for a CW (time) sweep, which isn't a
            %frequency plan

            plan = struct("StartFrequency_Hz", 0, "StopFrequency_Hz", 0, "NumPoints", 0);
            numbers = this.ParseNumbers(this.Server.Call("GetInfo", "FreqPlan"));
            assert(numel(numbers) == 5, "PicoVNA_NetworkAnalyser:NotAFrequencySweep", "%s", ...
                "The analyser is not set to a frequency sweep (it returned " + numel(numbers) + " values for its frequency plan, expected 5).");
            plan.StartFrequency_Hz = numbers(1);
            plan.StopFrequency_Hz = numbers(2);
            plan.NumPoints = numbers(4);
        end

        function settings = ReadSweepSettings(this)
            %The plan, power (the plan's test level), bandwidth and calibration type, from the library.

            numbers = this.ParseNumbers(this.Server.Call("GetInfo", "FreqPlan"));
            settings = this.ReadPlan();
            settings.Power_dBm = numbers(5);
            settings.Bandwidth_Hz = str2double(strip(string(this.Server.Call("GetInfo", "BWSet"))));
            settings.CalType = strip(string(this.Server.Call("GetInfo", "CalType")));
        end

        function SetSweepOptions(this, power_dBm, bandwidth_Hz)
            %Remember the power and bandwidth to send with the frequency plan.

            this.Power_dBm = power_dBm;
            this.Bandwidth_Hz = bandwidth_Hz;
        end

        function SetFrequencyPlan(this, start_Hz, stop_Hz, numPoints)
            %Set the frequency plan, with the power and bandwidth from SetSweepOptions (SetFreqPlan).
            %The library takes the start and the step in MHz: stop = start +
            %step * (points - 1). With a calibration loaded, a plan different
            %from the one it was made for makes the library interpolate its
            %error terms - calibrate at the plan you use for the best results

            step_MHz = (stop_Hz - start_Hz) / (numPoints - 1) / 1e6;
            reply = this.Server.Call("SetFreqPlan", start_Hz / 1e6, step_MHz, numPoints, this.Power_dBm, this.Bandwidth_Hz);
            this.ExpectOK(reply, "setting the frequency plan (" + start_Hz / 1e6 + " to " + stop_Hz / 1e6 + " MHz, " + numPoints + " points, " + ...
                this.Power_dBm + " dBm, " + this.Bandwidth_Hz + " Hz bandwidth)");
        end

        function StartSweep(this, sParameter, unit, ~)
            %Start a sweep in the background (Measure) and return at once. S11 and S21 are measured alone; S12 and S22 only with a full two-port measurement, "All".
            %First checks the calibration covers the S-parameter (see CheckCalibrationCovers)

            this.CheckCalibrationCovers(sParameter);
            switch sParameter
                case "S11";     para = "S11";
                case "S21";     para = "S21";
                otherwise;      para = "All";
            end
            this.SParameter = sParameter;
            this.Unit = unit;
            this.Server.CallAsync("Measure", char(para));
            this.Outstanding = true;
        end

        function done = IsSweepDone(this)
            %True once the library's Measure has returned (a check, without waiting).

            done = ~this.Outstanding || ~this.Server.IsBusy();
        end

        function data = CollectSweep(this)
            %Read the finished sweep: frequency and value of each point (GetData) - the log magnitude for dB, or the magnitude worked out from the real and imaginary parts for Absolute (the library has no linear magnitude format).
            %Errors if the sweep failed - the library says only "Error" when
            %its calibration doesn't cover the measurement

            this.Outstanding = false;
            reply = strip(string(this.Server.GetAsyncReply()));
            assert(reply == "OK", "PicoVNA_NetworkAnalyser:MeasureFailed", "%s", ...
                "measuring " + this.SParameter + " failed - the library replied """ + reply + """. It needs a calibration covering it (S12 and S22 need a two-port one): see Calibrate and LoadCalibration.");

            if this.Unit == "dB"
                [frequency, values] = this.GetSweepValues(this.SParameter, "logmag");
            else
                [frequency, realPart] = this.GetSweepValues(this.SParameter, "real");
                [~, imaginaryPart] = this.GetSweepValues(this.SParameter, "imag");
                values = hypot(realPart, imaginaryPart);
            end
            data = [frequency, values];
        end

        function AbortSweep(this)
            %Give up on a sweep not collected - the library can't stop it, so the next call waits for it to end.

            this.Outstanding = false;
        end

        function LoadCalibration(this, fileName)
            %Load a calibration and frequency plan saved with SaveCalibration (LoadCal) - not one saved by the PicoVNA application.

            assert(isfile(fileName), "PicoVNA_NetworkAnalyser:CalibrationFileMissing", "%s", "The calibration file `" + string(fileName) + "` does not exist.");
            this.ExpectOK(this.Server.Call("LoadCal", char(fileName)), "loading the calibration file " + string(fileName));
        end

        function Calibrate(this)
            %Open the library's calibration dialogue, to set the frequency plan and calibrate (SelectCal "?") - not while a scan is running.
            %The dialogue measures the standards you connect, and applies the
            %calibration when you finish. Keep it with SaveCalibration

            this.ExpectOK(this.Server.Call("SelectCal", "?"), "calibrating");
        end

        function SaveCalibration(this, fileName)
            %Save the calibration and frequency plan, to load again with LoadCalibration or the CalibrationFile setting (SaveCal).

            this.ExpectOK(this.Server.Call("SaveCal", char(fileName)), "saving the calibration to " + string(fileName));
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function CheckCalibrationCovers(this, sParameter)
            %Error, saying what is needed, unless the library's calibration covers the S-parameter - a one-port calibration covers S11 only.
            %Measure("All") says OK even for a one-port calibration, and
            %then gives placeholder values for S12 (-200 dB) and S22 (-120 dB)
            %that would be recorded as if measured. The calibration types
            %GetInfo reports are "S11", "S21", "S11+S21" and "12 Term"
            %(two-port), or "UnCal". One it doesn't know is left for the
            %library to judge

            calType = strip(string(this.Server.Call("GetInfo", "CalType")));
            switch lower(calType)
                case "12 term";     covered = ["S11", "S21", "S12", "S22"];
                case "s11+s21";     covered = ["S11", "S21"];
                case "s11";         covered = "S11";
                case "s21";         covered = "S21";
                case "uncal";       covered = strings(1, 0);
                otherwise;          return;
            end
            if any(covered == sParameter)
                return;
            end

            switch sParameter
                case "S11";         needed = "a calibration that includes S11 (a one-port S11 calibration is enough)";
                case "S21";         needed = "an S21 or S11+S21 calibration, or a two-port one";
                otherwise;          needed = "a two-port (""12 Term"") calibration";
            end
            error("PicoVNA_NetworkAnalyser:CalibrationDoesNotCover", "%s", "Measuring " + sParameter + " needs " + needed + ", but the analyser's calibration is """ + calType + """" + ...
                ". Calibrate (Calibrate, then SaveCalibration to keep it) or load a calibration (LoadCalibration, or the CalibrationFile setting) that covers " + sParameter + ".");
        end

        function ExpectOK(~, reply, action)
            %Error, naming the action, unless a library function's reply is "OK".

            reply = strip(string(reply));
            assert(reply == "OK", "PicoVNA_NetworkAnalyser:CommandFailed", "%s", action + " failed - the library replied """ + reply + """.");
        end

        function [frequency, values] = GetSweepValues(this, sParameter, format)
            %The whole sweep of one S-parameter in a format ("logmag", "real", "imag"...), as columns of frequency (Hz) and value.
            %GetData with point 0 returns every point, as frequency and value
            %for each, comma-separated

            numbers = this.ParseNumbers(this.Server.Call("GetData", char(sParameter), char(format), 0));
            assert(~isempty(numbers) && mod(numel(numbers), 2) == 0, "PicoVNA_NetworkAnalyser:DataSizeMismatch", "%s", ...
                "Expected a frequency and a value for each point of the sweep, but received " + numel(numbers) + " numbers.");
            frequency = numbers(1:2:end)';
            values = numbers(2:2:end)';
        end

        function numbers = ParseNumbers(~, reply)
            %A library reply of comma-separated numbers as a row vector - NaN for anything that isn't a number (e.g. "Error").

            numbers = str2double(split(strip(string(reply)), ","))';
        end

        function FindAnalyser(this, libraryName)
            %Ask the library to find the analyser on USB (FND, which takes a few seconds) - errors if it finds none. libraryName is for the description.

            serialNumber = str2double(string(this.Server.Call("FND")));
            assert(serialNumber > 0, "PicoVNA_NetworkAnalyser:PicoVNA3NoAnalyser", "%s", ...
                "the library started, but FND found no PicoVNA on USB (it returned " + serialNumber + ")");
            model = strip(string(this.Server.Call("GetInfo", "Model")));
            this.Description = "PicoVNA software's library " + libraryName + " (" + model + ", serial number " + serialNumber + ")";
        end

        function ReleaseServer(this)
            %Stop the library's process.

            delete(this.Server);
            this.Server = [];
        end

    end
end
