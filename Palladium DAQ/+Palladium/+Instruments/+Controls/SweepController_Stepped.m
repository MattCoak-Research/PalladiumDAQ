classdef SweepController_Stepped < Palladium.Instruments.Controls.SweepController
    %SweepController_Stepped - Implementation of abstract SweepController, for setups where the sweep works by setting a new value each measurement step, rather than setting a ramp and then listening for when it completes.
    % Logic controller add-on object to be added on to an
    %Instrument object, where it will handle the logic of stepping through
    %a Sweep, programmed by a SweepSetupPanel in the GUI
    
    properties
        PlotterType = "Default"; %Default or Simple - call before constructing GUI
    end

    properties (Access = private)
        StepNo = 0;
        TotalPoints;
        Data;
        Plotter;
        DataWriter;
        XLabelStr = "X axis var";
        YLabelStr = "Y axis var";
        ExtraDataColHeaders = [];
        CachedData = [];            %CachedData for the last iteration, ready to be written (need to wait until data fomr other instruments come in)
        DataArray = [];             %Store entire array of dataRows taken during this sweep - need it if we change axes on a Plotter mid-sweep
    end
    
    methods
        %% Constructor
        function this = SweepController_Stepped()
            
        end

        %% Calculate
        function sweepDetails = Calculate(this, sweepDetailsIn)
            %Copy current SweepDetails
            sweepDetails = sweepDetailsIn;

            %Calculate extremal points based on what sectors are selected
            targetPts = Palladium.Instruments.Controls.SweepController.CalculateExtremalPoints(sweepDetails.StartSectionNo, sweepDetails.EndSectionNo, sweepDetails.MinVal, sweepDetails.MidVal, sweepDetails.MaxVal);
            
            %Calculate the total amount the value must change over during
            %this sweep
            totalMag = Palladium.Instruments.Controls.SweepController.CalculateTotalMagnitude(targetPts);

            %Take the target number of steps (which will be empty if we are
            %choosing to set stepSize instead - by default in the GUI, as
            %these parameters are linked)
            [targetNumSteps, stepSize] = Palladium.Instruments.Controls.SweepController_Stepped.CalculateSteps(sweepDetails.TargetNumSteps, sweepDetails.StepSize, totalMag, targetPts);

            %Calculate how long this will take
            updateTime = this.ProgrammeTargetUpdateTime;
            estimatedMinUpdateTime = 0.05; %In seconds. A hardcoded semi-guess at the moment.. the minimum time the programme takes to run if not update-time limited. Will add to the Settle Time for a real total time
            timeMin = Palladium.Instruments.Controls.SweepController_Stepped.CalculateTotalTime(targetNumSteps, sweepDetails.SettleTime, updateTime, estimatedMinUpdateTime);

            %Trim any duplicate extremal points
            extremalPoints = Palladium.Instruments.Controls.SweepController.TrimExtremalPoints(targetPts);

            %Check for an empty sweep being entered
            if(isempty(extremalPoints) || length(extremalPoints) < 2)
                warning("Empty sweep");
                sweepDetails = [];
                return;
            end

            %Generate the individual points
            points = Palladium.Instruments.Controls.SweepController.CalculatePoints(extremalPoints, stepSize);

            %Assign the newly-calculated parameters and values into the
            %output struct
            sweepDetails.ExtremalPoints = extremalPoints;
            sweepDetails.Points = points;
            sweepDetails.TotalTimeMin = timeMin;
            sweepDetails.RemainingTimeMin = sweepDetails.TotalTimeMin;
            sweepDetails.TargetNumSteps = targetNumSteps;
            sweepDetails.StepSize = stepSize;

            %Get this from counting the points, not the target, as the way
            %points are split up into the quadrants, ensuring the extremal
            %points are hit, can give extra points that then don't get
            %included
            this.TotalPoints = length(sweepDetails.Points);
        end 

        %% CreateInstrumentControlGUI
        function CreateInstrumentControlGUI(this, controller, tab, instrRef)
            %Make a specific reference to and from the Instrument Class
            this.Instrument = instrRef;
            
            %Create grid and Sweepcontrol component and position them in the
            %tab.
            grid = uigridlayout(tab, "ColumnWidth", {10, 'fit', '1x'}, "RowHeight", {10, 'fit', 10, '1x'}, 'RowSpacing', 2);
            comp = Palladium.Instruments.Controls.SweepSetupControl_Stepped(grid);
            comp.Layout.Row = 2;
            comp.Layout.Column = 2;

            %Store the reference to this View as a property
            this.GUIView = comp;

            %Set title and metadata
            comp.SetTitle(instrRef.Name + " Sweep Control");           

            %Subscribe to events
            addlistener(comp, 'Run', @(src,evnt)this.SweepRun(src, evnt));
            addlistener(comp, 'Abort', @(src,evnt)this.SweepAbort(src, evnt));
            addlistener(comp, 'SweepDataChange', @(src,evnt)this.SweepDataChanged(src, evnt));

            %And to the event fired when instrument properties change! Note
            %that we have to store and register this listener handle
            %properly, or when we remove this control  the orphaned listener still lives on the instrument.
            %When you then change a dropdown (e.g., SourceMode), the PostSet → PropertyChanged event fires, the orphaned listener
            %tries to call RefreshUnitsAndLimits() on a deleted handle object, and MATLAB crashes.            
            ltr = addlistener(instrRef, 'PropertyChanged', @(src,evnt)this.RefreshUnitsAndLimits());
            this.RegisterEventListener(ltr);

            %Set up the defaults and populate parameters 
            this.RefreshUnitsAndLimits();

            %Add a plotter of the desired sort as well, to the right
            switch(this.PlotterType)
                case("Default")
                    %Don't register the plotter centrally, as we will push data to it only when the sweep is running, 
                    %and clear it on sweep start.                  
                    this.Plotter = controller.AddNewPlotter(grid, Size="Medium", RegisterPlotter=false);    %Don't register the plotter centrally, as we will push data to it only when the sweep is running, and clear it on sweep start. This does mean, for now at least, that the Plotter is not hooked up
                    this.Plotter.Layout.Row = [2 4];
                    this.Plotter.Layout.Column = 3;
                    ltr = addlistener(this.Plotter, 'AxesSelectionChange', @(src,evnt)this.PlotterAxesSelectionChange(src));
                    this.RegisterEventListener(ltr);
                case("Simple")
                    this.Plotter = controller.AddNewSimplePlotter(grid, "Medium");
                    this.Plotter.Layout.Row = [2 4];
                    this.Plotter.Layout.Column = 3;
                otherwise
                    error("Unsupported Plotter type in SweepController_Stepped");
            end

        end  

        %% OnSweepAbort
        function OnSweepAbort(this)
           this.Aborted = true;
        end

        %% OnSweepComplete
        function OnSweepComplete(~)  
            
        end

        %% OnSweepRun
        function OnSweepRun(this)
           %Reset the current step number
           this.StepNo = 0;
           this.Aborted = false;
           this.ClearData();

           %Set up a DataWriter, which will do things like generate the
           %Sweep Name, and pass in a bool to say if it will actually do any writing to file 
           this.CreateDataFile(this.ControlDetailsStruct.SweepDetails.SaveSweepFile);
           this.UpdatePlotterSavedPlotTitle();
        end

        %% RefreshUnitsAndLimits
        function RefreshUnitsAndLimits(this)
            [unitsStr, limits, xlabelStr, ylabelStr] = this.Instrument.GetSweepUnitsString();
            this.GUIView.SetUnitsString(unitsStr);
            this.GUIView.SetLimits(limits(1), limits(2));
            this.GUIView.SetStartingValues(limits(1), (limits(1)+limits(2))/2, limits(2));
            this.XLabelStr = xlabelStr;
            this.YLabelStr = ylabelStr;
        end

        %% RemoveControl
        function RemoveControl(this, instrRef)            
            %Delete GUI objects
            delete(this.GUIView);
            this.GUIView = [];
        end

        %% MeasurementsInitialised
        function MeasurementsInitialised(this, src, eventArgs)
            headers = eventArgs.Headers;
            this.GUIView.UpdateAvailableDataColumnHeaders(headers);
            this.Plotter.UpdateVariables(headers);
        end

        %% MeasurementsStarted
        function MeasurementsStarted(this, ~, ~, ~)
            this.UnlockRunButton(); 
        end
        
        %% MeasurementsStopped
        function MeasurementsStopped(this, ~, ~, ~)
            this.GUIView.OnAbortButtonPushed();
            this.LockRunButton();
            this.CachedData = [];
        end

        %% LockRunButton
        function LockRunButton(this)
            this.GUIView.LockRunButton();
        end

        %% UnlockRunButton
        function UnlockRunButton(this)
            this.GUIView.UnlockRunButton();
        end
        
        %% Update
        function Update(this)            
            if this.Running
                %Set the new value on the Instrument
                valueToSet = this.UpdateValueToSet();
                this.Instrument.SetNewSweepStepValue(valueToSet);

                %And now wait for the set Settle Time for that change
                %to take place before measuring
                this.WaitSettleTime();
            end
        end

        %% UpdateValueToSet
        function valueToSet = UpdateValueToSet(this)
            %Increment the step number
            this.StepNo = this.StepNo + 1;

            %Tick onto next value from the list
            valueToSet = this.ControlDetailsStruct.SweepDetails.Points(this.StepNo);

            %Calculate the remaining time
            totalTimeMin = this.ControlDetailsStruct.SweepDetails.TotalTimeMin;
            this.ControlDetailsStruct.SweepDetails.RemainingTimeMin = Palladium.Instruments.Controls.SweepController_Stepped.CalculateTimeRemaining(totalTimeMin, this.StepNo, this.TotalPoints);

            %Update the View GUI
            this.GUIView.StepComplete(this.StepNo, valueToSet);
            this.GUIView.UpdateTimeRemainingDisplay(this.ControlDetailsStruct.SweepDetails.RemainingTimeMin);
        end

        %% UpdateData
        function UpdateData(this, dataRow, headers)
            if this.Running
                %Instrument calls this to add latest x and y values to be
                %plotted and logged to file
                switch(this.PlotterType)
                    case("Simple")
                        %Let's assume if we are using Simple as the plotting
                        %option the data row is just 2 values, x and y.
                        this.Data.X = [this.Data.X; dataRow(1)];
                        this.Data.Y = [this.Data.Y; dataRow(2)];
                end

                %Do the actual data writing in the event-triggered
                %DataRowCollected call, which gets called when we have a full
                %dataRow from other instruments to interrogate. Cache for now.
                this.CachedData = dataRow;

                %Check if we reached the end of the sweep
                if(this.StepNo >= this.TotalPoints)
                    this.SweepComplete();
                end

            else
                %Loop the next sweep to start if in Continuous mode
                if this.RestartNextTick
                    this.RestartNextTick = false;
                    this.GUIView.RunSweep();
                end
            end
        end

        %% DataRowCollected
        function DataRowCollected(this, dataRow, headers)
            %Gets triggered every tick once the loop has collected the
            %entire dataRow from all instruments. Use to e.g. write sweep
            %data that includes columns from other instruments

            if isempty(this.CachedData)
                return;
            end

            %Append to the cached dataarray (this is the whole
            %programme-wide dataRow, so we can plot anything - but only
            %lines since the sweep started are to be stored)
            this.DataArray = [this.DataArray; dataRow];

            switch(this.PlotterType)
                case("Simple")
                 this.Plotter.PlotData(this.Data.X, this.Data.Y);
                case("Default")
                 success = this.Plotter.TryAppendData(dataRow);
                 if ~success
                     this.Plotter.PlotData(this.DataArray);
                 end
            end

            if this.ControlDetailsStruct.SweepDetails.SaveSweepFile
                this.DataWriter.WriteLine(this.GetDataRowToWrite(this.CachedData, dataRow, headers));

                if  ~this.Running
                    %Add in an end-of sweep metadata line if this is the
                    %last update
                    this.InsertEndMetadataIntoFile(this.DataWriter);
                end
            end

            this.CachedData = [];
        end

        %% GetDataRowToWrite
        function dataRowToWrite = GetDataRowToWrite(this, instrDataRow, dataRow, headers)
            dataRowToWrite = instrDataRow;

            if ~isempty(this.ExtraDataColHeaders)
                for i = 1 : length(this.ExtraDataColHeaders)
                     [~,idx] = ismember(this.ExtraDataColHeaders(i), headers);

                     if isempty(idx)
                         error("Invalid header in sweep");
                     end

                     dataRowToWrite = [dataRowToWrite, dataRow(idx)];
                end
            end
        end

        %% WaitSettleTime
        function WaitSettleTime(this)
            pauseTime = this.ControlDetailsStruct.SweepDetails.SettleTime;  %This is in seconds
            pause(pauseTime);
        end
    end

    methods (Access = private)

        %% CreateDataFile
        function CreateDataFile(this, writeToFile)
            %Create or reset the data writer class
            fileNameSuffix = this.ControlDetailsStruct.SweepDetails.FileName;
            this.DataWriter = this.InitialiseDataWriter(fileNameSuffix);

            %Built in functions in base class will write the data row of all instruments/diagnostics at the start
            %of the sweep, for things like temperature, time
            %Write the metadata string for this instrument - frequencies,
            %voltages, settings etc

            %Assemble some sweep metadata
            sweepMetadataDescLine = "Sweep Parameters:";
            sweepMetadataLine = this.CreateSweepMetaDataLine();

            %Get headers for the sweep data - not the same as overall
            %programme DataRow headers.
            headers = this.GetHeaders();

            %Create new file and write metadata and headers
            extraMetadataLines = [sweepMetadataDescLine, sweepMetadataLine];
            this.StartNewDataFile(this.DataWriter, headers, extraMetadataLines, writeToFile);
        end

        %% ClearData
        function ClearData(this)
            this.Data.X = [];
            this.Data.Y = [];
            this.CachedData = [];
            this.DataArray = [];

            this.Plotter.ClearData();
        end

        %% CreateSweepMetaDataLine
        function stringLine = CreateSweepMetaDataLine(this)
            %Copy only the required properties into a new temporary struct
            %for metadata writing
            strct.MinVal = this.ControlDetailsStruct.SweepDetails.MinVal;
            strct.MidVal = this.ControlDetailsStruct.SweepDetails.MidVal;
            strct.MaxVal = this.ControlDetailsStruct.SweepDetails.MaxVal;

            strct.TargetNumSteps = this.ControlDetailsStruct.SweepDetails.TargetNumSteps;
            strct.StepSize = this.ControlDetailsStruct.SweepDetails.StepSize;
            strct.StartSectionNo = this.ControlDetailsStruct.SweepDetails.StartSectionNo;
            strct.EndSectionNo = this.ControlDetailsStruct.SweepDetails.EndSectionNo;

            strct.SettleTime = this.ControlDetailsStruct.SweepDetails.SettleTime;
            strct.TotalTimeMin = this.ControlDetailsStruct.SweepDetails.TotalTimeMin;

            %Write the metadata to file
            stringLine = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", strct);
        end

        %% GetHeaders
        function headersString = GetHeaders(this)
           % headers = [this.XLabelStr, this.YLabelStr];
            headers = this.Instrument.GetHeaders();

            %Get any additional extra headers added in the GUI - extra
            %datacolumns from the wider programme to print into the Sweep
            %File
            this.ExtraDataColHeaders = this.GUIView.ExtraDataColumnsHeaders;
            if ~isempty(this.ExtraDataColHeaders)
                headers = [headers this.ExtraDataColHeaders];
            end

            %Make a simple string of all these headers, tab seperated
            headersString = '';
            for i= 1 : length(headers)
                headersString = sprintf('%s%s\t', headersString, headers{i});
            end
        end

        %% PlotterAxesSelectionChange
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

        %% UpdatePlotterSavedPlotTitle
        function UpdatePlotterSavedPlotTitle(this)
            this.Plotter.TitleForCopiedPlots = this.DataWriter.FileWriteDetails.FileName;
        end

    end

    methods (Static)

        %% CalculateSteps
        function [targetNumSteps, stepSize] = CalculateSteps(targetNumStepsIn, stepSizeIn, totalMag, targetPts)
            arguments
                targetNumStepsIn;   %Can be [] to signify we are using set stepsize
                stepSizeIn (1,1) double;
                totalMag (1,1) double;
                targetPts (:,1) double; %Array of extremal points to hit
            end

            %Take the target number of steps (which will be empty if we are
            %choosing to set stepSize instead - by default in the GUI, as
            %these parameters are linked)
            if isempty(targetNumStepsIn)
                %We set the number of steps based on the stepSize
                targetNumSteps = ceil(totalMag / stepSizeIn);
                stepSize = totalMag / targetNumSteps;   %Set this again to make it exactly fit the total range with no gap or excess (step size will update in the GUI)
            else
                %We have dictated a number of steps - work out the step
                %size from that
                if targetNumStepsIn < length(targetPts)%Catch and handle the case where we are asking for fewer steps than there are quadrants of the sweep - just step up to each extremal point in this case
                    targetNumSteps = length(targetPts);
                else
                    targetNumSteps = targetNumStepsIn;
                end
                stepSize = totalMag / targetNumSteps;   %Set this again to make it exactly fit the total range with no gap or excess (step size will update in the GUI)
            end
        end

        %% CalculateTimeRemaining
        function remainingTimeMin = CalculateTimeRemaining(totalTimeMin, currentStep, totalSteps)
            arguments
                totalTimeMin (1,1) double;
                currentStep (1,1) double {mustBeInteger};
                totalSteps (1,1) double {mustBeInteger};
            end

            remainingTimeMin = totalTimeMin * (1 - currentStep / totalSteps);
        end

        %% CalculateTotalTime
        function timeMin = CalculateTotalTime(totalSteps, pauseTime, updateTime, estimatedMinUpdateTime)
            arguments
                totalSteps (1,1) double;
                pauseTime (1,1) double;
                updateTime (1,1) double;
                estimatedMinUpdateTime (1,1) double;
            end

            if(updateTime > pauseTime - 0.1)
                tStep = updateTime;
            else
                tStep = pauseTime + estimatedMinUpdateTime;
            end

            %tStep is in seconds
            timeMin = (tStep / 60) * totalSteps;
        end

    end
end

