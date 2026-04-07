classdef SweepController_Ramp < Palladium.Instruments.Controls.SweepController
    %SweepController_Ramp - Implementation of abstract SweepController, for setups where the sweep works by setting a ramp and then listening for when it completes.
    % Logic controller add-on object to be added on to an
    %Instrument object, where it will handle the logic of stepping through
    %a Sweep, programmed by a SweepSetupPanel in the GUI

    %% Properties (Private)
    properties (Access = private)
        StepNo = 0;
        TotalPoints;
        TargetValue = 0;
        LastSimulatedValue = 0;
    end

    %% Constructor
    methods
        function this = SweepController_Ramp()

        end
    end

    %% Methods (Public)
    methods (Access = public)

        function sweepDetails = Calculate(~, sweepDetailsIn)
            %Copy current SweepDetails
            sweepDetails = sweepDetailsIn;

            %Calculate extremal points based on what sectors are selected
            targetPts = Palladium.Instruments.Controls.SweepController.CalculateExtremalPoints(sweepDetails.StartSectionNo, sweepDetails.EndSectionNo, sweepDetails.MinVal, sweepDetails.MidVal, sweepDetails.MaxVal);

            %Calculate the total amount the value must change over during
            %this sweep
            totalMag = Palladium.Instruments.Controls.SweepController.CalculateTotalMagnitude(targetPts);

            %Calculate how long this will take
            timeMin = Palladium.Instruments.Controls.SweepController_Ramp.CalculateTotalTime(totalMag, sweepDetails.RampRate_min);

            %Trim any duplicate extremal points
            extremalPoints = Palladium.Instruments.Controls.SweepController.TrimExtremalPoints(targetPts);

            %Check for an empty sweep being entered
            if(isempty(extremalPoints) || length(extremalPoints) < 2)
                warning("Empty sweep");
                sweepDetails = [];
                return;
            end

            %Generate the individual points - for the ramping case these
            %are just the extremal points
            points = extremalPoints;

            %Assign the newly-calculated parameters and values into the
            %output struct
            sweepDetails.ExtremalPoints = extremalPoints;
            sweepDetails.Points = points;
            sweepDetails.TotalTimeMin = timeMin;
            sweepDetails.RemainingTimeMin = sweepDetails.TotalTimeMin;
        end

        function CreateInstrumentControlGUI(this, controller, tab, instrRef)
            %Make a specific reference to and from the Instrument Class
            this.Instrument = instrRef;
            this.Instrument.SweepController = this;
            this.Controller = controller;

            %Create grid and Sweepcontrol component and position them in the
            %tab.
            grid = uigridlayout(tab, "ColumnWidth", {10, 'fit', '1x'}, "RowHeight", {10, 'fit', 10, '1x'}, 'RowSpacing', 2);
            comp = Palladium.Instruments.Controls.SweepSetupControl_Ramp(grid);
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
            addlistener(comp, 'RampToZero', @(src,evnt)this.RampToZero(src, evnt));

            %And to the event fired when instrument properties change!
            ltr = addlistener(instrRef, 'PropertyChanged', @(src,evnt)this.RefreshUnitsAndLimits());
            this.RegisterEventListener(ltr);

            %Set up the defaults and populate parameters
            this.RefreshUnitsAndLimits();

            %Add a plotter as well underneath
            pltr = controller.AddNewPlotter(grid);
            pltr.Layout.Row = [2 4];
            pltr.Layout.Column = 3;

            %Set default displayed axes for the plotter
            pltr.SetDefaultXAxis("Time (mins)");
        end

        function [reached, rampStatus] = IsTargetPointReached(this, timeElapsed_s, tDiff, currentTarget, rampRate_min)
            %Query whether we have reached the current target point or are
            %still ramping towards it
            reached = false;

            rampStatus = this.Instrument.CheckRampStatus(timeElapsed_s, tDiff, currentTarget, rampRate_min);

            if rampStatus.TargetReached
                reached = true;
            end
        end

        function OrderInstrumentAbort(this)
            this.Instrument.AbortRamp();
        end

        function OrderInstrumentRamp(this, target, rate)
            settings.Placeholder = "";
            this.Instrument.SetRampingToTarget(target, rate, settings);
        end

        function OnRampToZero(this)
            %hard coded ramp straight to zero
            this.TargetValue = 0;
            this.ControlDetailsStruct.SweepDetails.Points = [0 0];
            this.Running = true;
            this.TimeElapsed_s = 0;
            this.timerVal = tic();
            rate_perMin = this.ControlDetailsStruct.SweepDetails.RampRate_min;
            this.OrderInstrumentRamp(0, rate_perMin);
        end

        function OnSweepAbort(this)
            %Order Instrument to start the sweep - Stepped sweep controls do
            %not need to do this.
            this.OrderInstrumentAbort();
        end

        function OnSweepRun(this)
            %Order Instrument to start the sweep - it is all programmed in and
            %we are good to go.
            %TODO - should this be cached and then run in the next Update call,
            %to avoid async issues?
            this.StepNo = 2;    %First point is the origin point, we want the second
            this.TargetValue = this.ControlDetailsStruct.SweepDetails.Points(this.StepNo);

            %Send ramp command
            rate_perMin = this.ControlDetailsStruct.SweepDetails.RampRate_min;
            this.OrderInstrumentRamp(this.TargetValue, rate_perMin);
        end

        function [sweepCompleted] = OnTargetPointReached(this)
            this.StepNo = this.StepNo + 1;

            if this.StepNo > length(this.ControlDetailsStruct.SweepDetails.Points)
                sweepCompleted = true;
            else
                targetValue = this.ControlDetailsStruct.SweepDetails.Points(this.StepNo);
                this.SetNextTargetPoint(targetValue);
                sweepCompleted = false;
            end
        end

        function RampToZero(this, ~, ~)
            this.OnRampToZero();
        end

        function RefreshUnitsAndLimits(this)
            [unitsStr, limits, ~, ~] = this.Instrument.GetSweepUnitsString();
            this.GUIView.SetUnitsString(unitsStr);
            this.GUIView.SetLimits(limits(1), limits(2));
            this.GUIView.SetStartingValues(limits(1), (limits(1)+limits(2))/2, limits(2));
        end

        function RemoveControl(this, instrRef)
            %Clean up references to this in the Lakeshore Instrument Class
            %so it doesn't think we have a heater control
            instrRef.SweepController = [];

            %Delete GUI objects
            delete(this.GUIView);
            this.GUIView = [];
        end

        function SetNextTargetPoint(this, targetPt)
            this.TargetValue = targetPt;

            %Send ramp command
            rate_perMin = this.ControlDetailsStruct.SweepDetails.RampRate_min;
            this.OrderInstrumentRamp(this.TargetValue, rate_perMin);
        end

        function rampStatus = SimulateRamping(this, tDiff, currentTarget, rampRate_min)
            %Helper function for calculating expected values for
            %instruments in simulation mode

            rampStatus.TargetReached = false;
            newSimValue = this.LastSimulatedValue + tDiff * sign(currentTarget-this.LastSimulatedValue) * rampRate_min / 60;

            if newSimValue * sign(currentTarget-this.LastSimulatedValue) >= abs(currentTarget)
                newSimValue = currentTarget;
                rampStatus.TargetReached = true;
            end

            this.LastSimulatedValue = newSimValue;
            rampStatus.CurrentField = newSimValue;
        end

        function [valueToSet, complete] = Update(this)
            valueToSet = []; %Not currently used - OrderInstrumentRamp will handle it..
            oldTimeElapsed = this.TimeElapsed_s;
            this.TimeElapsed_s = this.GetElapsedTime();
            tDiff = this.TimeElapsed_s - oldTimeElapsed;

            currentTarget = this.TargetValue;
            rampRate = this.ControlDetailsStruct.SweepDetails.RampRate_min;

            %Check if we reached the current target
            if(this.IsTargetPointReached(this.TimeElapsed_s, tDiff, currentTarget, rampRate))
                disp("Target reached")
                complete = this.OnTargetPointReached();
            else
                complete = false;
            end

            %Calculate the remaining time
            totalTimeMin = this.ControlDetailsStruct.SweepDetails.TotalTimeMin;
            this.ControlDetailsStruct.SweepDetails.RemainingTimeMin = Palladium.Instruments.Controls.SweepController_Ramp.CalculateTimeRemaining(totalTimeMin, this.TimeElapsed_s / 60);

            %Update the View GUI
            this.GUIView.UpdateTimeRemainingDisplay(this.ControlDetailsStruct.SweepDetails.RemainingTimeMin);

            %Trigger sweep complete events if.. it's complete
            if complete
                this.SweepComplete();
            end
        end
    end

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function remainingTimeMin = CalculateTimeRemaining(totalTimeMin, timeElapsedMin)
            arguments
                totalTimeMin (1,1) double;
                timeElapsedMin (1,1) double;
            end

            %This is pretty simple for the ramp case..
            remainingTimeMin = max(0, totalTimeMin - timeElapsedMin);
        end

        function timeMin = CalculateTotalTime(totalMagnitude, rampRate_min)
            timeMin = totalMagnitude / rampRate_min;
        end

    end
end

