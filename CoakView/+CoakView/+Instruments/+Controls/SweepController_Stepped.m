classdef SweepController_Stepped < CoakView.Instruments.Controls.SweepController
    %SweepController_Stepped - Implementation of abstract SweepController, for setups where the sweep works by setting a new value each measurement step, rather than setting a ramp and then listening for when it completes.
    % Logic controller add-on object to be added on to an
    %Instrument object, where it will handle the logic of stepping through
    %a Sweep, programmed by a SweepSetupPanel in the GUI
    
    properties
    end

    properties (Access = private)
        StepNo = 0;
        TotalPoints;
        Data;
        Plotter;
        DataWriter;
        XLabelStr = "X axis var";
        YLabelStr = "Y axis var";
        Aborted = false;
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
            targetPts = CoakView.Instruments.Controls.SweepController.CalculateExtremalPoints(sweepDetails.StartSectionNo, sweepDetails.EndSectionNo, sweepDetails.MinVal, sweepDetails.MidVal, sweepDetails.MaxVal);
            
            %Calculate the total amount the value must change over during
            %this sweep
            totalMag = CoakView.Instruments.Controls.SweepController.CalculateTotalMagnitude(targetPts);

            %Take the target number of steps (which will be empty if we are
            %choosing to set stepSize instead - by default in the GUI, as
            %these parameters are linked)
            [targetNumSteps, stepSize] = CoakView.Instruments.Controls.SweepController_Stepped.CalculateSteps(sweepDetails.TargetNumSteps, sweepDetails.StepSize, totalMag);

            %Calculate how long this will take
            updateTime = this.Controller.TargetUpdateTime;
            estimatedMinUpdateTime = 0.05; %In seconds. A hardcoded semi-guess at the moment.. the minimum time the programme takes to run if not update-time limited. Will add to the Settle Time for a real total time
            timeMin = CoakView.Instruments.Controls.SweepController_Stepped.CalculateTotalTime(targetNumSteps, sweepDetails.SettleTime, updateTime, estimatedMinUpdateTime);

            %Trim any duplicate extremal points
            extremalPoints = CoakView.Instruments.Controls.SweepController.TrimExtremalPoints(targetPts);

            %Check for an empty sweep being entered
            if(isempty(extremalPoints) || length(extremalPoints) < 2)
                warning("Empty sweep");
                sweepDetails = [];
                return;
            end

            %Generate the individual points
            points = CoakView.Instruments.Controls.SweepController.CalculatePoints(extremalPoints, stepSize);

            %Assign the newly-calculated parameters and values into the
            %output struct
            sweepDetails.ExtremalPoints = extremalPoints;
            sweepDetails.Points = points;
            sweepDetails.TotalTimeMin = timeMin;
            sweepDetails.RemainingTimeMin = sweepDetails.TotalTimeMin;
            sweepDetails.TargetNumSteps = targetNumSteps;
            sweepDetails.StepSize = stepSize;

            this.TotalPoints = sweepDetails.TargetNumSteps;
        end 

        %% CreateInstrumentControlGUI
        function CreateInstrumentControlGUI(this, controller, tab, instrRef)
            %Make a specific reference to and from the Instrument Class
            this.Instrument = instrRef;
            this.Instrument.SweepController = this;
            this.Controller = controller;
            
            %Create grid and Sweepcontrol component and position them in the
            %tab.
            grid = uigridlayout(tab, "ColumnWidth", {10, 'fit', '1x'}, "RowHeight", {10, 'fit', 10, '1x'}, 'RowSpacing', 2);
            comp = CoakView.Instruments.Controls.SweepSetupControl_Stepped(grid);
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

            %And to the event fired when instrument properties change!
            addlistener(instrRef, 'PropertyChanged', @(src,evnt)this.RefreshUnitsAndLimits());

            %Set up the defaults and populate parameters 
            this.RefreshUnitsAndLimits();

            %Add a SIMPLE plotter as well, to the right
            this.Plotter = controller.AddNewSimplePlotter(grid, "Medium");
            this.Plotter.Layout.Row = [2 4];
            this.Plotter.Layout.Column = 3;

        end  

        %% OnSweepAbort
        function OnSweepAbort(this)
           this.Aborted = true;
        end

        %% OnSweepComplete
        function OnSweepComplete(this)  
            
        end

        %% OnSweepRun
        function OnSweepRun(this)
           %Reset the current step number
           this.StepNo = 0;
           this.Aborted = false;
           this.ClearData();

           if this.ControlDetailsStruct.SweepDetails.SaveSweepFile
               this.CreateDataFile();
           end
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
            %Clean up references to this in the Lakeshore Instrument Class
            %so it doesn't think we have a heater control
            instrRef.SweepController = [];

            %Delete GUI objects
            delete(this.GUIView);
            this.GUIView = [];
        end

        %% MeasurementsStarted
        function MeasurementsStarted(this, src, ~, ~)
            this.UnlockRunButton();            
        end
        
        %% MeasurementsStopped
        function MeasurementsStopped(this, src, ~, ~)
            this.GUIView.OnAbortButtonPushed();
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
        
        %% Update
        function valueToSet = Update(this)
            %Increment the step number
            this.StepNo = this.StepNo + 1;

            %Tick onto next value from the list
            valueToSet = this.ControlDetailsStruct.SweepDetails.Points(this.StepNo);

            %Check if we reached the end of the sweep
            if(this.StepNo > this.TotalPoints)
                this.StepNo = this.TotalPoints + 1;
                this.SweepComplete();
            end

            %Calculate the remaining time
            totalTimeMin = this.ControlDetailsStruct.SweepDetails.TotalTimeMin;
            this.ControlDetailsStruct.SweepDetails.RemainingTimeMin = CoakView.Instruments.Controls.SweepController_Stepped.CalculateTimeRemaining(totalTimeMin, this.StepNo, this.TotalPoints);

            %Update the View GUI
            this.GUIView.StepComplete(this.StepNo, valueToSet);
            this.GUIView.UpdateTimeRemainingDisplay(this.ControlDetailsStruct.SweepDetails.RemainingTimeMin);
        end

        %% UpdateData
        function UpdateData(this, x, y)
            %Instrument calls this to add latest x and y values to be
            %plotted and logged to file
            this.Data.X = [this.Data.X; x];
            this.Data.Y = [this.Data.Y; y];

            this.Plotter.PlotData(this.Data.X, this.Data.Y);

            if this.ControlDetailsStruct.SweepDetails.SaveSweepFile
                this.DataWriter.WriteLine([x, y]);

                if  ~this.Running
                    %Add in an end-of sweep metadata line if this is the
                    %last update
                    this.InsertEndMetadataIntoFile(this.DataWriter);

                    %Loop the next sweep to start if in Continuous mode
                    if this.GUIView.IsContinuousSelected() && ~this.Aborted
                        this.GUIView.RunSweep();
                    end

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
        function CreateDataFile(this)
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
            this.StartNewDataFile(this.DataWriter, headers, extraMetadataLines);
        end

        %% ClearData
        function ClearData(this)
            this.Data.X = [];
            this.Data.Y = [];

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
            stringLine = CoakView.DataWriting.DataWriter.BuildMetadataLineStringFromStruct("", strct);
        end

        %% GetHeaders
        function headersString = GetHeaders(this)
            headers = [this.XLabelStr, this.YLabelStr];

            %Make a simple string of all these headers, tab seperated
            headersString = '';
            for i= 1 : length(headers)
                headersString = sprintf('%s%s\t', headersString, headers{i});
            end
        end

    end

    methods (Static)

        %% CalculateSteps
        function [targetNumSteps, stepSize] = CalculateSteps(targetNumStepsIn, stepSizeIn, totalMag)
            arguments
                targetNumStepsIn;   %Can be [] to signify we are using set stepsize
                stepSizeIn (1,1) double;
                totalMag (1,1) double;
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
                targetNumSteps = targetNumStepsIn;
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

