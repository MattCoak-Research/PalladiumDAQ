classdef MFLI_SweepController < CoakView.Core.InstrumentControlBase
    %MFLI_SweepController - Logic controller add-on object to be added on to an
    %Instrument object, where it will handle the logic of controlling data
    %collection and independent logging of sweeps on a Zurich Instruments
    %MFLI

    properties

    end

    properties (GetAccess = public, SetAccess = protected)
        Running = false;
        TimeElapsed_s = 0;
    end

    properties (Access = private)
        SweepHandle = [];
        GUIView;
        Controller;
        Data;
        Plotter;
        DataWriter;
        timerVal;   %Used for tracking Elapsed Time since sweep started, with tic/toc
    end

    methods

        %% Constructor
        function this = MFLI_SweepController()
        end

        %% CreateInstrumentControlGUI
        function CreateInstrumentControlGUI(this, controller, tab, instrRef)
            %Make a specific reference to and from the Instrument Class
            this.Instrument = instrRef;
            this.Instrument.SweepController = this;
            this.Controller = controller;

            %Create grid and TempControl component and position them in the
            %tab.
            grid = uigridlayout(tab, "ColumnWidth", {'fit', '1x'}, "RowHeight", {10, '1x', 10}, 'RowSpacing', 2);

            %Create a .mlapp custom GUI control and add it to the grid
            comp = CoakView.Instruments.Controls.MFLISweepControlPanel(grid);
            comp.Layout.Row = 2;
            comp.Layout.Column = 1;

            %Store the reference to this View as a property
            this.GUIView = comp;
            this.GUIView.SetName(instrRef.Name + " - Sweep Control");

            %Subscribe to events
            addlistener(comp, 'RunSingleSweep', @(src,evnt)this.RunSweep(src, evnt));
            addlistener(comp, 'StopSweep', @(src,evnt)this.AbortSweep(src, evnt));

            %Add a SIMPLE plotter as well, to the right
            this.Plotter = controller.AddNewSimplePlotter(grid, "Medium");
            this.Plotter.Layout.Row = 2;
            this.Plotter.Layout.Column = 2;
        end

        %% RemoveControl
        function RemoveControl(this, instrRef)
            %Clean up references to this in the Lakeshore Instrument Class
            %so it doesn't think we have a heater control
            instrRef.SweepControlPanel = [];

            %Delete GUI objects
            delete(this.GUIView);
            this.GUIView = [];
        end

        %% RunSweep
        function RunSweep(this, ~, eventData)
            this.Running = true;
            this.TimeElapsed_s = 0;
            this.timerVal = tic();
            this.OnSweepRun(eventData.Value);
        end

        %% AbortSweep
        function AbortSweep(this, ~, eventData)
            this.Running = false;
            this.TimeElapsed_s = 0;
            this.OnSweepAbort();
        end


        %% OnSweepAbort
        function OnSweepAbort(this)
            this.Instrument.Sweep_Abort();
            %Todo - make sure to write the data so far on abort - right now
            %only writes at the end
        end

        %% OnSweepComplete
        function OnSweepComplete(this, sweepData)
            this.SweepHandle = [];
            this.Running = false;

            if this.ControlDetailsStruct.SweepDetails.SaveSweepFile
                this.DataWriter.WriteData([sweepData.SweepValues,...
                    sweepData.Amplitude,...
                    sweepData.Phase,...
                    sweepData.X,...
                    sweepData.Y]);

                %Add in an end-of sweep metadata line
                this.InsertEndMetadataIntoFile(this.DataWriter);
            end

            this.GUIView.SweepComplete();
        end

        %% OnSweepRun
        function OnSweepRun(this, eventData)
            %Unpack the settings from the eventData struct for convenience
            SweepName = eventData.SweepName;
            SweepParams = eventData.SweepParams;
            FileParams = eventData.FileParams;
            this.ControlDetailsStruct.SweepDetails = FileParams;

            %Clear any existing data from previous sweeps
            this.ClearData();

            %Set running bool
            this.Running = true;

            %Create data writer if a data file is being written
            if this.ControlDetailsStruct.SweepDetails.SaveSweepFile
                this.CreateDataFile(eventData);
            end

            %Create a sweep object on the instrument
            this.SweepHandle = this.Instrument.InitialiseSweep("Aux1", SweepName,...
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

        %% Update
        function Update(this)
            
            %Ping the instrument for data so far, and if the sweep is
            %complete
            [SweepData, complete] = this.Instrument.Sweep_Check_Completion_Poll_Data(this.SweepHandle);
      
            %Plot any data
            this.UpdateData(SweepData.SweepValues, SweepData.Amplitude);

            %Handle the sweep completion if it is finished
            if complete
                this.OnSweepComplete(SweepData);
            end
        end

        %% UpdateData
        function UpdateData(this, x, y)            
            this.Plotter.PlotData(x, y);           
        end

        %% MeasurementsStarted
        function MeasurementsStarted(this, src, ~, ~)
            this.UnlockRunButton();            
        end
        
        %% MeasurementsStopped
        function MeasurementsStopped(this, src, ~, ~)
            this.LockRunButton();
        end

        %% LockRunButton
        function LockRunButton(this)
            this.GUIView.LockRunButton();
        end

        %% UnlockRunButton
        function UnlockRunButton(this)
            this.GUIView.UnlockRunButton();
        end
    end

    methods (Access = private)


        %% CreateDataFile
        function CreateDataFile(this, sweepParams)
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
            this.StartNewDataFile(this.DataWriter, headers, extraMetadataLines);
        end

        %% ClearData
        function ClearData(this)
            this.Plotter.ClearData();
        end

        %% SweepEnded
        function SweepEnded(this)
            this.InsertEndMetadataIntoFile(this.DataWriter);
        end

        %% CreateSweepMetaDataLine
        function stringLine = CreateSweepMetaDataLine(this, sweepParams)
            SweepName = sweepParams.SweepName;
            SweepParams = sweepParams.SweepParams;
            FileParams = sweepParams.FileParams;

            stringLine = "SweepType: " + SweepName;

            sweepParamsStr = CoakView.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", SweepParams);

            stringLine = stringLine + " || Parameters: " + sweepParamsStr;
        end

        %% GetHeaders
        function headersString = GetHeaders(this, sweepParams)
            SweepName = sweepParams.SweepName;
            SweepParams = sweepParams.SweepParams;

            switch(SweepName)
                case("Frequency")
                    xAx = "Frequency_Hz";
                case("AuxOutput1")
                    xAx = "Voltage_V";
                case("OutputOffset")
                    xAx = "Voltage_V";
                otherwise
                    error(['Invalid Sweep Parameter for function. ' ...
                        'SweptParameter: Frequency, AuxOutput1, OutputOffset'])
            end

            headers = [xAx, "R_V", "Theta_Deg", "X_V", "Y_V"];

            %Make a simple string of all these headers, tab seperated
            headersString = '';
            for i= 1 : length(headers)
                headersString = sprintf('%s%s\t', headersString, headers{i});
            end
        end
    end
end

