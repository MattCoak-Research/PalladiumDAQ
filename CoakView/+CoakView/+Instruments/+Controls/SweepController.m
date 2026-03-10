classdef SweepController < CoakView.Core.InstrumentControlBase
    %SWEEPCONTROLLER - Logic controller add-on object to be added on to an
    %Instrument object, where it will handle the logic of stepping through
    %a Sweep, programmed by a SweepSetupPanel in the GUI
    
    properties (GetAccess = public, SetAccess = protected)
        Running = false;
        TimeElapsed_s = 0;
    end

    properties (Access = protected)
        GUIView;
        timerVal;   %Used for tracking Elapsed Time since sweep started, with tic/toc
    end

    properties (Access = private)
        StepNo = 0;
        TotalPoints;
    end

    methods (Abstract, Access = public)
        sweepDetails = Calculate(this, sweepDetailsIn);
        valueToSet = Update(this);
    end
    
    methods
        %% Constructor
        function this = SweepController()
        end
        
        %% GetElapsedTime
        function t_s = GetElapsedTime(this)
            t_s = toc(this.timerVal);
        end

        %% OnParametersChanged
        function OnParametersChanged(this, sweepDetails)

            this.ControlDetailsStruct.SweepDetails = this.Calculate(sweepDetails);

            this.GUIView.OnSweepDataChanged(this.ControlDetailsStruct.SweepDetails);
        end

        %% OnSweepAbort
        function OnSweepAbort(this)
           %Do nothing - child classes can override (but don't HAVE to, so
           %it isn't abstract)
        end

        %% OnSweepComplete
        function OnSweepComplete(this)  
           %Do nothing - child classes can override (but don't HAVE to, so
           %it isn't abstract)
        end

        %% OnSweepRun
        function OnSweepRun(this)
           %Do nothing - child classes can override (but don't HAVE to, so
           %it isn't abstract)
        end               

        %% SweepAbort
        function SweepAbort(this, ~, eventData)
           this.Running = false;     
           this.TimeElapsed_s = 0;
           this.OnSweepAbort();
        end

        %% SweepComplete
        function SweepComplete(this)
            this.Running = false;  
            this.TimeElapsed_s = 0;   
            this.GUIView.SweepComplete();
            this.OnSweepComplete();
        end

        %% SweepDataChanged
        function SweepDataChanged(this, ~, eventData)
            %Gets called from event handlers from the View
            sweepDetails = eventData.Value;
            this.OnParametersChanged(sweepDetails);
        end

        %% SweepRun
        function SweepRun(this, ~, eventData)
            this.Running = true;   
            this.TimeElapsed_s = 0;
            this.timerVal = tic();
            this.OnSweepRun();
        end

    end

    methods (Static)

        %% CalculateExtremalPoints
        function targetPts = CalculateExtremalPoints(startSectionNo, endSectionNo, minVal, midVal, maxVal)
            %Calculate the extremal key points the sweep should hit, based
            %on the selected sectors
            targetPts = [];
            for i = 0 : 6
                if(i >= startSectionNo && i <= endSectionNo)
                    switch(i)
                        case(0)
                            targetPts = [targetPts, midVal];
                        case(1)
                            targetPts = [targetPts, maxVal];
                        case(2)
                            targetPts = [targetPts, midVal];
                        case(3)
                            targetPts = [targetPts, minVal];
                        case(4)
                            targetPts = [targetPts, midVal];
                        case(5)
                            targetPts = [targetPts, maxVal];
                        case(6)
                            targetPts = [targetPts, midVal];
                    end
                end
            end
        end

        %% CalculatePoints
        function points = CalculatePoints(extremalPts, stepSize)
            %Calculate the array of points to generate for this sweep,
            %given the max/min extremal points and the step size
            points = [];

            if length(extremalPts) < 2
                return
            end

            if stepSize == 0
                return
            end

            for i = 1 : length(extremalPts) - 1
                noOfSteps = max(2, round(abs(extremalPts(i) - extremalPts(i+1)) / stepSize) + 1);    

                %Generate this set of points
                points = [points, CoakView.Instruments.Controls.SweepController.GenerateSweepPoints(extremalPts(i), extremalPts(i+1), 0, noOfSteps)];

                %Remove last point if this is not the final iteration, to
                %avoid duplicates
                if(i < length(extremalPts) - 1)
                    points(end) = [];
                end
            end

        end

        %% CalculateTotalMagnitude
        function totalMag = CalculateTotalMagnitude(targetPts)           
            
            totalMag = 0;
            for i = 1 : length(targetPts) - 1
                totalMag = totalMag + abs(targetPts(i + 1) - targetPts(i));
            end
        end

        %% GenerateSweepPoints
        function [points, numberOfPoints] = GenerateSweepPoints(startPt, endPt, step, numberOfSteps)
            %Helper function to generate an array of points between Start
            %and End values. If numberOfSteps is null, the points will be
            %spaced by Step (Step does not need to have its sign changed to
            %match the sign of end-start, that will be taken care of). If
            %numberOfSteps is not null, that will be used instead, via
            %'linspace'.
                                    
            if(isempty(numberOfSteps)) 
                %Error checking and validation
                if(abs(step) > abs(startPt - endPt))
                    warning('Step is larger than difference between start and end points in MathsUtils.GenerateSweepPoints. Only the start point will be returned.');
                end
                
                if(step == 0)
                    error('Step is set to zero when generating sweep points - this would generate an infinite number of points..');
                end
                
                %Ensure step has the correct sign
                step = abs(step);
                if(endPt < startPt)
                    step = -step;
                end
                
                %Generate points spaced by step. May not neccessarily end
                %neatly on endPt - depends on user's choice of step
                points = startPt : step : endPt;
            else %else, set number of steps
                
                %Generate numberOfSteps points evenly spaced between start
                %and end. Will include the exact start and end point, but
                %may be 0.3333333333333 or so on in between.
                points = linspace(startPt, endPt, numberOfSteps);
            end
            
            numberOfPoints = length(points);
        end
     
        %% TrimExtremalPoints
        function points = TrimExtremalPoints(extremalPts)
            %Remove any duplicate extremal points, and any unneeded ones -
            %ie if going from +1 to 0 to -1, we can safely remove the zero
            %there
            if isempty(extremalPts)
                points = [];
                return;
            end

            if length(extremalPts) < 3
                points = extremalPts;
                return;
            end

            %Remove any duplicates
            for i = length(extremalPts) : -1 : 2
                if(extremalPts(i) == extremalPts(i-1))
                    extremalPts(i) = [];
                end
            end

            %Remove any intermediate values
             for i = length(extremalPts) - 1 : -1 : 2
                if(extremalPts(i + 1) > extremalPts(i) && extremalPts(i) > extremalPts(i-1))
                    extremalPts(i) = [];
                elseif(extremalPts(i + 1) < extremalPts(i) && extremalPts(i) < extremalPts(i-1))
                    extremalPts(i) = [];
                end
             end

             points = extremalPts;
        end
    end
end

