classdef PythonInstrument < Palladium.Core.Instrument
    %PythonInstrument - Wraps an instrument written in Python, so Palladium DAQ can use it like any other.
    %Palladium treats it as an Instrument, but the work is done by the
    %Python object in PyInstr - a subclass of PalladiumPythonCore's
    %Instrument. Name and FullName are the Python object's; GetHeaders,
    %Measure and CollectMetaData call its GetHeaders, Measure and
    %collect_metadata. Connecting calls its connect method for the
    %connection type (e.g. connectGPIB), or, for Debug, sets its
    %SimulationMode. `PythonInstrumentController.CreateInstrument` makes
    %them. See [Python instruments](../python-instruments.md).

    %% Properties (Public)
    properties (Access = public)
        PyInstr = [];   %The Python instrument object this wraps
    end

    %% Properties (Dependent, Public)
    properties (Access=public, Dependent)
        FullName;       %The Python instrument's FullName, displayed in the GUI
    end

    %% Properties (Dependent, Public, Set Observable)
    properties (Access=public, Dependent, SetObservable)
        Name;           %The Python instrument's Name, used in its data column headers
    end

    %% Properties (Public, Set Observable)
    properties (Access=public, SetObservable)
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end

    %% Get and Set Accessors
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

        function set.Name(this, value)
            % Name setter: accept string or char, convert to Python str and set on PyInstr
            if isempty(this.PyInstr)
                error("SetNameError:PyInstrEmpty", "Python Instrument assignment empty, cannot set Name until PyInstr is assigned");
            end
            % Validate input
            if ~(ischar(value) || isstring(value)) || (isstring(value) && numel(value)~=1)
                error("SetNameError:InvalidType", "Name must be a scalar char vector or a scalar string.");
            end
            % Convert to char then to Python str
            try
                pyStr = py.str(char(value));
                this.PyInstr.Name = pyStr;
            catch ex
                error("SetNameError:PythonSetFailed", "Failed to set PyInstr.Name: %s", ex.message);
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

        function set.FullName(this, value)
            % FullName setter: accept string or char, convert to Python str and set on PyInstr
            if isempty(this.PyInstr)
                error("SetFullNameError:PyInstrEmpty", "Python Instrument assignment empty, cannot set FullName until PyInstr is assigned");
            end
            % Validate input
            if ~(ischar(value) || isstring(value)) || (isstring(value) && numel(value)~=1)
                error("SetFullNameError:InvalidType", "FullName must be a scalar char vector or a scalar string.");
            end
            try
                pyStr = py.str(char(value));
                this.PyInstr.FullName = pyStr;
            catch ex
                error("SetFullNameError:PythonSetFailed", "Failed to set PyInstr.FullName: %s", ex.message);
            end
        end
    end

    %% Constructor
    methods
        function this = PythonInstrument(pyInstr)
            %Wrap a Python instrument object. GPIB at address 22 by default.
            %
            %Inputs:
            %   pyInstr - the Python instrument (from PythonInstrumentController).
            %             Optional, so the API reference can construct one to read its defaults

            arguments
                pyInstr = [];
            end

            this@Palladium.Core.Instrument();

            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = 22;      %Default Address
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

            this.PyInstr = pyInstr;
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function metadataStruct = CollectMetaData(this)
            %The Python instrument's settings for the data file header, from its collect_metadata.
            %Its dict becomes a struct, with Python text converted to MATLAB
            %strings; [] if it returns None

            assert(~isempty(this.PyInstr), "CollectMetaDataError:PyInstrEmpty", "Python Instrument assignment empty, cannot call CollectMetadata until it is assigned");
            pyStruct = this.PyInstr.collect_metadata();

            %Return if this result is null
            if isequal(pyStruct, py.None) || isempty(pyStruct)
                metadataStruct = [];
                return;
            end

            %Convert to a MATLAB struct, with the Python text (py.str)
            %fields converted to strings
            metadataStruct = Palladium.Utilities.PythonUtils.ConvertPyStrFields(struct(pyStruct));
        end

        function [headers, units] = GetHeaders(this)
            %The Python instrument's column headers and units, from its GetHeaders, with Name added in front of each header.
            %Its GetHeaders returns (headers, units), two lists of text

            if isempty(this.PyInstr)
                error("GetHeadersError:PyInstrEmpty", "PyInstr reference is empty");
            end

            % pyOut is the Python return, e.g. (['Value1','Value2'], ['arb','K'])
            pyOut = this.PyInstr.GetHeaders();

            % Extract tuple/list elements
            if isa(pyOut, 'py.tuple') || isa(pyOut, 'py.list')
                firstPy  = pyOut{1};
                secondPy = pyOut{2};
            else
                error("GetHeadersError:UnexpectedReturnType", "Unexpected return type from Python GetHeaders");
            end

            % Helper to convert a Python sequence to a MATLAB string array
            % Example: headers -> ["Value1" "Value2"], units -> ["arb" "K"]
            toStringArray = @(p) string(cellfun(@char, cell(p), 'UniformOutput', false));

            headers = toStringArray(firstPy);
            units   = toStringArray(secondPy);

            % Prepend this.Name to each header element (this.Name is scalar)
            if ~isempty(this.Name)
                headers = strcat(string(this.Name), " - ", headers);
            end
        end

        function dataRow = Measure(this)
            %A reading from the Python instrument's Measure, as a row of numbers.
            %Its Measure returns a number, or a list or tuple of them

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

    end

    %% Methods (Protected)
    methods (Access = protected)

        function OpenConnection(this)
            %Connect the Python instrument - its connect method for the connection type - called by Connect.
            %Debug connects nothing, and sets SimulationMode on both sides

            assert(~isempty(this.PyInstr), "ConnectError:PyInstrEmpty", "Python Instrument assignment empty, cannot call Connect until it is assigned");

            % Handle Debug locally (no Python connect call)
            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    disp("Connected to simulated " + this.Name + " instrument.");
                    this.SimulationMode = true;
                    % Inform Python side of simulation mode
                    this.PyInstr.SimulationMode = py.bool(this.SimulationMode);
                    return;
            end

            % Ensure SimulationMode false for real connections
            this.SimulationMode = false;

            % Call Python connect functions with primitive args (char, int)
            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Ethernet)
                    this.PyInstr.connectTCPIP(py.str(char(this.IP_Address)), int32(this.ConnectionSettings.Port));
                case(Palladium.Enums.ConnectionType.GPIB)
                    this.PyInstr.connectGPIB(int32(this.ConnectionSettings.GPIB_BoardIndex), int32(this.GPIB_Address), double(this.ConnectionSettings.GPIB_Timeout));
                case(Palladium.Enums.ConnectionType.VISA)
                    this.PyInstr.connectVISA(py.str(char(this.VISA_Address)));
                case(Palladium.Enums.ConnectionType.USB)
                    this.PyInstr.connectUSB();
                case(Palladium.Enums.ConnectionType.Serial)
                    this.PyInstr.connectSerial(py.str(char(this.Serial_Address)));
                otherwise
                    error("ConnectError:UnsupportedConnectionType", "%s", "Unsupported connection type: " + this.Connection_Type + ". ConnectionType can be tcpip, gpib, serial, usb, or visa.");
            end

            % Inform Python side of simulation state (false for real connections)
            this.PyInstr.SimulationMode = py.bool(this.SimulationMode);
        end

        function CloseConnection(this)
            %Close the Python instrument's connection (its close method) - called by Disconnect.

            if isempty(this.PyInstr)
                warning("CloseWarning:PyInstrEmpty", "Python Instrument assignment empty, cannot call Close until it is assigned");
                return;
            end

            this.PyInstr.close();
        end

    end
end