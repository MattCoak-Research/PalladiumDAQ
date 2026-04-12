classdef PPMS < Palladium.Core.Instrument
    %Instrument implementation for communicating with a Quantum Design PPMS
    %croystat. This assumes the PPMS control PC is a separate machine to
    %the one running this, and they have a direct network link.
    %This uses the Quantum Design/PPMS Communication drivers library, which
    %has C# dll wrappers to allow MATLAB to interface with the QD server
    %Note that currently there is no way to UNload .NET assemblies in
    %MATLAB, but this is not a practical issue in this version of the code.

    %% Properties (Constant, Public)
    properties(Constant, Access = public)
        FullName = 'PPMS';                                          %Full name, just for displaying on GUI
    end

    %% Properties (Constant, Private)
    properties(Constant, Access = private)
        InterfacePath = "QDInterface.dll";
        PPMSCommDirectory = "PPMS Communication";
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'PPMS';                                              %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.Ethernet;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        RotatorInstalled = false;                                   %Set to true if using rotation option - rotation angle will be logged
    end

    %% Properties (Private)
    properties(Access = private)
        Interface;
    end

    %% Constructor
    methods
        function this = PPMS()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "Ethernet"]);
            this.IP_Address = "127.0.0.1";
            this.ConnectionSettings.Port = 11000;
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function Close(this)
            delete(this.Interface);
            this.Interface = [];
        end

        function Connect(this)
            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    disp("Connecting to simulated " + this.Name + " instrument...");
                    this.SimulationMode = true;
                    this.Interface = this.ConnectToInterface(true, this.PPMSCommDirectory,this.InterfacePath);
                    disp("Connected to simulated " + this.Name);

                case(Palladium.Enums.ConnectionType.Ethernet)
                    disp("Connecting to " + this.Name + " instrument.");
                    this.SimulationMode = false;
                    this.Interface = this.ConnectToInterface(false, this.PPMSCommDirectory, this.InterfacePath, this.IP_Address, this.ConnectionSettings.Port);
                    disp("Connected to " + this.Name + " instrument.");

                otherwise
                    error("Unsupported connection type on PPMS: " + this.Connection_Type);
            end
        end

        function B_T = GetField(this)
            assert(~isempty(this.Interface), "PPMS interface object is empty - call Connect first?");
            B_Oe = this.Interface.GetField();
            B_T = B_Oe / 10000;
        end

        function [Headers, Units] = GetHeaders(this)
            %Gets the column headers for data columns returned by this
            %instrument. There must be the same number as Measure returns.
            Headers = [this.Name + " - Temperature_K", this.Name + " - Field_T"];
            Units = ["K", "T"];

            if this.RotatorInstalled
                Headers(end + 1) = this.Name + " - Rotator_Position_Deg";
                Units(end + 1) = "Deg";
            end
        end

        function val = GetMapValue(this, channel)
            arguments
                this;
                channel (1,1) mustBeInteger;
            end

            assert(~isempty(this.Interface), "PPMS interface object is empty - call Connect first?");
            val = this.Interface.GetMapValue(channel);
        end

        function pos_Deg = GetRotatorPosition(this)
            assert(~isempty(this.Interface), "PPMS interface object is empty - call Connect first?");
            %pos_Deg = this.Interface.GetRotatorPosition();     %See
            %comments in the DLL source - GetRotatorPosition doesn't work
            %in there... or in Quantum Design's supplied example (!). THe
            %rotation angle is found, in testing, to be stored in generic
            %channel 3 however, so just grab that. This might break on
            %newer PPMS devices? Will want testing on hardware and dialogue
            %with QD to make more robust going forward
            pos_Deg = this.Interface.GetMapValue(3);
        end

        function T_K = GetTemperature(this)
            assert(~isempty(this.Interface), "PPMS interface object is empty - call Connect first?");
            T_K = this.Interface.GetTemperature();
        end

        function [dataRow] = Measure(this)

            field_T = this.GetField();
            temp_K = this.GetTemperature();

            dataRow = [temp_K, field_T];

            %Add rotation angle if rotator in use
            if this.RotatorInstalled
                dataRow(end + 1) = this.GetRotatorPosition();
            end
        end

    end

    %% Methods (Static, Private)
    methods(Static, Access = private)

        function interfaceObj = ConnectToInterface(simulationMode, ppmsCommDir, dllPath, ipAddress, portNumber)
            arguments
                simulationMode      (1,1) logical;
                ppmsCommDir         {mustBeTextScalar};
                dllPath             {mustBeTextScalar};
                ipAddress           {mustBeTextScalar}  = "127.0.0.1";
                portNumber (1,1)    {mustBeInteger}     = 11000;
            end

            %Get full path to the folder - if it is on the MATLAB search
            %path, otherwise will return empty
            ppmsCommDir_Full = Palladium.Utilities.PathUtils.GetPathOfFolderOnSearchPath(ppmsCommDir);

            %Check the driver folder is there
            assert(~isempty(ppmsCommDir_Full), "Cannot find PPMS Communication driver directory - check installation and that folders are added to the search path (Instrument Drivers may be packaged separately)");
            assert(isfolder(ppmsCommDir_Full), "Cannot find PPMS Communication driver directory - check installation and that folders are added to the search path (Instrument Drivers may be packaged separately)");

            %Check that the QD Instrument.dll file is there. User has to
            %download that from Pharos themselves and place it in that
            %folder, as it is not freely distributable
            assert(exist(fullfile(ppmsCommDir_Full, "QDInterface.dll"), "File") == 2,...
                "The built-in QDInterface.dll file is missing from the User Files directory. Restart Palladium and if this issue persists please contact the developer - this suggests something has gone wrong.");
            assert(exist(fullfile(ppmsCommDir_Full, "QDInstrument.dll"), "File") == 2,...
                "The driver file QDInstrument.dll is missing from the User Files directory. \n\nThis has to be installed manually by the end user as Quantum Design own the rights to it - it cannot be distributed as part of Palladium. This file can be downloaded from Quantum Design's Pharos file management site (requires creating an account).\n\n Once downloaded please place in:\n "+...
                string(strrep(ppmsCommDir_Full, '\', '\\')) + "\n - there should already be a file in there called QDInterface.dll, which is a built in Palladium wrapper to the expected QDInstrument driver. \n\nNote that the QD Instrument Server must be running on the target PPMS PC for this to then work - see documentation on Pharos when downloading the driver.");

            %Type of instrument to connect to - PPMS = 0, VersaLab = 1, DynaCool = 2, SVSM = 3
            instrType = 0;

            %Add the .NET namespace to the MATLAB search path
            NET.addAssembly(ppmsCommDir_Full + "\" + dllPath);

            %Create an instance of the Controller object in the dll's
            %namespace
            interfaceObj = QDInterface.Controller(instrType, ipAddress, portNumber, simulationMode);
        end

    end

end

