classdef ZI_MFLI < Palladium.Core.Instrument
    %ZI_MFLI - Instrument driver for the Zurich Instruments MFLI 500 kHz / 5 MHz lock-in amplifier.
    %Each measurement tick reads the latest sample of demodulator 1, as X and
    %Y or as amplitude R and phase (set by `MeasurementMode`), plus the
    %signal output level and the oscillator frequency. With a current
    %source on the signal output (`ConnectedCurrentSource`), the output is
    %logged as a current and a resistance column is added. The MFLI Sweep
    %Control tab runs the instrument's own Sweeper (frequency, amplitude,
    %Aux Output 1 or output offset), and the public methods give scripts
    %access to most demodulator, input, output, scope and Data Acquisition
    %settings.
    %
    %The MFLI is not controlled by SCPI: the driver talks to a LabOne Data
    %Server through Zurich Instruments' LabOne MATLAB API (`ziDAQ`), which
    %must be installed and on the MATLAB path. The instrument is identified
    %by `DeviceID` (e.g. "DEV7779"); Ethernet and USB both connect through
    %the Data Server running on this PC (localhost, port 8004), which
    %allows several MFLIs to be connected at once.
    %
    %Setup notes:
    %
    %* Install LabOne fully on the PC from the downloadable installer - not
    %  only the web interface served by the instrument - so the Data Server
    %  runs on the PC (see "Running LabOne on a Separate PC" in the MFLI
    %  manual).
    %* When first opening LabOne in the browser, select Local Data Servers
    %  in the device list before opening the instrument. Otherwise the
    %  instrument's internal Data Server claims it, it shows as In Use and
    %  usually needs a power cycle before this driver can connect. LabOne
    %  remembers the choice.
    %* LabOne can stay open in the browser alongside Palladium, and is the
    %  place for detailed settings - this driver does not duplicate them.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Zurich Instruments MFLI";                           %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = 'ZI MFLI';                                               %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.Ethernet;      %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        DeviceID string = "DEV7779";                                    %LabOne device ID of the instrument, e.g. "DEV7779", as shown in LabOne and on the rear panel
        ConnectedCurrentSource categorical;                             %Voltage-to-current converter on the signal output, if any - output is then logged as a current, and a resistance column is added
        AmplifierGain (1,1) double = 1;                                 %Gain of any external amplifier or transformer on the measured signal, used in the resistance calculation
        MeasurementMode categorical;                                    %What to log from demodulator 1: X and Y, or amplitude R and phase
    end

    %% Categoricals
    methods
        function catOut = CurrentSource(this, inputStr);    catOut = this.ConvertToCategorical(inputStr, ["None", "200 uA/V"]); end
        function catOut = MeasType(this, inputStr);         catOut = this.ConvertToCategorical(inputStr, ["Voltage XY", "Voltage RTheta", "Current"]); end
    end

    %% Constructor
    methods
        function this = ZI_MFLI()
            %Set the supported connection types, default settings and the Sweep Control tab.

            this.DefineSupportedConnectionTypes(["Debug", "Ethernet", "USB"]);
            this.ConnectedCurrentSource = this.CurrentSource("200 uA/V");
            this.MeasurementMode = this.MeasType("Voltage RTheta");

            %Define the Instrument Controls that can be added
            this.DefineInstrumentControl(Name = "MFLI Sweep Control", ClassName = "MFLI_SweepController", TabName = "MFLI Sweep Control", EnabledByDefault = true);
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function AddAuxInput(this, sigoutIndex)
            %Add the signal on Aux Input 1 to a signal output (the output's Add switch).
            %Used to put a DC offset from Aux Output 1, looped back into Aux
            %Input 1, onto the signal output
            %
            %Inputs:
            %   sigoutIndex - signal output index, 0 for Signal Output 1 (default)

            arguments
                this; sigoutIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigouts/' num2str(sigoutIndex) '/add'], 1); % turned on
        end

        function AllowDemodToSettle(this, demodIndex)
            %Wait for a demodulator's output to settle to 99% of its final value.
            %Waits a number of filter time constants that depends on the filter
            %order (Table 6.2 of the MFLI user manual); sends no commands while
            %waiting
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)

            arguments
                this ;
                demodIndex (1,1) double = 0;
            end
            filterOrder = this.GetFilterOrder(demodIndex);
            tc = this.GetTimeConstant(demodIndex);

            %Wait for n time constants, dependent on filter order, for
            %reading to settle to 99% of final value. See p297 of MFLI
            %user manual
            switch(filterOrder)
                case(1);    waitTime = tc * 4.6;
                case(2);    waitTime = tc * 6.6;
                case(3);    waitTime = tc * 8.4;
                case(4);    waitTime = tc * 10;
                case(5);    waitTime = tc * 12;
                case(6);    waitTime = tc * 12;
                case(7);    waitTime = tc * 15;
                case(8);    waitTime = tc * 16;
                otherwise
                    error("MFLI_AllowDemodToSettle_Error:UnsupportedFilterOrder", 'Unsupported filter order');
            end

            pause(waitTime);
        end

        function AutoRangeInput(this, siginIndex)
            %Set the input range automatically, to about twice the measured input amplitude.
            %Applies to whichever of Signal Input 1 or Current Input 1 is the
            %source of demodulator 1
            %
            %Inputs:
            %   siginIndex - input index, 0 (default) - the MFLI has one of each

            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            channelName = this.GetSignalSource();
            channelIdx = this.ConvertInputChannelNameToChannelIndex(channelName);

            if channelIdx == 0
                this.SetInt(['/sigins/' num2str(siginIndex) '/autorange'], 1); % turn on
            elseif channelIdx == 1
                this.SetInt(['/currins/' num2str(siginIndex) '/autorange'], 1); % turn on
            else
                error("MFLI_AutoRangeInput_Error:InvalidInputChannel", "AutoRange can only be turned on for Signal Input 1 and Current Input 1")
            end
        end

        function AutoRangeOutput(this, sigoutIndex)
            %Turn on automatic range selection for a signal output.
            %It stays on until turned off; SetRangeOutput turns it off before
            %setting a range
            %
            %Inputs:
            %   sigoutIndex - signal output index, 0 for Signal Output 1 (default)

            arguments
                this; sigoutIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigouts/' num2str(sigoutIndex) '/autorange'], 1); % turn on
        end

        function metadataStruct = CollectMetaData(this)
            %Main demodulator, input and output settings, recorded in the data-file header.
            %
            %Outputs:
            %   metadataStruct - struct of the device ID, demodulator 1 filter
            %   order and time constant, oscillator 1 frequency, and the Signal
            %   Input 1 and Signal Output 1 settings, read from LabOne

            if(this.SimulationMode)
                metadataStruct.Placeholder = "Simulated instrument - placeholder metadata";
                return;
            end

            %Poll the instrument for all its settings.
            zi_Params = this.GenerateFullSettingsSaveStruct();

            %Pull them out neatly here - extend this as required
            metadataStruct.DeviceID = this.DeviceID;
            metadataStruct.FilterOrder = zi_Params.demods(1).order.value;
            metadataStruct.Frequency_Hz = zi_Params.oscs(1).freq.value;
            metadataStruct.SignalIn_AC_ = zi_Params.sigins(1).ac.value;
            metadataStruct.SignalIn_Diff_ = zi_Params.sigins(1).diff.value;
            metadataStruct.SignalIn_Float_ = zi_Params.sigins(1).float.value;
            metadataStruct.SignalIn_Imp50_ = zi_Params.sigins(1).imp50.value;
            metadataStruct.SignalIn_Range_ = zi_Params.sigins(1).range.value;
            metadataStruct.SignalIn_Scaling_ = zi_Params.sigins(1).scaling.value;
            metadataStruct.SignalOut_Amplitude_V = zi_Params.sigouts(1).amplitudes(2).value.value;
            metadataStruct.SignalOut_Diff_Enabled_ = zi_Params.sigouts(1).diff.value;
            metadataStruct.SignalOut_SineComponentEnabled_ = zi_Params.sigouts(1).enables(2).value.value;
            metadataStruct.SignalOut_Imp50_Enabled_ = zi_Params.sigouts(1).imp50.value;
            metadataStruct.SignalOut_Offset = zi_Params.sigouts(1).offset.value;
            metadataStruct.SignalOut_On = zi_Params.sigouts(1).on.value;
            metadataStruct.TimeConstant_s = zi_Params.demods(1).timeconstant.value;
        end

        function ClearDAQ(~)
            %Reset the whole LabOne MATLAB API, disconnecting all Data Servers.
            %This disconnects every Zurich Instruments device in this MATLAB
            %session, not only this one

            clear ziDAQ;
        end

        function Close(this)
            %Leave the device connected to the Data Server, so LabOne and other MFLIs are unaffected.
            %Disconnecting the device would also close it in the LabOne web
            %interface, so nothing is sent to the instrument

            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    %Just print a message
                    disp("Disconnected from simulated " + this.Name + " instrument.");
                otherwise
                    %Disconnect from the actual device, rather than clearing the
                    %whole ziDAQ setup (which would mess up other MFLIs that might
                    %be connected)
                    %   ziDAQ('disconnectDevice', this.DeviceID); %do we
                    %   actually need to do this? Disconnecting it closes the
                    %   LabOne window which is pretty annoying..
            end
        end

        function Connect(this)
            %Open the connection through the LabOne Data Server running on this PC.
            %Ethernet and USB both connect to the local Data Server (which
            %reaches the instrument over either), so several MFLIs can be
            %connected at once. Debug connects to a simulated instrument

            %Make sure DeviceID is a string, and do some error
            %checking/verification
            this.DeviceID = string(this.DeviceID);
            assert(startsWith(this.DeviceID, "DEV"), "MFLI_Connect_Error:InvalidDeviceID", "%s", "Invalid Device ID:" + newline + string(this.DeviceID) + newline + "in MFLI connect. Device ID must start with ""DEV"" - form is DEV123, as a string");

            switch(this.Connection_Type)
                case(Palladium.Enums.ConnectionType.Debug)
                    %Do not make a physical connection to a real instrument
                    %- this places the class into SimulationMode, for
                    %testing without a real piece of hardware connected
                    disp("Connecting to simulated " + this.Name + " instrument....");
                    pause(0.3);
                    disp("Connected to simulated " + this.Name + " instrument.");
                    this.SimulationMode = true;

                case(Palladium.Enums.ConnectionType.Ethernet)
                    %Connect to instrument via ZI Matlab API
                    this.DeviceHandle = this.ZIConnect(this.DeviceID, '1GbE');

                case(Palladium.Enums.ConnectionType.USB)
                    %Connect to instrument via ZI Matlab API
                    this.DeviceHandle = this.ZIConnect(this.DeviceID, '1GbE'); %Don't tell it USB, keep it 1GbE instead - we actually connect to the dataserver on LocalHost (to allow connecting multiple instruments) - so USB errors out, even if the device is connected to the dataserver by USB. Let's hide the user from this, stop them panicking that USB is not a supported option

                otherwise
                    error("MFLI_Connect_Error:UnsupportedConnectionType", "%s", "Unsupported connection type: " + string(this.Connection_Type));
            end

        end

        function DAQHandle = DAQ_Initialise_Both(this, DemodSignal, demodIndex)
            %Set up a Data Acquisition Module recording of a demodulator signal in time and frequency.
            %Records the time trace and its FFT together, on a trigger from the
            %demodulator's R. Run it with DAQ_Execute_Both
            %
            %Inputs:
            %   DemodSignal - signal to record: 'X', 'Y', 'R' or 'Phase'
            %   demodIndex  - demodulator index, 0 for Demodulator 1 (default)
            %
            %Outputs:
            %   DAQHandle - handle of the Data Acquisition Module, empty in simulation

            arguments
                this;
                DemodSignal  {mustBeText};  % 'X','Y','R','Phase', 'XiY'
                demodIndex (1,1) double = 0;
            end

            if(this.SimulationMode)
                disp('Set up simulated MFLI DAQ');
                DAQHandle = []; % define empty DAQHandle
                return;
            end

            [demod_path_time, ~, ~] = this.DemodPath_Time(DemodSignal);
            [demod_path_freq, ~, ~] = this.DemodPath_FFT(DemodSignal);

            % create a handle for the dataAcquisitionModule
            DAQHandle = ziDAQ('dataAcquisitionModule');
            % device on which dataAcquisitionModule will be performed
            ziDAQ('set', DAQHandle, 'device', this.DeviceHandle);

            % 4 = exact grid mode is chosen - this is most suitable for FFTs
            % the subscribed signal with the highest sampling rate (as sent from the device) defines
            % the interval between samples on the DAQ Module's grid.
            ziDAQ('set', DAQHandle, 'grid/mode', 4);
            % specify the number of columns in the returned data grid. Data along horizontal grid is
            % resampled to number of samples defined by grid/cols.
            % number of bins =  2^bits
            ziDAQ('set', DAQHandle, 'grid/cols', 2^16);

            % subcribe to time node
            ziDAQ('subscribe', DAQHandle, demod_path_time);
            % subcribe to frequency node
            ziDAQ('subscribe', DAQHandle, demod_path_freq);

            % set the trigger node as the demodulated signal R
            ziDAQ('set', DAQHandle, 'triggernode', ['/' this.DeviceHandle '/demods/' num2str(demodIndex) '/sample.r']);
            % return preview - useful to display the progress of high resolution FFTs
            % that take a long time to capture. Successively higher resolution FFTs are calculated and returned.
            ziDAQ('set', DAQHandle, 'preview', 1);

            triggerpath = ['/' this.DeviceHandle '/demods/0/sample'];
            triggernode = [triggerpath '.r'];
            % The dots in the signal paths are replaced by underscores in the data returned by MATLAB to
            % prevent conflicts with the MATLAB syntax.
            ziDAQ('set', DAQHandle, 'triggernode', triggernode);

            ziDAQ('subscribe', DAQHandle, triggernode);

            % enable the dataAcquisitionModule's module.
            ziDAQ('set', DAQHandle, 'enable', 1);
        end

        function [daqData_time, daqData_freq] = DAQ_Execute_Both(this, DemodSignal, DAQHandle, time)
            %Run a recording set up by DAQ_Initialise_Both and return the time and frequency data.
            %Finds the trigger level automatically first
            %
            %Inputs:
            %   DemodSignal - signal to record, as given to DAQ_Initialise_Both
            %   DAQHandle   - handle returned by DAQ_Initialise_Both
            %   time        - timeout, in s, for finding the trigger level and for the recording (default 3)
            %
            %Outputs:
            %   daqData_time - LabOne data struct, with fields Amplitude and Time (in s) added
            %   daqData_freq - LabOne data struct, with fields Amplitude and bandwidth (in Hz) added

            arguments
                this;
                DemodSignal {mustBeText};  % 'X','Y','R','Phase', 'XiY'
                DAQHandle;
                time (1,1) double = 3;
            end

            if(this.SimulationMode)
                daqData_time.Time = linspace(0, 5, 2^16);
                daqData_time.Amplitude = this.GenerateSimulatedData(2^16, Baseline=1e-4, Variance=3e-6);
                daqData_freq.Amplitude = this.GenerateSimulatedData(2^16/2 + 1, Baseline=1e-4, Variance=3e-6);
                daqData_freq.bandwidth = 100;
                return
            end

            % enable the dataAcquisitionModule's module.
            ziDAQ('set', DAQHandle, 'enable', 1);

            % Tell the Data Acquisition Module to determine the trigger level.
            ziDAQ('set', DAQHandle, 'findlevel', 1);
            findlevel = 1;
            timeout = time;  % [s]
            t0 = tic;
            while (findlevel == 1)
                pause(0.05);
                findlevel = ziDAQ('getInt', DAQHandle, 'findlevel');
                if toc(t0) > timeout
                    ziDAQ('finish', DAQHandle);
                    error("MFLI_DAQ_Execute_Both_Error:TriggerLevelNotFound", 'Data Acquisition Module didn''t find a trigger level after %.3f seconds.\n', timeout)
                end
            end

            level = ziDAQ('getDouble', DAQHandle, 'level');
            hysteresis = ziDAQ('getDouble', DAQHandle, 'hysteresis');
            fprintf('Found and set level: %.3e, hysteresis: %.3e\n', level, hysteresis);

            [~, demod_path_us_time, path_time] = this.DemodPath_Time(DemodSignal);

            [~, demod_path_us_freq, path_freq] = this.DemodPath_FFT(DemodSignal);

            % clock of instument - needed to obtain time in seconds
            clockbase = double(this.GetInt('/clockbase'));

            timeout = time; % 60s - progress almost get to about 100%
            t0 = tic; % start matlab stopwatch timer

            % read intermediate data until the dataAcquisitionModule has finished.
            while ~ziDAQ('finished', DAQHandle)
                pause(0.1);

                if toc(t0) > timeout
                    disp(['dataAcquisitionModule stopped after' num2str(timeout) 'seconds.'])
                    break
                end
            end

            % Read and process any remaining data returned by read().
            tmp = ziDAQ('read', DAQHandle);

            daqData_time = this.Scope_AssembleData_Time(tmp, demod_path_us_time, path_time, clockbase);

            daqData_freq = this.Scope_AssembleData_FFT(tmp, demod_path_us_freq, path_freq);

            ziDAQ('set', DAQHandle, 'enable', 0);

        end

        function DAQHandle = DAQ_Initialise_Time(this, DemodSignal, GridColumns)
            %Set up a continuous Data Acquisition Module recording of a demodulator signal in time.
            %Run it with DAQ_Execute_Time
            %
            %Inputs:
            %   DemodSignal - signal to record: 'X', 'Y', 'R', 'Phase', or 'XiY' for X and Y together
            %   GridColumns - number of samples in the recording (default 2^16)
            %
            %Outputs:
            %   DAQHandle - handle of the Data Acquisition Module, empty in simulation

            arguments
                this;
                DemodSignal  {mustBeText};  % 'X','Y','R','Phase', 'XiY'
                GridColumns = 2^16;
            end

            if(this.SimulationMode)
                disp('Set up simulated MFLI DAQ');
                DAQHandle = []; % define empty DAQHandle
                return;
            end

            if strcmp(DemodSignal,"XiY")
                [demod_path_time_x, ~, ~] = this.DemodPath_Time("X");
                [demod_path_time_y, ~, ~] = this.DemodPath_Time("Y");
            else
                [demod_path_time, ~, ~] = this.DemodPath_Time(DemodSignal);
            end

            % create a handle for the dataAcquisitionModule
            DAQHandle = ziDAQ('dataAcquisitionModule');
            % device on which dataAcquisitionModule will be performed
            ziDAQ('set', DAQHandle, 'dataAcquisitionModule/device', this.DeviceHandle);

            % 4 = exact grid mode is chosen - this is most suitable for FFTs
            % the subscribed signal with the highest sampling rate (as sent from the device) defines
            % the interval between samples on the DAQ Module's grid.
            ziDAQ('set', DAQHandle, 'dataAcquisitionModule/grid/mode', 4);
            % specify the number of columns in the returned data grid. Data along horizontal grid is
            % resampled to number of samples defined by grid/cols.
            % number of bins =  2^bits
            ziDAQ('set', DAQHandle, 'dataAcquisitionModule/grid/cols', GridColumns);

            % 0 = continuous acquisition (trigger off)
            ziDAQ('set',DAQHandle,'dataAcquisitionModule/type',0);

            % subcribe to time node
            if strcmp(DemodSignal,"XiY")
                ziDAQ('subscribe', DAQHandle, demod_path_time_x);
                ziDAQ('subscribe', DAQHandle, demod_path_time_y);
            else
                ziDAQ('subscribe', DAQHandle, demod_path_time);
            end
        end

        function daqData_time = DAQ_Execute_Time(this, DemodSignal, DAQHandle)
            %Run a recording set up by DAQ_Initialise_Time and return the time-domain data.
            %
            %Inputs:
            %   DemodSignal - signal to record, as given to DAQ_Initialise_Time
            %   DAQHandle   - handle returned by DAQ_Initialise_Time
            %
            %Outputs:
            %   daqData_time - LabOne data struct, with fields Amplitude and Time (in s)
            %                  added. For 'XiY', a 2-element struct array of X then Y

            arguments
                this;
                DemodSignal {mustBeText};  % 'X','Y','R','Phase', 'XiY'
                DAQHandle;
            end

            if(this.SimulationMode)
                daqData_time.Time = linspace(0, 5, 2^16); %rand([2^16,1]);
                daqData_time.Amplitude = this.GenerateSimulatedData(2^16, Baseline=1e-4, Variance=3e-6);
                return
            end

            if strcmp(DemodSignal,"XiY")
                [~, demod_path_us_time_x, path_time_x] = this.DemodPath_Time("X");
                [~, demod_path_us_time_y, path_time_y] = this.DemodPath_Time("Y");
            else
                [~, demod_path_us_time, path_time] = this.DemodPath_Time(DemodSignal);
            end
            % clock of instument - needed to obtain time in seconds
            clockbase = double(this.GetInt('/clockbase'));


            ziDAQ('set', DAQHandle, 'enable', 1);
            buffer_size = ziDAQ('getDouble', DAQHandle, 'dataAcquisitionModule/buffersize');
            pause(buffer_size * 2.0);

            ziDAQ('sync');
            ziDAQ('execute', DAQHandle);
            while ~ziDAQ('finished', DAQHandle)
                pause(0.05);
            end

            tmp = ziDAQ('read', DAQHandle);
            ziDAQ('finish', DAQHandle);

            if strcmp(DemodSignal,"XiY")
                daqData_time_x = this.Scope_AssembleData_Time(tmp, demod_path_us_time_x, path_time_x, clockbase);
                daqData_time_y = this.Scope_AssembleData_Time(tmp, demod_path_us_time_y, path_time_y, clockbase);
                daqData_time = [daqData_time_x;daqData_time_y];
            else
                daqData_time = this.Scope_AssembleData_Time(tmp, demod_path_us_time, path_time, clockbase);
            end

            ziDAQ('set', DAQHandle, 'enable', 0);

        end

        function Disable50ImpedIn(this, siginIndex)
            %Set Signal Input 1 to its high (10 MOhm) input impedance.
            %
            %Inputs:
            %   siginIndex - signal input index, 0 for Signal Input 1 (default)

            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigins/' num2str(siginIndex) '/imp50'], 0); % turn off
        end

        function Disable50ImpedOut(this, sigoutIndex)
            %Set a signal output's load impedance to high impedance (HiZ), from 50 Ohm.
            %
            %Inputs:
            %   sigoutIndex - signal output index, 0 for Signal Output 1 (default)

            arguments
                this; sigoutIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigouts/' num2str(sigoutIndex) '/imp50'], 0); % turn off
        end

        function DisableAmplitude(this, channelName)
            %Turn off the sine amplitude of a signal output, leaving any DC offset.
            %
            %Inputs:
            %   channelName - 'SignalOutput1' (default; the only signal output)

            arguments
                this; channelName string = 'SignalOutput1'; % set default
            end
            if(this.SimulationMode); return; end
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);
            % Only one output amplitude /1
            this.SetInt(['/sigouts/' num2str(channelIdx) '/enables/1'], 0)
        end

        function DisableAC(this, siginIndex)
            %Set Signal Input 1 to DC coupling.
            %
            %Inputs:
            %   siginIndex - signal input index, 0 for Signal Input 1 (default)

            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigins/' num2str(siginIndex) '/ac'], 0); % turn off
        end

        function DisableAuxOut(this, channelName)
            %Set an Aux Output to 0 V, by zeroing its offset, scale and pre-offset.
            %The Aux Outputs have no off state
            %
            %Inputs:
            %   channelName - 'Aux1', 'Aux2', 'Aux3' or 'Aux4'

            arguments
                this;
                channelName {mustBeText};
            end
            if(this.SimulationMode); disp('Aux Output disabled'); return; end

            channelIdx = this.ConvertAuxChannelNameToChannelIndex(channelName);

            this.SetDouble(['/auxouts/' num2str(channelIdx) '/offset'], 0);
            this.SetDouble(['/auxouts/' num2str(channelIdx) '/scale'], 0);
            this.SetDouble(['/auxouts/' num2str(channelIdx) '/preoffset'], 0);
        end

        function DisableDemod(this, demodIndex)
            %Stop a demodulator streaming samples to the Data Server.
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)

            arguments
                this;
                demodIndex (1,1) double = 0; % set default to 0 for MFLI - one demodulator for measurement
            end
            if(this.SimulationMode); return; end

            this.SetInt(['/demods/' num2str(demodIndex) '/enable'], 0); % turned off
        end

        function DisableDiffInput(this, siginIndex)
            %Set Signal Input 1 to single-ended mode.
            %
            %Inputs:
            %   siginIndex - signal input index, 0 for Signal Input 1 (default)

            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigins/' num2str(siginIndex) '/diff'], 0); % turn off
        end

        function DisableDiffOutput(this, sigoutIndex)
            %Set a signal output to single-ended mode.
            %
            %Inputs:
            %   sigoutIndex - signal output index, 0 for Signal Output 1 (default)

            arguments
                this; sigoutIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigouts/' num2str(sigoutIndex) '/diff'], 0); % turned off
        end

        function DisableEverything(this)
            %Turn off all the instrument's outputs and streaming, using LabOne's ziDisableEverything.

            arguments
                this;
            end
            if(this.SimulationMode); return; end
            ziDisableEverything(this.DeviceID);
        end

        function DisableFloat(this, siginIndex)
            %Connect the input's ground to instrument ground (floating off).
            %Applies to whichever of Signal Input 1 or Current Input 1 is the
            %source of demodulator 1; the setting is shared by both inputs
            %
            %Inputs:
            %   siginIndex - input index, 0 (default)

            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            channelName = this.GetSignalSource();
            channelIdx = this.ConvertInputChannelNameToChannelIndex(channelName);

            if channelIdx == 0
                this.SetDouble(['/sigins/' num2str(siginIndex) '/float'], 0); % turn off
            elseif channelIdx == 1
                this.SetDouble(['/currins/' num2str(siginIndex) '/float'], 0); % turn off
            else
                error("MFLI_DisableFloat_Error:InvalidInputChannel", "Float can only be turned on for Signal Input 1 and Current Input 1")
            end
        end

        function DisableSignalOut(this, channelName)
            %Switch off a signal output.
            %
            %Inputs:
            %   channelName - 'SignalOutput1' (default; the only signal output)

            arguments
                this; channelName string = 'SignalOutput1'; % set default
            end
            if(this.SimulationMode); return; end
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            this.SetInt(['/sigouts/' num2str(channelIdx) '/on'], 0); % int = 0 = off
        end

        function DisableSincFilter(this, demodIndex)
            %Turn off a demodulator's sinc filter.
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)

            arguments
                this;
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/demods/' num2str(demodIndex) '/sinc'], 0); % turn off
        end

        function Enable50ImpedIn(this, siginIndex)
            %Set Signal Input 1 to 50 Ohm input impedance, from 10 MOhm.
            %With a 50 Ohm source, expect the measured signal to halve
            %
            %Inputs:
            %   siginIndex - signal input index, 0 for Signal Input 1 (default)

            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigins/' num2str(siginIndex) '/imp50'], 1); % turn on
        end

        function Enable50ImpedOut(this, sigoutIndex)
            %Set a signal output's load impedance to 50 Ohm, from high impedance.
            %The output impedance is always 50 Ohm; this tells the instrument the
            %load is 50 Ohm, so displayed voltages and ranges are halved to
            %match the voltage at the load
            %
            %Inputs:
            %   sigoutIndex - signal output index, 0 for Signal Output 1 (default)

            arguments
                this;
                sigoutIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigouts/' num2str(sigoutIndex) '/imp50'], 1); % turn on
        end

        function EnableAC(this, siginIndex)
            %Set Signal Input 1 to AC coupling, to block large DC components.
            %Inserts a high-pass filter with a cut-off of about 1.6 Hz
            %
            %Inputs:
            %   siginIndex - signal input index, 0 for Signal Input 1 (default)

            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigins/' num2str(siginIndex) '/ac'], 1); % turn on
        end

        function EnableAmplitude(this, channelName)
            %Turn on the sine amplitude of a signal output.
            %
            %Inputs:
            %   channelName - 'SignalOutput1' (default; the only signal output)

            arguments
                this; channelName string = 'SignalOutput1'; % set default
            end
            if(this.SimulationMode); return; end
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);
            this.SetInt(['/sigouts/' num2str(channelIdx) '/enables/1'], 1)
        end

        function EnableDemod(this, demodIndex)
            %Start a demodulator streaming samples to the Data Server.
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)

            arguments
                this;
                demodIndex (1,1) double = 0; % set default to 0 for MFLI - one used for measurement
            end
            if(this.SimulationMode); return; end

            this.SetInt(['/demods/' num2str(demodIndex) '/enable'], 1); % turned on
        end

        function EnableDiffInput(this, siginIndex)
            %Set Signal Input 1 to differential mode.
            %
            %Inputs:
            %   siginIndex - signal input index, 0 for Signal Input 1 (default)

            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigins/' num2str(siginIndex) '/diff'], 1); % turn on
        end

        function EnableDiffOutput(this, sigoutIndex)
            %Set a signal output to differential mode, between its +V and -V connectors.
            %
            %Inputs:
            %   sigoutIndex - signal output index, 0 for Signal Output 1 (default)

            arguments
                this; sigoutIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigouts/' num2str(sigoutIndex) '/diff'], 1); % turned on
        end

        function EnableFloat(this, siginIndex)
            %Float the input's ground, disconnecting it from instrument ground.
            %Applies to whichever of Signal Input 1 or Current Input 1 is the
            %source of demodulator 1; the setting is shared by both inputs. The
            %manual recommends enabling it only after the source has been
            %connected with the input grounded
            %
            %Inputs:
            %   siginIndex - input index, 0 (default)

            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            channelName = this.GetSignalSource();
            channelIdx = this.ConvertInputChannelNameToChannelIndex(channelName);

            if channelIdx == 0
                this.SetDouble(['/sigins/' num2str(siginIndex) '/float'], 1); % turn on
            elseif channelIdx == 1
                this.SetDouble(['/currins/' num2str(siginIndex) '/float'], 1); % turn on
            else
                error("MFLI_EnableFloat_Error:InvalidInputChannel", "Float can only be turned on for Signal Input 1 and Current Input 1")
            end
        end

        function EnableSignalOut(this, channelName)
            %Switch on a signal output.
            %
            %Inputs:
            %   channelName - 'SignalOutput1' (default; the only signal output)

            arguments
                this; channelName string = 'SignalOutput1'; % set default
            end
            if(this.SimulationMode); return; end
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            this.SetInt(['/sigouts/' num2str(channelIdx) '/on'], 1); % int = 1 = on
        end

        function EnableSincFilter(this, demodIndex)
            %Turn on a demodulator's sinc filter, for low frequencies (below about 200 Hz).
            %Use it when the filter bandwidth is comparable to or larger than the
            %demodulation frequency
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)

            arguments
                this;
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            this.SetInt(['/demods/' num2str(demodIndex) '/sinc'], 1); % turn on
        end

        function Instr_Params = GenerateSettingsSaveStruct(this)
            %Struct of voltage divider and attenuator settings, for a run's metadata file.
            %Not currently working: the GetVoltageDividerSettingString and
            %GetAttenuatorSettingString methods it calls are not defined in
            %this class

            if(this.SimulationMode)
                Instr_Params.Info = 'Simulated Instrument';
                return;
            end

            % Save the voltage divider parameters set in the XML/instrument config
            % GetVoltageDivider.. function defined later
            Instr_Params.VoltageDivider_Aux1 = this.GetVoltageDividerSettingString('Aux1');
            Instr_Params.VoltageDivider_Aux2 = this.GetVoltageDividerSettingString('Aux2');
            Instr_Params.VoltageDivider_Aux3 = this.GetVoltageDividerSettingString('Aux3');
            Instr_Params.VoltageDivider_Aux4 = this.GetVoltageDividerSettingString('Aux4');
            Instr_Params.VoltageDivider_SignalOutput1 = this.GetVoltageDividerSettingString('SignalOutput1');

            % Save attenuator parameters
            Instr_Params.Attenuators_SignalOutput1 = this.GetAttenuatorSettingString('SignalOutput1');
        end

        function zi_Params = GenerateFullSettingsSaveStruct(this)
            %Read every setting of the instrument from LabOne, as a nested struct.
            %Too large to print neatly into a text file - save it to a .mat
            %file instead
            %
            %Outputs:
            %   zi_Params - LabOne settings struct for this device (e.g. zi_Params.demods(1).order.value)

            if(this.SimulationMode)
                zi_Params.Info = 'Simulated Instrument';
            else
                % Grab all the settings on the LI from LabOne
                strct = ziDAQ('get', ['/' this.DeviceHandle]);
                flds = fields(strct);
                zi_Params = strct.(flds{1});
            end
        end

        function [R, theta] = GetAmplitudePhase(this, demodIndex)
            %Read the latest demodulator sample as amplitude and phase.
            %Call AllowDemodToSettle first after changing settings
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)
            %
            %Outputs:
            %   R     - amplitude, RMS, in V (or A on the current input)
            %   theta - phase, in degrees

            arguments
                this;
                demodIndex (1,1) double = 0;
            end

            %Get xy values
            [X, Y] = this.GetXY(demodIndex);

            % convert to polar coordinates
            [R, theta] = this.ConvertCartesian(X,Y); % R is RMS value
        end

        function amp_RMS = GetAmplitudeOutput(this, channelName)
            %Read the sine amplitude of a signal output, in V RMS (0 if the output is off).
            %
            %Inputs:
            %   channelName - 'SignalOutput1' (default; the only signal output)
            %
            %Outputs:
            %   amp_RMS - output amplitude, in V RMS

            arguments
                this; channelName {mustBeText} = 'SignalOutput1'; % only one signal output, can set as default
            end
            if(this.SimulationMode); amp_RMS = 1; return; end

            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            %Query if the output is actually turned on
            enabled = this.GetSignalOutEnabledState(channelName);

            if enabled
                % gives amplitude in Vpk
                amp_Vpk = this.GetDouble(['/sigouts/' num2str(channelIdx) '/amplitudes/1']);
                amp_RMS = amp_Vpk/sqrt(2);
            else
                amp_RMS = 0;
            end
        end

        function aux_voltage = GetAuxOutVoltage(this, channelName)
            %Read the DC offset of an Aux Output, in V.
            %
            %Inputs:
            %   channelName - 'Aux1', 'Aux2', 'Aux3' or 'Aux4'
            %
            %Outputs:
            %   aux_voltage - the Aux Output's offset, in V

            arguments
                this;
                channelName {mustBeText};
            end
            if(this.SimulationMode); aux_voltage = 0; return; end

            % Convert channel name to index to send to instrument
            auxChannelIndex = this.ConvertAuxChannelNameToChannelIndex(channelName);

            % Gives the voltage offset value - gives voltage at lock-in
            aux_voltage = this.GetDouble(['/auxouts/' num2str(auxChannelIndex) '/offset']);
        end

        function harm = GetDemodHarm(this, demodIndex)
            %Read the harmonic a demodulator works at, as a multiple of its oscillator frequency.
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1
            %
            %Outputs:
            %   harm - integer harmonic factor

            arguments
                this; demodIndex (1,1) double;
            end

            if(this.SimulationMode); harm = 1; return; end

            harm = this.GetDouble(['/demods/' num2str(demodIndex) '/harmonic']);
        end

        function phase_shift = GetDemodPhaseShift(this, demodIndex)
            %Read the phase shift applied to a demodulator's reference, in degrees.
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1
            %
            %Outputs:
            %   phase_shift - phase shift, in degrees

            arguments
                this; demodIndex (1,1) double;
            end

            if(this.SimulationMode); phase_shift = 0; return; end

            phase_shift = this.GetDouble(['/demods/' num2str(demodIndex) '/phaseshift']);
        end

        function sample_rate = GetDemodRate(this, demodIndex)
            %Read a demodulator's sample rate - samples sent to the Data Server per second.
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)
            %
            %Outputs:
            %   sample_rate - sample rate, in samples/s

            arguments
                this; demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); sample_rate = 8e3; return; end

            sample_rate = this.GetDouble(['/demods/' num2str(demodIndex) '/rate']);
        end

        function filter_order = GetFilterOrder(this, demodIndex)
            %Read a demodulator's low-pass filter order, 1 to 8 (6 to 48 dB/octave).
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)
            %
            %Outputs:
            %   filter_order - filter order, 1 to 8

            arguments
                this; demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); filter_order = 3; return; end

            filter_order = this.GetInt(['/demods/' num2str(demodIndex) '/order']);
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %Two demodulator columns (X and Y, or R and phase), the output level
            %and the frequency, plus a resistance column when a current source
            %is connected
            %
            %Outputs:
            %   Headers - e.g. ["ZI MFLI - Voltage (V)", "ZI MFLI - Phase (Deg)",
            %             "ZI MFLI - Output Current (A)", "ZI MFLI - Frequency (Hz)",
            %             "ZI MFLI - Resistance (Ohms)"]
            %   Units   - matching units, e.g. ["V", "Deg", "A", "Hz", "Ohm"]

            %Find out what units the device is supplying (current or
            %voltage)
            switch(this.ConnectedCurrentSource)
                case(this.CurrentSource("None"))
                    supplyOutUnits = "V";
                    supplyOutName = "Voltage (V)";
                    calculateResistance = false;
                otherwise
                    supplyOutUnits = "A";
                    supplyOutName = "Current (A)";
                    calculateResistance = true;
            end

            %Are we measuring voltage or current?
            switch(this.MeasurementMode)
                case(this.MeasType("Voltage XY"))
                    Headers = [...
                        this.Name + " - Voltage X (V)",...
                        this.Name + " - Voltage Y (V)",...
                        this.Name + " - Output " + supplyOutName,...
                        this.Name + " - Frequency (Hz)"...
                        ];
                    Units = ["V", "V", supplyOutUnits, "Hz"];

                case(this.MeasType("Voltage RTheta"))
                    Headers = [...
                        this.Name + " - Voltage (V)",...
                        this.Name + " - Phase (Deg)",...
                        this.Name + " - Output " + supplyOutName,...
                        this.Name + " - Frequency (Hz)"...
                        ];
                    Units = ["V", "Deg", supplyOutUnits, "Hz"];

                case(this.MeasType("Current"))
                    Headers = [...
                        this.Name + " - Current (A)",...
                        this.Name + " - Phase (Deg)",...
                        this.Name + " - Output " + supplyOutName,...
                        this.Name + " - Frequency (Hz)"...
                        ];
                    Units = ["A", "Deg", supplyOutUnits, "Hz"];

                otherwise
                    error("MFLI_GetHeaders_Error:InvalidMode", "%s", "Mode must be Voltage, or Current, this was " + string(this.MeasurementMode));
            end

            %Add on a resistance calculation too, if we have a current
            %source etc - just for convenience
            if calculateResistance
                Headers = [Headers, this.Name + " - Resistance (Ohms)"];
                Units = [Units "Ohm"];
            end
        end

        function osc_freq = GetOscFrequency(this, oscIndex)
            %Read an oscillator's frequency, in Hz.
            %
            %Inputs:
            %   oscIndex - oscillator index, 0 for Oscillator 1 (default; more need the MD option)
            %
            %Outputs:
            %   osc_freq - frequency, in Hz

            arguments
                this;
                oscIndex (1,1) double = 0;
            end
            if(this.SimulationMode)
                osc_freq = 100; % [Hz]
                return;
            end

            osc_freq = this.GetDouble(['/oscs/' num2str(oscIndex) '/freq']);
        end

        function input_range = GetRangeInput(this, siginIndex)
            %Read the input range of the input feeding demodulator 1, in V or A.
            %Signal Input 1 or Current Input 1, whichever is demodulator 1's
            %source
            %
            %Inputs:
            %   siginIndex - input index, 0 (default)
            %
            %Outputs:
            %   input_range - input range, in V (Signal Input) or A (Current Input)

            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); input_range = 1; return; end

            channelName = this.GetSignalSource();
            channelIdx = this.ConvertInputChannelNameToChannelIndex(channelName);

            if channelIdx == 0
                input_range = this.GetDouble(['/sigins/' num2str(siginIndex) '/range']);
            elseif channelIdx == 1
                input_range = this.GetDouble(['/currins/' num2str(siginIndex) '/range']);
            else
                error("MFLI_GetRangeInput_Error:InvalidInputChannel", "Range can only be adjusted for Signal Input 1 and Current Input 1")
            end
        end

        function output_range = GetRangeOutput(this, channelName)
            %Read a signal output's range - the largest amplitude plus offset it can output, in V.
            %
            %Inputs:
            %   channelName - 'SignalOutput1' (default; the only signal output)
            %
            %Outputs:
            %   output_range - output range, in V

            arguments
                this; channelName {mustBeText} = 'SignalOutput1'; % only one signal output, can set as default
            end
            if(this.SimulationMode); output_range = 1; return; end
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            output_range = this.GetDouble(['/sigouts/' num2str(channelIdx) '/range']);
        end

        function scaling = GetScaling(this, siginIndex)
            %Read the scale factor applied to the input feeding demodulator 1.
            %Signal Input 1 or Current Input 1, whichever is demodulator 1's
            %source
            %
            %Inputs:
            %   siginIndex - input index, 0 (default)
            %
            %Outputs:
            %   scaling - scale factor

            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); scaling = 1; return; end

            channelName = this.GetSignalSource();
            channelIdx = this.ConvertInputChannelNameToChannelIndex(channelName);

            if channelIdx == 0
                scaling = this.GetDouble(['/sigins/' num2str(siginIndex) '/scaling']);
            elseif channelIdx == 1
                scaling = this.GetDouble(['/currins/' num2str(siginIndex) '/scaling']);
            else
                error("MFLI_GetScaling_Error:InvalidInputChannel", "Scaling can only be adjusted for Signal Input 1 and Current Input 1")
            end
        end

        function DCoffset = GetSignalOutDCOffset(this, channelName)
            %Read the DC offset of a signal output, in V.
            %
            %Inputs:
            %   channelName - 'SignalOutput1' (default; the only signal output)
            %
            %Outputs:
            %   DCoffset - DC offset, in V

            arguments
                this; channelName {mustBeText} = 'SignalOutput1';
            end
            if(this.SimulationMode); DCoffset = 0 ;return; end

            channelIndex = this.ConvertChannelNameToChannelIndex(channelName);

            DCoffset = this.GetDouble(['/sigouts/' num2str(channelIndex) '/offset']);
        end

        function enabledBool = GetSignalOutEnabledState(this, channelName)
            %Read whether a signal output is switched on.
            %
            %Inputs:
            %   channelName - 'SignalOutput1' (default; the only signal output)
            %
            %Outputs:
            %   enabledBool - true if the output is on (always true in simulation)

            arguments
                this; channelName string = 'SignalOutput1'; % set default
            end

            if(this.SimulationMode); enabledBool = true; return; end

            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            state = this.GetInt(['/sigouts/' num2str(channelIdx) '/on']); % int = 1 = on

            enabledBool = logical(state);
        end

        function sourceName = GetSignalSource(this, demodIndex)
            %Read which input a demodulator is demodulating, e.g. 'SignalInput1' or 'CurrentInput1'.
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)
            %
            %Outputs:
            %   sourceName - input name, as accepted by SetSignalSource

            arguments
                this;
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); sourceName = 'CurrentInput1'; return; end

            % source index
            sourceIdx = this.GetInt(['/demods/' num2str(demodIndex) '/adcselect']);
            % source name
            sourceName = this.ConvertInputChannelIndexToChannelName(sourceIdx);
        end

        function sincf = GetSincFilter(this, demodIndex)
            %Read whether a demodulator's sinc filter is on (1) or off (0).
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)
            %
            %Outputs:
            %   sincf - 1 if the sinc filter is on, 0 if off

            arguments
                this;
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); sincf = 0; return; end % sinc filter off in simulation

            sincf = this.GetInt(['/demods/' num2str(demodIndex) '/sinc']);
        end

        function tc = GetTimeConstant(this, demodIndex)
            %Read a demodulator's low-pass filter time constant, in s.
            %Convert it to a 3 dB bandwidth with ConvertTCtoBW
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)
            %
            %Outputs:
            %   tc - time constant, in s

            arguments
                this; demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); tc = 3e-4; return; end

            % time constant in seconds
            tc = this.GetDouble(['/demods/' num2str(demodIndex) '/timeconstant']);
        end

        function [X, Y] = GetXY(this, demodIndex)
            %Read the latest demodulator sample received by the Data Server, as X and Y.
            %Call AllowDemodToSettle first after changing settings
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)
            %
            %Outputs:
            %   X - in-phase component, RMS, in V (or A on the current input)
            %   Y - quadrature component, RMS, in V (or A on the current input)

            arguments
                this ;
                demodIndex (1,1) double = 0;
            end

            if(this.SimulationMode)
                X = this.GenerateSimulatedData(1, Baseline=1e-6, Variance=2e-8);
                Y = this.GenerateSimulatedData(1, Baseline=1e-8, Variance=3e-10);
                return;
            end


            % get a sample from the instrument
            sample = ziDAQ('getSample', ['/' this.DeviceHandle '/demods/' num2str(demodIndex) '/sample']);

            % obtain x and y from sample struct
            X = sample.x;
            Y = sample.y;
        end

        function LoadDefaultPresetSettings(this, fileName)
            %Load a baseline settings file, saved by SaveDefaultPresetSettings, into the instrument.
            %Not currently working: it looks for the file through
            %QNano.DataWriting.ConfigIO, which is not part of Palladium
            %
            %Inputs:
            %   fileName - settings file name (default 'ZI_MFLI_BaseSettings.xml')

            arguments
                this;
                fileName = 'ZI_MFLI_BaseSettings.xml'; % automatically inputs required fileName
            end

            if(this.SimulationMode); return; end

            dw = QNano.DataWriting.ConfigIO;
            presetsDir = dw.GetInstrumentPresetsDirPath();

            filePath = fullfile(presetsDir, fileName);

            assert(isfolder(presetsDir), "MFLI_LoadDefaultPresetSettings_Error:PresetsFolderNotFound", "%s", ['Directory to save instrument preset not found at ' presetsDir]);

            assert(exist(filePath, 'file'), "MFLI_LoadDefaultPresetSettings_Error:PresetsFileNotFound", "%s", ['Presets file not found at ' filePath]);

            % load the default settings
            ziLoadSettings(this.DeviceID, filePath);

            % And some more default calls just in case
            this.SetDemodPhaseShift(0,0);
        end

        function [dataRow] = Measure(this)
            %Read demodulator 1, the output level and the frequency.
            %The resistance, when a current source is connected, is the
            %demodulator amplitude (R, or X in Voltage XY mode) divided by
            %the output current and AmplifierGain. The Current measurement
            %mode is not supported yet
            %
            %Outputs:
            %   dataRow - values matching GetHeaders

            demodIndex = 0;

            %Retrieve frequency and voltage out levels
            output = this.GetSuppliedVoltageOrCurrentAndUnits();
            frequency = this.GetOscFrequency(demodIndex);

            %Do the voltage/current measurement, depending on settings
            switch(this.MeasurementMode)
                case(this.MeasType("Voltage XY"))
                    [vx, vy] = this.GetXY(demodIndex);
                    dataRow = [vx, vy, output, frequency];
                    R=vx;%needed for resistance calculation below;
                case(this.MeasType("Voltage RTheta"))
                    [R, theta] = this.GetAmplitudePhase(demodIndex);
                    dataRow = [R, theta, output, frequency];
                otherwise
                    error("MFLI_Measure_Error:UnsupportedMeasurementMode", "Measurement mode not currently supported");
            end


            %Calculate resistance if current source attached
            switch(this.ConnectedCurrentSource)
                case(this.CurrentSource("None"))
                    %Do nothing
                otherwise
                    resistance_Ohms = R / (output * this.AmplifierGain);
                    dataRow = [dataRow resistance_Ohms];
            end
        end

        function SaveDefaultPresetSettings(this, fileName)
            %Save the instrument's current settings as a baseline settings file.
            %Set a sensible baseline first, e.g. with all outputs off. Not
            %currently working: it saves through QNano.DataWriting.ConfigIO,
            %which is not part of Palladium
            %
            %Inputs:
            %   fileName - settings file name (default 'ZI_MFLI_BaseSettings.xml')

            arguments
                this;
                fileName = 'ZI_MFLI_BaseSettings.xml';
            end

            if(this.SimulationMode); return; end

            dw = QNano.DataWriting.ConfigIO;
            presetsDir = dw.GetInstrumentPresetsDirPath();

            filePath = fullfile(presetsDir, fileName);

            assert(isfolder(presetsDir), "MFLI_SaveDefaultPresetSettings_Error:PresetsFolderNotFound", "%s", ['Directory to save instrument preset not found at ' presetsDir]);

            % save the default settings
            ziSaveSettings(this.DeviceID, filePath);
        end

        function SetAuxOutVoltage(this, channelName, value)
            %Set an Aux Output to a constant DC voltage, in V.
            %Selects Manual output, sets the pre-offset to 0 and the scale to 1,
            %and sets the offset to the voltage. The Aux Outputs have no off
            %state - set 0 V instead
            %
            %Inputs:
            %   channelName - 'Aux1', 'Aux2', 'Aux3' or 'Aux4'
            %   value       - voltage, in V

            arguments
                this;
                channelName {mustBeText};
                value (1,1) double;
            end
            if(this.SimulationMode); return; end

            % Convert channel name to index to send to instrument
            auxChannelIndex = this.ConvertAuxChannelNameToChannelIndex(channelName);

            % Set signal to manual
            this.SetInt(['/auxouts/' num2str(auxChannelIndex) '/outputselect'], -1);

            % Set preoffset to zero
            this.SetDouble(['/auxouts/' num2str(auxChannelIndex) '/preoffset'], 0);

            % Set scale to 1 - this should not actually be needed here as scale only applies to preoffset not offset
            this.SetDouble(['/auxouts/' num2str(auxChannelIndex) '/scale'], 1);

            % Set actual offset. Signal = (AWGSignal+Preoffset)*Scale + Offset
            this.SetDouble(['/auxouts/' num2str(auxChannelIndex) '/offset'], value);

        end

        function SetAuxOutVoltage_Scaled(this, channelName, value)
            %Set an Aux Output to a constant DC voltage, in V - currently the same as SetAuxOutVoltage.
            %No scaling (e.g. for a voltage divider) is applied yet. Prints the
            %setting in simulation
            %
            %Inputs:
            %   channelName - 'Aux1', 'Aux2', 'Aux3' or 'Aux4'
            %   value       - voltage, in V

            arguments
                this;
                channelName {mustBeText};
                value (1,1) double;
            end

            % Convert channel name to index to send to instrument, and error
            % checking. auxChannelIndex will now be 0 for Aux1, 1 for Aux2..
            auxChannelIndex = this.ConvertAuxChannelNameToChannelIndex(channelName);

            if(this.SimulationMode)
                disp(['Setting ' channelName ' to ' num2str(value) ' V, to give requested ' num2str(value) ' V']);
                return;
            end
            % Set signal to manual
            this.SetInt(['/auxouts/' num2str(auxChannelIndex) '/outputselect'], -1);

            % Set preoffset to zero
            this.SetDouble(['/auxouts/' num2str(auxChannelIndex) '/preoffset'], 0);

            % Set scale to 1 - this should not actually be needed here as scale only applies to preoffset not offset
            this.SetDouble(['/auxouts/' num2str(auxChannelIndex) '/scale'], 1);

            % Set actual offset. Signal = (AWGSignal+Preoffset)*Scale + Offset
            this.SetDouble(['/auxouts/' num2str(auxChannelIndex) '/offset'], value);
        end

        function SetDemodHarm(this, value, demodIndex)
            %Set the harmonic a demodulator works at, as a multiple of its oscillator frequency.
            %
            %Inputs:
            %   value      - integer harmonic factor
            %   demodIndex - demodulator index, 0 for Demodulator 1

            arguments
                this; value (1,1) double; demodIndex (1,1) double;
            end
            if(this.SimulationMode); return; end

            this.SetDouble(['/demods/' num2str(demodIndex) '/harmonic'], value);
        end

        function SetDemodPhaseShift(this, phase, demodIndex)
            %Set the phase shift applied to a demodulator's reference, in degrees.
            %
            %Inputs:
            %   phase      - phase shift, in degrees
            %   demodIndex - demodulator index, 0 for Demodulator 1

            arguments
                this; phase (1,1) double; demodIndex (1,1) double;
            end
            if(this.SimulationMode); return; end

            this.SetDouble(['/demods/' num2str(demodIndex) '/phaseshift'], phase);
        end

        function SetDemodRate(this, rate, demodIndex)
            %Set a demodulator's sample rate - samples sent to the Data Server per second.
            %About 7 to 10 times the filter bandwidth avoids aliasing. The
            %instrument rounds to the nearest rate it supports
            %
            %Inputs:
            %   rate       - sample rate, in samples/s
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)

            arguments
                this;
                rate;
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            this.SetDouble(['/demods/' num2str(demodIndex) '/rate'], rate);
        end

        function SetDemodTrigger(this, demodIndex)
            %Set a demodulator to stream data continuously (no trigger).
            %
            %Inputs:
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)

            arguments
                this;
                demodIndex (1,1) double = 0;
            end

            if(this.SimulationMode); return; end

            this.SetInt(['/demods/' num2str(demodIndex) '/trigger'], 0);
        end

        function SetFilterOrder(this, order, demodIndex)
            %Set a demodulator's low-pass filter order, 1 to 8 (6 to 48 dB/octave).
            %
            %Inputs:
            %   order      - filter order, 1 to 8 (roll-off of 6 dB/octave per order)
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)

            arguments
                this; order {mustBeInRange(order, 1, 8)};
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            this.SetInt(['/demods/' num2str(demodIndex) '/order'], order);
        end

        function SetOscFrequency(this, oscFreq, oscIndex)
            %Set an oscillator's frequency, in Hz - the reference and output frequency.
            %
            %Inputs:
            %   oscFreq  - frequency, in Hz
            %   oscIndex - oscillator index, 0 for Oscillator 1 (default; more need the MD option)

            arguments
                this; oscFreq (1,1) double; oscIndex (1,1) double = 0; % default set as 0
            end
            if(this.SimulationMode); return; end

            this.SetDouble(['/oscs/' num2str(oscIndex) '/freq'], oscFreq);
        end

        function SetRangeInput(this, range, siginIndex)
            %Set the input range of the input feeding demodulator 1, in V or A.
            %Signal Input 1 or Current Input 1, whichever is demodulator 1's
            %source. The range should be about twice the signal, including any
            %DC offset; the instrument selects the next higher range it has
            %(3 mV to 3 V for the voltage input, 1 nA to 10 mA for the current
            %input). First measures the input with the scope, and errors
            %instead if the range is smaller than the signal
            %
            %Inputs:
            %   range      - input range, in V (Signal Input) or A (Current Input)
            %   siginIndex - input index, 0 (default)

            arguments
                this; range;
                siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            channelName = this.GetSignalSource();
            channelIdx = this.ConvertInputChannelNameToChannelIndex(channelName);

            amplitude = this.Scope_GetScopeTimeData('Max'); %in V or A already as input value

            if range < amplitude %+ offset
                error("MFLI_SetRangeInput_Error:InputOverload", "%s", "Signal Input Overload - analog input amplifier overloaded. " + ...
                    "Input a different range or use AutoRangeInput function." + ...
                    " Note: Range or amplitude may be automatically adjusted")
            else
                if channelIdx == 0
                    this.SetDouble(['/sigins/' num2str(siginIndex) '/range'], range);
                elseif channelIdx == 1
                    this.SetDouble(['/currins/' num2str(siginIndex) '/range'], range);
                else
                    error("MFLI_SetRangeInput_Error:InvalidInputChannel", "Range can only be adjusted for Signal Input 1 and Current Input 1")
                end
            end
        end

        function SetRangeOutput(this, range, channelName)
            %Set a signal output's range - the largest amplitude plus offset it can output, in V.
            %Use the smallest range that fits, for the best signal quality.
            %Turns off automatic ranging first, and errors instead if the
            %present amplitude plus offset would not fit
            %
            %Inputs:
            %   range       - output range, in V: 0.01, 0.1, 1 or 10
            %   channelName - 'SignalOutput1' (default; the only signal output)

            arguments
                this; range; channelName string = 'SignalOutput1';
            end
            if(this.SimulationMode); return; end

            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            % can't edit range if autorange is turned on, therefore turn off
            this.SetInt(['/sigouts/' num2str(channelIdx) '/autorange'], 0); % turn off

            amplitude = this.GetDouble(['/sigouts/' num2str(channelIdx) '/amplitudes/1']); %in Vpk
            offset = this.GetSignalOutDCOffset;

            if range < round(amplitude,3) + offset
                error("MFLI_SetRangeOutput_Error:OutputOverload", "%s", "Signal Output Overloaded - Signal clipping occurs and the output signal quality is degraded. " + ...
                    "Input a different range or use AutoRangeOutput function." + ...
                    "Note: Range or amplitude may be automatically adjusted")
            else
                this.SetDouble(['/sigouts/' num2str(channelIdx) '/range'], range);
            end
        end

        function SetScaling(this, scale, siginIndex)
            %Set a scale factor on the input feeding demodulator 1, e.g. to undo an external amplifier's gain.
            %Applies to Signal Input 1 or Current Input 1, whichever is
            %demodulator 1's source
            %
            %Inputs:
            %   scale      - scale factor
            %   siginIndex - input index, 0 (default)

            arguments
                this; scale;
                siginIndex (1,1) double = 0;
            end

            if(this.SimulationMode); return; end

            channelName = this.GetSignalSource();
            channelIdx = this.ConvertInputChannelNameToChannelIndex(channelName);

            if channelIdx == 0
                this.SetDouble(['/sigins/' num2str(siginIndex) '/scaling'], scale); % scaling factor in V
            elseif channelIdx == 1
                this.SetDouble(['/currins/' num2str(siginIndex) '/scaling'], scale); % scaling factor in A
            else
                error("MFLI_SetScaling_Error:InvalidInputChannel", "Scaling can only be adjusted for Signal Input 1 and Current Input 1")
            end
        end

        function SetSignalOutDCOffset(this, value, channelName)
            %Set the DC offset added to a signal output, in V.
            %
            %Inputs:
            %   value       - DC offset, in V
            %   channelName - 'SignalOutput1' (default; the only signal output)

            arguments
                this; value; channelName {mustBeText} = 'SignalOutput1';
            end

            % Convert channel name to index to send to instrument, and error checking.
            channelIndex = this.ConvertChannelNameToChannelIndex(channelName);

            if(this.SimulationMode)
                disp(['Setting ' channelName ' offset to ' num2str(value) ' V to give requested ' num2str(value) ' V']);
                return;
            end

            this.SetDouble(['/sigouts/' num2str(channelIndex) '/offset'], value);
        end

        function SetSignalOutVoltage(this, value_Vrms, channelName)
            %Set the sine amplitude of a signal output, in V RMS.
            %Sent to the instrument as a peak amplitude (value_Vrms * sqrt(2))
            %
            %Inputs:
            %   value_Vrms  - amplitude, in V RMS
            %   channelName - 'SignalOutput1' (default; the only signal output)

            arguments
                this;
                value_Vrms (1,1) double;
                channelName {mustBeText} = 'SignalOutput1';
            end

            % Convert RMS value to peak value
            value_Vp = value_Vrms*sqrt(2);

            % Convert channel name to index to send to instrument and error checking
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            if(this.SimulationMode); disp(['Simulated peak voltage at MFLI output port set to ' num2str(value_Vp) ' V']); return; end

            this.SetDouble(['/sigouts/' num2str(channelIdx) '/amplitudes/1'], value_Vp);
        end

        function SetSignalSource(this, channelName, demodIndex)
            %Set which input a demodulator demodulates.
            %
            %Inputs:
            %   channelName - input name: 'SignalInput1', 'CurrentInput1',
            %                 'Trigger1', 'Trigger2', 'AuxOut1' to 'AuxOut4',
            %                 'AuxIn1' or 'AuxIn2'
            %   demodIndex  - demodulator index, 0 for Demodulator 1 (default)

            arguments
                this; channelName {mustBeText};
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            channelIdx = this.ConvertInputChannelNameToChannelIndex(channelName);

            this.SetInt(['/demods/' num2str(demodIndex) '/adcselect'], channelIdx);
        end

        function SetTimeConstant(this, TC, demodIndex)
            %Set a demodulator's low-pass filter time constant, in s.
            %To set a 3 dB bandwidth instead, convert it with ConvertBWtoTC
            %
            %Inputs:
            %   TC         - time constant, in s
            %   demodIndex - demodulator index, 0 for Demodulator 1 (default)

            arguments
                this;
                TC;
                demodIndex (1,1) {mustBeInteger} = 0;
            end

            if(this.SimulationMode); return; end

            this.SetDouble(['/demods/' num2str(demodIndex) '/timeconstant'], TC);
        end

        function Sweep_Abort(this, sweepHandle)
            %Stop a running Sweeper Module sweep.
            %
            %Inputs:
            %   sweepHandle - handle returned by Sweep_InitialiseSweep

            if(this.SimulationMode)
                disp("Sweep aborted");
                return;
            end

            if~isempty(sweepHandle)
                ziDAQ('finish', sweepHandle);
            end
        end

        function [SweepData, complete] = Sweep_Check_Completion_Poll_Data(this, sweepHandle, demodIndex)
            %Read the data a sweep has recorded so far, and whether it has finished.
            %
            %Inputs:
            %   sweepHandle - handle returned by Sweep_InitialiseSweep
            %   demodIndex  - demodulator index, 0 for Demodulator 1 (default)
            %
            %Outputs:
            %   SweepData - struct with column vectors SweepValues (the swept
            %               parameter), Amplitude (R, in V), Phase (in degrees),
            %               X and Y (in V) - empty if no data yet
            %   complete  - true once the sweep has finished

            arguments
                this;
                sweepHandle;
                demodIndex (1,1) double = 0;
            end

            SweepData = [];
            complete = false;

            if(this.SimulationMode)
                pause(0.1);
                % Do basic simulation of sweep, random values, and not the
                % settings specified in the sweep handle, as we can't
                % access that without a real instrument
                SweepData.SweepValues = linspace(100, 1000, 100)';

                SweepData.Amplitude = this.GenerateSimulatedData(100, Baseline=1e-5, Variance=3e-6);
                SweepData.X = this.GenerateSimulatedData(100, Baseline=1e-5, Variance=3e-6);
                SweepData.Y = this.GenerateSimulatedData(100, Baseline=1e-6, Variance=8e-7);
                SweepData.Phase = this.GenerateSimulatedData(100, Baseline=60, Variance=5); % in degrees

                %Run a random (but reasonably small)  number of times.
                %Doing anything fancier than everything here would mean
                %passing info in to the instrument it doesn't need in
                %non-debug world
                complete = rand(1) > 0.85;
                return;
            end

            %Sweep handle can be empty in simulation mode - not if we get
            %to here though
            assert(~isempty(sweepHandle), "MFLI_Sweep_Error:EmptySweepHandle", "Sweep handle is empty in MFLI Sweep_Check_Completion call");

            %Query whether the sweep is complete
            complete = ziDAQ('finished', sweepHandle);

            % Read the data.
            tmp = ziDAQ('read', sweepHandle);
            devID = this.DeviceHandle; %Make sure to use DeviceHandle, not DeviceID - it is lower case - struct will have tmp.dev7779 for example, not .DEV7779

            % Process any remaining data returned by read().
            if ziCheckPathInData(tmp, ['/' devID '/demods/' num2str(demodIndex) '/sample'])
                sample = tmp.(devID).demods(1).sample{1};
                if ~isempty(sample)
                    SweepData = tmp;
                end
            end

            %Handle case of empty data so far
            if isempty(SweepData)
                SweepData.SweepValues = [];
                SweepData.Amplitude = [];
                SweepData.Phase = [];
                SweepData.X = [];
                SweepData.Y = [];
                return;
            end

            % Extract useful values from within the struct
            SweepData.SweepValues = SweepData.(devID).demods.sample{1,1}.grid'; % x axis values
            SweepData.Amplitude = SweepData.(devID).demods.sample{1,1}.r'; % in V
            SweepData.Phase = rad2deg(SweepData.(devID).demods.sample{1,1}.phase'); % in rads from device, convert to degrees
            SweepData.X = SweepData.(devID).demods.sample{1,1}.x'; % in V
            SweepData.Y = SweepData.(devID).demods.sample{1,1}.y'; % in V

        end

        function Sweep_Execute(this, sweepHandle)
            %Start a sweep set up by Sweep_InitialiseSweep.
            %
            %Inputs:
            %   sweepHandle - handle returned by Sweep_InitialiseSweep

            arguments
                this;
                sweepHandle;
            end

            if(this.SimulationMode)
                disp("Execute sweep");
                return;
            end

            % execute handle
            ziDAQ('execute', sweepHandle);
            ziDAQ('trigger', sweepHandle);
        end

        function sweepHandle = Sweep_InitialiseSweep(this, auxChannelName, oscIndex, SweepName, SweepParams)
            %Set up a Sweeper Module sweep of demodulator 1 against frequency, amplitude or a DC offset.
            %Each point averages the demodulator over a number of samples or
            %time constants, at a fixed filter bandwidth. For dI/dV sweeps of
            %Aux Output 1, loop a cable from Aux Output 1 to Aux Input 1 and
            %turn on Add for the signal output (see AddAuxInput)
            %
            %Inputs:
            %   auxChannelName - Aux Output swept by "AuxOutput1" sweeps (default "Aux1")
            %   oscIndex       - oscillator swept by "Frequency" sweeps (default 0)
            %   SweepName      - parameter to sweep: "Frequency" (Hz), "Amplitude"
            %                    (signal output peak amplitude, V), "AuxOutput1" (Aux
            %                    Output offset, V) or "OutputOffset" (signal output offset, V)
            %   SweepParams    - name-value settings: Start, Stop, NumberOfSteps,
            %                    LogScale, Bandwidth (Hz), FilterOrder, SettleTime,
            %                    SweepInaccuracy, AveSample, AveTC and SweepMode
            %                    ("Sequential", "Binary", "BiDirectional" or "Reverse")
            %
            %Outputs:
            %   sweepHandle - handle of the Sweeper Module, for Sweep_Execute,
            %                 Sweep_Check_Completion_Poll_Data and Sweep_Abort

            arguments
                this;
                auxChannelName              {mustBeText} = "Aux1"; % set default as Aux Output 1
                oscIndex                    (1,1) {mustBeInteger} = 0;
                SweepName                   {mustBeText} = "Frequency";    % What parameter to sweep over (x axis units)

                SweepParams.Start           (1,1) double = -0.1; % start value of sweep in appropriate units e.g Hz or V
                SweepParams.Stop            (1,1) double = 0.1;
                SweepParams.NumberOfSteps   (1,1) {mustBeInteger} = 5;
                SweepParams.LogScale        (1,1) logical = false;

                SweepParams.Bandwidth       (1,1) double  = 100; %In Hz Bandwith or Cutoff - determines sweep speed. A smaller BW will have a longer sweep time.
                SweepParams.FilterOrder     (1,1) double  = 4;

                SweepParams.SettleTime      (1,1) double  = 0.1; % Minimum wait time in seconds between a sweep parameter change and the recording of the next sweep point.- want 7 or larger
                SweepParams.SweepInaccuracy (1,1) double  = 1e-5; % How to long to wait until measurement accuracy has approached slowly towards perfectly settled. Fractional error tolerated. Effective wait time is maximum between settling time and inaccuracy. Demodulator filter settling inaccuracy defines the wait time between a sweep parameter change and recording of the next sweep point.

                SweepParams.AveSample       (1,1) double  = 100; % Sets the effective number of samples (clock cycles) per sweeper parameter point that is considered in the measurement.
                SweepParams.AveTC           (1,1) double  = 1;   % Effective calculation time is the maximum between samples and number of time constants. Usually set the Sample Count.

                SweepParams.SweepMode       {mustBeText}  = "Sequential";  %Select the scanning type, default is sequential (incremental scanning from start to stop value)
            end

            if(this.SimulationMode)
                disp("Set up simulated MFLI " + string(SweepName) + " sweep");
                sweepHandle = "SweepHandlePLACEHOLDER-Simulation"; % define empty sweepHandle
                return;
            end

            %Select different parameters for the x axis of the sweep:
            % frequency, Aux Offset or Signal Output Offset
            switch(SweepName)
                case("Frequency")
                    gridnode = ['oscs/' num2str(oscIndex) '/freq'] ;
                case("Amplitude")
                    sigoutIndex = 0;
                    gridnode = ['sigouts/' num2str(sigoutIndex) '/amplitudes/1'] ;
                case("AuxOutput1")
                    auxIndex = this.ConvertAuxChannelNameToChannelIndex(auxChannelName);
                    gridnode = ['auxouts/' num2str(auxIndex) '/offset'];
                    this.SetAuxOutVoltage(auxChannelName, 0)
                case("OutputOffset")%Using Aux ouput and the Add toggle to add that onto the Signal Output port via a bias tee is reccomended by ZI over setting the offset on SO. This is because it lets you keep a small range setting for Sig Out while applying a large DC offset from the Aux. This is basically for dI/dV measurements
                    sigoutIndex = 0;
                    gridnode = ['sigouts/' num2str(sigoutIndex) '/offset'];
                otherwise
                    error("MFLI_Sweep_InitialiseSweep_Error:InvalidSweptParameter", "%s", ['Invalid Sweep Parameter for function. ' ...
                        'SweptParameter: Frequency, Amplitude, AuxOutput1, OutputOffset'])
            end

            % obtain time constant from BW and filter order defined
            time_constant = this.ConvertBWtoTC(SweepParams.Bandwidth, SweepParams.FilterOrder);
            settle_time = SweepParams.SettleTime * time_constant;

            % set demodulator trigger to continuous data acquisition
            this.SetDemodTrigger()

            % create sweep handle
            sweepHandle = ziDAQ('sweep');

            % configure all the parameters
            ziDAQ('set', sweepHandle, 'sweep/device', this.DeviceHandle);
            ziDAQ('set', sweepHandle, 'sweep/gridnode', gridnode); % sweep parameter
            ziDAQ('set', sweepHandle, 'sweep/start', SweepParams.Start);
            ziDAQ('set', sweepHandle, 'sweep/stop', SweepParams.Stop);
            ziDAQ('set', sweepHandle, 'sweep/endless', 0); % don't run sweep continuously
            ziDAQ('set', sweepHandle, 'sweep/samplecount', SweepParams.NumberOfSteps); % number of sweep points

            ziDAQ('set', sweepHandle, 'sweep/loopcount', 1); % number of sweeps to perform
            if SweepParams.LogScale
                ziDAQ('set', sweepHandle, 'sweep/xmapping', 1);% 1 = logarithmic spacing
            else
                ziDAQ('set', sweepHandle, 'sweep/xmapping', 0); % 0 = linear sweep - spacing between two values is linear
            end

            %Scan order of the values from start to stop
            switch (SweepParams.SweepMode)
                case("Sequential");     ziDAQ('set', sweepHandle, 'sweep/scan', 0); % smallest to largest
                case("Binary");         ziDAQ('set', sweepHandle, 'sweep/scan', 1); % middle first, then halving the intervals
                case("BiDirectional");  ziDAQ('set', sweepHandle, 'sweep/scan', 2); % sequential, then back again
                case("Reverse");        ziDAQ('set', sweepHandle, 'sweep/scan', 3); % largest to smallest
                otherwise
                    error("MFLI_Sweep_InitialiseSweep_Error:UnsupportedSweepDirection", "%s", "Unsupported sweep direction " + string(SweepParams.SweepMode));
            end

            ziDAQ('set', sweepHandle, 'sweep/settling/time', settle_time);
            ziDAQ('set', sweepHandle, 'sweep/settling/inaccuracy', SweepParams.SweepInaccuracy);
            ziDAQ('set', sweepHandle, 'sweep/averaging/tc', SweepParams.AveTC); % 50
            ziDAQ('set', sweepHandle, 'sweep/averaging/sample', SweepParams.AveSample); % 100
            ziDAQ('set', sweepHandle, 'sweep/bandwidthcontrol', 1); % 2 = automatic, 1 = fixed, 0 = manual control
            ziDAQ('set', sweepHandle, 'sweep/bandwidth', SweepParams.Bandwidth);
            ziDAQ('set', sweepHandle, 'sweep/order', SweepParams.FilterOrder);
            ziDAQ('set', sweepHandle, 'sweep/bandwidthoverlap', 0);
            ziDAQ('set', sweepHandle, 'sweep/phaseunwrap', 1);

            ziDAQ('subscribe', sweepHandle, ['/' this.DeviceHandle '/demods/0/sample']);
            ziDAQ('execute', sweepHandle);
        end

        function daqData = Scope_AssembleData_FFT(this, tmp, demod_path_us, path)
            %Extract the FFT amplitude and its bandwidth from Data Acquisition Module data.
            %
            %Inputs:
            %   tmp           - data struct read from the module
            %   demod_path_us - subscribed node path, with dots replaced by underscores
            %   path          - name of the signal's field, e.g. 'sample_r_fft_abs'
            %
            %Outputs:
            %   daqData - the data struct, with fields Amplitude and bandwidth (in Hz) added

            arguments
                this; tmp; demod_path_us; path;
            end
            if(this.SimulationMode); return; end

            daqData = tmp;

            if ziCheckPathInData(tmp, demod_path_us)
                devID = this.DeviceHandle;
                sample = tmp.(devID).demods(1).(path){1};
                disp(sample)
                if ~isempty(sample)
                    daqData = tmp;
                end

                % Get the amplitude of the demodulator signal
                daqData.Amplitude = daqData.(devID).demods(1).(path){1}.value;

                % Frequency data is calculated from the grid column delta.
                bin_resolution = daqData.(devID).demods(1).(path){1}.header.gridcoldelta;

                daqData.bandwidth = bin_resolution * length(daqData.Amplitude);
            end
        end

        function daqData = Scope_AssembleData_Time(this, tmp, demod_path_us, path, clockbase)
            %Extract the amplitude and time, in s, from Data Acquisition Module data.
            %
            %Inputs:
            %   tmp           - data struct read from the module
            %   demod_path_us - subscribed node path, with dots replaced by underscores
            %   path          - name of the signal's field, e.g. 'sample_r_avg'
            %   clockbase     - instrument clock frequency, in Hz, to convert timestamps to s
            %
            %Outputs:
            %   daqData - the data struct, with fields Amplitude and Time (in s, from 0) added

            arguments
                this; tmp; demod_path_us; path; clockbase;
            end
            if(this.SimulationMode); return; end

            % assign data
            daqData = tmp;

            if ziCheckPathInData(tmp, demod_path_us)
                devID = this.DeviceHandle;
                sample = tmp.(devID).demods(1).(path){1};
                if ~isempty(sample)
                    % Get the amplitude of the demodulator signal
                    daqData = tmp;
                end
                % obtain amplitude data
                daqData.Amplitude = tmp.(devID).demods(1).(path){1}.value;

                % Set the first timestamp to the first timestamp obtained.
                timestamp0 = double(tmp.(devID).demods(1).(path){1}.timestamp(1, 1));

                % Convert from device ticks to time in seconds.
                daqData.Time = (double(tmp.(devID).demods(1).(path){1}.timestamp(1, :)) - timestamp0)/clockbase;
            end
        end

        function data = Scope_Execute(this, scopeModule, SamplingRate)
            %Record scope shots with a Scope Module set up by Scope_Initialise, and return the first.
            %Waits for up to 20 records, or 30 s
            %
            %Inputs:
            %   scopeModule  - handle returned by Scope_Initialise
            %   SamplingRate - scope time base index, as set by Scope_Initialise (default 6, 938 kHz)
            %
            %Outputs:
            %   data - the Scope Module data struct, with fields Amplitude (the
            %          first record, in V or A), Frequency (FFT frequency axis,
            %          in Hz) and time (in s) added

            arguments
                this;
                scopeModule;
                SamplingRate (1,1) double = 6;
            end

            if(this.SimulationMode)
                data.Frequency = linspace(0, 400e3, 2048);
                data.Amplitude = this.GenerateSimulatedData(2048, Baseline=1e-5, Variance=3e-6);
                return;
            end

            % minimum number of records obtained
            min_num_records = 20;

            % execute scope handle
            ziDAQ('execute', scopeModule);

            % enable the scope - scope ready to record data upon receiving triggers.
            this.SetInt('/scopes/0/enable', 1);
            ziDAQ('sync');

            time_start = tic;
            timeout = 30;  % [s]
            records = 0;
            % wait until the Scope Module has received and processed the desired number of records.
            while records < min_num_records
                pause(0.5)
                records = ziDAQ('getInt', scopeModule, 'records');

                if toc(time_start) > timeout
                    % break out of the loop if no longer receiving scope data from the device.
                    fprintf('\nScope Module did not return %d records after %f s - forcing stop.', min_num_records, timeout);
                    break
                end
            end

            % read out the scope data from the module.
            data = ziDAQ('read', scopeModule);
            % stop the module - to use again, call execute()
            ziDAQ('finish', scopeModule);

            % dividing by timestamp by clockbase gives time in seconds
            clockbase = this.GetInt('/clockbase');

            % obtain data. The data struct's device field is the lower-case
            % device ID, i.e. DeviceHandle
            records = data.(this.DeviceHandle).scopes(1).wave;

            % take first sample as data
            totalsamples = double(records{1}.totalsamples);
            dt = double(records{1}.dt);

            % rate or frequency = (clockbase / 2^SamplingRate)/2
            scope_rate = double(clockbase)/2^SamplingRate;

            % frequency
            data.Frequency = linspace(0, scope_rate/2, totalsamples); % in Hz
            % amplitude in V - first sample is data
            data.Amplitude = records{1}.wave(:, 1);
            % time
            data.time = linspace(0, dt*totalsamples, totalsamples);

            % disable scope after obtained data to stop running in LabOne
            this.SetInt('/scopes/0/enable', 0);
        end

        function length = Scope_GetScopeLength(this)
            %Read the length of a scope shot, in samples.
            %
            %Outputs:
            %   length - number of samples per scope shot

            arguments
                this;
            end
            if(this.SimulationMode); length = 1000; return; end

            length = this.GetInt('/scopes/0/length');
        end

        function resolution = Scope_GetScopeResolution(this)
            %Calculate the scope's FFT frequency resolution, in Hz, from its sample rate and shot length.
            %
            %Outputs:
            %   resolution - frequency resolution, in Hz (the reciprocal of the shot duration)

            arguments
                this
            end
            if(this.SimulationMode); resolution = 14; return; end % in [Hz]

            % sample rate of scope
            sample_rate = this.Scope_GetScopeSampleRate();

            % length of recorded scope shot
            length = this.GetDouble('/scopes/0/length');

            % calculate acquistion time
            acq_time = length/double(sample_rate);
            % reciprocal of acquistion time
            resolution = 1/acq_time;
        end

        function sample_rate = Scope_GetScopeSampleRate(this)
            %Read the scope's sample rate, in Hz (60 MHz / 2^n for time base index n).
            %
            %Outputs:
            %   sample_rate - sample rate, in Hz

            arguments
                this;
            end
            if(this.SimulationMode); sample_rate = 938000; return; end % in [Hz]

            sample_index = this.GetInt('/scopes/0/time');
            % calculate sample rate from index
            sample_rate = 60e6/2^sample_index;
        end

        function int = Scope_GetScopeSampleRateInt(this)
            %Read the scope's time base index n, 0 to 15 - the sample rate is 60 MHz / 2^n.
            %
            %Outputs:
            %   int - time base index

            arguments
                this;
            end
            if(this.SimulationMode); int = 6; return; end
            int = this.GetInt('/scopes/0/time');
        end

        function scope_value = Scope_GetScopeTimeData(this, Calculation, ScopeParams)
            %Record a scope shot of demodulator 1's input and return its maximum, mean or minimum.
            %
            %Inputs:
            %   Calculation - 'Max', 'Avg' or 'Min'
            %   ScopeParams - name-value scope settings, as for Scope_Initialise
            %
            %Outputs:
            %   scope_value - the result, in V or A

            arguments
                this;
                Calculation {mustBeText};
                ScopeParams.Length     (1,1) double = 10e3;
                ScopeParams.SamplingRate        (1,1) int64 = 6; % 938 kHz
                ScopeParams.Weight      (1,1) double = 1;
                ScopeParams.Window      (1,1) double = 1;
                ScopeParams.SpectralDensity     (1,1) double = false; % turned off as default
                ScopeParams.Power     (1,1) double = false; % turned off as default
            end

            if(this.SimulationMode)
                scope_value = 0.01;
                return;
            end
            channelName = this.GetSignalSource();

            % obtain the scope handle for defualt parameters
            scopeHandle = this.Scope_Initialise('Time','ChannelIdx', channelName,'Length', ...
                ScopeParams.Length,'SamplingRate', ScopeParams.SamplingRate,'Window', ScopeParams.Window, ...
                'SpectralDensity', ScopeParams.SpectralDensity, 'Power', ScopeParams.Power, ...
                'Weight', ScopeParams.Weight);

            % obtain data in time domain by executing the handle
            timeData = this.Scope_Execute(scopeHandle, ScopeParams.SamplingRate);

            switch(Calculation)
                case('Max');    scope_value = max(timeData.Amplitude);
                case('Avg');    scope_value = mean(timeData.Amplitude);
                case('Min');    scope_value = min(timeData.Amplitude);
                otherwise
                    error("MFLI_Scope_GetScopeTimeData_Error:InvalidCalculation", "%s", "Calculation must be Max, Avg or Min, was " + string(Calculation));
            end
        end

        function scopeModule = Scope_Initialise(this, DomainSignal, ScopeParams)
            %Set up the scope and a Scope Module to record an input in the time or frequency domain.
            %Run it with Scope_Execute
            %
            %Inputs:
            %   DomainSignal - 'Time' or 'FFT'
            %   ScopeParams  - name-value settings: ChannelIdx (input name:
            %                  'SignalInput1', 'CurrentInput1' or 'SignalOutput1'),
            %                  Length (samples per shot), SamplingRate (time base
            %                  index n, rate 60 MHz / 2^n), Weight (averaging weight,
            %                  1 for none), Window (FFT window, 1 = Hann),
            %                  SpectralDensity and Power (FFT options)
            %
            %Outputs:
            %   scopeModule - handle of the Scope Module, empty in simulation

            arguments
                this;
                DomainSignal {mustBeText};
                % channel into Scope. 'Signal Input 1' = 0, 'Current Input 1' = 1, 'Signal Output 1' 12.
                ScopeParams.ChannelIdx  {mustBeText} = 'CurrentInput1';
                % length - the length of each segment - length of recorded scope shot
                % decreasing this gives less points on scope graph.
                % Increasing gives a smaller resolution.
                ScopeParams.Length     (1,1) double = 10e3;
                % sampling rate of the scope - given as an integer
                ScopeParams.SamplingRate        (1,1) int64 = 6; % 938 kHz

                % for weight = 1, don't average. if weight > 1 average the scope record segments using an
                % exponentially weighted moving average.
                ScopeParams.Weight      (1,1) double = 1;
                % use a Hann window function.
                ScopeParams.Window      (1,1) double = 1;
                % spectral density of data used to analyse noise
                ScopeParams.SpectralDensity     (1,1) double = false; % turned off as default
                % calculation of power value
                ScopeParams.Power     (1,1) double = false; % turned off as default
            end

            if(this.SimulationMode)
                disp('Set up simulated MFLI Scope FFT');
                scopeModule = []; % define empty scopeModule
                return;
            end

            % convert channel string to index
            channel = this.ConvertScopeInputNameToIndex(ScopeParams.ChannelIdx);

            this.SetInt('/scopes/0/length', ScopeParams.Length);

            % channel - select the scope channel/s to enable.
            %  1 - enable scope channel 0, 2 - enable scope channel 1, 3 - enable both scope channels
            this.SetInt('/scopes/0/channel', 1); % only interested in one scope channel

            % bandwidth limit the scope data - avoids antialiasing effects due to subsampling when the scope
            % sample rate is less than the input channel's sample rate.
            % note: 1 channel being used therefore channels/1/bwlimit
            this.SetInt('/scopes/0/channels/0/bwlimit', 1); % turn on BW limit
            this.SetInt('/scopes/0/channels/0/inputselect', channel);
            this.SetInt('/scopes/0/time', ScopeParams.SamplingRate);

            % only get a single scope record.
            this.SetInt('/scopes/0/single', 0); % turned off - want multiple to get error
            % the scope's trigger
            this.SetInt('/scopes/0/trigenable', 0); % turned off  - acquire continuous records

            % set the scope trigger hold off time inbetween acquiring triggers (still
            % relevant if triggering is disabled).
            this.SetDouble('/scopes/0/trigholdoff', 0.05);
            % perform a global synchronisation between the device and the data server:
            ziDAQ('sync');

            % initialize and configure the Scope Module.
            scopeModule = ziDAQ('scopeModule');
            % Scope data processing mode.
            % 1 - time domain of scope
            % 3 - FFT is applied to every segment of the scope
            if(strcmp(DomainSignal, 'Time'))
                ziDAQ('set', scopeModule, 'mode', 1); % time mode
            elseif(strcmp(DomainSignal, 'FFT'))
                ziDAQ('set', scopeModule, 'mode', 3); % FFT mode
            end
            % as weight = 1, don't average. if weight > 1 average the scope record segments using an
            % exponentially weighted moving average.
            ziDAQ('set', scopeModule, 'averager/weight', ScopeParams.Weight);
            % keep 1 scope record in the Scope Module's memory
            ziDAQ('set', scopeModule, 'historylength', 1)
            ziDAQ('set', scopeModule, 'fft/window', ScopeParams.Window);

            ziDAQ('set', scopeModule, 'fft/spectraldensity', ScopeParams.SpectralDensity);
            ziDAQ('set', scopeModule, 'fft/power', ScopeParams.Power);

            % subscribe to the scope's data in the module. The node path
            % uses the lower-case device ID, DeviceHandle, as a char
            wave_nodepath = ['/' this.DeviceHandle '/scopes/0/wave'];
            ziDAQ('subscribe', scopeModule, wave_nodepath);
        end

        function Scope_SetScopeResolution(this, resolution)
            %Set the scope shot length to give a frequency resolution, in Hz, at the present sample rate.
            %
            %Inputs:
            %   resolution - frequency resolution, in Hz

            arguments
                this; resolution;
            end
            if(this.SimulationMode); return; end

            sample_rate = this.Scope_GetScopeSampleRate();

            length = sample_rate/resolution;

            this.SetInt('/scopes/0/length', length);
        end

        function Scope_SetScopeFreqMax(this, maxFreq)
            %Set the scope sample rate to give an FFT frequency range up to about maxFreq, in Hz.
            %Picks the scope time base nearest to a sample rate of twice maxFreq
            %
            %Inputs:
            %   maxFreq - highest frequency wanted in the FFT, in Hz

            arguments
                this; maxFreq;
            end
            if(this.SimulationMode); return; end
            sample_rate = maxFreq*2;

            % if sample rate half way between given sample rate values, set
            % integer value. The slowest time base is 15 (1.83 kHz)
            if(sample_rate <= 1.3e3)
                int = 15;
            elseif(1.3e3 < sample_rate && sample_rate <= 2.7e3)
                int = 15;
            elseif(2.7e3 < sample_rate && sample_rate <= 5.5e3)
                int = 14;
            elseif(5.5e3 < sample_rate && sample_rate <= 10.9e3)
                int = 13;
            elseif(10.9e3 < sample_rate && sample_rate <= 21.9e3)
                int = 12;
            elseif(21.9e3 < sample_rate && sample_rate <= 43.9e3)
                int = 11;
            elseif(43.9e3 < sample_rate && sample_rate <= 87.8e3)
                int = 10;
            elseif(87.8e3 < sample_rate && sample_rate <= 175.5e3)
                int = 9;
            elseif(175.5e3 < sample_rate && sample_rate <= 351.5e3)
                int = 8;
            elseif(351.5e3 < sample_rate && sample_rate <= 703.5e3)
                int = 7;
            elseif(703.5e3 < sample_rate && sample_rate <= 1.877e6)
                int = 6;
            elseif(1.877e6 < sample_rate && sample_rate <= 2.815e6)
                int = 5;
            elseif(2.815e6 < sample_rate && sample_rate <= 5.625e6)
                int = 4;
            elseif(5.625e6 < sample_rate && sample_rate <= 11.25e6)
                int = 3;
            elseif(11.25e6 < sample_rate && sample_rate <= 22.5e6)
                int = 2;
            elseif(22.5e6 < sample_rate && sample_rate <= 45e6)
                int = 1;
            elseif(45e6 < sample_rate)
                int = 1;
            else
                error("MFLI_Scope_SetScopeFreqMax_Error:FrequencyOutOfRange", 'Out of frequency range')
            end

            this.SetInt('/scopes/0/time', int);

        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function channelIdx = ConvertAuxChannelNameToChannelIndex(~, channelName)
            %Node index of an Aux Output name, 0 for 'Aux1' to 3 for 'Aux4'.

            switch(channelName)
                case('Aux1');   channelIdx = 0;
                case('Aux2');   channelIdx = 1;
                case('Aux3');   channelIdx = 2;
                case('Aux4');   channelIdx = 3;
                otherwise
                    error("MFLI_ConvertAuxChannelNameToChannelIndex_Error:InvalidChannelName", "%s", ['Invalid channelName in ZI_MFLI ConvertAuxChannelNameToChannelIndex. ChannelName can be Aux1, Aux2, Aux3, Aux4, was ' num2str(channelName)]);
            end
        end

        function channelIdx = ConvertChannelNameToChannelIndex(~, channelName)
            %Node index of a signal output name - 0 for 'SignalOutput1', the only one.

            if(strcmp(channelName, 'SignalOutput1'))
                channelIdx = 0;
            else
                error("MFLI_ConvertChannelNameToChannelIndex_Error:InvalidChannelName", "%s", ['Invalid channelName in ZI_MFLI ConvertChannelNameToChannelIndex. ChannelName can be SignalOutput1, was ' num2str(channelName)]);
            end
        end

        function channelIdx = ConvertInputChannelNameToChannelIndex(~, channelName)
            %Demodulator input select (ADCSELECT) value of an input name, e.g. 1 for 'CurrentInput1'.

            switch(channelName)
                case('SignalInput1');   channelIdx = 0;
                case('CurrentInput1');  channelIdx = 1;
                case('Trigger1');       channelIdx = 2;
                case('Trigger2');       channelIdx = 3;
                case('AuxOut1');        channelIdx = 4;
                case('AuxOut2');        channelIdx = 5;
                case('AuxOut3');        channelIdx = 6;
                case('AuxOut4');        channelIdx = 7;
                case('AuxIn1');         channelIdx = 8;
                case('AuxIn2');         channelIdx = 9;
                otherwise
                    error("MFLI_ConvertInputChannelNameToChannelIndex_Error:InvalidChannelName", "%s", ['Invalid channelName in ZI_MFLI ConvertInputChannelNameToChannelIndex, was ' num2str(channelName)]);
            end
        end

        function channelName = ConvertInputChannelIndexToChannelName(~, channelIdx)
            %Input name of a demodulator input select (ADCSELECT) value, e.g. 'CurrentInput1' for 1.

            switch(channelIdx)
                case(0);    channelName = 'SignalInput1';
                case(1);    channelName = 'CurrentInput1';
                case(2);    channelName = 'Trigger1';
                case(3);    channelName = 'Trigger2';
                case(4);    channelName = 'AuxOut1';
                case(5);    channelName = 'AuxOut2';
                case(6);    channelName = 'AuxOut3';
                case(7);    channelName = 'AuxOut4';
                case(8);    channelName = 'AuxIn1';
                case(9);    channelName = 'AuxIn2';
                otherwise
                    error("MFLI_ConvertInputChannelIndexToChannelName_Error:InvalidChannelIndex", 'Invalid channel index in ZI_MFLI ConvertInputChannelIndexToChannelName');
            end
        end

        function val = GetDouble(this, command)
            %Read a double node of this device, e.g. '/oscs/0/freq' (0 in simulation).

            if(this.SimulationMode)
                val = 0;
                return;
            end

            %Query value from instrument via ZI Matlab API
            val = ziDAQ('getDouble', ['/' this.DeviceHandle char(command)]);
        end

        function val = GetInt(this, command)
            %Read an integer node of this device, e.g. '/demods/0/order' (0 in simulation).

            if(this.SimulationMode)
                val = 0;
                return;
            end

            %Query value from instrument via ZI Matlab API
            val = ziDAQ('getInt', ['/' this.DeviceHandle char(command)]);
        end

        function propertiesToIgnore = GetPropertiesToIgnore(~)
            %Hide the address properties in the GUI - the MFLI is identified by DeviceID only.

            propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address", "VISA_Address"};
        end

        function [magnitude, unit, name] = GetSuppliedVoltageOrCurrentAndUnits(this)
            %Signal output level, in V RMS, or in A RMS through the connected current source.

            %Get the size of voltage being output at the signal out port
            vOut = this.GetAmplitudeOutput();   % note, this is RMS voltage

            switch(this.ConnectedCurrentSource)
                case(this.CurrentSource("None"))
                    magnitude = vOut;
                    unit = "V";
                    name = "Voltage";
                case(this.CurrentSource("200 uA/V"))
                    magnitude = 200e-6 * vOut;
                    unit = "A";
                    name = "Current";
                otherwise
                    error("MFLI_GetSuppliedVoltageOrCurrentAndUnits_Error:UnsupportedCurrentSource", "%s", "Connected current source option " + this.ConnectedCurrentSource + " not implemented in MFLI");
            end
        end

        function SetDouble(this, command, value)
            %Set a double node of this device, e.g. '/oscs/0/freq' (nothing in simulation).

            if(this.SimulationMode)
                return;
            end

            %Relay command to instrument via ZI Matlab API
            ziDAQ('setDouble', ['/' this.DeviceHandle char(command)], value);
        end

        function SetInt(this, command, value)
            %Set an integer node of this device, e.g. '/sigouts/0/on' (nothing in simulation).

            if(this.SimulationMode)
                return;
            end

            %Relay command to instrument via ZI Matlab API
            ziDAQ('setInt', ['/' this.DeviceHandle char(command)], value);
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function [demod_path, demod_path_us, path] = DemodPath_Time(this, DemodSignal, demodIndex)
            %Data Acquisition Module node path, underscored path and field name of a time-domain demodulator signal.

            arguments
                this;
                DemodSignal {mustBeText}; % 'X','Y','R','Phase'
                demodIndex (1,1) double = 0; % only 1 demodulator
            end
            if(this.SimulationMode); return; end

            if(strcmp(DemodSignal, 'X'))
                % node from which data will be recorded
                demod_path = ['/' this.DeviceHandle '/demods/' num2str(demodIndex) '/sample.x.avg'];
                % dots in the signal paths replaced by underscores in the data returned by MATLAB to
                % prevent conflicts with the MATLAB syntax.
                demod_path_us = strrep(demod_path,'.','_');
                path = 'sample_x_avg' ;

            elseif(strcmp(DemodSignal,'Y'))
                demod_path = ['/' this.DeviceHandle '/demods/' num2str(demodIndex) '/sample.y.avg'];
                demod_path_us = strrep(demod_path,'.','_');
                path = 'sample_y_avg' ;

            elseif(strcmp(DemodSignal, 'R'))
                demod_path = ['/' this.DeviceHandle '/demods/' num2str(demodIndex) '/sample.r.avg'];
                demod_path_us = strrep(demod_path,'.','_');
                path = 'sample_r_avg' ;

            elseif(strcmp(DemodSignal, 'Phase'))
                demod_path = ['/' this.DeviceHandle '/demods/' num2str(demodIndex) '/sample.theta.avg'];
                demod_path_us = strrep(demod_path,'.','_');
                path = 'sample_theta_avg' ;

            else
                error("MFLI_DemodPath_Time_Error:InvalidDemodSignal", 'Invalid DemodSignal name - can be X, Y, R or Phase')
            end

        end

        function [demod_path, demod_path_us, path] = DemodPath_FFT(this, DemodSignal, demodIndex)
            %Data Acquisition Module node path, underscored path and field name of a demodulator signal's FFT.

            arguments
                this;
                DemodSignal {mustBeText}; % 'X','Y','R','Phase', 'XiY'
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            if(strcmp(DemodSignal, 'X'))
                % node from which data will be recorded
                demod_path = ['/' this.DeviceHandle '/demods/' num2str(demodIndex) '/sample.x.fft.abs'];
                % dots in the signal paths replaced by underscores in the data returned by MATLAB to
                % prevent conflicts with the MATLAB syntax.
                demod_path_us = strrep(demod_path,'.','_');
                path = 'sample_x_fft_abs';

            elseif(strcmp(DemodSignal, 'Y'))
                demod_path = ['/' this.DeviceHandle '/demods/' num2str(demodIndex) '/sample.y.fft.abs'];
                demod_path_us = strrep(demod_path,'.','_');
                path = 'sample_y_fft_abs' ;

            elseif(strcmp(DemodSignal, 'R'))
                demod_path = ['/' this.DeviceHandle '/demods/' num2str(demodIndex) '/sample.r.fft.abs'];
                demod_path_us = strrep(demod_path,'.','_');
                path = 'sample_r_fft_abs' ;

            elseif(strcmp(DemodSignal, 'Phase'))
                demod_path = ['/' this.DeviceHandle '/demods/' num2str(demodIndex) '/sample.theta.fft.abs'];
                demod_path_us = strrep(demod_path,'.','_');
                path = 'sample_theta_fft_abs' ;

            elseif(strcmp(DemodSignal, 'XiY'))
                % XiY can only be found for the Time Domain
                % Filter Compensation can only be applied to XiY signal
                demod_path = ['/' this.DeviceHandle '/demods/' num2str(demodIndex)  '/sample.xiy.fft.abs'];
                demod_path_us = strrep(demod_path,'.','_');
                path = 'sample_xiy_fft_abs' ;
            else
                error("MFLI_DemodPath_FFT_Error:InvalidDemodSignal", 'Invalid DemodSignal name - can be X, Y, R, Phase or XiY')
            end
        end

    end

    %% Methods (Static, Public)
    methods(Static, Access = public)

        function [R, theta] = ConvertCartesian(x, y)
            %Convert demodulator X and Y to amplitude R and phase in degrees.
            %
            %Inputs:
            %   x - in-phase component X
            %   y - quadrature component Y, in the same units
            %
            %Outputs:
            %   R     - amplitude, sqrt(x^2 + y^2), in the units of x and y
            %   theta - phase, in degrees, from -180 to 180

            arguments
                x; y;
            end
            R = sqrt(x^2 + y^2);
            theta = atan2d(y, x); % degrees, in all four quadrants
        end

        function TC_convert = ConvertBWtoTC(BW, order)
            %Convert a demodulator filter's 3 dB bandwidth to its time constant.
            %The result can be passed to SetTimeConstant
            %
            %Inputs:
            %   BW    - 3 dB bandwidth, in Hz
            %   order - filter order, 1 to 8
            %
            %Outputs:
            %   TC_convert - time constant, in s

            arguments
                BW;
                order {mustBeInRange(order, 1, 8)}; % FO depends on filter order - table of conversions
            end
            % each filter order has a corresponding factor FO that depends on filter slope
            switch order
                case 1;     FO = 1.0;
                case 2;     FO = 0.6436;
                case 3;     FO = 0.5098;
                case 4;     FO = 0.4350;
                case 5;     FO = 0.3856;
                case 6;     FO = 0.3499;
                case 7;     FO = 0.3226;
                case 8;     FO = 0.3008;
                otherwise
                    error("MFLI_ConvertBWtoTC_Error:InvalidFilterOrder", 'Error: Order (%d) must be between 1 and 8!\n', order);
            end
            % equation to give time constant from bandwidth frequency
            TC_convert = FO / (2*pi*BW);
        end

        function channelIdx = ConvertScopeInputNameToIndex(channelName)
            %Scope input select value of an input name: 'SignalInput1', 'CurrentInput1' or 'SignalOutput1'.
            %
            %Inputs:
            %   channelName - input name
            %
            %Outputs:
            %   channelIdx - value for the scope channel's INPUTSELECT node

            switch(channelName)
                case('SignalInput1');   channelIdx = 0;
                case('CurrentInput1');  channelIdx = 1;
                case('SignalOutput1');  channelIdx = 12;
                otherwise
                    error("MFLI_ConvertScopeInputNameToIndex_Error:InvalidChannelName", "%s", "Scope input must be SignalInput1, CurrentInput1 or SignalOutput1, was " + string(channelName));
            end
        end

        function BW_convert = ConvertTCtoBW(TC, order)
            %Convert a demodulator filter's time constant to its 3 dB bandwidth.
            %
            %Inputs:
            %   TC    - time constant, in s
            %   order - filter order, 1 to 8
            %
            %Outputs:
            %   BW_convert - 3 dB bandwidth, in Hz

            arguments
                TC;
                order {mustBeInRange(order, 1, 8)}; % FO depends on filter order - table of conversions
            end
            % each filter order has a corresponding factor FO that depends on filter slope
            switch order
                case 1;     FO = 1.0;
                case 2;     FO = 0.6436;
                case 3;     FO = 0.5098;
                case 4;     FO = 0.4350;
                case 5;     FO = 0.3856;
                case 6;     FO = 0.3499;
                case 7;     FO = 0.3226;
                case 8;     FO = 0.3008;
                otherwise
                    error("MFLI_ConvertTCtoBW_Error:InvalidFilterOrder", 'Error: Order (%d) must be between 1 and 8!\n', order);
            end

            % equation to give bandwidth frequency from time constant
            BW_convert = FO / (2*pi*TC);
        end

    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function deviceHandle = ZIConnect(deviceID, interface)
            %Check the LabOne API is on the path, connect to the local Data Server and the device, and return the lower-case device ID.

            % Check the ziDAQ MEX (DLL) and Utility functions can be found in Matlab's path.
            if ~(exist('ziDAQ', 'file') == 3) || ~(exist('ziCreateAPISession', 'file') == 2)
                error("MFLI_ZIConnect_Error:LabOneApiNotFound", "%s", "Failed to find the LabOne MATLAB API (the ziDAQ mex file or its utility functions). " + ...
                    "Add it to the MATLAB path with the ziAddPath function in the API subfolder of the LabOne installation - on Windows this is typically " + ...
                    "C:\Program Files\Zurich Instruments\LabOne\API\MATLAB2012\");
            end

            % The API level 5 gives full functionality for an MFLI
            % according to the ziDAQ.m metadata comments
            supported_apilevel = 5;

            %Connect to a dataserver if not already connected, then connect
            %this device to that. Assumes LabOne is installed and running on
            %the PC, not internally on the MFLI. See comments in ZI_HandleConnect_LabOneServerRunningOnPC
            deviceHandle = Palladium.Instruments.ZI_MFLI.ZI_HandleConnect_LabOneServerRunningOnPC(deviceID, interface, supported_apilevel);

            %Check the API and firmware are the same version. Not required but
            %a nice error check
            ziApiServerVersionCheck();

        end

        function device = ZI_HandleConnect(device_serial, maximum_supported_apilevel)
            %Connect to a device through the Data Server it reports by discovery (not currently used).
            %Simplified version of the ziCreateAPISession utility - without
            %the clear command at the start among other changes, as that
            %looked to stop us ever having 2 devices connected

            % Determine the device identifier from it's serial/id
            device = lower(ziDAQ('discoveryFind', device_serial));

            % Get the device's default connectivity properties.
            props = ziDAQ('discoveryGet', device);

            %Check the device is there and discoverable
            assert(props.discoverable, "MFLI_ZI_HandleConnect_Error:DeviceNotDiscoverable", "%s", "The specified device " + string(device_serial) + " is not discoverable from the API. Please ensure the device is powered-on and visible using the LabOne User Interface or ziControl.");

            % The maximum API level supported by the device class, e.g., MF.
            apilevel_device = props.apilevel;

            % Ensure that we connect on an compatible API Level (from where
            % ziCreateAPISession() was called).
            apilevel = min(apilevel_device, maximum_supported_apilevel);

            % Create a connection to a Zurich Instruments Data Server (a API session)
            % using the device's default connectivity properties.
            ziDAQ('connect', props.serveraddress, props.serverport, apilevel);

            if isempty(props.connected)
                fprintf('Will try to connect device `%s` on interface `%s`.\n', props.deviceid, props.interfaces{1})
                ziDAQ('connectDevice', props.deviceid, props.interfaces{1});
            end
        end

        function deviceHandle = ZI_HandleConnect_LabOneServerRunningOnPC(device_serial, interface, apilevel, server_address, port_number)
            %Connect to the Data Server on this PC and the device through it, and return the lower-case device ID.
            %Needed to connect more than one ZI instrument at once, as ziDAQ is
            %a single global session in the MATLAB API. See the "Running LabOne
            %on a Separate PC" section of the MFLI manual (and emails with ZI,
            %15/4/2025): the Data Server runs on the PC running Palladium
            %rather than inside the MFLI

            arguments
                device_serial {mustBeTextScalar};
                interface {mustBeTextScalar, mustBeMember(interface, {'1GbE', 'USB'})};
                apilevel {mustBeInteger} = 6;
                server_address {mustBeTextScalar} = '127.0.0.1'; %localhost address
                port_number {mustBeInteger} = 8004; %8004 for MFLIs, 8005 for fancier instruments it seems - can see in the LabOne web broswer GUI
            end

            %Connect to data server (I think this can be called even if
            %it's already connected so no need to check..)
            ziDAQ('connect', server_address, port_number, apilevel);

            %Connect to the actual device
            ziDAQ('connectDevice', char(device_serial), interface);

            % Determine the device identifier from it's serial/id
            deviceHandle = lower(ziDAQ('discoveryFind', char(device_serial)));
        end

    end
end
