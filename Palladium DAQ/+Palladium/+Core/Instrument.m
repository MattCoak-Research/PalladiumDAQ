classdef(Abstract) Instrument < Palladium.Core.Entity
    %Instrument - Abstract base class that every instrument driver inherits from.
    %Drivers must define `FullName`, `Name` and `Connection_Type`, and implement
    %`GetHeaders` and `Measure`. This class provides the rest:
    %
    %* **Connecting** over GPIB, VISA, USB, Ethernet or serial (`Connect`,
    %  `Close`), and a Debug connection type that puts the driver in
    %  `SimulationMode`, for testing without hardware.
    %* **Communication**: `WriteCommand`, `QueryString`, `QueryDouble` and
    %  `ReadString`, which do nothing (or return dummy values) in simulation.
    %* **GUI settings**: public `SetObservable` properties are shown and
    %  editable in the Instrument Options panel, and raise `PropertyChanged`.
    %  `ShowProperty` hides the addresses not used by the connection type.
    %* **Instrument Controls**: `DefineInstrumentControl` (in the constructor)
    %  offers controls such as a Sweep Control; Palladium creates them and
    %  registers them here.
    %* **Metadata**: override `CollectMetaData` to record settings in the
    %  data file header.
    %
    %See `ExamplesAndTemplates/Instruments/TemplateInstrumentClass.m` and the
    %"Writing an instrument driver" guide.

    %% Properties (Abstract, Public)
    properties(Abstract, Access = public)
        FullName;           %Full name of the instrument, displayed in the GUI, e.g. "Keithley 2000 Multimeter"
        Name;               %Instrument name, used as the prefix of its data column headers - Palladium adds a number, e.g. "K2000_1"
        Connection_Type;    %Type of connection used to talk to the instrument: a Palladium.Enums.ConnectionType, one of those set by DefineSupportedConnectionTypes
    end

    %% Properties (Public)
    % Not shown in the GUI
    properties(Access = public)
        LastFullDataRow = [];           %The last row of data from all instruments, stored here each tick by the InstrumentController - for Instrument Controls that write their own data files
        FullHeadersRow = [];            %The data column headers of all instruments, stored here when measurements start - matches LastFullDataRow
        FileWriteDetails = [];          %The main data file's settings (directory, file name, whether writing), copied here when measurements start - for Instrument Controls that write their own data files
        InstrumentDriversDir = "";      %The user files folder's Instrument Drivers folder, set by Palladium when the instrument is added - for drivers that load vendor files (e.g. .NET dlls) from there. Empty if the instrument was made outside Palladium
    end

    %% Properties (Public, Set Observable)
    properties(Access = public, SetObservable)
        %GPIB primary address of the instrument (0-30), set on its front panel. Used (and shown in the GUI) when Connection_Type is GPIB; the interface board is ConnectionSettings.GPIB_BoardIndex.
        GPIB_Address    (1,1) {mustBeInteger, mustBeBetween(GPIB_Address, 0, 30)} = 0;

        %IP address or hostname of the instrument, e.g. '192.168.1.10'. Used (and shown in the GUI) when Connection_Type is Ethernet; the TCP port is ConnectionSettings.Port.
        IP_Address      {mustBeTextScalar}  = '127.0.0.1';

        %Serial port name, e.g. 'COM3' on Windows or '/dev/ttyUSB0' on Linux. Used (and shown in the GUI) when Connection_Type is Serial; baud rate etc. are in ConnectionSettings.SerialSettings.
        Serial_Address  {mustBeTextScalar} = 'COM12';

        %VISA resource name, e.g. "USB0::0x05E6::0x2450::04412345::INSTR" or "TCPIP0::192.168.1.10::inst0::INSTR". Used (and shown in the GUI) when Connection_Type is VISA or USB.
        VISA_Address    {mustBeTextScalar} = "VISA_ADDRESS";
    end

    %% Properties (Public, Protected Set)
    properties(GetAccess = public, SetAccess = protected)
        SimulationMode = false;         %True when connected with the Debug connection type: no hardware is used, and drivers return simulated data
    end

    %% Properties (Protected)
    properties(Access = protected)
        DeviceHandle = [];              %The connection to the instrument (visadev, tcpclient or serialport), set by Connect - empty when not connected
        SettingsToApply = [];           %Settings entered in an Instrument Control (e.g. a Heater Control), waiting to be applied on the next tick, or [] for none
        SimulatedData = [];             %Struct of values a driver stores for its simulated data, e.g. SimulatedData.SourceLevel - see RetrieveSimulatedDataValue

        %Connection settings - drivers override individual fields in their
        %constructors: GPIB_BoardIndex, Port (TCP, for Ethernet),
        %GPIB_Terminators (read and write), GPIB_Timeout (s) and SerialSettings
        %(BaudRate, DataBits, Parity, StopBits, Terminator)
        ConnectionSettings = struct('GPIB_BoardIndex', 0,...
            'Port', 5025,...
            'GPIB_Terminators', ["CR/LF", "CR/LF"],...
            'GPIB_Timeout', 10,...
            'SerialSettings', struct('BaudRate', 9600, 'DataBits', 8, 'Parity', 'none', 'StopBits', 2, 'Terminator', 'LF')...
            );
    end

    %% Properties (Private)
    properties(Access = private)
        AllowedConnectionTypes = [...
            Palladium.Enums.ConnectionType.Debug,...
            Palladium.Enums.ConnectionType.GPIB,...
            Palladium.Enums.ConnectionType.VISA,...
            Palladium.Enums.ConnectionType.Ethernet,...
            Palladium.Enums.ConnectionType.Serial,...
            Palladium.Enums.ConnectionType.USB...
            ];                          %Connection types offered for this instrument - all by default, set by DefineSupportedConnectionTypes
        ControlClasses = [];            %The Instrument Controls added to this instrument
        ControlDetailsStructs = [];     %Definitions of the Instrument Controls that can be added, from DefineInstrumentControl
    end

    %% Events
    events (NotifyAccess = private)
        PropertyChanged;                %Raised when any public SetObservable property (a GUI setting) changes
    end

    %% Methods (Abstract, Public)
    methods(Abstract, Access = public)
        %Data column headers and units for the values returned by Measure.
        %Each header should start with the instrument's Name, e.g.
        %`this.Name + " - Voltage (V)"`
        %
        %Outputs:
        %   Headers - string array of column headers
        %   Units   - string array of their units, the same length
        [Headers, Units] = GetHeaders(this);

        %Take a reading, returning one value per header of GetHeaders.
        %Called once per measurement tick. In SimulationMode, return
        %simulated values (see GenerateSimulatedData)
        %
        %Outputs:
        %   dataRow - row of values, in the order of GetHeaders
        [dataRow] = Measure(this);
    end

    %% Constructor
    methods
        function this = Instrument()
            %Set up the PropertyChanged event for the GUI settings.
            %Driver constructors must work with no arguments and no hardware
            %attached: they only set defaults, the supported connection types
            %and the Instrument Controls offered

            %Register events that will auto-fire when we modify
            %SetObservable events on this instance ("PropertyChanged")
            this.RegisterPropertyChangedEvents();
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function AbortRamp(this)
            %Stop a ramp in progress - override for instruments with a Ramp Sweep Control.
            %Called by SweepController_Ramp when a sweep is aborted. Does
            %nothing by default
        end

        function CheckForSettingsToApply(this)
            %Apply settings entered in an Instrument Control, if there are any waiting.
            %Called by the InstrumentController each tick. Passes the settings
            %stored by SettingsInput to ApplySettings, then clears them

            if ~isempty(this.SettingsToApply)
                this.ApplySettings(this.SettingsToApply);
                this.SettingsToApply = [];
            end
        end

        function Close(this)
            %Disconnect from the instrument.
            %Drivers can override this to do more first (e.g. return the
            %instrument to local control), then call
            %`Close@Palladium.Core.Instrument(this)`

            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    %Just print a message
                    disp("Disconnected from simulated " + this.Name + " instrument.");
                otherwise
                    %Warn and return if there is no connection to disconnect from
                    if(isempty(this.DeviceHandle))
                        disp("Tried to close " + this.Name + " but it is not connected, or has no device handle. Returning Disconnect() with no action taken.");
                        return;
                    end

                    %Terminate the connection, reporting any errors if
                    %found
                    try
                        this.DeviceHandle = [];
                    catch e
                        error("CloseError:DisconnectFailed", "%s", "Error disconnecting from " + this.Name + ": " + e.message);
                    end
            end
        end

        function metadataStruct = CollectMetaData(this) %#ok<*MANU>
            %Instrument settings to record in the data file header - override to add some.
            %Use it for settings that don't change during a measurement, such
            %as ranges, frequencies or modes, rather than logging them every
            %tick. Each field becomes "Field = value" on a line starting with
            %the instrument's Name (see GrabMetadataString)
            %
            %Outputs:
            %   metadataStruct - struct of settings, or [] (the default) for
            %                    no header line

            metadataStruct = [];
        end

        function Connect(this)
            %Open the connection to the instrument, using Connection_Type.
            %The Debug connection type makes no connection, and puts the
            %driver in SimulationMode. Drivers can override this to do more
            %after connecting (e.g. read settings), calling
            %`Connect@Palladium.Core.Instrument(this)` first

            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    %Do not make a physical connection to a real instrument
                    %- this places the class into SimulationMode, for
                    %testing without a real piece of hardware connected
                    disp("Connected to simulated " + this.Name + " instrument.");
                    this.SimulationMode = true;
                case(Palladium.Enums.ConnectionType.Ethernet)
                    this.ConnectTCPIP();
                case(Palladium.Enums.ConnectionType.GPIB)
                    this.ConnectGPIB();
                case(Palladium.Enums.ConnectionType.VISA)
                    this.ConnectVISA();
                case(Palladium.Enums.ConnectionType.USB)
                    this.ConnectUSB();
                case(Palladium.Enums.ConnectionType.Serial)
                    this.ConnectSerial();
                otherwise
                    error("ConnectError:UnsupportedConnectionType", "%s", "Unsupported connection type: " + this.Connection_Type + ". ConnectionType can be tcpip, gpib, serial, usb, or visa.");
            end
        end

        function datArray = GenerateSimulatedData(~, numRows, numCols, Settings)
            %Create random simulated data, for Measure in SimulationMode.
            %Each column (or row, with Transpose) scatters about its own
            %baseline. Values are normally distributed about Baseline with
            %standard deviation Variance, clamped to within 5 standard
            %deviations, so the output is strictly bounded
            %
            %Inputs:
            %   numRows   - number of rows
            %   numCols   - number of columns. Default 1
            %   Baseline  - mean value: one for all, or one per column (row).
            %               Default NaN, a random baseline for each
            %   Transpose - true to make each row, rather than each column, a
            %               simulated data series. Default false
            %   Variance  - standard deviation: one for all, or one per column
            %               (row). Default NaN, a random one for each
            %
            %Outputs:
            %   datArray - numRows-by-numCols array of values

            arguments
                ~;
                numRows (1,1) {mustBeInteger};
                numCols (1,1) {mustBeInteger} = 1;
                Settings.Baseline (:,1) double = nan; %Default = nan - (nx1) double, make n be the number of rows/cols. Random baseline value will be generated for each column/row if not set. Set a value to have all rows/columns scatter around this mean value if a single value is given, set for each row/col if an array is passed in.
                Settings.Transpose (1,1) logical = false; % By default, columns are created with random but cohesive numbers. Tranpose=true switches to having rows be the simulated 'data column' instead
                Settings.Variance (:,1) double = nan; %Default = nan - (nx1) double, make n be the number of rows/cols. Random variance value will be generated for each column/row if not set. Set a value to have all rows/columns scatter by this set value instead if a single value is given, set for each row/col if an array is passed in.
            end

            %Pre-initialise array
            datArray = nan(numRows, numCols);

            %Outliers beyond this many standard deviations are clamped, so
            %extremely rare large randn draws can't give wild values
            MaxStdDeviations = 5;

            %Choose whether to fill row-wise or column-wise
            if Settings.Transpose
                for i = 1 : numRows
                    seed = rand*100;
                    exp = round(rand*10 - 6);

                    if isnan(Settings.Baseline)
                        baseline = seed*10^exp;
                    elseif isscalar(Settings.Baseline)
                        baseline = Settings.Baseline;
                    else
                        assert(length(Settings.Baseline) == numRows, "GenerateSimulatedDataError:BaselineLengthMismatch", "Baseline must match number of rows (GenerateSimulatedData)");
                        baseline = Settings.Baseline(i);
                    end

                    if isnan(Settings.Variance)
                        var = rand*5*10^exp;
                    elseif isscalar(Settings.Variance)
                        var = Settings.Variance;
                    else
                        assert(length(Settings.Variance) == numRows, "GenerateSimulatedDataError:VarianceLengthMismatch", "Variance must match number of rows (GenerateSimulatedData)");
                        var = Settings.Variance(i);
                    end

                    deviations = max(min(randn(1, numCols), MaxStdDeviations), -MaxStdDeviations);
                    datArray(i, :) = deviations * var + baseline;
                end
            else
                for i = 1 : numCols
                    seed = rand*100;
                    exp = round(rand*10 - 6);

                    if isnan(Settings.Baseline)
                        baseline = seed*10^exp;
                    elseif isscalar(Settings.Baseline)

                        baseline = Settings.Baseline;
                    else
                        assert(length(Settings.Baseline) == numCols, "GenerateSimulatedDataError:BaselineLengthMismatch", "Baseline must match number of columns (GenerateSimulatedData)");
                        baseline = Settings.Baseline(i);
                    end

                    if isnan(Settings.Variance)
                        var = rand*5*10^exp;
                    elseif isscalar(Settings.Variance)
                        var = Settings.Variance;
                    else
                        assert(length(Settings.Variance) == numCols, "GenerateSimulatedDataError:VarianceLengthMismatch", "Variance must match number of columns (GenerateSimulatedData)");
                        var = Settings.Variance(i);
                    end

                    deviations = max(min(randn(numRows, 1), MaxStdDeviations), -MaxStdDeviations);
                    datArray(:, i) = deviations * var + baseline;
                end
            end


        end

        function controlDetailsStruct = GetControlOption(this, controlName)
            %Get the definition of one of the Instrument Controls this instrument offers.
            %Errors, listing the names offered, if there is none of that name
            %
            %Inputs:
            %   controlName - the control's Name, e.g. "Sweep Control"
            %
            %Outputs:
            %   controlDetailsStruct - its definition, from DefineInstrumentControl

            arguments
                this;
                controlName {mustBeTextScalar}
            end

            controlDetailsStructs = this.GetAvailableControlOptions();

            listOfPotentialNames = "";

            for i = 1 : length(controlDetailsStructs)
                listOfPotentialNames = listOfPotentialNames + string(controlDetailsStructs(i).Name);

                if i < length(controlDetailsStructs)
                    listOfPotentialNames = listOfPotentialNames + ", ";
                end

                if strcmp(controlName, controlDetailsStructs(i).Name)
                    controlDetailsStruct = controlDetailsStructs(i);
                    return;
                end
            end

            error("GetControlOptionError:NotFound", "%s", "Could not find Control Detail Struct with name " + string(controlName) + ". Supported options: " + listOfPotentialNames);
        end

        function names = GetRegisteredControlNames(this)
            %Names of the Instrument Controls added to this instrument.
            %
            %Outputs:
            %   names - string array of names, or [] if none are added

            names = [];

            for i = 1 : length(this.ControlClasses)
                names = [names, string(this.ControlClasses(i).GetName())]; %#ok<AGROW>
            end
        end

        function [objsList, controlDetailsStructsList] = GetRegisteredControlObjects(this)
            %The Instrument Controls added to this instrument, and their definitions.
            %
            %Outputs:
            %   objsList                  - the controls, or [] if none are added
            %   controlDetailsStructsList - their definitions (ControlDetailsStruct)

            objsList = [];
            controlDetailsStructsList = [];

            %Scan through all the Registered InstrumentControl classes and
            %return all
            for i = 1 : length(this.ControlClasses)
                objsList = [objsList this.ControlClasses(i)]; %#ok<AGROW>
                strct = this.ControlClasses(i).ControlDetailsStruct;
                controlDetailsStructsList = [controlDetailsStructsList strct]; %#ok<AGROW>
            end
        end

        function objsList = GetRegisteredControlObjectsFromName(this, name)
            %The Instrument Controls added to this instrument with a given name.
            %
            %Inputs:
            %   name - the control's name, e.g. "Sweep Control"
            %
            %Outputs:
            %   objsList - the matching controls, or [] if there are none

            objsList = [];

            %Scan through all the Registered InstrumentControl classes and
            %return all the ones with Name matching the input name
            for i = 1 : length(this.ControlClasses)
                if(strcmp(name, this.ControlClasses(i).GetName()))
                    objsList = [objsList this.ControlClasses(i)]; %#ok<AGROW>
                end
            end
        end

        function connectionTypes = GetSupportedConnectionTypes(this)
            %The connection types offered for this instrument.
            %
            %Outputs:
            %   connectionTypes - Palladium.Enums.ConnectionType array, as set by
            %                     DefineSupportedConnectionTypes

            connectionTypes = this.AllowedConnectionTypes;
        end

        function [success, msg] = Initialise(this)
            %Connect to the instrument when measurements start, reporting rather than throwing errors.
            %Called by the InstrumentController for each instrument. On
            %success, calls OnInitialised
            %
            %Outputs:
            %   success - true if the connection was made
            %   msg     - if not, a message for the user, naming the
            %             instrument and connection type, with the error

            try
                this.Connect();
            catch err

                success = false;
                msg = "Could not connect to Instrument:" + newline + this.FullName + " - " + this.Name + newline + "Connection type " + string(this.Connection_Type) + newline + newline + "Error message: " + err.message;
                return;
            end

            success = true;
            msg = "";

            this.OnInitialised();
        end

        function str = PrintIdentifier(this)
            %Print the instrument's full name to the Command Window, for debugging.
            %
            %Outputs:
            %   str - the text printed, "Palladium Instrument <FullName>"

            str = "Palladium Instrument " + this.FullName;
            disp(str);
        end

        function val = QueryDouble(this, command)
            %Send a query and return the reply as a number.
            %In SimulationMode, returns a random number between 100 and 101
            %
            %Inputs:
            %   command - the query to send, e.g. "MEAS:VOLT?"
            %
            %Outputs:
            %   val - the reply, converted with str2double (NaN if it isn't a number)

            arguments
                this;
                command (1,1) string;
            end

            if(this.SimulationMode)
                val = rand() + 100;
            else
                %Quickly check to make sure we are (in theory at least)
                %connected before sending command - warn if not
                assert(~isempty(this.DeviceHandle), "QueryDoubleError:NotConnected", "%s", "Device Handle is empty - device is not connected yet when sending Query command (" + this.FullName + ")");

                %Send query
                val = str2double(query(this.DeviceHandle, command));
            end
        end

        function val = QueryString(this, command)
            %Send a query and return the reply as text.
            %In SimulationMode, returns 'null'
            %
            %Inputs:
            %   command - the query to send, e.g. "*IDN?"
            %
            %Outputs:
            %   val - the reply, with leading and trailing whitespace removed

            arguments
                this;
                command (1,1) string;
            end

            if(this.SimulationMode)
                val = 'null';
            else
                %Quickly check to make sure we are (in theory at least)
                %connected before sending command - warn if not
                assert(~isempty(this.DeviceHandle), "QueryStringError:NotConnected", "%s", "Device Handle is empty - device is not connected yet when sending Query command (" + this.FullName + ")");

                %Send query
                val = query(this.DeviceHandle, command);

                %Strip any leading or trailing whitespace or newlines
                val = strip(val);
            end
        end

        function data = ReadString(this)
            %Read a reply from the instrument without sending anything first.
            %For instruments that send data on their own, or replies to an
            %earlier WriteCommand. In SimulationMode, returns 'null'
            %
            %Outputs:
            %   data - the text read

            if(this.SimulationMode)
                data = 'null';
            else
                %Quickly check to make sure we are (in theory at least)
                %connected before sending command - warn if not
                assert(~isempty(this.DeviceHandle), "ReadStringError:NotConnected", "%s", "Device Handle is empty - device is not connected yet when reading from the instrument (" + this.FullName + ")");

                data= fscanf(this.DeviceHandle);
            end
        end

        function SetNewSweepStepValue(this, value) %#ok<INUSD>
            %Go to the next step of a stepped sweep - override for instruments with a Sweep Control.
            %Called by SweepController_Stepped at each step. The default only
            %warns that it isn't implemented. See Keithley2410 for an example
            %
            %Inputs:
            %   value - the new value, in the units of GetSweepUnitsString

            warning("SetNewSweepStepValueWarning:NotOverridden", "An override method for SetNewSweepStepValue has not been defined for this Instrument. A SweepController_Stepped is probably trying to tell this Instrument to go to the next step in its sweep but the Instrument doesn't have a function written to tell it how. Look at the Keithley2410 class for an example");
        end

        function SetRampingToTarget(this, target, rate, settings) %#ok<INUSD>
            %Start ramping to a target - override for instruments with a Ramp Sweep Control.
            %Called by SweepController_Ramp. Does nothing by default
            %
            %Inputs:
            %   target   - the value to ramp to
            %   rate     - the ramp rate, per minute
            %   settings - other ramp settings from the Sweep Control
        end

        function SettingsInput(this, settings)
            %Store settings entered in an Instrument Control, to apply on the next tick.
            %Called from the event raised when e.g. Set is pressed on a
            %Lakeshore Heater Control. CheckForSettingsToApply then passes them
            %to ApplySettings, so they are applied between readings. Ignored
            %if earlier settings are still waiting
            %
            %Inputs:
            %   settings - struct of settings, as the Instrument Control sends them

            if isempty(this.SettingsToApply)    %Just to avoid any crazy async double setting of overriding halfway through giving command stuff
                this.SettingsToApply = settings;
            end
        end

        function value = ShowProperty(this, propertyName)
            %Whether a GUI setting should be shown in the Instrument Options panel.
            %Hides the address properties not used by the current connection
            %type (e.g. Serial_Address when connecting over GPIB), and any
            %property listed by GetPropertiesToIgnore
            %
            %Inputs:
            %   propertyName - name of a SetObservable property
            %
            %Outputs:
            %   value - true to show it

            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address", "VISA_Address"};
                case(Palladium.Enums.ConnectionType.Ethernet)
                    propertiesToIgnore = {"GPIB_Address", "Serial_Address", "VISA_Address"};
                case(Palladium.Enums.ConnectionType.GPIB)
                    propertiesToIgnore = {"IP_Address", "Serial_Address", "VISA_Address"};
                case(Palladium.Enums.ConnectionType.VISA)
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address"};
                case(Palladium.Enums.ConnectionType.Serial)
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "VISA_Address"};
                case(Palladium.Enums.ConnectionType.USB)
                    %USB connects through VISA (see ConnectUSB), so it uses
                    %the VISA address
                    propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address"};
                otherwise
                    error("ShowPropertyError:UnsupportedConnectionType", "%s", "Unsupported connection type: " + this.Connection_Type + ". ConnectionType can be tcpip, gpib, serial, usb, or visa.");
            end

            for i = 1 : length(propertiesToIgnore)
                if(strcmp(propertiesToIgnore{i}, propertyName))
                    value = false;
                    return;
                end
            end

            %Allow ignoring additional properties specified by an
            %Instrument by overriding this call:
            propertiesToIgnore = this.GetPropertiesToIgnore();
            for i = 1 : length(propertiesToIgnore)
                if(strcmp(propertiesToIgnore{i}, propertyName))
                    value = false;
                    return;
                end
            end

            value = true;
        end

        function WriteCommand(this, command)
            %Send a command that has no reply.
            %Does nothing in SimulationMode
            %
            %Inputs:
            %   command - the command to send, e.g. "OUTP ON"

            arguments
                this;
                command (1,1) string;
            end

            if(this.SimulationMode); return; end
            %Quickly check to make sure we are (in theory at least)
            %connected before sending command - warn if not
            assert(~isempty(this.DeviceHandle), "WriteCommandError:NotConnected", "%s", "Device Handle is empty - device is not connected yet when sending a command (" + this.FullName + ")");

            %Send command
            fprintf(this.DeviceHandle, command);
        end

    end

    %% Methods (Public, Sealed)
    methods (Access = public, Sealed)

        function DefineSupportedConnectionTypes(this, connectionTypes)
            %Set the connection types offered for this instrument - call in the constructor.
            %Only these are offered in the GUI's Connection_Type drop-down
            %
            %Inputs:
            %   connectionTypes - Palladium.Enums.ConnectionType values, or
            %                     their names, e.g. ["Debug", "GPIB", "VISA"]

            arguments
                this
                connectionTypes (:,1) Palladium.Enums.ConnectionType;
            end

            this.AllowedConnectionTypes = connectionTypes;
        end

        function [controlDetailsStructs] = GetAvailableControlOptions(this)
            %Definitions of the Instrument Controls this instrument offers.
            %
            %Outputs:
            %   controlDetailsStructs - struct array, one per control defined with
            %                           DefineInstrumentControl, or [] for none

            controlDetailsStructs = this.ControlDetailsStructs;
        end

        function stringLine = GrabMetadataString(this)
            %The data file header line of this instrument's settings, from CollectMetaData.
            %Called by the Controller when measurements start
            %
            %Outputs:
            %   stringLine - e.g. "K2000_1 Settings: Range = 10 V, NPLC = 1", or
            %                [] if CollectMetaData returns []

            %Get the metadata, which is either empty or a struct
            result = this.CollectMetaData();

            %Return empty if this is empty (default)
            if isempty(result)
                stringLine = [];
                return;
            end

            %Error checking
            assert(isstruct(result), "GrabMetadataStringError:MetadataNotStruct", "%s", "Return value of CollectMetadata is not Struct on Instrument " + this.Name);

            %Otherwise turn the struct into a human readable one-line
            %string...
            preInfStr = this.Name + " Settings: ";
            stringLine = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct(preInfStr, result);
        end

        function RegisterControlObject(this, classRef)
            %Register an Instrument Control that has been added to this instrument.
            %Called by Palladium when it creates the control. Errors if a
            %control of the same name is already registered
            %
            %Inputs:
            %   classRef - the Instrument Control

            name = classRef.GetName();

            %Check we didn't already register a control of this name to
            %avoid duplication
            if ~isempty(this.GetRegisteredControlObjectsFromName(name))
                error("RegisterControlObjectError:DuplicateName", "%s", "A Control object of name " + name + " has already been added to Instrument " + this.Name);
            end

            %Add to the list of tracked things
            if isempty(this.ControlClasses)
                this.ControlClasses = classRef;
            else
                this.ControlClasses = [this.ControlClasses, classRef];
            end
        end

        function RemoveControlObject(this, className)
            %Unregister the Instrument Controls of a given name from this instrument.
            %Called by Palladium when a control is removed
            %
            %Inputs:
            %   className - the control's name, e.g. "Sweep Control"

            for i = length(this.ControlClasses) : -1 : 1
                if(strcmp(className, this.ControlClasses(i).GetName()))
                    this.ControlClasses(i) = [];
                end
            end
        end

        function dataRow = UpdateAndMeasure(this, headers)
            %Update the Instrument Controls, take a reading, and pass it to the controls.
            %The entry point for each measurement tick, called by the
            %InstrumentController: calls each control's Update, then Measure,
            %then each control's UpdateData with the new reading
            %
            %Inputs:
            %   headers - the data column headers of this instrument
            %
            %Outputs:
            %   dataRow - the reading from Measure

            %First Update any added Controls
            this.UpdateControls();

            %Pass through and do the actual measure command
            dataRow = this.Measure();

            %And then UpdateData any added Controls, handing them that
            %last-acquired dataRow
            this.UpdateControlsData(dataRow, headers);
        end

    end

    %% Methods (Protected)
    methods(Access = protected)

        function ApplySettings(this, settings) %#ok<INUSD>
            %Apply settings entered in an Instrument Control - override to use them.
            %Called on the next tick after SettingsInput, between readings.
            %Does nothing by default
            %
            %Inputs:
            %   settings - struct of settings, as the Instrument Control sends them
        end

        function ConnectGPIB(this)
            %Connect over GPIB, using GPIB_Address and ConnectionSettings.
            %Uses GPIB_BoardIndex, GPIB_Terminators and GPIB_Timeout

            this.DeviceHandle = visadev("GPIB::" + num2str(this.GPIB_Address) + "::" + num2str(this.ConnectionSettings.GPIB_BoardIndex) + "::INSTR");
            configureTerminator(this.DeviceHandle, this.ConnectionSettings.GPIB_Terminators(1), this.ConnectionSettings.GPIB_Terminators(2));
            this.DeviceHandle.Timeout = this.ConnectionSettings.GPIB_Timeout;%In seconds
        end

        function ConnectSerial(this)
            %Connect over a serial (COM) port, using Serial_Address and ConnectionSettings.SerialSettings.

            this.DeviceHandle = serialport(this.Serial_Address, this.ConnectionSettings.SerialSettings.BaudRate);

            %Configure serial settings
            this.DeviceHandle.DataBits = this.ConnectionSettings.SerialSettings.DataBits;
            this.DeviceHandle.Parity = this.ConnectionSettings.SerialSettings.Parity;
            this.DeviceHandle.StopBits = this.ConnectionSettings.SerialSettings.StopBits;
            configureTerminator(this.DeviceHandle, this.ConnectionSettings.SerialSettings.Terminator);
        end

        function ConnectTCPIP(this)
            %Connect over Ethernet (TCP), using IP_Address and ConnectionSettings.Port.
            %Reuses an existing connection to the same address and port if
            %there is one

            %Note that 2022 Matlab has changed the syntax for these -
            %removing fopen and fclose in particular:
            %https://uk.mathworks.com/help/instrument/transition-your-code-to-tcpclient-interface.html

            %Check for existing connection -  Find a tcpip object at this address and port.
            existingHandle = tcpclientfind("Address", char(this.IP_Address), 'RemotePort', this.ConnectionSettings.Port); %This requires Matlab 2024a

            if(~isempty(existingHandle))    %If we already are connected, don't try to connect again - will error
                this.DeviceHandle = existingHandle;
                disp("Existing connection to " + this.Name + " found, using that");
            else                            %Make a new connection
                %Connect to the device
                this.DeviceHandle = tcpclient(char(this.IP_Address), this.ConnectionSettings.Port);
                this.DeviceHandle.ByteOrder = "big-endian";
            end
        end

        function ConnectUSB(this)
            %Connect over USB, through VISA, using VISA_Address.

            this.ConnectVISA();
        end

        function ConnectVISA(this)
            %Connect through VISA, using VISA_Address.
            %Reuses an existing connection to the same resource if there is one

            %Note that 2022 Matlab has changed the syntax for these -
            %removing fopen and fclose in particular:
            %https://uk.mathworks.com/help/instrument/transition-your-code-to-visadev-interface.html

            %Check for an existing connection to this VISA resource
            existingHandle = visadevfind(Name=this.VISA_Address);   %This requires Matlab 2024a
            if(~isempty(existingHandle))    %If we already are connected, don't try to connect again - will error
                this.DeviceHandle = existingHandle;
                disp("Existing connection to " + this.Name + " found, using that");
            else
                this.DeviceHandle = visadev(this.VISA_Address);
            end
        end

        function catOut = ConvertToCategorical(~, inputStr, catNamesStrArray)
            %Convert text to a categorical with the given categories, for a driver's categorical settings.
            %Used by the one-line converters in a driver's Categoricals
            %block. Errors, listing the categories, if the text isn't one
            %of them
            %
            %Inputs:
            %   inputStr         - the value, e.g. "DC Voltage"
            %   catNamesStrArray - all the allowed values, in drop-down order
            %
            %Outputs:
            %   catOut - categorical with value inputStr and categories catNamesStrArray

            arguments
                ~;
                inputStr (1,1) string;
                catNamesStrArray (1,:) string;
            end

            %Convert the string to a categorical (which is basically an
            %enum)
            catOut = categorical(inputStr, catNamesStrArray);

            %Check that the conversion was successful - ie that the input
            %could be found in the catNames
            if isundefined(catOut)
                catNam = "";
                for i = 1 : length(catNamesStrArray)
                    catNam = catNam + catNamesStrArray(i) + " ";
                end
                error("ConvertToCategoricalError:ValueNotInCategories", "%s", "Error in converting string to categorical in Instrument. Given value: " + inputStr + " was not found in the input category names: " + catNam);
            end
        end

        function DefineInstrumentControl(this, Settings)
            %Offer an Instrument Control for this instrument - call in the constructor.
            %For example a Sweep Control, or a magnet's control panel. It then
            %appears as an option in the GUI and to AddInstrumentControl, or
            %is added automatically if EnabledByDefault
            %
            %Inputs:
            %   Name             - name of the control, e.g. "Sweep Control"
            %   ClassName        - its class in Palladium.Instruments.Controls,
            %                      e.g. "SweepController_Stepped"
            %   TabName          - title of the tab it is shown in
            %   EnabledByDefault - true to add it whenever the instrument is
            %                      added. Default false
            %   UserData         - any extra data the control needs. Default []

            arguments
                this;
                Settings.Name               {mustBeTextScalar}
                Settings.ClassName          {mustBeTextScalar}
                Settings.TabName            {mustBeTextScalar}
                Settings.EnabledByDefault   (1,1) logical = false;
                Settings.UserData = []; %Spare field to use for specific Control data flexibly
            end

            s = struct(...
                "Name", Settings.Name,...
                "ControlClassFileName", Settings.ClassName,...
                "TabName", Settings.TabName,...
                "EnabledByDefault", Settings.EnabledByDefault,...
                "UserData", Settings.UserData);

            this.ControlDetailsStructs = [this.ControlDetailsStructs, s];
        end

        function propertiesToIgnore = GetPropertiesToIgnore(this)
            %GUI settings to hide in the Instrument Options panel - override to hide some.
            %
            %Outputs:
            %   propertiesToIgnore - cell array of property names. Default {}

            propertiesToIgnore = {};
        end

        function OnInitialised(this)
            %Called after connecting when measurements start - override to do more then.
            %Does nothing by default
        end


        function val = RetrieveSimulatedDataValue(this, propName, defaultValue)
            %Get a value stored in SimulatedData, storing a default if it isn't there yet.
            %
            %Inputs:
            %   propName     - the field of SimulatedData, e.g. "SourceLevel"
            %   defaultValue - value to use (and store) if the field isn't set.
            %                  Default 0
            %
            %Outputs:
            %   val - the stored value, or defaultValue

            arguments
                this;
                propName {mustBeTextScalar};
                defaultValue = 0;
            end

            if isempty(this.SimulatedData)
                this.SimulatedData.(propName) = defaultValue;
                val = defaultValue;
                return;
            end

            if ~isfield(this.SimulatedData, propName)
                this.SimulatedData.(propName) = defaultValue;
                val = defaultValue;
                return;
            end

            %We made it past all the error handling! Now we can just
            %extract the field, knowing it's there
            val = this.SimulatedData.(propName);
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function HandlePropEvents(this, ~, evnt)
            %Raise PropertyChanged when a SetObservable property changes.
            %Listener for each property's PostSet event, passing the event on
            %so the GUI updates

            %Trigger event
            notify(this, "PropertyChanged", evnt);
        end

        function RegisterPropertyChangedEvents(this)
            %Listen for changes to every SetObservable property.

            mc = metaclass(this);
            metaprops = [mc(:).Properties];
            for i = length(metaprops): -1 : 1
                prop = metaprops(i);
                if(prop{1}.SetObservable)
                    %Add event listener to these properties changing
                    addlistener(this, prop{1}.Name, 'PostSet', @this.HandlePropEvents);
                end
            end
        end

        function UpdateControls(this)
            %Call Update on each Instrument Control, before a reading.

            for i = 1 : length(this.ControlClasses)
                this.ControlClasses(i).Update();
            end
        end

        function UpdateControlsData(this, dataRow, headers)
            %Pass a new reading to each Instrument Control.

            for i = 1 : length(this.ControlClasses)
                this.ControlClasses(i).UpdateData(dataRow, headers);
            end
        end

    end
end
