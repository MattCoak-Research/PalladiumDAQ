classdef PPMS < Palladium.Core.Instrument
    %PPMS - Instrument driver for the Quantum Design PPMS (Physical Property Measurement System) cryostat.
    %Logs the temperature (K) and magnetic field (T) each measurement tick,
    %plus the sample rotator angle (degrees) if `RotatorInstalled` is set.
    %`SetTemperature` and `SetField` change them; in a sequence, each waits
    %until the temperature or field is stable before the next command runs.
    %
    %The driver talks to the Quantum Design instrument server on the PPMS
    %control PC, over the network (Ethernet, default port 11000). It does this
    %through two .NET files in the user files folder's
    %`Instrument Drivers/Quantum Design/PPMS Communication` folder: Palladium's
    %`QDInterface.dll`, and Quantum Design's `QDInstrument.dll`, which users
    %download from Quantum Design themselves. Debug mode needs both files too,
    %as it uses Quantum Design's own simulation. Windows only.
    %
    %MATLAB cannot unload .NET assemblies, so the files stay loaded until
    %MATLAB closes; this causes no problems in use.

    %% Properties (Constant, Private)
    properties(Constant, Access = private)
        InterfacePath = "QDInterface.dll";                          %File name of Palladium's .NET interface to Quantum Design's driver
        PPMSCommDirectory = "PPMS Communication";                   %Name of the folder holding both .NET files
    end

    %% Properties (Public)
    properties(Access = public)
        FullName = 'PPMS';                                          %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'PPMS';                                              %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.Ethernet;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        RotatorInstalled (1,1) logical = false;                     %Set to true if using the rotation option - the rotator angle is then logged too
    end

    %% Properties (Private)
    properties(Access = private)
        Interface;                                                  %QDInterface.Controller .NET object, created by Connect
    end

    %% Constructor
    methods
        function this = PPMS()
            %Set the connection defaults, and register the commands a sequence waits for.

            this.DefineSupportedConnectionTypes(["Debug", "Ethernet"]);
            this.IP_Address = "127.0.0.1";
            this.ConnectionSettings.Port = 11000;

            %A sequence waits for these to finish before its next command
            this.RegisterCommandCompleteQuery("SetField", @this.IsFieldStable);
            this.RegisterCommandCompleteQuery("SetTemperature", @this.IsTemperatureStable);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function Close(this)
            %Release the connection to the Quantum Design instrument server.

            delete(this.Interface);
            this.Interface = [];

            if this.SimulationMode
                disp("Disconnected from simulated PPMS");
            end
        end

        function Connect(this)
            %Load the Quantum Design .NET files and connect to the instrument server.
            %In Debug mode, connects to Quantum Design's simulated PPMS instead.
            %Errors with instructions if either .NET file is missing

            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    disp("Connecting to simulated " + this.Name + " instrument...");
                    this.SimulationMode = true;
                    this.Interface = this.ConnectToInterface(true, this.GetPPMSCommDirectory(), this.InterfacePath);
                    disp("Connected to simulated " + this.Name);

                case(Palladium.Enums.ConnectionType.Ethernet)
                    disp("Connecting to " + this.Name + " instrument.");
                    this.SimulationMode = false;
                    this.Interface = this.ConnectToInterface(false, this.GetPPMSCommDirectory(), this.InterfacePath, this.IP_Address, this.ConnectionSettings.Port);
                    disp("Connected to " + this.Name + " instrument.");

                otherwise
                    error("PPMS:UnsupportedConnectionType", "%s", "Unsupported connection type on PPMS: " + this.Connection_Type);
            end
        end

        function B_T = GetField(this)
            %Read the magnetic field, in T.
            %
            %Outputs:
            %   B_T - the field, in T (the PPMS reports it in Oe; 1 T = 10000 Oe)

            assert(~isempty(this.Interface), "PPMS:InterfaceEmpty", "PPMS interface object is empty - call Connect first?");
            B_Oe = this.Interface.GetField();
            B_T = B_Oe / 10000;
        end

        function [statusInt, statusName] = GetFieldStatus(this)
            %Read the magnet's status, e.g. StablePersistent or Charging.
            %
            %Outputs:
            %   statusInt  - Quantum Design's FieldStatus code, 0 to 15
            %   statusName - its name, e.g. "StableDriven"

            assert(~isempty(this.Interface), "PPMS:InterfaceEmpty", "PPMS interface object is empty - call Connect first?");
            statusInt = this.Interface.GetFieldStatus();

            %Quantum Design's FieldStatus enumeration, in QDInstrument.dll
            switch(statusInt)
                case(0);    statusName = "MagnetUnknown";
                case(1);    statusName = "StablePersistent";
                case(2);    statusName = "WarmingSwitch";
                case(3);    statusName = "CoolingSwitch";
                case(4);    statusName = "StableDriven";
                case(5);    statusName = "Iterating";
                case(6);    statusName = "Charging";
                case(7);    statusName = "Discharging";
                case(8);    statusName = "CurrentError";
                case(9);    statusName = "Unused9";
                case(10);   statusName = "Unused10";
                case(11);   statusName = "Unused11";
                case(12);   statusName = "Unused12";
                case(13);   statusName = "Unused13";
                case(14);   statusName = "Unused14";
                case(15);   statusName = "MagnetFailure";
                otherwise
                    error("PPMS:InvalidStatus", "%s", "Invalid field status returned by the PPMS: " + string(statusInt));
            end
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %
            %Outputs:
            %   Headers - e.g. ["PPMS - Temperature_K", "PPMS - Field_T"], then
            %             "PPMS - Rotator_Position_Deg" if RotatorInstalled
            %   Units   - matching units: "K", "T" and "Deg"

            Headers = [this.Name + " - Temperature_K", this.Name + " - Field_T"];
            Units = ["K", "T"];

            if this.RotatorInstalled
                Headers(end + 1) = this.Name + " - Rotator_Position_Deg";
                Units(end + 1) = "Deg";
            end
        end

        function val = GetMapValue(this, channel)
            %Read one of the PPMS's numbered data items, through Quantum Design's GetPPMSItem.
            %
            %Inputs:
            %   channel - the item number, e.g. 3 for the rotator angle (see
            %             GetRotatorPosition)
            %
            %Outputs:
            %   val - its value

            arguments
                this;
                channel (1,1) {mustBeInteger};
            end

            assert(~isempty(this.Interface), "PPMS:InterfaceEmpty", "PPMS interface object is empty - call Connect first?");
            val = this.Interface.GetMapValue(channel);
        end

        function pos_Deg = GetRotatorPosition(this)
            %Read the sample rotator angle, in degrees.
            %
            %Outputs:
            %   pos_Deg - the rotator angle, in degrees

            assert(~isempty(this.Interface), "PPMS:InterfaceEmpty", "PPMS interface object is empty - call Connect first?");

            %Interface.GetRotatorPosition doesn't work - in the dll, or in
            %Quantum Design's own example. In testing, the rotation angle
            %was found in data item 3, so it is read from there. This may
            %differ on newer PPMS systems: it needs testing on hardware, and
            %checking with Quantum Design
            pos_Deg = this.Interface.GetMapValue(3);
        end

        function T_K = GetTemperature(this)
            %Read the temperature, in K.
            %
            %Outputs:
            %   T_K - the temperature, in K

            assert(~isempty(this.Interface), "PPMS:InterfaceEmpty", "PPMS interface object is empty - call Connect first?");
            T_K = this.Interface.GetTemperature();
        end

        function [statusInt, statusName] = GetTemperatureStatus(this)
            %Read the temperature control status, e.g. Stable or Chasing.
            %
            %Outputs:
            %   statusInt  - Quantum Design's TemperatureStatus code, 0 to 15
            %   statusName - its name, e.g. "Stable"

            assert(~isempty(this.Interface), "PPMS:InterfaceEmpty", "PPMS interface object is empty - call Connect first?");
            statusInt = this.Interface.GetTemperatureStatus();

            %Quantum Design's TemperatureStatus enumeration, in QDInstrument.dll
            switch(statusInt)
                case(0);    statusName = "TemperatureUnknown";
                case(1);    statusName = "Stable";
                case(2);    statusName = "Tracking";
                case(3);    statusName = "Unused3";
                case(4);    statusName = "Unused4";
                case(5);    statusName = "Near";
                case(6);    statusName = "Chasing";
                case(7);    statusName = "Filling";
                case(8);    statusName = "Unused8";
                case(9);    statusName = "Unused9";
                case(10);   statusName = "Standby";
                case(11);   statusName = "Unused11";
                case(12);   statusName = "Unused12";
                case(13);   statusName = "Disabled";
                case(14);   statusName = "ImpedanceNotFunction";
                case(15);   statusName = "TempFailure";
                otherwise
                    error("PPMS:InvalidStatus", "%s", "Invalid temperature status returned by the PPMS: " + string(statusInt));
            end
        end

        %Quantum Design's ChamberStatus enumeration, for reference (not yet
        %used): 0 ChamberUnknown, 1 PurgedAndSealed, 2 VentedAndSealed,
        %3 Sealed, 4 Purging, 5 Venting, 6 PreHiVac, 7 HighVac,
        %8 PumpContinuous, 9 VentContinuous, 10-14 Unused, 15 ChamberFailure

        function tf = IsFieldStable(this)
            %Check whether the field has reached its setpoint, in persistent or driven mode.
            %A sequence calls this to know when SetField has finished
            %
            %Outputs:
            %   tf - true if the status is StablePersistent or StableDriven

            val = this.GetFieldStatus();
            tf = val == 1 || val == 4;
        end

        function tf = IsTemperatureStable(this)
            %Check whether the temperature is stable at its setpoint.
            %A sequence calls this to know when SetTemperature has finished
            %
            %Outputs:
            %   tf - true if the status is Stable

            val = this.GetTemperatureStatus();
            tf = val == 1;
        end

        function [dataRow] = Measure(this)
            %Read the temperature and field, and the rotator angle if installed.
            %
            %Outputs:
            %   dataRow - temperature (K), field (T), then the rotator angle
            %             (degrees) if RotatorInstalled, matching GetHeaders

            field_T = this.GetField();
            temp_K = this.GetTemperature();

            dataRow = [temp_K, field_T];

            if this.RotatorInstalled
                dataRow(end + 1) = this.GetRotatorPosition();
            end
        end

        function SetField(this, val_T, rate_TperMin, Settings)
            %Ramp the magnetic field to a new value.
            %In a sequence, the next command waits until the field is stable
            %(IsFieldStable). Settings are name-value arguments, e.g.
            %`SetField(1, 0.5, ApproachMode="NoOvershoot", FieldMode="Driven")`
            %
            %Inputs:
            %   val_T        - the field to go to, in T
            %   rate_TperMin - ramp rate, in T/min
            %   ApproachMode - "Linear" (default), "NoOvershoot" or "Oscillate"
            %   FieldMode    - what the magnet is left in at the end: "Persistent"
            %                  (default) or "Driven"

            arguments
                this;
                val_T (1,1) double;
                rate_TperMin (1,1) double {mustBePositive};
                Settings.ApproachMode {mustBeMember(Settings.ApproachMode, ["Linear", "NoOvershoot", "Oscillate"])} = "Linear";
                Settings.FieldMode {mustBeMember(Settings.FieldMode, ["Persistent", "Driven"])} = "Persistent";
            end

            %Quantum Design's FieldApproach and FieldMode codes. The defaults
            %are the PPMS's own (FIELD command, PPMS GPIB Commands Manual)
            switch(Settings.ApproachMode)
                case("Linear");         am = 0;
                case("NoOvershoot");    am = 1;
                case("Oscillate");      am = 2;
                otherwise
                    error("PPMS:InvalidApproachMode", "Invalid approach mode");
            end

            switch(Settings.FieldMode)
                case("Persistent");     fm = 0;
                case("Driven");         fm = 1;
                otherwise
                    error("PPMS:InvalidFieldMode", "Invalid field mode");
            end

            %The PPMS takes the field in Oe and the rate in Oe/s
            val_Oe = val_T * 10000;
            rate_OePerSec = rate_TperMin * 10000 / 60;

            if this.SimulationMode
                disp("Setting PPMS field to " + num2str(val_Oe) + " Oe, at rate " + num2str(rate_OePerSec) + " Oe per s, " + string(Settings.ApproachMode) + ", " + string(Settings.FieldMode));
            end

            assert(~isempty(this.Interface), "PPMS:InterfaceEmpty", "PPMS interface object is empty - call Connect first?");
            this.Interface.SetField(val_Oe, rate_OePerSec, am, fm);
        end

        function SetTemperature(this, val_K, rate_KperMin, Settings)
            %Ramp the temperature to a new setpoint.
            %In a sequence, the next command waits until the temperature is
            %stable (IsTemperatureStable). The approach mode is a name-value
            %argument, e.g. `SetTemperature(10, 2, ApproachMode="NoOvershoot")`
            %
            %Inputs:
            %   val_K        - the setpoint, in K (1.9 to 350 K on the PPMS)
            %   rate_KperMin - ramp rate, in K/min (up to 20 K/min)
            %   ApproachMode - "FastSettle" (default) or "NoOvershoot"

            arguments
                this;
                val_K (1,1) double;
                rate_KperMin (1,1) double {mustBePositive};
                Settings.ApproachMode {mustBeMember(Settings.ApproachMode, ["FastSettle", "NoOvershoot"])} = "FastSettle";
            end

            %Quantum Design's TemperatureApproach codes. The default is the
            %PPMS's own (TEMP command, PPMS GPIB Commands Manual)
            switch(Settings.ApproachMode)
                case("FastSettle");     am = 0;
                case("NoOvershoot");    am = 1;
                otherwise
                    error("PPMS:InvalidApproachMode", "Invalid approach mode");
            end

            if this.SimulationMode
                disp("Setting PPMS temperature to " + num2str(val_K) + " K, at rate " + num2str(rate_KperMin) + " K per min, " + string(Settings.ApproachMode));
            end

            assert(~isempty(this.Interface), "PPMS:InterfaceEmpty", "PPMS interface object is empty - call Connect first?");
            this.Interface.SetTemperature(val_K, rate_KperMin, am);
        end

    end

    %% Methods (Private)
    methods(Access = private)

        function ppmsCommDir_Full = GetPPMSCommDirectory(this)
            %Find the PPMS Communication folder, which holds both .NET files.
            %It is in the user files folder's Instrument Drivers folder, which
            %Palladium sets on the instrument (InstrumentDriversDir). The
            %search path is only a fallback, for a PPMS made outside
            %Palladium - the compiled app can't add folders to it
            %
            %Outputs:
            %   ppmsCommDir_Full - full path of the folder

            ppmsCommDir_Full = "";
            if strlength(this.InstrumentDriversDir) > 0
                ppmsCommDir_Full = fullfile(this.InstrumentDriversDir, "Quantum Design", this.PPMSCommDirectory);
            end
            if ~isfolder(ppmsCommDir_Full)
                try
                    ppmsCommDir_Full = Palladium.Utilities.PathUtils.GetPathOfFolderOnSearchPath(this.PPMSCommDirectory);
                catch
                    ppmsCommDir_Full = "";  %Not on the path either - error below
                end
            end
            assert(isfolder(ppmsCommDir_Full), "PPMS:DriverDirectoryNotFound", "%s",...
                "Cannot find the PPMS driver folder. It should be at `" + fullfile("Instrument Drivers", "Quantum Design", this.PPMSCommDirectory) + "` in the Palladium user files folder - restarting Palladium creates it.");
        end

    end

    %% Methods (Static, Private)
    methods(Static, Access = private)

        function interfaceObj = ConnectToInterface(simulationMode, ppmsCommDir_Full, dllPath, ipAddress, portNumber)
            %Check both .NET files are present, load them, and create the interface object.
            %
            %Inputs:
            %   simulationMode   - true to connect to Quantum Design's simulated PPMS
            %   ppmsCommDir_Full - full path of the folder holding both .NET files
            %   dllPath          - file name of the interface .NET file, QDInterface.dll
            %   ipAddress        - address of the PPMS control PC
            %   portNumber       - port of its instrument server
            %
            %Outputs:
            %   interfaceObj - QDInterface.Controller .NET object

            arguments
                simulationMode      (1,1) logical;
                ppmsCommDir_Full    {mustBeTextScalar};     %Full path to the folder holding both dlls
                dllPath             {mustBeTextScalar};
                ipAddress           {mustBeTextScalar}  = "127.0.0.1";
                portNumber (1,1)    {mustBeInteger}     = 11000;
            end

            %Check that both dlls are there. The user has to download
            %QDInstrument.dll from Pharos themselves and place it in that
            %folder, as it is not freely distributable.
            %Messages are plain text: `backticks` show as code and web
            %addresses as links in Palladium's dialog boxes
            %(GUIUtils.MessageToHTML)
            assert(isfile(fullfile(ppmsCommDir_Full, "QDInterface.dll")), "PPMS:InterfaceDllMissing", "%s",...
                "Palladium's PPMS interface file `QDInterface.dll` is missing from:" + newline + "`" + string(ppmsCommDir_Full) + "`" + newline + newline +...
                "Restart Palladium, which copies it back in. If it is still missing, please contact the developer.");
            assert(isfile(fullfile(ppmsCommDir_Full, "QDInstrument.dll")), "PPMS:InstrumentDllMissing", "%s",...
                "Quantum Design's driver file `QDInstrument.dll` is not installed." + newline + newline +...
                "Quantum Design licence it, so it can't be included with Palladium. Download it from Quantum Design's Pharos site (you need an account): https://www.qdusa.com/pharos/" + newline + newline +...
                "Then put it in this folder, next to `QDInterface.dll`:" + newline + "`" + string(ppmsCommDir_Full) + "`" + newline + newline +...
                "See ""Setting up the PPMS"" in the Palladium help.");

            %Type of instrument to connect to - PPMS = 0, VersaLab = 1, DynaCool = 2, SVSM = 3
            instrType = 0;

            %Load the .NET assembly from its full path - it doesn't need to
            %be on the search path. .NET finds QDInstrument.dll, which
            %QDInterface.dll depends on, in the same folder
            NET.addAssembly(fullfile(ppmsCommDir_Full, dllPath));

            %Create an instance of the Controller object in the dll's
            %namespace
            interfaceObj = QDInterface.Controller(instrType, ipAddress, portNumber, simulationMode);
        end

    end

end
