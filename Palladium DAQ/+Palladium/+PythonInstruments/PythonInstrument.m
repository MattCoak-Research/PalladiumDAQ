classdef PythonInstrument < Palladium.Core.Instrument
    %PYTHONINSTRUMENT Wrapper for an Instrument.py python-defined
    %instrument.
    %This is an Instrument, and will be handled by Palladium as one, but it
    %contains a reference to a Python class object that does all the actual
    %logic.

    %% properties (Dependent)
    properties (Dependent)
        Name;
        FullName;
    end

    %% Properties (Public)
    properties
        PyInstr = [];      
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;      %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end

    %% Properties (Private)
    properties(Access=private)
        server;
        Port;
    end

    %% Constructor
    methods
        function this = PythonInstrument(pyInstr)
            this@Palladium.Core.Instrument();
            this.PyInstr = pyInstr;

            [this.server, this.Port] = this.startTcpEventServer();
            this.PyInstr.ConnectToMessageServer(py.int(this.Port));
            this.PyInstr.test_event();

%TODO - set simulationmode bool in the .py instance
        end
    end

    %% Accessors
    methods

        function name = get.Name(this)
            % Name getter: wrap pyInstr.Name -> MATLAB string
            if isempty(this.PyInstr)
                name = string.empty;
                return
            end
            try
                pyVal = this.PyInstr.Name;
                % Convert Python str or bytes to MATLAB string/char
                name = string(char(pyVal));
            catch
                name = string.empty;
            end
        end

        function fullname = get.FullName(this)
            % FullName getter: wrap pyInstr.FullName -> MATLAB string
            if isempty(this.PyInstr)
                fullname = string.empty;
                return
            end
            try
                pyVal = this.PyInstr.FullName;
                fullname = string(char(pyVal));
            catch
                fullname = string.empty;
            end
        end

    end

    %% Methods (Public)
    methods(Access = public)

        function [headers, units] = GetHeaders(this)
            % Call the Python GetHeaders() -> (headers, units)

            if isempty(this.PyInstr)
                error("PyInstr reference is empty");
            end

            pyOut = this.PyInstr.GetHeaders();
            % pyOut is a Python tuple/list of two sequences
            if ~isempty(pyOut) && numel(pyOut) >= 2
                % Convert each sequence to a cellstr
                headers = cellfun(@char, cell(py.list(pyOut{1})), 'UniformOutput', false);
                units   = cellfun(@char, cell(py.list(pyOut{2})), 'UniformOutput', false);
            end
        end

        function dataRow = Measure(this)
            % Call the Python Measure() and convert to numeric array or cell


            pyOut = this.PyInstr.Measure();
            % If pyOut is a sequence (tuple/list), convert to numeric vector
            if isa(pyOut, 'py.list') || isa(pyOut, 'py.tuple')
                pyCells = cell(py.list(pyOut));
                % Try numeric conversion
                num = zeros(1, numel(pyCells));
                for k = 1:numel(pyCells)
                    % Convert Python number to double
                    num(k) = double(pyCells{k});
                end
                dataRow = num;
            else
                % Single numeric return
                dataRow = double(pyOut);
            end
        end

        function [s, port] = startTcpEventServer(this, port)
            arguments
                this;
                port (1,1) {mustBeInteger} = 0;
            end

            if port == 0
                port = this.getFreePort();
            end

            % Create server that listens on all addresses
            s = tcpserver("127.0.0.1", port, "ConnectionChangedFcn", @onConnectionChanged);
            s.UserData.Buffer = "";
            fprintf("TCP event server listening on port %d\n", port);

            function onConnectionChanged(serverObj, ~)
                if serverObj.Connected
                    fprintf("Client connected: %s:%d\n", serverObj.ClientAddress, serverObj.ClientPort);
                    % Configure callback to read any bytes available and call readFcn
                    configureCallback(serverObj, "byte", 1, @readFcn); % trigger when bytes arrive
                else
                    fprintf("Client disconnected\n");
                    configureCallback(serverObj, "off");
                end
            end

            function readFcn(serverObj, ~)
                % Read all available bytes and append to buffer
                n = serverObj.NumBytesAvailable;
                if n > 0
                    data = char(read(serverObj, n, "char")');
                    % Ensure UserData.Buffer becomes a single string scalar
                    oldBuf = serverObj.UserData.Buffer;
                    if ~isstring(oldBuf)
                        oldBuf = string(oldBuf);
                    end
                    % If Buffer somehow became an array, join to one scalar
                    if ~isscalar(oldBuf)
                        oldBuf = strjoin(oldBuf, "");
                    end
                    buf = oldBuf + string(data);
                    
                    % Split into lines robustly
                    parts = splitlines(buf);

                    % Determine if last line is complete (buf ended with newline)
                    if endsWith(buf, newline)
                        complete = parts;    % last element may be ""
                        remaining = "";
                    else
                        if isscalar(parts)
                            complete = string.empty;
                            remaining = parts(1);
                        else
                            complete = parts(1:end-1);
                            remaining = parts(end);
                        end
                    end

                    % Process complete lines
                    for k = 1:numel(complete)
                        txt = strtrim(complete{k});
                        if strlength(txt) == 0, continue; end
                        try
                            evt = jsondecode(txt);
                            handleEvent(evt);
                        catch ME
                            warning("Failed to decode JSON: %s", ME.message);
                        end
                    end

                    serverObj.UserData.Buffer = remaining;
                end
            end


            function handleEvent(evt)
                % Customize: dispatch to your instrument instance(s) here
                if isstruct(evt) && isfield(evt,'event')
                    fprintf("Received event: %s\n", evt.event);
                    disp(evt.data);
                else
                    fprintf("Received message (no 'event' field)\n");
                    disp(evt);
                end
            end
        end

        function shutdownEventServer(this, timeoutSec)
            arguments
                this
                timeoutSec (1,1) double = 0.5;
            end

            if isempty(this.server) || ~isvalid(this.server)
                return
            end

            % Try to inform client to shutdown cleanly
            try
                msg = jsonencode(struct('cmd','shutdown')) + newline;
                write(this.server, char(msg), "char");
            catch
                % ignore write failures
            end

            % Give client a moment to close its socket
            pause(timeoutSec);

            % Turn off callbacks and delete server object
            try
                configureCallback(this.server, "off");
            catch
                % ignore
            end
            try
                delete(this.server);
            catch
                % fallback to clearing property
                this.server = [];
            end
            this.server = [];
        end

        function port = getFreePort(~)
            % GETFREEPORT  Return an available TCP port chosen by the OS.
            % Uses Java ServerSocket bound to port 0 (ephemeral port).
            import java.net.ServerSocket
            import java.io.IOException

            maxRetries = 5;
            for attempt = 1:maxRetries
                try
                    ss = ServerSocket(0);        % ask OS for ephemeral port
                    port = ss.getLocalPort();   % java int -> numeric
                    ss.close();
                    port = double(port);
                    return
                catch ME
                    warning("getFreePort attempt %d failed: %s", attempt, ME.message);
                    pause(0.05);
                end
            end
            error("Unable to obtain free port after %d attempts", maxRetries);
        end

        function delete(this)
            try
                this.shutdownEventServer();
            catch
            end
        end

    end
end