classdef Software5 < Palladium.Instruments.PicoVNA.Backend
    %Software5 - PicoVNA_NetworkAnalyser's connection to the PicoVNA 5 software, with SCPI commands over TCP.
    %The software must be running, with its SCPI interface enabled (it is by
    %default, on port 5025 - User Preferences, Network, in the software).
    %(Commands from the PicoVNA 5 User Guide, SCPI chapter.)
    %
    %A sweep is started with `INITiate`, and its data asked for straight
    %after with `CALCulate:DATa` - which the software answers only once the
    %sweep is done. So starting a sweep never waits, and `IsSweepDone` just
    %checks, without waiting, whether the answer has arrived. Every command
    %replies, "OK" or a message, so each setter's reply is read and checked.
    %Nothing can be asked while a data request is waiting, so the caller
    %reads what it needs before starting a sweep. A sweep that is given up
    %on is stopped with `ABORt` (which works on the same connection, and
    %makes the software answer the waiting request with what it has).
    %
    %The calibration, bandwidth and power are the software's own - set them
    %there.

    %% Properties (Private)
    properties(Access = private)
        Address = "127.0.0.1";      %Where the software is running
        Port = 5025;                %Its SCPI port
        Handle = [];                %The connection (tcpclient) - or a stand-in for one in tests
        Outstanding = false;        %True while a data request has been sent and its reply not yet read
        Plan = [];                  %The frequency plan the outstanding sweep runs with
    end

    %% Constructor
    methods
        function this = Software5(Settings)
            %Prepare to connect (see Open) to the software at an address and port.
            %
            %Inputs:
            %   Address - (name-value) where the software is running. Default "127.0.0.1"
            %   Port    - (name-value) its SCPI port. Default 5025
            %   Handle  - (name-value) an already open connection to use in place of making one - for tests

            arguments
                Settings.Address (1,1) string = "127.0.0.1";
                Settings.Port (1,1) double = 5025;
                Settings.Handle = [];
            end

            this.Address = Settings.Address;
            this.Port = Settings.Port;
            this.Handle = Settings.Handle;
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function Open(this)
            %Connect to the software's SCPI port and check it has a PicoVNA - errors with the reason and a hint if not.

            if isempty(this.Handle)
                try
                    this.Handle = tcpclient(char(this.Address), this.Port, ConnectTimeout = 3);
                catch err
                    error("PicoVNA_NetworkAnalyser:PicoVNA5NotFound", "%s", "PicoVNA 5 software not found at " + this.Address + ":" + this.Port + " - " + err.message);
                end
            end
            this.Handle.Timeout = 30;

            %Some other service on the port, or the software without an
            %analyser, doesn't give a PicoVNA's identity
            identity = this.Query("*IDN?");
            if ~contains(identity, "PicoVNA", IgnoreCase = true)
                this.Handle = [];
                error("PicoVNA_NetworkAnalyser:PicoVNA5NoAnalyser", "%s", "PicoVNA 5 software at " + this.Address + ":" + this.Port + " has no analyser connected (it replied """ + identity + """ to *IDN?).");
            end
            this.Description = "PicoVNA 5 software at " + this.Address + ":" + this.Port + " (" + identity + ")";
        end

        function Close(this)
            %Stop a sweep still going, then close the connection.

            if isempty(this.Handle)
                return;
            end
            try
                this.AbortSweep();
            catch
                %Close it anyway
            end
            this.Handle = [];
        end

        function plan = ReadPlan(this)
            %The frequency plan, asked for.

            plan = struct("StartFrequency_Hz", this.ParseValue(this.Query("SENSe:FREQuency:STARt?")), ...
                "StopFrequency_Hz", this.ParseValue(this.Query("SENSe:FREQuency:STOP?")), ...
                "NumPoints", this.ParseValue(this.Query("SENSe:SWEep:POINts?")));
        end

        function settings = ReadSweepSettings(this)
            %The plan, power, bandwidth and calibration type, asked for.

            settings = this.ReadPlan();
            settings.Power_dBm = this.ParseValue(this.Query("SENSe:LEVel?"));
            settings.Bandwidth_Hz = this.ParseValue(this.Query("SENSe:BANDwidth?"));
            settings.CalType = this.Query("MMEMory:CALibration:INFO:TYPe?");
        end

        function SetFrequencyPlan(this, start_Hz, stop_Hz, numPoints)
            %Set the start and stop frequency and the number of points - the software refuses what the analyser can't do, and its message is given in the error.

            %The software won't put the start above the current stop, so
            %when moving the whole sweep up, the stop goes first
            number = @(value) Palladium.Core.Instrument.NumberToCommandString(value);
            setStart = @() this.Send("SENSe:FREQuency:STARt " + number(start_Hz), "setting the start frequency");
            setStop = @() this.Send("SENSe:FREQuency:STOP " + number(stop_Hz), "setting the stop frequency");
            if start_Hz >= this.ParseValue(this.Query("SENSe:FREQuency:STOP?"))
                setStop();
                setStart();
            else
                setStart();
                setStop();
            end
            this.Send("SENSe:SWEep:POINts " + number(numPoints), "setting the number of points");
        end

        function StartSweep(this, sParameter, unit, plan)
            %Start a sweep and ask for its data - LOGMAG for dB, MAG (linear magnitude) for Absolute. Returns without waiting.

            if unit == "dB";    type = "LOGMAG";
            else;               type = "MAG";
            end

            this.Send("FORMat ASCii", "setting the data format");
            this.Send("INITiate", "starting the sweep");
            fprintf(this.Handle, char("CALCulate:DATa " + sParameter + "," + type));
            this.Plan = plan;
            this.Outstanding = true;
        end

        function done = IsSweepDone(this)
            %True once the software's answer to the data request has arrived (a check, without waiting).

            done = ~this.Outstanding || this.Handle.NumBytesAvailable > 0;
        end

        function data = CollectSweep(this)
            %Read the answer to the data request: the values of each point, with frequencies evenly spaced from start to stop.
            %The software gives only the values. Errors with its message if
            %it didn't answer with numbers (e.g. no calibration, or it is
            %sweeping continuously)

            reply = strip(string(fscanf(this.Handle)));
            this.Outstanding = false;
            values = str2double(split(reply, ","));
            if isscalar(values) && isnan(values) && lower(reply) ~= "nan"
                error("PicoVNA_NetworkAnalyser:MeasureFailed", "%s", "measuring failed - the software replied """ + reply + """.");
            end
            %A short reply gets frequencies to match, so the driver can report the shortfall
            plan = this.Plan;
            data = [linspace(plan.StartFrequency_Hz, plan.StopFrequency_Hz, numel(values))', values];
        end

        function AbortSweep(this)
            %Stop a sweep started and not collected, and throw away the reply to its data request.
            %ABORt on the same connection makes the software answer the data
            %request with what the sweep had got, then OK

            if ~this.Outstanding
                return;
            end

            fprintf(this.Handle, "ABORt");
            reply = "";
            while reply ~= "OK"
                reply = strip(string(fscanf(this.Handle)));
            end
            this.Outstanding = false;
        end

        function LoadCalibration(this, fileName)
            %Load a calibration made in the PicoVNA 5 software and apply it.

            %Quoted, as the software wants for a path with backslashes
            this.Send("MMEMory:APPLY:CALibration '" + string(fileName) + "'", "applying the calibration file " + string(fileName));
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function value = ParseValue(~, reply)
            %A number from the software's reply, which has a unit after it, e.g. "1000000.000000 Hz" or "0.300000 MHz" - frequencies are returned in Hz.

            parts = split(strip(string(reply)));
            value = str2double(parts(1));
            if numel(parts) > 1
                scales = dictionary(["Hz", "kHz", "MHz", "GHz"], [1, 1e3, 1e6, 1e9]);
                if isKey(scales, parts(2))
                    value = value * scales(parts(2));
                end
            end
        end

        function reply = Query(this, command)
            %Send a command and read its one-line reply, as text.

            reply = strip(string(query(this.Handle, char(command))));
        end

        function Send(this, command, action)
            %Send a command and error, naming the action, unless the software replies OK - it replies to every command.

            reply = this.Query(command);
            assert(reply == "OK", "PicoVNA_NetworkAnalyser:CommandFailed", "%s", ...
                action + " failed - the software replied """ + reply + """.");
        end

    end
end
