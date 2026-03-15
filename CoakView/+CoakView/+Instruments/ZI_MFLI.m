classdef ZI_MFLI < CoakView.Core.Instrument
    % ZI_MFLI - Zurich Instruments MFLI medium-frequency lockin, Instrument implementation
    %The connection code allows multiple MFLI instruments to be connected
    %at once. Due to how MFLIs run an on-instrument server as well as the
    %option for PC-hosted more advanced ones (which are anyway more
    %performant), this complicates install and operation. LabOne must be
    %fully installed via downloadable exectuable, not just via plug and
    %play of the instrument, before connecting. This gives the PC hosting -
    %see the MFLI manual for more information. And then when launching
    %LabOne in the browser on the PC, select Local Data Servers from the
    %drop down when browsing connected instruments, before doing anything.
    %Otherwise opening the instrument in LabOne will lock it into a state
    %where this code cannot connect, it will keep showing as In Use and
    %pretty much has to be power cycled to get it to connect again. LabOne
    %will remember the Local selection between runs, so only need to select
    %on first use then never change.
    %LabOne can be running in the browser while this code is active, and
    %indeed is intended to be used this way - complex settings and control are not
    %duplicated here.

    properties(Constant, Access = public)
        FullName = "Zurich Instruments MFLI";                           %Full name, just for displaying on GUI
    end

    properties(Access = public, SetObservable)
        Name = 'ZI MFLI';
        Connection_Type = CoakView.Enums.ConnectionType.Ethernet;       %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        DeviceID = 'DEV7779';                                           %Instrument hardware address
        ConnectedCurrentSource;                                         %Do we have a current source connected that will turn voltage out into a current?
        AmplifierGain = 1;                                              %Gain of any externally-added amplifiers or transformers to take into account.
        MeasurementMode;                                                %Measuring voltage or current?
    end

    
    methods(Access = public)

        %% Categoricals
        function catOut = CurrentSource(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["None", "200 uA/V"]); end
        function catOut = MeasType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Voltage XY", "Voltage RTheta", "Current"]); end

        %% Constructor
        function this = ZI_MFLI()
            %Specify communication options and settings
            this.DefineSupportedConnectionTypes(["Debug", "Ethernet", "USB"]);
            this.ConnectedCurrentSource = this.CurrentSource("200 uA/V");
            this.MeasurementMode = this.MeasType("Voltage RTheta");

            %Define the Instrument Controls that can be added 
            this.DefineInstrumentControl(Name = "MFLI Sweep Control", ClassName = "MFLI_SweepController", TabName = "MFLI Sweep Control", EnabledByDefault = false);
        end

        %% GenerateSettingsSaveStruct
        function Instr_Params = GenerateSettingsSaveStruct(this)
            % For logging diagnostics at end of scripts - each instrument returns a struct of all its
            % measurement parameters and settings, that will be dumped into the MeasurementInfo/Metadata
            % textfile in the Run Folder
            if(this.SimulationMode)
                Instr_Params.Info = 'Simulated Instrument';
                return;
            end

            % Save the voltage divider parameters set in the XML/instrument config
            % GetVoltageDivider.. function defined later
            Instr_Params.VoltageDivider_Aux1 = this.GetVoltageDividerSettingString('Aux1');
            Instr_Params.VoltageDivider_Aux2 = this.GetVoltageDividerSettingString('Aux2');
            Instr_Params.VoltageDivider_Aux2 = this.GetVoltageDividerSettingString('Aux3');
            Instr_Params.VoltageDivider_Aux2 = this.GetVoltageDividerSettingString('Aux4');
            Instr_Params.VoltageDivider_SignalOutput1 = this.GetVoltageDividerSettingString('SignalOutput1');

            % Save attenuator parameters
            Instr_Params.Attenuators_SignalOutput1 = this.GetAttenuatorSettingString('SignalOutput1');
        end

        %% GenerateFullSettingsSaveStruct
        function zi_Params = GenerateFullSettingsSaveStruct(this)
            % For logging diagnostics at end of scripts - each instrument returns a struct of all its
            % measurement parameters and settings, that will be dumped into the MeasurementInfo/Metadata
            % textfile in the Run Folder. The LI is a bit different to other instruments, in that it
            % can generate a struct itself with literally everything in it - but it's a mess
            % and impossible to neatly print to txt. let scripts grab it as a struct and save it directly
            % to .mat, as well as separately saving the txt of simpler parameters.
            if(this.SimulationMode)
                zi_Params.Info = 'Simulated Instrument';
            else
                % Grab all the settings on the LI from LabOne
                strct = ziDAQ('get', ['/' this.DeviceHandle]);
                flds = fields(strct);
                zi_Params = strct.(flds{1});
            end
        end

        %% CollectMetadata
        function metadataStruct = CollectMetaData(this)
            %Does nothing by default - implementations of individual
            %instruments can override this to give functionality.
            %Delete this function if no metadata is desired for this
            %instrument.
            %If a struct is returned it will be parsed
            %into a string and that added as a line in the data file
            %header.
            %Use this to record instrument settings and metadata like
            %frequency, voltage, measurement mode, that will not change
            %during the measurement and therefore don't merit logging each
            %step
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

        %% Connect to Instrument
        function Connect(this)
            % Function to connect to MFLI instrument.

            switch(this.Connection_Type)
                case(CoakView.Enums.ConnectionType.Debug)
                    %Do not make a physical connection to a real instrument
                    %- this places the class into SimulationMode, for
                    %testing without a real piece of hardware connected
                    disp("Connecting to simulated " + this.Name + " instrument....");
                    pause(0.3);
                    disp("Connected to simulated " + this.Name + " instrument.");
                    this.SimulationMode = true;

                case(CoakView.Enums.ConnectionType.Ethernet)
                    %Connect to instrument via ZI Matlab API
                    this.DeviceHandle = this.ZIConnect(this.DeviceID, '1GbE');

                case(CoakView.Enums.ConnectionType.USB)
                    %Connect to instrument via ZI Matlab API
                    this.DeviceHandle = this.ZIConnect(this.DeviceID, '1GbE'); %Don't tell it USB, keep it 1GbE instead - we actually connect to the dataserver on LocalHost (to allow connecting multiple instruments) - so USB errors out, even if the device is connected to the dataserver by USB. Let's hide the user from this, stop them panicking that USB is not a supported option

                otherwise
                    error("Unsupported connection type: " + this.ConnectionType);
            end

        end

          

        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)

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
                    error("Mode must be Voltage, or Current, this was " + string(this.Mode));
            end

            %Add on a resistance calculation too, if we have a current
            %source etc - just for convenience
            if calculateResistance
                Headers = [Headers, this.Name + " - Resistance (Ohms)"];
                Units = [Units "Ohm"];
            end
        end

        %% Measure
        function [dataRow] = Measure(this)
            %Query data on demodulator 0
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
                    error("Measurement mode not currently supported");
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

        %% Close
        function Close(this)
            %This (so far) looks to be common behaviour across all instruments.
            %Can override this function in implementing class if more behaviour needed.
            switch(this.Connection_Type)
                case(CoakView.Enums.ConnectionType.Debug)
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

        %% ClearDAQ
        function ClearDAQ(~)
            %Complete reset of the entire ZI data acquisition
            %drivers, disconnects everything including data
            %servers. Will do this to any other ZI devices that are
            %connected
            clear ziDAQ;
        end

        %% LoadDefaultPresetSettings
        function LoadDefaultPresetSettings(this, fileName)
            % LoadDefaultPresetSettings() - Assumes that you have previously saved a sensible baseline
            % set of settings for the MFLI as 'BaseSettings'. Loads those in so we are starting from a known
            % point, nice clean slate. FileName is optional, default behaviour if not included.
            arguments
                this;
                fileName = 'ZI_MFLI_BaseSettings.xml'; % automatically inputs required fileName
            end

            if(this.SimulationMode); return; end

            dw = QNano.DataWriting.ConfigIO;
            presetsDir = dw.GetInstrumentPresetsDirPath();

            filePath = fullfile(presetsDir, fileName);

            assert(isfolder(presetsDir), ['Directory to save instrument preset not found at ' presetsDir]);

            assert(exist(filePath, 'file'), ['Presets file not found at ' filePath]);

            % load the default settings
            ziLoadSettings(this.DeviceID, filePath);

            % And some more default calls just in case
            this.SetDemodPhaseShift(0,0);
        end

        %% SaveDefaultPresetSettings
        function SaveDefaultPresetSettings(this, fileName)
            % SaveDefaultPresetSettings() - Save the current instrument settings, hopefully a sensible
            % baseline set of settings for the MFLI as 'BaseSettings' or an overridden filename other
            % than this default. Saves into the Config folder. Can then later load those in so we are starting
            % from a known point, nice clean slate.
            % Set baseline settings with all outputs off, amplitude disabled and aux outputs off.
            arguments
                this;
                fileName = 'ZI_MFLI_BaseSettings.xml';
            end

            if(this.SimulationMode); return; end

            dw = QNano.DataWriting.ConfigIO;
            presetsDir = dw.GetInstrumentPresetsDirPath();

            filePath = fullfile(presetsDir, fileName);

            assert(isfolder(presetsDir), ['Directory to save instrument preset not found at ' presetsDir]);

            % save the default settings
            ziSaveSettings(this.DeviceID, filePath);
        end

        %% EnableDemod
        function EnableDemod(this, demodIndex)
            % EnableDemod(demodIndex) - enables data transfer of measurement samples from the demodulator
            % to the host computer.
            % demodIndex set to default value of 0 - only one demodulator acquires data.
            arguments
                this;
                demodIndex (1,1) double = 0; % set default to 0 for MFLI - one used for measurement
            end
            if(this.SimulationMode); return; end

            this.SetInt(['/demods/' num2str(demodIndex) '/enable'], 1); % turned on
        end

        %% DisableDemod
        function DisableDemod(this, demodIndex)
            % DisableDemod(demodIndex) - disables data transfer of measurement samples from the demodulator
            % to the host computer.
            % demodIndex set to default value of 0 - only one demodulator acquires data.
            arguments
                this;
                demodIndex (1,1) double = 0; % set default to 0 for MFLI - one demodulator for measurement
            end
            if(this.SimulationMode); return; end

            this.SetInt(['/demods/' num2str(demodIndex) '/enable'], 0); % turned off
        end

        %% DisableEverything
        function DisableEverything(this)
            % DisableEverything() - disables all outputs of MFLI
            arguments
                this;
            end
            if(this.SimulationMode); return; end
            ziDisableEverything(this.DeviceID);
        end

        %% SetDemodPhaseShift
        function SetDemodPhaseShift(this, phase, demodIndex)
            % SetDemodPhaseShift(value, demodIndex) - set the phase shift applied to the reference input
            % of the demodulator
            % phase - phase shift in degrees
            % demodIndex-can apply phase shift to either signal output (index 1) or reference demodulator (index 0)
            arguments
                this; phase (1,1) double; demodIndex (1,1) double;
            end
            if(this.SimulationMode); return; end

            this.SetDouble(['/demods/' num2str(demodIndex) '/phaseshift'], phase);
        end

        %% GetDemodPhaseShift
        function phase_shift = GetDemodPhaseShift(this, demodIndex)
            % GetDemodPhaseShift(value, demodIndex) - get the phase shift applied to the reference
            % input of the demodulator
            % demodIndex-can apply phase shift to either signal output (index 1) or reference demodulator (index 0)
            arguments
                this; demodIndex (1,1) double;
            end

            if(this.SimulationMode); phase_shift = 0; return; end

            phase_shift = this.GetDouble(['/demods/' num2str(demodIndex) '/phaseshift']);
        end

        %% SetDemodHarm
        function SetDemodHarm(this, value, demodIndex)
            % SetDemodHarm(value, demodIndex) - multiplies demodulator's (1 or 2) reference frequency
            % with defined integer factor
            % value - integer factor
            % demodIndex - can apply to either signal output (index 1) or reference demodulator (index 0)
            arguments
                this; value (1,1) double; demodIndex (1,1) double;
            end
            if(this.SimulationMode); return; end

            this.SetDouble(['/demods/' num2str(demodIndex) '/harmonic'], value);
        end

        %% GetDemodHarm
        function harm = GetDemodHarm(this, demodIndex)
            % GetDemodHarm(value, demodIndex) - get integer factor multiplying demodulator's (1 or 2)
            % reference frequency
            % demodIndex - can apply to either signal output (index 1) or reference demodulator (index 0)
            arguments
                this; demodIndex (1,1) double;
            end

            if(this.SimulationMode); harm = 1; return; end

            harm = this.GetDouble(['/demods/' num2str(demodIndex) '/harmonic']);
        end

        %% SetOscFrequency
        function SetOscFrequency(this, oscFreq, oscIndex)
            % SetOscFrequency(oscFreq, oscIndex) - set the frequency of the oscillator connected to the
            % demodulator. Provides the reference signal.
            % oscFreq - the frequency of the oscillator given in Hz.
            % oscIndex set to default of 0 - only one oscillator. Can upgrade device to 4 oscillators.
            arguments
                this; oscFreq (1,1) double; oscIndex (1,1) double = 0; % default set as 0
            end
            if(this.SimulationMode); return; end

            this.SetDouble(['/oscs/' num2str(oscIndex) '/freq'], oscFreq);
        end

        %% GetOscFrequency
        function osc_freq = GetOscFrequency(this, oscIndex)
            % GetOscFrequency(oscIndex) - get the frequency of the oscillator connected to the demodulator.
            % oscIndex set to default of 0 - only one oscillator. Can upgrade device to 4 oscillators.
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

        %% SetFilterOrder
        function SetFilterOrder(this, order, demodIndex)
            % SetFilterOrder(order, demodIndex) - set low-pass filter roll-off.
            % order given by index 1 to 8, corresponding to 6, 12, 18, 24, 30 dB/oct etc.
            % demodIndex set to default value of 0 - set order for the demodulator that acquires data.
            % can also set demodIndex to 1 to change filter order for second demodulator used as
            % an external reference demodulator
            arguments
                this; order {mustBeInRange(order, 1, 8)};
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            this.SetInt(['/demods/' num2str(demodIndex) '/order'], order);
        end

        %% GetFilterOrder
        function filter_order = GetFilterOrder(this, demodIndex)
            % GetFilterOrder(demodIndex) - get low-pass filter roll-off.
            % demodIndex set to default value of 0 - set order for demodulator that acquires data.
            % can also set demodIndex to 1 to change filter order for second demodulator used as
            % an external reference demodulator
            arguments
                this; demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); filter_order = 3; return; end

            filter_order = this.GetInt(['/demods/' num2str(demodIndex) '/order']);
        end

        %% SetTimeConstant
        function SetTimeConstant(this, TC, demodIndex)
            % SetTimeConstant(TC, demodIndex) - function to define the time constant of the low-pass filter.
            % TC - time constant in seconds
            % demodIndex set to default value of 0 - set time constant for demodulator that acquires data.
            % can also set demodIndex to 1 to change time constant for second demodulator used as
            % an external reference demodulator
            % Note: to adjust the filter 3dB bandwidth, bandwidth must be converted into a time constant
            % for a given order using function ConvertBWintoTC then inputted into SetTimeConstant.
            arguments
                this;
                TC;
                demodIndex (1,1) {mustBeInteger} = 0;
            end

            if(this.SimulationMode); return; end

            this.SetDouble(['/demods/' num2str(demodIndex) '/timeconstant'], TC);
        end

        %% GetTimeConstant
        function tc = GetTimeConstant(this, demodIndex)
            % GetTimeConstant(demodIndex) - get the time constant of the low-pass filter.
            % demodIndex set to default value of 0 - set time constant for demodulator that acquires data.
            % can also set demodIndex to 1 to change time constant for second demodulator used as
            % an external reference demodulator
            % Note: to get the filter 3 dB bandwidth, time constant obtained must be converted into a bandwidth
            % for a given order using function ConvertTCintoBW.
            arguments
                this; demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); tc = 3e-4; return; end

            % time constant in seconds
            tc = this.GetDouble(['/demods/' num2str(demodIndex) '/timeconstant']);
        end

        %% EnableSincFilter
        function EnableSincFilter(this, demodIndex)
            % EnableSincFilter(demodIndex) - turn on Sinc filter. Turn on when low-pass filter bandwidth
            % comparable or larger than demodulation frequency. Use when frequency below 200 Hz.
            % demodIndex set to default value of 0 - turn on sinc for demodulator that acquires data.
            % can also set demodIndex to 1 to turn on sinc for second demodulator used as
            % an external reference demodulator
            arguments
                this;
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            this.SetInt(['/demods/' num2str(demodIndex) '/sinc'], 1); % turn on
        end

        %% DisableSincFilter
        function DisableSincFilter(this, demodIndex)
            % DisableSincFilter(demodIndex) - turn off Sinc filter.
            % demodIndex set to default value of 0 - turn off sinc for demodulator that acquires data.
            % can also set demodIndex to 1 to turn off sinc for second demodulator used as
            % an external reference demodulator
            arguments
                this;
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/demods/' num2str(demodIndex) '/sinc'], 0); % turn off
        end

        %% GetSincFilter
        function sincf = GetSincFilter(this, demodIndex)
            % GetSincFilter(demodIndex) - get sinc filter status.
            % demodIndex set to default value of 0. Can also set demodIndex to 1 to get sinc
            % status for second demodulator used as an external reference demodulator
            arguments
                this;
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); sincf = 0; return; end % sinc filter off in simulation

            sincf = this.GetInt(['/demods/' num2str(demodIndex) '/sinc']);
        end

        %% AllowDemodToSettle
        function AllowDemodToSettle(this, demodIndex)
            %AllowDemodToSettle - simply wait a set time, with no commands
            %sent to instrument, for the demodulator to settle after a
            %change. This is dependent on filterOrder and TimeConstant. See p297 of MFLI
            %user manual.
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
                case(1)
                    waitTime = tc * 4.6;
                case(2)
                    waitTime = tc * 6.6;
                case(3)
                    waitTime = tc * 8.4;
                case(4)
                    waitTime = tc * 10;
                case(5)
                    waitTime = tc * 12;
                case(6)
                    waitTime = tc * 12;
                case(7)
                    waitTime = tc * 15;
                case(8)
                    waitTime = tc * 16;

                otherwise
                    error('Unsupported filter order');
            end

            pause(waitTime);
        end

        %% GetXY
        function [X, Y] = GetXY(this, demodIndex)
            % GetXY(demodIndex) - get the Cartesian components of the demodulated signal for the last sample
            % that the Data Server received from the instrument. Gives a single measurement of X and Y RMS
            % voltage in Volts.
            % Device only transfers X and Y to the PC. X,Y,R,Theta obtained from each Aux Output.
            % demodIndex set to default value of 0 - only one demodulator
            % acquires data and sends to computer.
            % Reccomended to call AllowDemodToSettle before calling this.
            arguments
                this ;
                demodIndex (1,1) double = 0;
            end

            if(this.SimulationMode)
                X = rand(1)*100e-8; Y = rand(1)*10e-9;
                return;
            end


            % get a sample from the instrument
            sample = ziDAQ('getSample', ['/' this.DeviceHandle '/demods/' num2str(demodIndex) '/sample']);

            % obtain x and y from sample struct
            X = sample.x;
            Y = sample.y;
        end

        %% GetAmplitudePhase
        function [R, theta] = GetAmplitudePhase(this, demodIndex)
            % GetAmplitudePhase(demodIndex) - obtain the amplitude and phase of the demodulated signal.
            % Instrument outputs in Cartesian coordinates X and Y, hence function converts components
            % X and Y from the last sample recieved from the instrument to R (RMS voltage in Volts) and
            % theta (in degrees). Function can be used instead of ReadXY then ConvertCartesian.
            % demodIndex set to default value of 0 - only one demodulator acquires data and sends to computer.
            % Reccomended to call AllowDemodToSettle before calling this.
            arguments
                this;
                demodIndex (1,1) double = 0;
            end

            %Get xy values
            [X, Y] = this.GetXY(demodIndex);

            % convert to polar coordinates
            [R, theta] = this.ConvertCartesian(X,Y); % R is RMS value
        end

        %% SetDemodRate
        function SetDemodRate(this, rate, demodIndex)
            % SetDemodRate(rate, demodIndex) - defines the demodulator sampling rate, the number of samples
            % sent to the host computer per second.
            % rate needs to be about 7-10 higher than bandwidth to give good surpression of alaising.
            % Note: rate will automatically adjust to appropriate value near rate inputted.
            % demodIndex set to default of 0 - only 1 demodulator connected to host computer
            arguments
                this;
                rate;
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            this.SetDouble(['/demods/' num2str(demodIndex) '/rate'], rate);
        end

        %% GetDemodRate
        function sample_rate = GetDemodRate(this, demodIndex)
            % GetDemodRate(rate, demodIndex)- Get the demodulator sampling rate.
            % Note: rate will automatically adjust to appropriate value near rate inputted.
            % demodIndex set to default of 0 - only 1 demodulator connected to host computer
            arguments
                this; demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); sample_rate = 8e3; return; end

            sample_rate = this.GetDouble(['/demods/' num2str(demodIndex) '/rate']);
        end


        %% Signal Input Parameters
        %% SetSignalSource
        function SetSignalSource(this, channelName, demodIndex)
            % SetSignalSource(channelIndex, demodIndex) - set the input signal source for a demodulator.
            % channelName defines the input source - most common use: Signal Input 1 or Current Input 1
            % demodIndex set to default value of 0 - set source for the demodulator that acquires data.
            % can also set demodIndex to 1 to change source for second demodulator used as
            % a reference demodulator.
            arguments
                this; channelName {mustBeText};
                demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            channelIdx = this.ConvertInputChannelNameToChannelIndex(channelName);

            this.SetInt(['/demods/' num2str(demodIndex) '/adcselect'], channelIdx);
        end

        %% GetSignalSource
        function sourceName = GetSignalSource(this, demodIndex)
            % GetSignalSource(demodIndex) - get the input signal source for a demodulator.
            % Function outputs the input source name.
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

        %% SetScaling
        function SetScaling(this, scale, siginIndex)
            % SetScaling(scale, siginIndex) - apply an arbitary scale factor to the input signal
            % Can be used to account for gain of external amplifier
            % Function only applies for SignalInput1 and CurrentInput1 - can only adjust scaling for these inputs
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
                error("Scaling can only be adjusted for Signal Input 1 and Current Input 1")
            end
        end

        %% GetScaling
        function scaling = GetScaling(this, siginIndex)
            % GetScaling(siginIndex) - get the scaling factor of the input signal
            % Scaling factor only adjusted for 'SignalInput1' and 'CurrentInput1'
            % siginIndex - default to 0 as only one type of each input
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
                error("Scaling can only be adjusted for Signal Input 1 and Current Input 1")
            end
        end

        %% SetRangeInput
        function SetRangeInput(this, range, siginIndex)
            % SetRangeInput(range, siginIndex) - defines the gain of the analog input amplifier.
            % The range should exceed the incoming signal by a factor two, including the DC offset.
            % range - instrument selects the next higher range relative to value given.
            % Range values: 3m,10m,30m,100m,300m,1,3 in Volts for SignalInput1
            %               1n,10n,100n,1u,10u,100u,1m,10m in Amps for CurrentInput1
            % Range can only be adjusted for 'SignalInput1' and 'CurrentInput1'
            % siginIndex - default to 0 as only one type of each input
            arguments
                this; range;
                siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            channelName = this.GetSignalSource();
            channelIdx = this.ConvertInputChannelNameToChannelIndex(channelName);

            amplitude = this.GetScopeTimeData('Max'); %in V or A already as input value

            if range < amplitude %+ offset
                error("Signal Input Overload - analog input amplifier overloaded. " + ...
                    "Input a different range or use AutoRangeInput function." + ...
                    " Note: Range or amplitude may be automatically adjusted")
            else
                if channelIdx == 0
                    this.SetDouble(['/sigins/' num2str(siginIndex) '/range'], range);
                elseif channelIdx == 1
                    this.SetDouble(['/currins/' num2str(siginIndex) '/range'], range);
                else
                    error("Range can only be adjusted for Signal Input 1 and Current Input 1")
                end
            end
        end

        %% GetRangeInput
        function input_range = GetRangeInput(this, siginIndex)
            % GetRangeInput(range, siginIndex) - get the gain of the analog input amplifier.
            % Range in Volts. Only adjusted for 'SignalInput1' and 'CurrentInput1'
            % siginIndex - default to 0 as only one type of each input
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
                error("Range can only be adjusted for Signal Input 1 and Current Input 1")
            end
        end

        %% EnableAC
        function EnableAC(this, siginIndex)
            % EnableAC(siginIndex) - turn on AC coupling. This inserts a high-pass filter with a cut-off
            % frequency of 1.6 Hz that can be used to block large DC signal components to prevent input signal
            % saturation during amplification.
            % Can only be enabled for Signal Input 1
            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigins/' num2str(siginIndex) '/ac'], 1); % turn on
        end

        %% DisableAC
        function DisableAC(this, siginIndex)
            % DisableAC(siginIndex) - turn off AC coupling. Only for Signal Input 1.
            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigins/' num2str(siginIndex) '/ac'], 0); % turn off
        end

        %% EnableDiffInput
        function EnableDiffInput(this, siginIndex)
            % EnableDifferentialInput -  switch from single ended to differential mode.
            % Only applied for Signal Input 1.
            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigins/' num2str(siginIndex) '/diff'], 1); % turn on
        end

        %% DisableDiffInput
        function DisableDiffInput(this, siginIndex)
            % DisableDifferentialInput - switch from differential to single ended mode.
            % Only applied for Signal Input 1.
            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            zthis.SetInt(['/sigins/' num2str(siginIndex) '/diff'], 0); % turn on
        end

        %% Enable50ImpedIn
        function Enable50ImpedIn(this, siginIndex)
            % Enable50ImpedIn - switch from high impedance of 10 MOhms to low impedance of 50 Ohms.
            % With 50 Ohms, expect reduction by factor 2 in measured signal if source also has 50 Ohm impedance.
            % Only applied for Signal Input 1.
            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigins/' num2str(siginIndex) '/imp50'], 1); % turn on
        end

        %% Disable50ImpedIn
        function Disable50ImpedIn(this, siginIndex)
            % Disable50ImpedIn - switch from low impedance of 50 Ohms to high impedance of 10 MOhms.
            % Only applied for Signal Input 1.
            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            zthis.SetInt(['/sigins/' num2str(siginIndex) '/imp50'], 0); % turn off
        end

        %% EnableFloat
        function EnableFloat(this, siginIndex)
            % EnableFloat(siginIndex) - switch from connected to floating ground
            % Recommended to enable setting only after the signal source has been connected to the Signal Input
            % in grounded mode.
            % Function only applies for SignalInput1 and CurrentInput1
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
                error("Float can only be turned on for Signal Input 1 and Current Input 1")
            end
        end

        %% DisableFloat
        function DisableFloat(this, siginIndex)
            % DisableFloat(siginIndex) - switch from floating to connected ground.
            % Function only applies for SignalInput1 and CurrentInput1
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
                error("Float can only be turned on for Signal Input 1 and Current Input 1")
            end
        end

        %% AutoRangeInput
        function AutoRangeInput(this, siginIndex)
            % AutoRangeInput(siginIndex) - automatically adjust range so instrument not overloaded
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
                error("AutoRange can only be turned on for Signal Input 1 and Current Input 1")
            end
        end


        %% Signal Output Parameters
        %% SetSignalOutVoltage
        function SetSignalOutVoltage(this, value_Vrms, channelName)
            % SetSignalOutVoltage(value_V, channelName) - set the MFLI output voltage
            % value_Vrms - RMS voltage at device given in Volts
            % channelName - 'SignalOutput1' set as default
            arguments
                this; value_Vrms (1,1) double; channelName {mustBeText} = 'SignalOutput1';
            end

            % Convert RMS value to peak-to-peak value
            value_Vp = value_Vrms*sqrt(2);

            % Convert channel name to index to send to instrument and error checking
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            if(this.SimulationMode); disp(['Simulated peak voltage at MFLI output port set to ' num2str(value_Vp) ' V']); return; end

            this.SetDouble(['/sigouts/' num2str(channelIdx) '/amplitudes/1'], value_Vp);
        end

        %% EnableSignalOut
        function EnableSignalOut(this, channelName)
            % EnableSignalOut(channelName) - turn on signal output RF port.
            % channelName - 'SignalOutput1' set as default
            arguments
                this; channelName string = 'SignalOutput1'; % set default
            end
            if(this.SimulationMode); return; end
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            this.SetInt(['/sigouts/' num2str(channelIdx) '/on'], 1); % int = 1 = on
        end

        %% DisableSignalOut
        function DisableSignalOut(this, channelName)
            % DisableSignalOut(channelName) - turn off signal output RF port.
            % channelName - 'SignalOutput1' set as default
            arguments
                this; channelName string = 'SignalOutput1'; % set default
            end
            if(this.SimulationMode); return; end
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            this.SetInt(['/sigouts/' num2str(channelIdx) '/on'], 0); % int = 0 = off
        end

        %% GetSignalOutEnabledState
        function enabledBool = GetSignalOutEnabledState(this, channelName)
            % GetSignalOutEnabledState(channelName) - tquery whether the
            % Signal Out is actually turned on at the moment
            arguments
                this; channelName string = 'SignalOutput1'; % set default
            end

            if(this.SimulationMode); return; end

            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            state = this.GetInt(['/sigouts/' num2str(channelIdx) '/on']); % int = 1 = on

            enabledBool = logical(state);
        end

        %% EnableAmplitude
        function EnableAmplitude(this, channelName)
            % EnableAmplitude(channelName) - enable the output amplitude.
            % channelName - 'SignalOutput1' set as default
            arguments
                this; channelName string = 'SignalOutput1'; % set default
            end
            if(this.SimulationMode); return; end
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);
            this.SetInt(['/sigouts/' num2str(channelIdx) '/enables/1'], 1)
        end

        %% DisableAmplitude
        function DisableAmplitude(this, channelName)
            % DisableAmplitude(channelName) - disable the output amplitude.
            % channelName - 'SignalOutput1' set as default
            arguments
                this; channelName string = 'SignalOutput1'; % set default
            end
            if(this.SimulationMode); return; end
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);
            % Only one output amplitude /1
            this.SetInt(['/sigouts/' num2str(channelIdx) '/enables/1'], 0)
        end

        %% GetAmplitudeOutput
        function amp_RMS = GetAmplitudeOutput(this, channelName)
            % GetAmplitudeOutput(channelName) - get the output amplitude for the single demodulator in units Vrms.
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

        %% SetRangeOutput
        function SetRangeOutput(this, range, channelName)
            % SetRangeOutput(range, channelName) - define the maximum output voltage that is generated by the
            % corresponding Signal Output.
            % Includes the Signal Amplitudes and Offsets summed up. Need the smallest range possible to optimize
            % signal quality.
            % range - 10m, 100m, 1, 10 in Volts
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
                error("Signal Output Overloaded - Signal clipping occurs and the output signal quality is degraded. " + ...
                    "Input a different range or use AutoRangeOutput function." + ...
                    "Note: Range or amplitude may be automatically adjusted")
            else
                zthis.SetDouble(['/sigouts/' num2str(channelIdx) '/range'], range);
            end
        end

        %% GetRangeOutput
        function output_range = GetRangeOutput(this, channelName)
            % GetRangeOutput(range, channelName) - obtain the maximum output voltage that is generated
            % by the corresponding Signal Output.
            % This includes the Signal Amplitudes and Offsets summed up.
            arguments
                this; channelName {mustBeText} = 'SignalOutput1'; % only one signal output, can set as default
            end
            if(this.SimulationMode); output_range = 1; return; end
            channelIdx = this.ConvertChannelNameToChannelIndex(channelName);

            output_range = this.GetDouble(['/sigouts/' num2str(channelIdx) '/range']);
        end

        %% AutoRangeOutput
        function AutoRangeOutput(this, sigoutIndex)
            % AutoRangeOutput(siginIndex) - automatically adjust range so instrument not overloaded
            % Note: when turned on, need to manually turn off. SetRangeOutput takes this into account.
            arguments
                this; sigoutIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigouts/' num2str(sigoutIndex) '/autorange'], 1); % turn on
        end

        %% SetSignalOutDCOffset
        function SetSignalOutDCOffset(this, value, channelName)
            % SetSignalOutDCOffset(channelName, value) - Set the constant DC
            % voltage being output by a SignalOut port to be voltage 'value' at the device, after taking
            % voltage dividers installed on this channel into account.
            % Note: this immediately 'Enables' the port - there is no Off state, just set to zero for these ports. channelName
            % channelName - 'SignalOutput1' set as default
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

        %% GetSignalOutDCOffset
        function DCoffset = GetSignalOutDCOffset(this, channelName)
            % GetSignalOutDCOffset(channelName)
            % Function to get the DC voltage offset in Volts of the signal output
            arguments
                this; channelName {mustBeText} = 'SignalOutput1';
            end
            if(this.SimulationMode); DCoffset = 0 ;return; end

            channelIndex = this.ConvertChannelNameToChannelIndex(channelName);

            DCoffset = this.GetDouble(['/sigouts/' num2str(channelIndex) '/offset']);
        end

        %% AddAuxInput
        function AddAuxInput(this, sigoutIndex)
            % AddAuxInput(sigoutIndex) - add Aux Input 1 to Signal Output 1
            arguments
                this; sigoutIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigouts/' num2str(sigoutIndex) '/add'], 1); % turned on
        end

        %% EnableDiffOutput
        function EnableDiffOutput(this, sigoutIndex)
            % EnableDiffOutput(sigoutIndex) - switch from single ended to differential mode for signal output
            % In differential mode the signal swing is defined between Signal Output +V / -V.
            arguments
                this; sigoutIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigouts/' num2str(sigoutIndex) '/diff'], 1); % turned on
        end

        %% DisableDiffOutput
        function DisableDiffOutput(this, sigoutIndex)
            % DisableDiffOutput(sigoutIndex) - switch from differential to single ended mode for signal output.
            arguments
                this; sigoutIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigouts/' num2str(sigoutIndex) '/diff'], 0); % turned off
        end

        %% Enable50ImpedOut
        function Enable50ImpedOut(this, siginIndex)
            % Enable50ImpedOut(siginIndex) - enable 50 Ohms load impedance at output.
            % Select the load impedance between 50 Ohms and HiZ.
            % The impedance of the output is always 50 Ohms. For a load impedance of 50 Ohms, the displayed
            % voltage is half the output voltage to reflect the voltage seen at the load - range values half.
            arguments
                this;
                siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            zthis.SetInt(['/sigouts/' num2str(siginIndex) '/imp50'], 1); % turn on
        end

        %% Disable50ImpedOut
        function Disable50ImpedOut(this, siginIndex)
            % Disable50ImpedOut(siginIndex) - disable 50 Ohms load impedance at output.
            arguments
                this; siginIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end
            this.SetInt(['/sigouts/' num2str(siginIndex) '/imp50'], 0); % turn off
        end

        %% SetDemodTrigger
        function SetDemodTrigger(this, demodIndex)
            % SetDemodTrigger(demodIndex) - set the demodulator trigger to continuous data acquisition
            arguments
                this; demodIndex (1,1) double = 0;
            end
            if(this.SimulationMode); return; end

            this.SetInt(['/demods/' num2str(demodIndex) '/trigger'], 0);
        end


        %% Aux Output Parameters
        % AuxOutput used as the DC Offset and connected back into AuxInput therefore not scaled as not
        % connected to device
        %% SetAuxOutVoltage
        function SetAuxOutVoltage(this, channelName, value)
            % SetAuxOutVoltage(channelName, value) - set the constant DC voltage to be used as DC Offset.
            % AuxOutput connected back into AuxInput.
            % value - DC Offset in Volts
            % channelName - 'Aux1', 'Aux2', 'Aux3' or 'Aux4', as string.
            arguments
                this; channelName {mustBeText}; value (1,1) double;
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

        %% SetAuxOutVoltage_Scaled
        % Is this function just needed for UHFLI?
        function SetAuxOutVoltage_Scaled(this, channelName, value)
            % SetAuxOutVoltage(channelName, value) - Set the constant DC
            % voltage being output by an AuxOut port to be voltage 'value' at the device, after taking
            % voltage dividers installed on this channel into account.
            % Note: this immediately 'Enables' the port - there is no Off state, just set to zero for
            % these ports.
            % channelName - 'Aux1', 'Aux2', 'Aux3' or 'Aux4', as string.
            arguments
                this; channelName {mustBeText}; value (1,1) double;
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

        %% GetAuxOutVoltage
        function aux_voltage = GetAuxOutVoltage(this, channelName)
            % GetAuxOutVoltage(channelName, value) - Get the constant DC voltage being output by an AuxOut port.
            % channelName - 'Aux1', 'Aux2', 'Aux3' or 'Aux4', as string.
            arguments
                this; channelName {mustBeText};
            end
            if(this.SimulationMode); aux_voltage = 0; return; end

            % Convert channel name to index to send to instrument
            auxChannelIndex = this.ConvertAuxChannelNameToChannelIndex(channelName);

            % Gives the voltage offset value - gives voltage at lock-in
            aux_voltage = this.GetDouble(['/auxouts/' num2str(auxChannelIndex) '/offset']);
        end

        %% DisableAuxOut
        function DisableAuxOut(this, channelName)
            % DisableAuxOut(channelName)
            % Turn off an Aux output port, setting its offset and scale to 0.
            % channelName - 'Aux1', 'Aux2', 'Aux3' or 'Aux4', as string.
            arguments
                this; channelName {mustBeText};
            end
            if(this.SimulationMode); disp('Aux Output disabled'); return; end

            channelIdx = this.ConvertAuxChannelNameToChannelIndex(channelName);

            this.SetDouble(['/auxouts/' num2str(channelIdx) '/offset'], 0);
            this.SetDouble(['/auxouts/' num2str(channelIdx) '/scale'], 0);
            this.SetDouble(['/auxouts/' num2str(channelIdx) '/preoffset'], 0);
        end


        %% InitialiseSweep
        function sweepHandle = InitialiseSweep(this, auxChannelName, oscIndex, SweepName, SweepParams)
            % InitialiseSweep - Function to initialise a sweep of the DC Aux
            % Output 1 to produce a graph of demodulated amplitude R against the sweep parameter.
            %This is for dI/dV sweeps. Loop back a coax wire from Aux1 out
            %to Aux1 In, and set "Add" to true in the Output panel options
            %in LabOne

            % Measurement method is set to averaging - calculates average on each data set
            % Sets the number of data samples per sweeper parameter point that is considered in the
            % measurement.
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
                case("AuxOutput1")
                    auxIndex = this.ConvertAuxChannelNameToChannelIndex(auxChannelName);
                    gridnode = ['auxouts/' num2str(auxIndex) '/offset'];
                    this.SetAuxOutVoltage(auxChannelName, 0)
                case("OutputOffset")%Using Aux ouput and the Add toggle to add that onto the Signal Output port via a bias tee is reccomended by ZI over setting the offset on SO. This is because it lets you keep a small range setting for Sig Out while applying a large DC offset from the Aux. This is basically for dI/dV measurements
                    sigoutIndex = 0;
                    gridnode = ['sigouts/' num2str(sigoutIndex) '/offset'];
                otherwise
                    error(['Invalid Sweep Parameter for function. ' ...
                        'SweptParameter: Frequency, AuxOutput1, OutputOffset'])
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
                ziDAQ('set', sweepHandle, 'sweep/xmapping', 1);%Not yet tested
            else
                ziDAQ('set', sweepHandle, 'sweep/xmapping', 0); % 0 = linear sweep - spacing between two values is linear
            end
            ziDAQ('set', sweepHandle, 'sweep/scan', 0); % sequential sweep - values change incrementally from small to large

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

        %% Sweep_Abort
        function Sweep_Abort(this, sweepHandle)
            if(this.SimulationMode)
                disp("Sweep aborted");
                return;
            end
            
            if~isempty(sweepHandle)
                ziDAQ('finish', sweepHandle);
            end
        end

        %% Sweep_Check_Completion_Poll_Data
        function [SweepData, complete] = Sweep_Check_Completion_Poll_Data(this, sweepHandle, demodIndex)
            arguments
                this;
                sweepHandle;
                demodIndex (1,1) double = 0;
            end

            SweepData = [];

            if(this.SimulationMode)
                pause(0.1);
                % Do basic simulation of sweep, random values, and not the
                % settings specified in the sweep handle, as we can't
                % access that without a real instrument
                SweepData.SweepValues = linspace(100, 1000, 100)';

                SweepData.Amplitude = rand([100, 1])*1e-5+3e-5;
                SweepData.X = rand([100, 1])*1e-5+2e-5;
                SweepData.Y = rand([100, 1])*0.14e-5+0.2e-5;
                SweepData.Phase = rand([100, 1])*360; % in degrees
                
                %Run a random (but reasonably small)  number of times.
                %Doing anything fancier than everything here would mean
                %passing info in to the instrument it doesn't need in
                %non-debug world
                complete = rand(1) > 0.85;
                return;
            end

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

        %% Sweep_Execute
        function Sweep_Execute(this, sweepHandle)
            % Sweep_Execute(sweepHandle) - Execute a sweep previously set up by OffsetSweep_Initialise, which
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
            ziDAQ('trigger', sweepHandle');            
        end


        %% Scope Data

        %% Scope_Initialise
        function scopeModule = Scope_Initialise(this, DomainSignal, ScopeParams)
            % Scope_Initialise(ScopeParams) - Initialise an FFT or Time Domain measurement
            % of the input signal into the Oscilloscope
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

            % subscribe to the scope's data in the module.
            wave_nodepath = ['/' this.DeviceID '/scopes/0/wave'];
            ziDAQ('subscribe', scopeModule, wave_nodepath);
        end

        %% Scope_Execute
        function data = Scope_Execute(this, scopeModule, SamplingRate)
            % Scope_Execute(scopeModule, ScopeParams) - Execute a measurement of the Scope in time or
            % frequency domain using previously set up parameters by Scope_Initialise
            arguments
                this;
                scopeModule;
                SamplingRate (1,1) double = 6;
            end

            if(this.SimulationMode)
                data.Frequency = linspace(0, 400e3, 2048);
                data.Amplitude = rand([2048,1])*1e-5;
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
                %progress = ziDAQ('progress', scopeModule);
                %fprintf('Scope module has acquired %d records (requested %d). \n', records, min_num_records);

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

            % obtain data
            records = data.(this.DeviceID).scopes(1).wave;

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

        %% GetScopeTimeData
        function scope_value = GetScopeTimeData(this, Calculation, ScopeParams)
            % GetScopeTimeData(Calculation, ScopeParams) - get the maximum amplitude of input signal
            % pk of current or voltage amplitude
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

            if(strcmp(Calculation, 'Max'))
                % max value of scope data
                scope_value = max(timeData.Amplitude);
            elseif(strcmp(Calculation, 'Avg'))
                % average value of scope data
                scope_value = mean(timeData.Amplitude);
            elseif(strcmp(Calculation, 'Min'))
                % min value of scope data
                scope_value = min(timeData.Amplitude);
            end
        end

        %% SetScopeResolution
        function SetScopeResolution(this, resolution)
            % SetResolution(resolution, sample_rate) - calculates the length of recorded scope shot for
            % a given sampling rate to give the required resolution.
            arguments
                this; resolution;
            end
            if(this.SimulationMode); return; end

            sample_rate = this.GetScopeSampleRate();

            length = sample_rate/resolution;

            this.SetInt('/scopes/0/length', length);
        end

        %% GetScopeResolution
        % resolution functions give a rough indication of values - often
        % values rounded to nearest integer or most appropriate value
        function resolution = GetScopeResolution(this)
            % GetScopeResolution(this) - get the spectral resolution of the scope in Hz
            arguments
                this
            end
            if(this.SimulationMode); resolution = 14; return; end % in [Hz]

            % sample rate of scope
            sample_rate = this.GetScopeSampleRate();

            % length of recorded scope shot
            length = this.GetDouble('/scopes/0/length');

            % calculate acquistion time
            acq_time = length/double(sample_rate);
            % reciprocal of acquistion time
            resolution = 1/acq_time;
        end

        %% GetScopeLength
        function length = GetScopeLength(this)
            % GetScopeLength
            % Function to get the length of a scope segment
            arguments
                this;
            end
            if(this.SimulationMode); length = 1000; return; end

            length = this.GetInt('/scopes/0/length');
        end

        %% SetScopeFreqMax
        function SetScopeFreqMax(this, maxFreq)
            % SetScopeFreqMax(maxFreq) - set the frequency range of the Scope FFT
            % Function will give closest to required maximum frequency value as possible as sampling rate
            % are specified and encoded as integers in LabOne
            arguments
                this; maxFreq;
            end
            if(this.SimulationMode); return; end
            sample_rate = maxFreq*2;

            % if sample rate half way between given sample rate values, set
            % integer value
            if(sample_rate <= 1.3e3)
                int = 16;
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
                error('Out of frequency range')
            end

            this.SetInt('/scopes/0/time', int);

        end

        %% GetScopeSampleRate
        function sample_rate = GetScopeSampleRate(this)
            % GetScopeSampleRate - obtain the scope sampling rate in Hz
            arguments
                this;
            end
            if(this.SimulationMode); sample_rate = 938000; return; end % in [Hz]

            sample_index = this.GetInt('/scopes/0/time');
            % calculate sample rate from index
            sample_rate = 60e6/2^sample_index;
        end

        %% GetScopeSampleRateInt
        function int = GetScopeSampleRateInt(this)
            % GetScopeSampleRateInt - get the sampling rate of the scope as an integer
            arguments
                this;
            end
            if(this.SimulationMode); int = 6; return; end
            int = this.GetInt('/scopes/0/time');
        end


        %% DAQ Data
        %% DemodPath_Time
        function [demod_path, demod_path_us, path] = DemodPath_Time(this, DemodSignal, demodIndex)
            % DemodPath_Time(DemodSignal, demodIndex) - get the path for the demodulated signal in the Time Domain
            % Outputs:
            % demod_path - node from which data will be recorded
            % demod_path_us - dots in signal
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
                error('Invalid DemodSignal name - can be X, Y, R or Theta')
            end

        end

        %% DemodPath_FFT
        function [demod_path, demod_path_us, path] = DemodPath_FFT(this, DemodSignal, demodIndex)
            % DemodPath_FFT(DemodSignal, demodIndex) - get the path for the demodulated signal in the
            % Frequency Domain
            % Outputs:
            % demod_path - node from which data will be recorded
            % demod_path_us - dots in signal
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
                error('Invalid DemodSignal name - can be X, Y, R or Theta')
            end
        end

        %% DAQ_Initialise_Both
        function DAQHandle = DAQ_Initialise_Both(this, DemodSignal, demodIndex)
            % DAQ_Initialise_Both(DemodSignal, Domain, DAQParams, demodIndex) - initialise a measurement
            % of the demodulated signal in the time and frequency domain simulaneously using the Data
            % Acquisition module. Gives data set based on a trigger event.
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

        %% DAQ_Execute_Both
        function [daqData_time, daqData_freq] = DAQ_Execute_Both(this, DemodSignal, DAQHandle, time)
            % DAQ_Execute_Both(DemodSignal, Domain, DAQHandle, time) - execute a measurement of the demodulated
            % signal in the time and frequency domain simultaneously using previously set up parameters
            % by DAQ_Initialise_Both
            % time - specifies length of data acquisiton
            % 60s takes long - not necessary to have that much data?
            arguments
                this;
                DemodSignal {mustBeText};  % 'X','Y','R','Phase', 'XiY'
                DAQHandle;
                time (1,1) double = 3;
            end

            if(this.SimulationMode)
                daqData_time.Time = linspace(0, 5, 2^16); %rand([2^16,1]);
                daqData_time.Amplitude = rand([2^16, 1]);
                daqData_freq.Amplitude = rand([2^16/2 + 1, 1]);
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
                    error('Data Acquisition Module didn''t find a trigger level after %.3f seconds.\n', timeout)
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

            daqData_time = [];
            daqData_freq = [];

            % read intermediate data until the dataAcquisitionModule has finished.
            while ~ziDAQ('finished', DAQHandle)
                pause(0.5);
                tmp = ziDAQ('read', DAQHandle);
                %fprintf('dataAcquisitionModule progress %0.0f%%\n', ziDAQ('progress', DAQHandle) * 100)
                % using intermediate reads can obtain continous data
                % obtain data in time or frequency domain
                daqData_time = this.AssembleData_Time(tmp, demod_path_us_time, path_time, clockbase);

                daqData_freq = this.AssembleData_FFT(tmp, demod_path_us_freq, path_freq);

                if toc(t0) > timeout
                    disp(['dataAcquisitionModule stopped after' num2str(timeout) 'seconds.'])
                    break
                end
            end

            % Read and process any remaining data returned by read().
            tmp = ziDAQ('read', DAQHandle);

            daqData_time = this.AssembleData_Time(tmp, demod_path_us_time, path_time, clockbase);

            daqData_freq = this.AssembleData_FFT(tmp, demod_path_us_freq, path_freq);

            ziDAQ('set', DAQHandle, 'enable', 0);

        end

        %% DAQ_Initialise_Time
        function DAQHandle = DAQ_Initialise_Time(this, DemodSignal, demodIndex,GridColumns)
            % DAQ_Initialise_Both(DemodSignal, Domain, DAQParams, demodIndex) - initialise a measurement
            % of the demodulated signal in the time and frequency domain simulaneously using the Data
            % Acquisition module. Gives data set based on a trigger event.
            arguments
                this;
                DemodSignal  {mustBeText};  % 'X','Y','R','Phase', 'XiY'
                demodIndex (1,1) double = 0;
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
            ziDAQ('set', DAQHandle, 'dataAcquisitionModule/device', this.DeviceID);

            % 4 = exact grid mode is chosen - this is most suitable for FFTs
            % the subscribed signal with the highest sampling rate (as sent from the device) defines
            % the interval between samples on the DAQ Module's grid.
            ziDAQ('set', DAQHandle, 'dataAcquisitionModule/grid/mode', 4);
            % specify the number of columns in the returned data grid. Data along horizontal grid is
            % resampled to number of samples defined by grid/cols.
            % number of bins =  2^bits
            ziDAQ('set', DAQHandle, 'dataAcquisitionModule/grid/cols', GridColumns);

            ziDAQ('set',DAQHandle,'dataAcquisitionModule/type',0);

            % subcribe to time node
            if strcmp(DemodSignal,"XiY")
                ziDAQ('subscribe', DAQHandle, demod_path_time_x);
                ziDAQ('subscribe', DAQHandle, demod_path_time_y);
            else
                ziDAQ('subscribe', DAQHandle, demod_path_time);
            end
        end

        %% DAQ_Execute_Time
        function daqData_time = DAQ_Execute_Time(this, DemodSignal, DAQHandle, time)
            % DAQ_Execute_Both(DemodSignal, Domain, DAQHandle, time) - execute a measurement of the demodulated
            % signal in the time and frequency domain simultaneously using previously set up parameters
            % by DAQ_Initialise_Both
            % time - specifies length of data acquisiton
            % 60s takes long - not necessary to have that much data?
            arguments
                this;
                DemodSignal {mustBeText};  % 'X','Y','R','Phase', 'XiY'
                DAQHandle;
                time (1,1) double = 3;
            end

            if(this.SimulationMode)
                daqData_time.Time = linspace(0, 5, 2^16); %rand([2^16,1]);
                daqData_time.Amplitude = rand([2^16, 1]);
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


            timeout = time*2; % 60s - progress almost get to about 100%
            t0 = tic; % start matlab stopwatch timer

            daqData_time = [];
            ziDAQ('set', DAQHandle, 'enable', 1);
            buffer_size = ziDAQ('getDouble', DAQHandle, 'dataAcquisitionModule/buffersize');
            pause(buffer_size * 2.0);

            ziDAQ('sync');
            ziDAQ('execute', DAQHandle);
            data = [];
            while ~ziDAQ('finished', DAQHandle)
                pause(0.05);
            end

            tmp = ziDAQ('read', DAQHandle);
            ziDAQ('finish', DAQHandle);

            if strcmp(DemodSignal,"XiY")
                daqData_time_x = this.AssembleData_Time(tmp, demod_path_us_time_x, path_time_x, clockbase);
                daqData_time_y = this.AssembleData_Time(tmp, demod_path_us_time_y, path_time_y, clockbase);
                daqData_time = [daqData_time_x;daqData_time_y];
            else
                daqData_time = this.AssembleData_Time(tmp, demod_path_us_time, path_time, clockbase);
            end

            ziDAQ('set', DAQHandle, 'enable', 0);

        end

        %% AssembleData_Time
        function daqData = AssembleData_Time(this, tmp, demod_path_us, path, clockbase)
            % AssembleData_Time(tmp, demod_path_us, path, clockbase) - obtain the demodulated signal
            % in the time domain
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

        %% AssembleData_FFT
        function daqData = AssembleData_FFT(this, tmp, demod_path_us, path)
            % AssembleData_FFT(tmp, demod_path_us, path) - obtain the demodulated signal in
            % the frequency domain
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

    end


    methods(Static)
        %% Convert Cartesian to Polar Coordinates
        function [R, theta] = ConvertCartesian(x, y)
            % ConvertCartesian(x,y) - convert Cartesian coordinates to Polar coordinates.
            % x and y in Volts
            % outputs R (RMS voltage) in Volts and theta in degrees
            arguments
                x; y;
            end
            R = sqrt(x^2 + y^2);
            theta = atand(y/x); % degrees
        end

        %% Convert BW into TC
        function TC_convert = ConvertBWtoTC(BW, order)
            % ConvertBWtoTC(BW,order) - convert bandwidth frequency to time constant for a given filter order.
            % BW - 3 dB frequency bandwidth in Hz. Equivalent to cut-off frequency.
            % order - filter order
            % Time constant obtained can be inputted into SetTimeConstant.
            arguments
                BW;
                order {mustBeInRange(order, 1, 8)}; % FO depends on filter order - table of conversions
            end
            % each filter order has a corresponding factor FO that depends on filter slope
            switch order
                case 1
                    FO = 1.0;
                case 2
                    FO = 0.6436;
                case 3
                    FO = 0.5098;
                case 4
                    FO = 0.4350;
                case 5
                    FO = 0.3856;
                case 6
                    FO = 0.3499;
                case 7
                    FO = 0.3226;
                case 8
                    FO = 0.3008;
                otherwise
                    error('Error: Order (%d) must be between 1 and 8!\n', order);
            end
            % equation to give time constant from bandwidth frequency
            TC_convert = FO / (2*pi*BW);
        end

        %% Convert TC into BW
        function BW_convert = ConvertTCtoBW(TC, order)
            % ConvertTCtoBW(TC,order) - convert time constant to bandwidth frequency for a given filter order.
            % TC - time constant in seconds
            % order - filter order
            arguments
                TC;
                order {mustBeInRange(order, 1, 8)}; % FO depends on filter order - table of conversions
            end
            % each filter order has a corresponding factor FO that depends on filter slope
            switch order
                case 1
                    FO = 1.0;
                case 2
                    FO = 0.6436;
                case 3
                    FO = 0.5098;
                case 4
                    FO = 0.4350;
                case 5
                    FO = 0.3856;
                case 6
                    FO = 0.3499;
                case 7
                    FO = 0.3226;
                case 8
                    FO = 0.3008;
                otherwise
                    error('Error: Order (%d) must be between 1 and 8!\n', order);
            end

            % equation to give bandwidth frequency from time constant
            BW_convert = FO / (2*pi*TC);
        end

        %% ConvertScopeInputNameToIndex
        function channelIdx = ConvertScopeInputNameToIndex(channelName)
            % ConvertScopeInputNameToIndex(channelName) - convert channel name input into the scope into an index
            % more than 3 indexes are possible
            if(strcmp(channelName, 'SignalInput1'))
                channelIdx = 0;
            elseif(strcmp(channelName, 'CurrentInput1'))
                channelIdx = 1;
            elseif(strcmp(channelName, 'SignalOutput1'))
                channelIdx = 12;
            end
        end

    end

    methods (Access = protected)

        %% GetPropertiesToIgnore
        function propertiesToIgnore = GetPropertiesToIgnore(this)
            %MFLI does not connect in the usual way, has a device ID only -
            %hide all these connection options in the GUI..
            propertiesToIgnore = {"GPIB_Address", "IP_Address", "Serial_Address", "VISA_Address"};
        end

        %% GetDouble
        function val = GetDouble(this, command)
            if(this.SimulationMode)
                val = 0;
                return;
            end

            %Query value from instrument via ZI Matlab API
            val = ziDAQ('getDouble', ['/' this.DeviceHandle char(command)]);
        end

        %% GetInt
        function val = GetInt(this, command)
            if(this.SimulationMode)
                val = 0;
                return;
            end

            %Query value from instrument via ZI Matlab API
            val = ziDAQ('getInt', ['/' this.DeviceHandle char(command)]);
        end

        %% SetDouble
        function SetDouble(this, command, value)
            if(this.SimulationMode)
                return;
            end

            %Relay command to instrument via ZI Matlab API
            ziDAQ('setDouble', ['/' this.DeviceHandle char(command)], value);
        end

        %% SetInt
        function SetInt(this, command, value)
            if(this.SimulationMode)
                return;
            end

            %Relay command to instrument via ZI Matlab API
            ziDAQ('setInt', ['/' this.DeviceHandle char(command)], value); % turned on
        end

        %% ConvertInputChannelNameToChannelIndex
        function channelIdx = ConvertInputChannelNameToChannelIndex(~, channelName)
            % ConvertInputChannelNameToChannelIndex(channelName)
            % Function to convert input channel name to index to send to instrument.
            % There are 11 possible input channels. The input channel is connected to the demodulator.

            if(strcmp(channelName, 'SignalInput1'))
                channelIdx = 0;
            elseif(strcmp(channelName, 'CurrentInput1'))
                channelIdx = 1;
            elseif(strcmp(channelName, 'Trigger1'))
                channelIdx = 2;
            elseif(strcmp(channelName, 'Trigger2'))
                channelIdx = 3;
            elseif(strcmp(channelName, 'AuxOut1'))
                channelIdx = 4;
            elseif(strcmp(channelName, 'AuxOut2'))
                channelIdx = 5;
            elseif(strcmp(channelName, 'AuxOut3'))
                channelIdx = 6;
            elseif(strcmp(channelName, 'AuxOut4'))
                channelIdx = 7;
            elseif(strcmp(channelName, 'AuxIn1'))
                channelIdx = 8;
            elseif(strcmp(channelName, 'AuxIn2'))
                channelIdx = 9;
            else
                error(['Invalid channelName in ZI_MFLI ConvertInputChannelNameToChannelIndex, was ' num2str(channelName)]);
            end
        end

        %% ConvertInputChannelIndexToChannelName
        function channelName = ConvertInputChannelIndexToChannelName(~, channelIdx)
            % ConvertInputChannelIndexToChannelName(channelIdx)
            % Function to convert input channel index to name to send to instrument.
            % There are 11 possible input channels. The input channel is connected to the demodulator.

            if channelIdx == 0
                channelName ='SignalInput1';
            elseif channelIdx == 1
                channelName = 'CurrentInput1';
            elseif channelIdx == 2
                channelName ='Trigger1';
            elseif channelIdx == 3
                channelName = 'Trigger2';
            elseif channelIdx == 4
                channelName = 'AuxOut1';
            elseif channelIdx == 5
                channelName = 'AuxOut2';
            elseif channelIdx == 6
                channelName = 'AuxOut3';
            elseif channelIdx == 7
                channelName = 'AuxOut4';
            elseif channelIdx == 8
                channelName = 'AuxIn1';
            elseif channelIdx == 9
                channelName = 'AuxIn2';
            else
                error('Invalid channel index in ZI_MFLI ConvertInputChannelIndexToChannelName');
            end
        end

        %% ConvertChannelNameToChannelIndex
        function channelIdx = ConvertChannelNameToChannelIndex(~, channelName)
            % ConvertChannelNameToChannelIndex(channelName)
            % Convert output channel name to index to send to instrument - MFLI only has one signal output
            if(strcmp(channelName, 'SignalOutput1'))
                channelIdx = 0;
            else
                error(['Invalid channelName in ZI_MFLI ConvertChannelNameToChannelIndex. ChannelName can be SignalOutput1, was ' num2str(channelName)]);
            end
        end

        %% ConvertAuxChannelNameToChannelIndex
        function channelIdx = ConvertAuxChannelNameToChannelIndex(~, channelName)
            % ConvertAuxChannelNameToChannelIndex(channelName)
            % Convert channel name of aux channel ('Aux1', 'Aux2', 'Aux3', 'Aux4' to index
            % to send to instrument and error checking.

            if(strcmp(channelName, 'Aux1'))
                channelIdx = 0;
            elseif(strcmp(channelName, 'Aux2'))
                channelIdx = 1;
            elseif(strcmp(channelName, 'Aux3'))
                channelIdx = 2;
            elseif(strcmp(channelName, 'Aux4'))
                channelIdx = 3;
            else
                error(['Invalid channelName in ZI_MFLI ConvertAuxChannelNameToChannelIndex. ChannelName can be Aux1, Aux2, Aux3, Aux4, was ' num2str(channelName)]);
            end
        end

        %% GetSuppliedVoltageOrCurrentAndUnits
        function [magnitude, unit, name] = GetSuppliedVoltageOrCurrentAndUnits(this)

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
                    error("Connected current source option " + this.ConnectedCurrentSource + " not implemented in MFLI");
            end
        end
    end

    methods (Static, Access = private)

        %% ZIConnect
        function deviceHandle = ZIConnect(deviceID, interface)
                      
            % Check the ziDAQ MEX (DLL) and Utility functions can be found in Matlab's path.
            if ~(exist('ziDAQ', 'file') == 3) && ~(exist('ziCreateAPISession', 'file') == 2)
                fprintf('Failed to either find the ziDAQ mex file or ziDevices() utility.\n')
                fprintf('Please configure your path using the ziDAQ function ziAddPath().\n')
                fprintf('This can be found in the API subfolder of your LabOne installation.\n');
                fprintf('On Windows this is typically:\n');
                fprintf('C:\\Program Files\\Zurich Instruments\\LabOne\\API\\MATLAB2012\\\n');
                return
            end

            % The API level 5 gives full functionality for an MFLI
            % according to the ziDAQ.m metadata comments
            supported_apilevel = 5;

            %Connect to a dataserver if not already connected, then connect
            %this device to that. Assumes LabOne is installed and running on
            %the PC, not internally on the MFLI. See comments in ZI_HandleConnect_LabOneServerRunningOnPC
            deviceHandle = CoakView.Instruments.ZI_MFLI.ZI_HandleConnect_LabOneServerRunningOnPC(deviceID, interface, supported_apilevel);

            %Check the API and firmware are the same version. Not required but
            %a nice error check
            ziApiServerVersionCheck();

        end    

        %% ZI_HandleConnect
        function device = ZI_HandleConnect(device_serial, maximum_supported_apilevel)
            %Simplified version of the ziCreateAPISession Util - without
            %the clear command at the start among other changes, as that
            %looked to stop us ever having 2 devices connected..

            % Determine the device identifier from it's serial/id
            device = lower(ziDAQ('discoveryFind', device_serial));

            % Get the device's default connectivity properties.
            props = ziDAQ('discoveryGet', device);

            %Check the device is there and discoverable
            assert(props.discoverable, "The specified device " + string(device_serial) + " is not discoverable from the API. Please ensure the device is powered-on and visible using the LabOne User Interface or ziControl.");
            
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

        %% ZI_HandleConnect_LabOneServerRunningOnPC
        function deviceHandle = ZI_HandleConnect_LabOneServerRunningOnPC(device_serial, interface, apilevel, server_address, port_number)
            %Need to use this if want to be able to connect more than one ZI instrument at once as ziDAQ is a static/global object in the
            %MATLAB API, cannot have 2 instances.
            %See emails from 15/4/2025 with ZI. Look in MFLI manual under
            %the MDS option and the 2.5. Running LabOne on a Separate PC
            %section - LabOne can run on the internal PC in the instrument
            %with no installation on the PC, but we need to run it on the
            %PC running CoakView (which is a 'seperate PC' in this
            %parlance, it means separate to the MFLI's internals). This
            %function connects to MFLIs configured in that manner

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
