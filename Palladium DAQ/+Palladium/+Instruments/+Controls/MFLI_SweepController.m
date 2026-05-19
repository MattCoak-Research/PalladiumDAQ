classdef MFLI_SweepController < Palladium.Core.InstrumentControlBase
    %MFLI_SweepController - Logic controller add-on object to be added on to an
    %Instrument object, where it will handle the logic of controlling data
    %collection and independent logging of sweeps on a Zurich Instruments
    %MFLI

    %% Properties (Public, Private Set)
    properties (GetAccess = public, SetAccess = protected)
        Running = false;
        TimeElapsed_s = 0;
    end

    %% Properties (Private)
    properties (Access = private)
        SweepHandle = [];
        GUIView;
        Data;
        Plotter;
        DataWriter;
        timerVal;   %Used for tracking Elapsed Time since sweep started, with tic/toc
        CachedSweepRunFunction = [];
    end

    %% Constructor
    methods
        function this = MFLI_SweepController()
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function AbortSweep(this, ~, ~)
            this.Running = false;
            this.TimeElapsed_s = 0;
            this.OnSweepAbort();
        end

        function CreateInstrumentControlGUI(this, controller, tab, instrRef)
            %Make a specific reference to and from the Instrument Class
            this.Instrument = instrRef;

            %Create grid and TempControl component and position them in the
            %tab.
            grid = uigridlayout(tab, "ColumnWidth", {'fit', '1x'}, "RowHeight", {10, '1x', 10}, 'RowSpacing', 2);

            %Create a .mlapp custom GUI control and add it to the grid
            comp = Palladium.Instruments.Controls.MFLISweepControlPanel(grid);
            comp.Layout.Row = 2;
            comp.Layout.Column = 1;

            %Store the reference to this View as a property
            this.GUIView = comp;
            this.GUIView.SetName(instrRef.Name + " - Sweep Control");

            %Subscribe to events
            addlistener(comp, 'RunSingleSweep', @(src,evnt)this.RunSweep(src, evnt));
            addlistener(comp, 'StopSweep', @(src,evnt)this.AbortSweep(src, evnt));
            addlistener(comp, 'InsertSmartTag', @(src,evnt)this.InsertSmartTagRequest(src, evnt, controller));

            %Add a plotter as well, to the right
            this.Plotter = controller.AddNewPlotter(grid, Size="Medium", RegisterPlotter=false);    %Don't register the plotter centrally, as we will push data to it only when the sweep is running, and clear it on sweep start. This does mean, for now at least, that the Plotter is not hooked up
            this.Plotter.Layout.Row = 2;
            this.Plotter.Layout.Column = 2;
            ltr = addlistener(this.Plotter, 'AxesSelectionChange', @(src,evnt)this.PlotterAxesSelectionChange(src));
            this.RegisterEventListener(ltr);
        end


        function OnSweepAbort(this)

            %Write the data (will check if Save to File is selected)
            this.WriteData(this.DataArray);

            %Abort the sweep and clear the handle reference to the sweep
            %object
            this.SweepHandle = [];
            this.Instrument.Sweep_Abort(this.SweepHandle);
        end

        function OnSweepComplete(this, sweepData)
            this.SweepHandle = [];
            this.Running = false;
sweepData
            %Plot the data
            this.Plotter.PlotData(sweepData);

            %Write the data (will check if Save to File is selected)
            this.WriteData(sweepData)

            %Update the View
            this.GUIView.SweepComplete();

            %Loop the next one if in Continuous mode
            if this.GUIView.IsContinuousSelected()
                this.GUIView.RunSweep();
            end
        end

        function CacheSweepRunFunction(this, sweepData)
            %Run commands will come asynchronously, as they are event
            %based. Cache the function to run, don't run it immediately, to
            %make sure it always executes at a well-defined time in the
            %measurement tick cycle
            this.CachedSweepRunFunction = @()this.StartSweep(sweepData);
        end

        function OnSweepRun(this, sweepData)
            %Unpack the settings from the eventData struct for convenience
            FileParams = sweepData.FileParams;
            this.ControlDetailsStruct.SweepDetails = FileParams;

            %Clear any existing data from previous sweeps
            this.ClearData();

            %Create data writer if a data file is being written
            this.CreateDataFile(sweepData, this.ControlDetailsStruct.SweepDetails.SaveSweepFile);
            this.UpdatePlotterSavedPlotTitle();
        end

        function RemoveControl(this, ~)
            %Delete GUI objects
            delete(this.GUIView);
            this.GUIView = [];
        end

        function RunSweep(this, ~, eventData)
            this.Running = true;
            this.TimeElapsed_s = 0;
            this.timerVal = tic();
            this.CacheSweepRunFunction(eventData.Value);
            this.OnSweepRun(eventData.Value);
        end

        function Update(this)

            if ~isempty(this.CachedSweepRunFunction)
                %Execute the function (will be the command to actually
                %start a sweep, so it is synchronous), and then clear that
                %cache so it doesn't execute again
                try
                    this.CachedSweepRunFunction();
                catch ME
                    this.CachedSweepRunFunction = [];
                    rethrow(ME);
                end

                this.CachedSweepRunFunction = [];

                %Wait until next tick to do anything with this
                return;
            end

            if this.Running
                %Ping the instrument for data so far, and if the sweep is
                %complete
                [sweepData, complete] = this.Instrument.Sweep_Check_Completion_Poll_Data(this.SweepHandle);

                if ~isempty(sweepData)
                    %Unpack data into an array
                    unpackedData = [sweepData.SweepValues,...
                        sweepData.Amplitude,...
                        sweepData.Phase,...
                        sweepData.X,...
                        sweepData.Y];

                    %Cache the data - in case we abort, we can write the
                    %data-so-far to file
                    this.DataArray = unpackedData;

                    %Plot the data
                    % this.Plotter.PlotData(unpackedData);

                    %Plot any data - this is a relic of having a SimplePlotter
                    % if ~isempty(SweepData.SweepValues)
                    %      this.UpdateData(SweepData.SweepValues, SweepData.Amplitude);
                    %  end

                end

                %Handle the sweep completion if it is finished
                if complete
                    disp("MFLI Sweep Complete"); %If I remove this line.. every other sweep doesn't write to file, just empty lines after the header?
                    this.OnSweepComplete(unpackedData);
                end

            end
        end

        function UpdateData(this, dataRow, headers) %#ok<INUSD>
        end

        function MeasurementsInitialised(this, ~, eventArgs)
            headers = eventArgs.Headers;
            this.AvailableHeaders = headers;

            sweepPlotHeaders = ["SweepValues", "Amplitude", "Phase", "X", "Y"];
            this.Plotter.UpdateVariables(sweepPlotHeaders);
        end

        function MeasurementsStarted(this, ~, ~, ~)
            this.UnlockRunButton();
        end

        function MeasurementsStopped(this, ~, ~, ~)
            this.GUIView.AbortSweep();
            this.LockRunButton();
        end

        function LockRunButton(this)
            this.GUIView.LockRunButton();
        end

        function UnlockRunButton(this)
            this.GUIView.UnlockRunButton();
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function CreateDataFile(this, sweepParams, writeToFile)
            %Create or reset the data writer class
            fileNameSuffix = this.ControlDetailsStruct.SweepDetails.FileName;
            this.DataWriter = this.InitialiseDataWriter(fileNameSuffix);

            %Built in functions in base class will write the data row of all instruments/diagnostics at the start
            %of the sweep, for things like temperature, time
            %Write the metadata string for this instrument - frequencies,
            %voltages, settings etc

            %Assemble some sweep metadata
            sweepMetadataDescLine = "Sweep Parameters:";
            sweepMetadataLine = this.CreateSweepMetaDataLine(sweepParams);

            %Get headers for the sweep data - not the same as overall
            %programme DataRow headers.
            headers = this.GetHeaders(sweepParams);

            %Create new file and write metadata and headers
            extraMetadataLines = [sweepMetadataDescLine, sweepMetadataLine];
            this.StartNewDataFile(this.DataWriter, headers, extraMetadataLines, writeToFile);
        end

        function ClearData(this)
            %   this.Plotter.ClearData();
        end



        function stringLine = CreateSweepMetaDataLine(this, sweepParams) %#ok<INUSD>
            SweepName = sweepParams.SweepName;
            SweepParams = sweepParams.SweepParams;
            FileParams = sweepParams.FileParams; %#ok<NASGU>

            stringLine = "SweepType: " + SweepName;

            sweepParamsStr = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", SweepParams);

            stringLine = stringLine + " || Parameters: " + sweepParamsStr;
        end

        function headersString = GetHeaders(this, sweepParams) %#ok<INUSD>
            SweepName = sweepParams.SweepName;
            SweepParams = sweepParams.SweepParams; %#ok<NASGU>

            switch(SweepName)
                case("Frequency")
                    xAx = "Frequency (Hz)";
                case("AuxOutput1")
                    xAx = "Voltage (V)";
                case("OutputOffset")
                    xAx = "Voltage (V)";
                otherwise
                    error(['Invalid Sweep Parameter for function. ' ...
                        'SweptParameter: Frequency, AuxOutput1, OutputOffset'])
            end

            headers = [xAx, "Amplitude (V)", "Phase (Deg)", "VoltageX (V)", "VoltageY (V)"];

            %Make a simple string of all these headers, tab seperated
            headersString = '';
            for i= 1 : length(headers)
                headersString = sprintf('%s%s\t', headersString, headers{i});
            end

            %Update the plotter axes labels
            %            this.Plotter.LabelAxes(xAx, "Amplitude (V)");
        end
        function StartSweep(this, eventData)
            %Actually launch a sweep. This is called only via
            %CachedSweepRunFunction, to ensure it gets calls synchronously in
            %the measurement tick each time. RunSweep basically queues this up

            %Unpack the settings from the eventData struct for convenience
            SweepName = eventData.SweepName;
            SweepParams = eventData.SweepParams;
            FileParams = eventData.FileParams;
            this.ControlDetailsStruct.SweepDetails = FileParams;

            %Clear any existing data from previous sweeps
            this.ClearData();

            %Create a sweep object on the instrument
            this.SweepHandle = this.Instrument.Sweep_InitialiseSweep("Aux1", 0,...
                SweepName,...
                "AveSample", SweepParams.AveSample,...
                "AveTC", SweepParams.AveTC,...
                "Bandwidth", SweepParams.Bandwidth,...
                "FilterOrder", SweepParams.FilterOrder,...
                "LogScale", SweepParams.LogScale,...
                "NumberOfSteps", SweepParams.NumberOfSteps,...
                "SettleTime", SweepParams.SettleTime,...
                "SweepInaccuracy", SweepParams.SweepInaccuracy,...
                "Start", SweepParams.Start,...
                "Stop", SweepParams.Stop);

            %Execute the sweep
            this.Instrument.Sweep_Execute(this.SweepHandle);
        end

        function SweepEnded(this)
            this.InsertEndMetadataIntoFile(this.DataWriter);
        end

        function UpdatePlotterSavedPlotTitle(this)
            this.Plotter.TitleForCopiedPlots = this.DataWriter.FileWriteDetails.FileName;
        end

        function WriteData(this, sweepData)
            %Write final details to file if option selected
            if this.ControlDetailsStruct.SweepDetails.SaveSweepFile
                this.DataWriter.WriteData(sweepData);

                %Add in an end-of sweep metadata line
                this.InsertEndMetadataIntoFile(this.DataWriter);
            end
        end

    end
end

