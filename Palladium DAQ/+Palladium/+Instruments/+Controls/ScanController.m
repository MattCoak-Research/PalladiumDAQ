classdef ScanController < Palladium.Core.InstrumentControlBase
    %SCANCONTROLLER - Logic controller add-on object to be added on to an
    %Instrument object, where it will handle the logic of running a 'slow'
    %measurement that occurs over multiple measurement ticks. A good
    %example is a VNA, slowly scanning. This is like a SweepController, but
    %without the setting of a ticking up varilable

    %% Properties (Public)
    properties (Access = public)
        PlotterType = "Simple"; %Default or Simple - call before constructing GUI
    end

    %% Properties (Public, Protected Set)
    properties (GetAccess = public, SetAccess = protected)
        Running = false;
        TimeElapsed_s = 0;
    end

    %% Properties (Protected)
    properties (Access = protected)
        GUIView;
        timerVal;   %Used for tracking Elapsed Time since sweep started, with tic/toc
        RestartNextTick = false;
        Aborted = false;
    end

    %% Properties (Private)
    properties (Access = private)
        Data;
        Plotter;
        DataWriter;
        CachedData = [];            %CachedData for the last iteration, ready to be written (need to wait until data fomr other instruments come in)
        DataArray = [];             %Store entire array of dataRows taken during this sweep - need it if we change axes on a Plotter mid-sweep
    end

    %% Constructor
    methods
        function this = ScanController()
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function complete = CheckComplete(this)
            complete = this.Instrument.CheckScanComplete();
        end

        function ClearData(this)
            this.Data.X = [];
            this.Data.Y = [];
            this.CachedData = [];
            this.DataArray = [];
        end

        function CreateInstrumentControlGUI(this, controller, tab, instrRef)
            %Make a specific reference to and from the Instrument Class
            this.Instrument = instrRef;

            %Create grid and Sweepcontrol component and position them in the
            %tab.
            grid = uigridlayout(tab, "ColumnWidth", {10, 540, 10, '1x'}, "RowHeight", {10, '1x', 10}, 'RowSpacing', 2);
            scrollableGrid = uigridlayout(grid, [1,1], "ColumnWidth", {'1x'}, "RowHeight", {30, 'fit', '1x'}, 'RowSpacing', 0, Scrollable='on');
            scrollableGrid.Layout.Row = 2;
            scrollableGrid.Layout.Column = 2;
            
            %Add a title label
            title = instrRef.Name + " Scan Control";
            uilabel(scrollableGrid, "Text", title, "FontName", "Georgia", FontSize=18, HorizontalAlignment="Center");

            %Add the Run/Abort and file handling GUI control
            comp = Palladium.Instruments.Controls.ScanFileSetupControlPanel(scrollableGrid);

            %It doesn't make sense to allow extra data columns when we are
            %doing an 'async' scan with a different number of rows than the
            %measurement ticks, so hide that GUI.
            comp.HideDataColumnAddPanel();

            %Store the reference to this View as a property
            this.GUIView = comp;

            %Subscribe to events
            addlistener(comp, 'RunPushed', @(src,evnt)this.ScanRun(src, evnt));
            addlistener(comp, 'AbortPushed', @(src,evnt)this.ScanAbort(src, evnt));
            addlistener(comp, 'InsertSmartTag', @(src,evnt)this.InsertSmartTagRequest(src, evnt, controller));
            addlistener(comp, 'ScanDataChange', @(src,evnt)this.ScanDataChanged(src, evnt));

            %And to the event fired when instrument properties change! Note
            %that we have to store and register this listener handle
            %properly, or when we remove this control  the orphaned listener still lives on the instrument.
            %When you then change a dropdown (e.g., SourceMode), the PostSet → PropertyChanged event fires, the orphaned listener
            %tries to call RefreshUnitsAndLimits() on a deleted handle object, and MATLAB crashes.
            ltr = addlistener(instrRef, 'PropertyChanged', @(src,evnt)this.RefreshUnitsAndLimits());
            this.RegisterEventListener(ltr);


            %Add a plotter of the desired sort as well, to the right
            switch(this.PlotterType)
                case("Default")
                    %Don't register the plotter centrally, as we will push data to it only when the sweep is running,
                    %and clear it on sweep start.
                    this.Plotter = controller.AddNewPlotter(grid, Size="Medium", RegisterPlotter=false);    %Don't register the plotter centrally, as we will push data to it only when the sweep is running, and clear it on sweep start. This does mean, for now at least, that the Plotter is not hooked up
                    this.Plotter.Layout.Row = 2;
                    this.Plotter.Layout.Column = 4;
                    ltr = addlistener(this.Plotter, 'AxesSelectionChange', @(src,evnt)this.PlotterAxesSelectionChange(src));
                    this.RegisterEventListener(ltr);
                case("Simple")
                    this.Plotter = controller.AddNewSimplePlotter(grid, "Medium");
                    this.Plotter.Layout.Row = 2;
                    this.Plotter.Layout.Column = 4;
                otherwise
                    error("Unsupported Plotter type in ScanController");
            end

        end               

        function t_s = GetElapsedTime(this)
            t_s = toc(this.timerVal);
        end

        function LockRunButton(this)
            this.GUIView.DisableRunButton();
        end

        function MeasurementsInitialised(this, ~, eventArgs)
            headers = eventArgs.Headers;
            switch(this.PlotterType)
                case("Default")
                    this.Plotter.UpdateVariables(headers);
                otherwise
            end
        end

        function MeasurementsStarted(this, ~, ~, ~)
            this.UnlockRunButton();
        end

        function MeasurementsStopped(this, ~, ~, ~)
            this.GUIView.EnableRunButton();
            this.LockRunButton();
            this.CachedData = [];
        end


        function OnParametersChanged(this, sweepDetails)
            this.ControlDetailsStruct.SweepDetails = sweepDetails;
            this.GUIView.OnScanDataChanged(this.ControlDetailsStruct.SweepDetails);
        end

        function OnScanAbort(this)
            this.Aborted = true;
            this.GUIView.SetReady();
        end

        function OnScanComplete(this)
            this.GUIView.SetReady();
        end

        function OnScanRun(this)
            %Reset the current step number
            this.Aborted = false;
            this.ClearData();

            %Get parameter
            this.ControlDetailsStruct.SweepDetails = this.GUIView.CollectScanDetails();

            %Update the GUI
            this.GUIView.SetRunning();

            %Set up a DataWriter, which will do things like generate the
            %Sweep Name, and pass in a bool to say if it will actually do any writing to file
            this.CreateDataFile(this.ControlDetailsStruct.SweepDetails.SaveSweepFile);
            this.UpdatePlotterSavedPlotTitle();

            %Tell the Instrument to run the scan - it must have a RunScan() method
            %defined or this will error
            this.Instrument.RunScan();
        end

        function ScanAbort(this, ~, ~)
            this.Running = false;
            this.TimeElapsed_s = 0;
            this.OnScanAbort();
        end

        function ScanComplete(this)
            this.Running = false;
            this.TimeElapsed_s = 0;

            %Grab the data from the Instrument (will need to define a
            %GetCompletedScanData function)
            this.DataArray = this.Instrument.GetCompletedScanData();

            %Write data to file
            this.WriteScanData(this.DataArray);

            %Add in an end-of sweep metadata line if this is the
            %last update
            this.InsertEndMetadataIntoFile(this.DataWriter);

            switch(this.PlotterType)
                case("Simple")
                    this.Plotter.PlotData(this.DataArray(:,1), this.DataArray(:,2));
                case("Default")
                    this.Plotter.PlotData(this.DataArray);
            end

            %Update GUI and settings
            this.OnScanComplete();

            %Loop the next Scan to start if in Continuous mode
            if this.GUIView.IsContinuousSelected() && ~this.Aborted
                this.RestartNextTick = true;
            end
        end

        function ScanDataChanged(this, ~, eventData)
            %Gets called from event handlers from the View
            sweepDetails = eventData.Value;
            this.ControlDetailsStruct.SweepDetails = sweepDetails;
            this.GUIView.OnScanDataChanged(this.ControlDetailsStruct.SweepDetails);
        end

        function ScanRun(this, ~, ~)
            this.Running = true;
            this.TimeElapsed_s = 0;
            this.timerVal = tic();
            this.OnScanRun();
        end

        function RemoveControl(this, ~)
            %Delete GUI objects
            delete(this.GUIView);
            this.GUIView = [];
        end

        function UnlockRunButton(this)
            this.GUIView.EnableRunButton();
        end

        function UpdateData(this, ~, ~)
            if this.Running
                %Check if we reached the end of the sweep
                if this.CheckComplete()
                    this.ScanComplete();
                end
            else
                %Loop the next Scan to start if in Continuous mode
                if this.RestartNextTick
                    this.RestartNextTick = false;
                    this.GUIView.Run();
                end
            end
        end

    end

    %% Methods (Static, Public)
    methods (Static, Access = public)


    end

    %% Methods (Private)
    methods (Access = private)

        function CreateDataFile(this, writeToFile)
            %Create or reset the data writer class
            fileNameSuffix = this.ControlDetailsStruct.SweepDetails.FileName;
            this.DataWriter = this.InitialiseDataWriter(fileNameSuffix);

            %Built in functions in base class will write the data row of all instruments/diagnostics at the start
            %of the sweep, for things like temperature, time
            %Write the metadata string for this instrument - frequencies,
            %voltages, settings etc

            %Assemble some sweep metadata
            sweepMetadataDescLine = "Scan Parameters:";
            sweepMetadataLine = this.CreateScanMetaDataLine();

            %Get headers for the sweep data - not the same as overall
            %programme DataRow headers.
            headers = this.GetHeaders();

            %Create new file and write metadata and headers
            extraMetadataLines = [sweepMetadataDescLine, sweepMetadataLine];
            this.StartNewDataFile(this.DataWriter, headers, extraMetadataLines, writeToFile);
        end

        function stringLine = CreateScanMetaDataLine(this)
            %Copy only the required properties into a new temporary struct
            %for metadata writing
            strct.SweepMetadataPlaceholder = "Scan metadata placeholder";

            %Write the metadata to file
            stringLine = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", strct);
        end

         function headersString = GetHeaders(this)
            headers = this.Instrument.GetScanHeaders();

            %Make a simple string of all these headers, tab seperated
            headersString = '';
            for i= 1 : length(headers)
                headersString = sprintf('%s%s\t', headersString, headers{i});
            end
        end

        function PlotterAxesSelectionChange(this, pltr)
            %This is needed for the case where we want to change the
            %displayed data in a Plotter, but the loop is not running.
            %While measurement loop is running, the Plotter will get an
            %Update call with new data every tick, and if it has
            %established that a button has been pressed and it needs to
            %e.g. change the data plotted on a y axis, it sets a bool flag
            %to do a plot refresh next update tick. If there are no ticks
            %this does not happen, so in that case, we hook into the
            %Plotter's event and fire a manual replot in the case that
            %measurements are stopped
            if ~this.Running
                %Have to pass whole data table back in - Plotters do not
                %store/copy these, that would be very expensive.
                %If the data table is empty, for now just do nothing -
                %might be clearer UX to clear the plot, but then again
                %might be annoying to delete the data for no obvious reason
                if ~isempty(this.DataArray)
                    pltr.PlotData(this.DataArray);
                end
            end
        end

        function UpdatePlotterSavedPlotTitle(this)
            this.Plotter.TitleForCopiedPlots = this.DataWriter.FileWriteDetails.FileName;
        end

        function WriteScanData(this, data)
            this.DataWriter.WriteData(data);
        end

    end
end

