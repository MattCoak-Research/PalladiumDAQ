classdef PythonInstrument < Palladium.Core.Instrument
    %PYTHONINSTRUMENT Wrapper for an Instrument.py python-defined
    %instrument.
    %This is an Instrument, and will be handled by Palladium as one, but it
    %contains a reference to a Python class object that does all the actual
    %logic.

    %% Properties (Public, Dependent)
    properties (Access=public, Dependent)
        FullName;
    end

    %% Properties (Public, Dependent, SetObservable)
    properties (Access=public, Dependent, SetObservable)
        Name;
    end

    %% Properties (Public, SetObservable)
    properties (Access=public, SetObservable)
        Connection_Type = Palladium.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    end

    %% Properties (Public)
    properties
        PyInstr = [];   
    end

    %% Properties (Private)
    properties(Access=private)
    end

    %% Constructor
    methods
        function this = PythonInstrument(pyInstr)
            this@Palladium.Core.Instrument();

            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.GPIB_Address = 22;      %Default Address
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

            this.PyInstr = pyInstr;
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

        function set.Name(this, value)
            % Name setter: accept string or char, convert to Python str and set on PyInstr
            if isempty(this.PyInstr)
                error("Python Instrument assignment empty, cannot set Name until PyInstr is assigned");
            end
            % Validate input
            if ~(ischar(value) || isstring(value)) || (isstring(value) && numel(value)~=1)
                error("Name must be a scalar char vector or a scalar string.");
            end
            % Convert to char then to Python str
            try
                pyStr = py.str(char(value));
                this.PyInstr.Name = pyStr;
            catch ex
                error("Failed to set PyInstr.Name: %s", ex.message);
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
                error("Python Instrument assignment empty, cannot set FullName until PyInstr is assigned");
            end
            % Validate input
            if ~(ischar(value) || isstring(value)) || (isstring(value) && numel(value)~=1)
                error("FullName must be a scalar char vector or a scalar string.");
            end
            try
                pyStr = py.str(char(value));
                this.PyInstr.FullName = pyStr;
            catch ex
                error("Failed to set PyInstr.FullName: %s", ex.message);
            end
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function metadataStruct = CollectMetaData(this) 
            assert(~isempty(this.PyInstr), "Python Instrument assignment empty, cannot call CollectMetadata until it is assigned");
            pyStruct = this.PyInstr.collect_metadata();
            
            %Return if this result is null
            if isequal(pyStruct, py.None) || isempty(pyStruct)
                metadataStruct = [];
                return;
            end

            %Convert to MATLAB type
            metadataStruct = Palladium.Utilities.PythonUtils.ConvertPyStrFields(struct(pyStruct));

            %string fields will be of type py.str here, scan through and
            %convert them
           % metadataStruct = 
        end

        function Close(this)
            if isempty(this.PyInstr)
                warning("Python Instrument assignment empty, cannot call Close until it is assigned");
                return;
            end

            this.PyInstr.close();

        end

        function Connect(this)
            assert(~isempty(this.PyInstr), "Python Instrument assignment empty, cannot call Connect until it is assigned");

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
                    error("Unsupported connection type: " + this.Connection_Type + ". ConnectionType can be tcpip, gpib, serial, usb, or visa.");
            end

            % Inform Python side of simulation state (false for real connections)
            this.PyInstr.SimulationMode = py.bool(this.SimulationMode);
        end


        function [headers, units] = GetHeaders(this)
            % Call the Python GetHeaders() -> (headers, units)

            if isempty(this.PyInstr)
                error("PyInstr reference is empty");
            end

            % pyOut is the Python return, e.g. (['Value1','Value2'], ['arb','K'])
            pyOut = this.PyInstr.GetHeaders();

            % Extract tuple/list elements
            if isa(pyOut, 'py.tuple') || isa(pyOut, 'py.list')
                firstPy  = pyOut{1};
                secondPy = pyOut{2};
            else
                error("Unexpected return type from Python GetHeaders");
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

    end
end