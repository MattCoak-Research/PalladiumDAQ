classdef Keithley24X0 < CoakView.Core.Instrument
    %Instrument implementation for Keithley 2400 and 2410 source meters.
    %Note that this assumes the instrument is measuring already - just reads data.

    properties(Access = public, SetObservable)
        FullName = "Keithley 24X0 Src Meter";       %Full name, just for displaying on GUI
        Name = "SrcMtr";                            %Instrument name
        Connection_Type = CoakView.Enums.ConnectionType.GPIB;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        MeasMode;                                   %Resistance, Voltage, Current
        SourceMode;                                 %Current, Voltage
        OffsetComp = false;
    end

    properties(Access = private)
        DefaultGPIB_Address = 24;          %GPIB address
    end

    methods

        %% Categoricals
        function catOut = MeasType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Resistance", "Voltage", "Current"]); end
        function catOut = SourceType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Voltage", "Current"]); end

        %% Constructor
        function this = Keithley24X0()
            this.GPIB_Address = this.DefaultGPIB_Address;
            this.ConnectionSettings.GPIB_Terminators = ["LF" "LF"];

            %Make sure to set values for Properties of Categorical type
            %like these
            this.MeasMode = this.MeasType("Resistance");
            this.SourceMode = this.SourceType("Current");
        end

        %% CreateInstrumentControl
        function CreateInstrumentControl(this, tab, controller)
            %Create grid and Sweepcontrol component and position them in the
            %tab.
            grid = uigridlayout(tab, "ColumnWidth", {10, 'fit', '1x'}, "RowHeight", {10, 'fit', 10, '1x'}, 'RowSpacing', 2);
            comp = CoakView.Instruments.Controls.SweepSetupControl(grid);
            comp.Layout.Row = 2;
            comp.Layout.Column = 2;

            %Set title and metadata
            comp.SetTitle(this.Name + " Sweep Control");
            switch(this.SourceMode)
                case(this.MeasType("Voltage"))
                    comp.SetUnitsString("V");
                    comp.SetLimits(-50, 50);    %Need to check what these physical limits actually are and improve this
                case(this.MeasType("Current"))
                    comp.SetUnitsString("A");
                    comp.SetLimits(-1, 1); %Need to check what these physical limits actually are and improve this
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

            %Subscribe to events
            addlistener(comp, 'Run', @(src,evnt)this.SweepRun(src,evnt));
            addlistener(comp, 'Abort', @(src,evnt)this.SweepAbort(src,evnt));

            this.SweepControlPanel = comp;

            %Add a plotter as well underneath
            pltr = controller.AddNewPlotter(grid);
            pltr.Layout.Row = [2 4];
            pltr.Layout.Column = 3;

            %Set default displayed axes for the plotter
            pltr.SetXAxisVariable("Time (mins)");
        end

        %% GetSupportedConnectionTypes
        function connectionTypes = GetSupportedConnectionTypes(this)
            connectionTypes = [...
                CoakView.Enums.ConnectionType.Debug,...
                CoakView.Enums.ConnectionType.GPIB,...
                CoakView.Enums.ConnectionType.VISA,...
                CoakView.Enums.ConnectionType.Ethernet,...
                CoakView.Enums.ConnectionType.Serial,...
                CoakView.Enums.ConnectionType.USB...
                ];
        end

        %% GenerateTabNames
        function names = GenerateTabNames(this)
            names = this.Name + " SweepControl";
        end

        %% SweepRun
        function SweepRun(this, src, eventData)
            sweepMode = CoakView.Enums.SweepMode.Stepped;
            this.SweepController = CoakView.Instruments.Controllers.SweepController(sweepMode, eventData.SweepDetails);
        end

        %% SweepAbort
        function SweepAbort(this, src, eventData)
            this.SweepController = [];
        end

        %% SweepComplete
        function SweepComplete(this)
            this.SweepController = [];
            this.SweepControlPanel.SweepComplete();
        end

        %% GetAvailableControlOptions
        function [controlDetailsStructs] = GetAvailableControlOptions(this)
            %Tell the GUI what options for Control GUIs to create
            controlDetailsStructs = struct(...
                "Name", "Sweep Control",...
                "ControlClassFileName", "SweepController_Stepped",...
                "TabName", "Sweep Control",...
                "EnabledByDefault", false);
        end

        %% GetSweepUnitsString
        function [str, limits, xlabelStr, ylabelStr] = GetSweepUnitsString(this)
            switch(this.SourceMode)
                case(this.MeasType("Voltage"))
                    xlabelStr = "Source Voltage (V)";
                    str = "V";
                    limits = [-50, 50];    %Need to check what these physical limits actually are and improve this
                case(this.MeasType("Current"))
                    xlabelStr = "Source Current (A)";
                    str = "A";
                    limits = [-1, 1]; %Need to check what these physical limits actually are and improve this
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

            hdrs = this.GetHeaders();
            ylabelStr = hdrs(1);
        end

        %% GetHeaders
        function [Headers, Units] = GetHeaders(this)
            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    Headers = [this.Name + " - Resistance_Ohms", this.Name + " - Current_A", this.Name + " - Voltage_V"];
                    Units = ["Ohms", "A", "V"];
                case(this.MeasType("Voltage"))
                    Headers = [this.Name + " - Current_A", this.Name + " - Voltage_V"];
                    Units = ["A", "V"];
                case(this.MeasType("Current"))
                    Headers = [this.Name + " - Voltage_V", this.Name + " - Current_A"];
                    Units = ["V", "A"];
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + string(this.MeasMode));
            end
        end

        %% Measure
        function [dataRow] = Measure(this)

            sweepActive =  ~isempty(this.SweepController) && this.SweepController.Running;

            %Update attached SweepController, if it exists
            if sweepActive
                valueToSet = this.SweepController.Update();

                %Set the source ouput to the new value
                this.SetSourceLevel(valueToSet, true);

                %And now wait for the set Settle Time for that change
                %to take place before measuring
                this.SweepController.WaitSettleTime();
            end

            if(this.SimulationMode)
                %Dummy values
                resistance = 10 + 0.1*rand();
                current = 5 + 0.01*rand();
                voltage =1 + 0.01*rand;

                if sweepActive
                    switch(this.SourceMode)
                        case(this.SourceType("Voltage"))
                            voltage = valueToSet;
                        case(this.SourceType("Current"))
                            current = valueToSet;
                    end
                end
            else
                %Query the source meter for latest measurement and get a string
                %returned. example for a 184 kOhm resistor with 10 microA current: '+1.839736E+00,+9.999968E-06,+1.839742E+05,+6.482821E+04,+4.506000E+04'
                if(this.OffsetComp)
                    %Error if not in Ohms mode
                    if(this.MeasMode ~= this.MeasType("Resistance"))
                        error("OffsetComp only functions in Resistance Mode");
                    end

                    %Store the currently set source level
                    sourceLvl = this.GetSourceLevel();

                    %Set to zero source level and measure
                    this.SetSourceLevel(0, true);
                    data = this.QueryString("MEAS?");
                    [voltage1, current1, resistance1] = this.ParseDataString(data);

                    %Set to initial source level and measure
                    this.SetSourceLevel(sourceLvl, true);
                    data = this.QueryString("MEAS?");
                    [voltage2, current2, resistance2] = this.ParseDataString(data);

                    resistance = resistance2 - resistance1;
                    voltage = voltage2; %Maybe should do something a bit more clever with these? Depending on source mode?
                    current = current2;
                else
                    data = this.QueryString("MEAS?");
                    [voltage, current, resistance] = this.ParseDataString(data);
                end
            end

            %Assign data to output data row
            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    dataRow = [resistance, current, voltage];
                    %Update attached SweepController, if it exists
                    if sweepActive
                        switch(this.SourceMode)
                            case(this.SourceType("Voltage"))
                                this.SweepController.UpdateData(voltage, resistance);
                            case(this.SourceType("Current"))
                                this.SweepController.UpdateData(current, resistance);
                        end
                    end

                case(this.MeasType("Voltage"))
                    dataRow = [current, voltage];

                    %Update attached SweepController, if it exists
                    if sweepActive
                        this.SweepController.UpdateData(current, voltage);
                    end

                case(this.MeasType("Current"))
                    %Assign data to output data row
                    dataRow = [voltage, current];

                    %Update attached SweepController, if it exists
                    if sweepActive
                        this.SweepController.UpdateData(voltage, current);
                    end

                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + this.MeasMode);
            end
        end

        %% GetSourceLevel
        function [srcLevel, srcEnabled] = GetSourceLevel(this)
            %Returns in amps.
            if(this.SimulationMode)
                %Dummy values
                srcLevel = 1.5;
                srcEnabled = true;
            else
                %Query whether the source is enabled
                enabled = this.QueryDouble("OUTP?");
                srcEnabled = (enabled == 1);

                switch(this.SourceMode)
                    case(this.SourceType("Voltage"))
                        srcLevel = this.QueryDouble("SOUR:VOLT:LEV:AMPL?");
                    case(this.SourceType("Current"))
                        srcLevel = this.QueryDouble("SOUR:CURR:LEV:AMPL?");
                    otherwise
                        error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
                end
            end
        end

        %% SetSourceLevel
        function SetSourceLevel(this, level, enableOutput)
            if(this.SimulationMode)
                %Do nothing
                return;
            end

            %Turn output on or off
            if(enableOutput)
                this.WriteCommand("OUTP ON");
            else
                this.WriteCommand("OUTP OFF");
            end

            switch(this.SourceMode)
                case(this.SourceType("Voltage"))
                    this.WriteCommand("SOUR:VOLT:LEV " + num2str(level));
                case(this.SourceType("Current"))
                    this.WriteCommand("SOUR:CURR:LEV " + num2str(level));
                otherwise
                    error("Source mode must be Voltage or Current, received " + string(this.SourceMode));
            end

        end
    end

    methods (Access = private)

        %% ParseDataString
        function [voltage, current, resistance] = ParseDataString(this, data)
            %Split the string into a cell array, split at the commas
            splitData = strsplit(data, ',');

            switch(this.MeasMode)
                case(this.MeasType("Resistance"))
                    %Get measurement values from the split string
                    voltage = str2double(splitData{1});
                    current = str2double(splitData{2});
                    resistance = str2double(splitData{3});
                    %Not sure what 4 and 5 are right now..

                case(this.MeasType("Voltage"))
                    %Get measurement values from the split string
                    voltage = str2double(splitData{1});
                    current = str2double(splitData{2});
                    resistance = NaN;

                case(this.MeasType("Current"))
                    %Get measurement values from the split string
                    voltage = str2double(splitData{1});
                    current = str2double(splitData{2});
                    resistance = NaN;
                otherwise
                    error("Mode must be Resistance, Voltage, or Current, this was " + string(this.MeasMode));
            end
        end
    end
end

