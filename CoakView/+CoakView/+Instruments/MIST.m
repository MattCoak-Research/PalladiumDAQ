classdef MIST < CoakView.Core.Instrument
    %Instrument implementation for MIST

    properties(Constant, Access = public)
        FullName = 'MiST';       %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = 'MiST';                            %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.Ethernet;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
    
        SettlingTime_us = 500; % Microseconds
        DataRate_Hz = 200;  % Data rate, in Hertz
        Gain = [1000, 1000, 1000, 1000]; %Gain for the 4 channels (default = [1000 1000 1000 1000])
        Current_uA = [500, 500, 500, 500]; %Current for each channel, in microAmps. (Default [500 500 500 500])
        EnableChannels = [1, 0, 0, 0];  %1s or 0s as booleans to toggle measurement channels on or off
    end

    properties(Access = public)
        MiSTControlPanel = [];
    end

    properties(Access = private)
        DefaultDebugDriverFile = "Debug_MIST_Python_Polling_Driver";
        DefaultDriverFile = "MIST_Python_Polling_Driver";
        DriverFile;
        InfoJSON;
    end

    properties(Constant, Access = private)
        NUM_CHANNELS = 4;
    end

    methods

        %% Constructor
        function this = MIST()
            this.AddDriversToPythonPath();

            %Define the Instrument Controls that can be added 
            this.DefineInstrumentControl(Name = "MiST Control", ClassName = "MiSTController", TabName = "MiST Control", EnabledByDefault = true);       
        end

        %% Connect
        function Connect(this)
            switch(this.Connection_Type)
                case(CoakView.Enums.ConnectionType.Debug)
                    %Do not make a physical connection to a real instrument
                    %- this places the class into SimulationMode, for
                    %testing without a real piece of hardware connected
                    disp("Connecting to simulated " + this.Name + " instrument.");
                    this.SimulationMode = true;
                    this.DriverFile = this.DefaultDebugDriverFile;
                otherwise
                    this.DriverFile = this.DefaultDriverFile;
            end

            %Attempt to connect, with a timeout
            timeOut = 10;    %s
            this.DeviceHandle = this.ConnectMIST(timeOut);
        end

        %% Configure
        function Configure(this, Settings)
            arguments
                this;
                Settings.settlingTime (1,1) {mustBeInteger} = 500; % Microseconds
                Settings.dataRate (1,1) {mustBeInteger} = 200; % Hertz
                Settings.deviceIDs = {'PlaceholderID','PlaceholderID','PlaceholderID','PlaceholderID'}; %NB if the user is skipping channels (e.g. only enabling channels 0 and 3) intervening placeholder IDs (1 and 2) must be specified or IDs will be incorrectly assigned
                Settings.gain (1,4) {mustBeInteger} = [1000, 1000, 1000, 1000];
                Settings.current (1,4) {mustBeInteger} = [500, 500, 500, 500]; %Microamps
                Settings.enableChannels (1,4) {logical} = [1, 0, 0, 0];   %NB enabled channels are numbered with integers in range 0-3. enableChannels is NOT an array of booleans (true/false, 0/1 etc.(; to leave a channel disabled, simply do not put its number in this array.
            end

            %Error checking first
            assert(~isempty(this.DeviceHandle), "MiST not connected, call Connect() first");

            %Send command to python driver
            result = py.(this.DriverFile).configMiSTsettings(this.DeviceHandle,...
                int32(Settings.settlingTime),...
                int32(Settings.dataRate),...
                Settings.deviceIDs,...
                int32(Settings.gain),...
                int32(Settings.current),...
                Settings.enableChannels);

            % Parse JSON string into a nice MATLAB struct
            data = jsondecode(string(result));

            %Print config info:
            disp(data);

            this.InfoJSON = result;

            %update GUI if added
            if ~isempty(this.MiSTControlPanel)
                this.MiSTControlPanel.Initialise(this.Gain, this.EnableChannels, this.Current_uA);
            end
        end

        %% Close
        function Close(this)
            %This (so far) looks to be common behaviour across all instruments.
            %Can override this function in implementing class if more behaviour needed.
            switch(this.Connection_Type)
                case(CoakView.Enums.ConnectionType.Debug)
                    %Just print a message
                    disp("Disconnected from simulated " + this.Name + " instrument.");
                otherwise
                    this.DisableSync();
                    this.SendCommand('disconnectMiST');
            end
        end
        
        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
   
            Headers = [];
            Units = [];

            %Add a block of headers for each channel that is enabled
            for i = 1 : this.NUM_CHANNELS
                if this.ChannelEnabled(i)
                    Headers = [Headers,...
                        this.Name + " Ch" + num2str(i) +  " - mP0Avg",...
                        this.Name + " Ch" + num2str(i) + " - mP1Avg",...
                        this.Name + " Ch" + num2str(i) + " - mP2Avg",...
                        this.Name + " Ch" + num2str(i) + " - mP3Avg",...
                        this.Name + " Ch" + num2str(i) + " - mdataAvg",...
                        this.Name + " Ch" + num2str(i) + " - offstAvg",...
                        ];

                    Units = [Units,...
                        "V",...
                        "V",...
                        "V",...
                        "V",...
                        "V",...
                        "V",...
                        ];
                end
            end
           
        end

        %% GetSupportedConnectionTypes
        function connectionTypes = GetSupportedConnectionTypes(this)
            connectionTypes = [...
                CoakView.Enums.ConnectionType.Debug,...
                CoakView.Enums.ConnectionType.Ethernet
                ];
        end

        %% InitialiseMeasurements
        function InitialiseMeasurements(this)
            %Gets called automatically in OnInitialised, right after Connect, at programme start

            %Configure settings
            disp("Configuring MiST");
            this.Configure("current", this.Current_uA, "dataRate", this.DataRate_Hz, "enableChannels", this.EnableChannels, "gain", this.Gain, "settlingTime", this.SettlingTime_us);

            %Calibrate offsets
            this.CalibrateOffsets();

            %Turn on Spin
            disp("Enabling spin on MiST");
            this.SendCommand('enableSpin');

            %Turn on Sync
            disp("Enabling sync on MiST");
            this.EnableSync();

            disp("MiST Initialisation Complete");
        end

        %% Measure
        function [dataRow] = Measure(this)

            %Get last second of data from the MiST
            [mP0Avg, mP1Avg, mP2Avg, mP3Avg, mdataAvg, offstAvg] = this.PollData(this.InfoJSON);

            dataRow = [];
            saturationPercent = [nan nan nan nan];
            for i = 1 : this.NUM_CHANNELS
                if this.ChannelEnabled(i)
                        dataRow = [dataRow,...
                            double(mP0Avg(i)),...
                            double(mP1Avg(i)),...
                            double(mP2Avg(i)),...
                            double(mP3Avg(i)),...
                            double(mdataAvg(i)),...
                            double(offstAvg(i))...
                            ];

                        maxV = max([...
                            abs(double(mP0Avg(i))),...
                            abs(double(mP1Avg(i))),...
                            abs(double(mP2Avg(i))),...
                            abs(double(mP3Avg(i)))]);

                        saturationPercent(i) = 100 * maxV / 4.096;
                end
            end

            %Update the magnet control panel if one is added
            if ~isempty(this.MiSTControlPanel)
                this.MiSTControlPanel.UpdateDisplayedStatus(saturationPercent, this.EnableChannels);
            end
        end

        %% CalibrateOffsets
        function CalibrateOffsets(this)
            this.SendCommand('calibrateOffsets');
        end


        %% DisableChannel
        function DisableChannel(this, channelNo)
             arguments
                this;
                channelNo (1,1) {mustBeInteger};
             end

             this.SendCommand('disableChannel', int32(channelNo));
        end

        %% DisableSync
        function DisableSync(this, Settings)
            arguments
                this;
                Settings.SyncOut (1,1) logical = true;
            end

           % this.SendCommand('set_synchronisation', false, Settings.SyncOut);
            py.(this.DriverFile).set_synchronisation(this.DeviceHandle, false, Settings.SyncOut);
        end

        %% EnableChannel
        function EnableChannel(this, channelNo)
             arguments
                this;
                channelNo (1,1) {mustBeInteger};
             end

             this.SendCommand('enableChannel', int32(channelNo));
        end

        %% EnableSync
        function EnableSync(this, Settings)
             arguments
                this;
                Settings.SyncOut (1,1) logical = true;
             end

          %  this.SendCommand('set_synchronisation', true, Settings.SyncOut);
            py.(this.DriverFile).set_synchronisation(this.DeviceHandle, true, Settings.SyncOut);
        end

        %% StartMiST
        function StartMiST(this, spinningEnabled)
            arguments
                this;
                spinningEnabled (1,1) logical = true;
            end
            this.SendCommand('start_MiST', spinningEnabled);
        end

        %% RunMiST
        function RunMiST(this, duration, spinningEnabled)
            arguments
                this;
                duration (1,1) {mustBeInteger};
                spinningEnabled (1,1) logical = true;
            end

            %Runs the MiST for a specified duration only
            this.SendCommand('run_MiST', spinningEnabled, duration);
        end

        %% StopMiST
        function StopMiST(this, spinningEnabled)
            arguments
                this;
                spinningEnabled (1,1) logical = true;
            end
            this.SendCommand('stop_MiST', spinningEnabled);
        end

        %% SetSingleCurrentValue
        function SetSingleCurrentValue(this, index, current_uA)
            this.Current_uA(index) = current_uA;
            this.SetCurrents(this.Current_uA);
        end

        %% SetSingleGainValue
        function SetSingleGainValue(this, index, gain)
            this.Gain(index) = gain;
            this.SetGainValues(this.Gain);
        end

        %% SetCurrents
        function SetCurrents(this, currentsArray_muA)
             arguments
                this;
                currentsArray_muA (1,4) {mustBeInteger};
             end

             newVals = this.SendQuery('setCurrent', int32(currentsArray_muA));
             this.Current_uA = CoakView.Instruments.MIST.ConvertIntTuple(newVals{1});
        end

        %% SetGainValues
        function SetGainValues(this, gainValuesArray)
             arguments
                this;
                gainValuesArray (1,4) {mustBeInteger};
             end

             newVals = this.SendQuery('setGainValues', int32(gainValuesArray));
             this.Gain = CoakView.Instruments.MIST.ConvertIntTuple(newVals{1});
        end

    end

    methods(Access = protected)
  
        %% GetPropertiesToIgnore
        function propertiesToIgnore = GetPropertiesToIgnore(this)
            %MIST does not connect in the usual way, hide these connection options in the GUI as they are not used..
            propertiesToIgnore = {"IP_Address"};
        end

        %% OnInitialised
        function OnInitialised(this)
            %This gets called right after Connect, at programme start
            this.InitialiseMeasurements();
        end

    end

    methods(Access = private)

        %% AddDriversToPythonPath
        function AddDriversToPythonPath(this)
            %Ok we need to do this properly..
            %Should probably be a static CoakView util even (other
            %instruments could have python drivers)


            %Firstly, build the path to the Instrument drivers folder, relative to this
            %one (Assuming this is in +Instruments)
            pathOfThisClassFile = fileparts(mfilename('fullpath'));
            parts = strsplit(pathOfThisClassFile, filesep);
            pathOfMainFolder = strjoin(parts(1:end-2), filesep);
            pathOfInstrumentDriversFolder = pathOfMainFolder + "\Instrument Drivers";
            pathOfThisInstrumentDriversFolder = pathOfInstrumentDriversFolder + "\Paragraf MIST";

            %This looks to see if a folder is added to the python search
            %path and inserts it if not.
            dirPath = pathOfThisInstrumentDriversFolder;
            if count(py.sys.path,dirPath) == 0
                insert(py.sys.path,int32(0),dirPath);
            end

            %This.. should just do the same as above? Is the above needed?
            CoakView.Utilities.PythonUtils.PythonUtils.AppendFolderToPythonPath(pathOfThisInstrumentDriversFolder);
        end

        %% ChannelEnabled
        function enabledBool = ChannelEnabled(this, chIndex)
            if this.EnableChannels(chIndex)
                enabledBool = true;
            else
                enabledBool = false;
            end
        end

        %% ConnectMIST
        function deviceHandle = ConnectMIST(this, timeOut)
            arguments
                this;
                timeOut (1,1) double;
            end

            %Attempt to connect. returns -1 after timeout if no instrument
            %found
            result = py.(this.DriverFile).connect(int32(timeOut));

            %Cast python int object to MATLAB one
            castResult = int32(result);

            %Handle failure to connect
            if castResult == -1
                error("Failed to connect to a MiST via the discovery service. Operation timed out.")
            end

            %Life is good, assign handle (keep it a python int) and continue
            deviceHandle = result;

            %Display message to say connection worked
            disp("MiST Connected, ID " + num2str(int32(deviceHandle)));
        end    

        %% PollData
        function [mP0Avg, mP1Avg, mP2Avg, mP3Avg, mdataAvg, offstAvg] = PollData(this, infoJSON)
            %Call the pollMiST function within the selected python driver
            result = py.(this.DriverFile).pollMiST(infoJSON);
            c = cell(result);

            %Unpack the result, stored in a tuple of lists
            mP0Avg = CoakView.Instruments.MIST.ConvertTuple(c{1});
            mP1Avg = CoakView.Instruments.MIST.ConvertTuple(c{2});
            mP2Avg = CoakView.Instruments.MIST.ConvertTuple(c{3});
            mP3Avg = CoakView.Instruments.MIST.ConvertTuple(c{4});
            mdataAvg = CoakView.Instruments.MIST.ConvertTuple(c{5});
            offstAvg = CoakView.Instruments.MIST.ConvertTuple(c{6});
        end

        %% SendCommand
        function SendCommand(this, command, varargin)
            if isempty(varargin)
                py.(this.DriverFile).(command)(this.DeviceHandle);
            else
                py.(this.DriverFile).(command)(this.DeviceHandle, varargin);
            end
        end

        %% SendQuery
        function varout = SendQuery(this, command, varargin)
            if isempty(varargin)
                varout = py.(this.DriverFile).(command)(this.DeviceHandle);
            else
                varout = py.(this.DriverFile).(command)(this.DeviceHandle, varargin);
            end
        end

    end

    methods (Access = private, Static)

        %% ConvertTuple
        function doubleOut = ConvertTuple(pythonTupleIn)
            %A try/catch for this is so dirty! Google said do isa
            %'py.NoneType', but this didn't work (it's a single element
            %list of NoneTypes?). Fix this properly later.
            for i = 1 : length(pythonTupleIn)
                try
                    doubleOut(i) = double(pythonTupleIn(i));
                catch
                    doubleOut(i) = nan;
                end
            end
        end

        %% ConvertIntTuple
        function intOut = ConvertIntTuple(pythonTupleIn)
            %A try/catch for this is so dirty! Google said do isa
            %'py.NoneType', but this didn't work (it's a single element
            %list of NoneTypes?). Fix this properly later.
            for i = 1 : length(pythonTupleIn)
                try
                    intOut(i) = int32(pythonTupleIn(i));
                catch
                    intOut(i) = nan;
                end
            end
        end
    end

end

