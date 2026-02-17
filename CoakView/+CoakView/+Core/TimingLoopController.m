classdef TimingLoopController < handle
    %TIMINGLOOPCONTROLLER 

    properties(GetAccess = public, SetAccess = private)    
        State = categorical("Ready", ["Running", "Ready", "Pausing", "Stopping", "Paused"]);
        TargetUpdateTime = 0.1;
    end

    properties(Access = private)
        Timer;
        Controller;
    end

    events
        MeasurementsInitialised;
        Started;
        Paused;
        Resumed;
        Stopped;
        TargetUpdateTimeChanged;
        UpdateTimeChanged;
    end

    methods

        %% Constructor
        function this = TimingLoopController(controller)
            this.Controller = controller;
        end
       
        %% CloseTimer
        function CloseTimer(this)
            this.Timer.stop();
            delete(this.Timer);
        end

        %% Initialise
        function Initialise(this)
            %Create a Timer object that will schedule all the
            %measurement loop calls
            this.Timer = timer('TimerFcn', @this.Update, 'ExecutionMode', 'fixedRate', 'Period', 0.1, 'ObjectVisibility','off');
        end     

        %% OnPaused
        function OnPaused(this)
            %Called from the main loop after "Pausing" state has been set
            %by GUI event calls, and then the update loop has passed
            %through again to here. Stop the timer and basically halt
            %measurements - but we won't clear everything upon Resuming,
            %unlike Stop/Start
            this.Timer.stop();
            this.State = "Paused";

            %Log some information
            this.Controller.Log("Debug", "Measurements paused", "Yellow", "Paused");

            %Fire event
            notify(this, "Paused");
        end

        %% OnResumed
        function OnResumed(this)
            %Log some information
            this.Controller.Log("Debug", "Measurements resumed", "Green", "Running");

            this.State = "Running";
            this.RunMeasurementLoop();

            %Fire event
            notify(this, "Resumed");
        end

        %% OnStarted
        function OnStarted(this)
            this.State = "Running";

            %Fire event
            notify(this, "Started");
        end

        %% OnStopped
        function OnStopped(this)
            this.Timer.stop();
            this.Controller.OnMeasurementsStopped();
            this.State = "Ready";

            %Log some information
            this.Controller.Log("Info", "Measurements stopped", "Green", "Ready");
            this.Controller.ShowStatus("Green", "Ready");

            %Fire event
            notify(this, "Stopped");
        end

        %% Pause
        function Pause(this)
            %Display a status message in the logger
            this.Controller.ShowStatus("Yellow", "Pausing");

            this.State = "Pausing";
        end

        %% Resume
        function Resume(this)
            %Similar to Start - but we don't clear anything first, just get
            %the measurement loop running again
            this.State = "Running";
            this.RunMeasurementLoop();
        end

        %% SetUpdateTime
        function SetUpdateTime(this, targetTime_s)
            try
                %Need to stop the timer, change the period, then restart it -
                %get an error if we try to change the period while it is
                %running
                if(strcmp(this.Timer.Running, 'on'))
                    this.Timer.stop();
                    this.Timer.Period = targetTime_s;
                    this.Timer.start();
                else
                    this.Timer.Period = targetTime_s;
                end

                %Store value as a property - things like Sweep Controllers
                %will want to query it to get their time estimates
                this.TargetUpdateTime = targetTime_s;

                %Update the View to reflect the change
                args = CoakView.Events.ValueChangedEventData(targetTime_s);
                notify(this, "UpdateTimeChanged", args);
            catch err
                this.Controller.HandleError("Error setting update time", err);
            end
        end

        %% Start
        function Start(this)
            %Set up the Data Writing
            this.Controller.InitialiseDataWriting();

            if(this.Controller.CanStart)
                this.OnStarted();

                %Connect to all instruments and start writing data table
                [success, msg, title] = this.Controller.InitialiseMeasurements();
                if success
                    %We connected successfully - run the measurements
                    this.OnMeasurementsInitialised(this.Controller.Headers);
                    this.RunMeasurementLoop();
                else
                    %We get to here if we failed to connect to an
                    %instrument. We have already disconnected from all the
                    %ones we did manange to connect to. Now abort instead
                    %of starting the measurement loop, show a warning, and
                    %return to the Ready state
                    this.AbortStart(msg, title);
                end
            else
                %Abort and warn that we couldn't start - in fact should it
                %even be possible to get here if so?
                this.AbortStart("Could not start, aborting. Controller.CanStart was false, this really shouldn't have been possible..", "Intialisation failed");
            end
        end

        %% Stop
        function Stop(this)
            %Pressing the stop button sets the State to 'Stopping' only. Current loop
            %iteration will complete, then CloseAll will be called, and THERE
            %all instruments can be stopped.
            this.StopMeasurements();
        end

    end

    methods(Access=private)

        %% AbortStart
        function AbortStart(this, msg, title)
            %abort instead starting the measurement loop, show a warning, and return to the Ready state

            %Display a status message in the logger
            this.Controller.Log("Info", "Initialisation aborted", "Red", "Initialisation aborted");

            %Build out full string to print
            msg = msg + "\n\nInitialisation has been aborted.";

            this.Controller.HandleWarning(msg, title);

            this.OnStopped();
        end

        %% OnMeasurementsInitialised
        function OnMeasurementsInitialised(this, headers)
            %Fired after successful connection to instruments, data column
            %headers locked in.

            %Fire event
            args = CoakView.Events.MeasurementsInitialisedEventData(headers);
            notify(this, "MeasurementsInitialised", args);
        end


        %% RunMeasurementLoop
        function RunMeasurementLoop(this)
            %Display a status message in the logger
            this.Controller.Log("Info", "Measurement Loop started", "Green", "Running");

            %Start the Timer object that calls the loop updates
            this.Timer.start();
        end

        %% StopMeasurements
        function StopMeasurements(this)
            %Pressing the stop button sets the State to 'Stopping' only. Current loop
            %iteration will complete, then CloseAll will be called, and THERE
            %all instruments can be stopped.

            %Display a status message in the logger           
            this.Controller.Log("Info", "Measurement Loop Stopping...", "Yellow", "Stopping measurements");

            
            if strcmp(this.State, "Paused") || strcmp(this.State, "Pausing")
                %If we are currently paused, the timer is suspended and
                %there will be no update calls, so Stop will never
                %properly fire. Call it manually here.
                this.State = "Stopping";
                this.OnStopped();
            else                
                %Normal behaviour - mark the programme as due to stop on
                %the next update tick
                this.State = "Stopping";
            end
        end


        %% Update
        function Update(this, ~, ~)
            %Execute one 'tick' of the measurement loop - poll each
            %instrument for one row of data, update all GUI and plots. This
            %keeps running, triggered async off a Timer object, until state
            %is changed to Pausing or Stopping by Pause or Stop events

            %Process GUI events like button presses and force the async
            %timer to check in with the GUI - get hangs without this if
            %update time is set too short
            drawnow();

            try
                %Check for exit conditions from the measurement loop - are we
                %trying to Pause or Stop the loop?
                switch(this.State)
                    case("Stopping")
                        this.OnStopped();
                    case("Pausing")
                        this.OnPaused();
                end
            catch e
                CatchMeasurementLoopError(this, e);
            end

            switch(this.State)
                case("Running")   
                    %Execute the core 'tick' measurement command in
                    %Controller. Gets data, writes data to file, updates
                    %plots etc
                    this.Controller.Measure();

                    try
                        %Fire event to allow updating the time elapsed this frame in the GUI
                        elapsedTimeSinceLastTick_s = this.Timer.InstantPeriod;
                        args = CoakView.Events.ValueChangedEventData(elapsedTimeSinceLastTick_s);
                        notify(this, "UpdateTimeChanged", args);
                    catch e
                        warning("Measurement time update failed: " + string(e.message));
                    end
                otherwise
                    %Do nothing if not Running
                    
            end
        end
    end

end