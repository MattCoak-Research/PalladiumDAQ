classdef TimingLoopController < handle
    %TimingLoopController - Runs the measurement loop on a timer, and starts, pauses, resumes and stops it.
    %Created by the Controller, which holds it as `TimingLoopController`;
    %`Controller.Initialise` calls `Initialise` to create the timer.
    %`Start`, `Pause`, `Resume`, `Stop` and `SetUpdateTime` are called by
    %the GUI's buttons and by the matching methods of `Palladium`.
    %
    %**Starting.** `Start` asks the Controller to set up data writing
    %(`InitialiseDataWriting`) and checks `CanStart`, then:
    %
    %1. Sets `State` to Running and raises `Started`.
    %2. Calls `Controller.InitialiseMeasurements`, which has the
    %   InstrumentController connect every instrument
    %   (`InitialiseInstruments`) and build the data column headers
    %   (`InitialiseHeaders`), resets the plots, and writes the headers and
    %   metadata to the data file.
    %3. If that succeeds, raises `MeasurementsInitialised` with the headers,
    %   and starts the timer. If an instrument could not connect, warns the
    %   user and returns to Ready, raising `Stopped`.
    %
    %**Each tick.** The timer calls `Update` every `TargetUpdateTime`
    %seconds. While Running, that calls `Controller.Measure`, which runs
    %the CommandController's `Update` (queued sequence and instrument
    %commands), then the InstrumentController's `CollectMeasurement` (one
    %data row from all instruments), and writes and plots the row. `Update`
    %then raises `UpdateTimeChanged` with the actual time since the last
    %tick.
    %
    %**Pausing and stopping.** `Pause` and `Stop` only set `State` to
    %Pausing or Stopping, so that a tick in progress finishes first. The
    %next tick then calls `OnPaused` or `OnStopped`, which stop the timer
    %and raise `Paused` or `Stopped`; `OnStopped` also has the Controller
    %close all instruments. Stopping while paused calls `OnStopped` at
    %once, as no ticks are running. `Resume` restarts the timer without
    %connecting the instruments again, and raises `Resumed`. Each of
    %`Start`, `Pause`, `Resume` and `Stop` checks the state first, and only
    %logs a warning if it doesn't apply (e.g. `Start` while running, or
    %`Pause` when not running). `Resume` while still Pausing cancels the
    %pause.
    %
    %The GUI listens to `Started`, `Paused`, `Resumed`, `Stopped`,
    %`TargetUpdateTimeChanged` and `UpdateTimeChanged`. Every Instrument
    %Control listens to `Started`, `Paused`, `Resumed`, `Stopped`,
    %`MeasurementsInitialised` and `TargetUpdateTimeChanged`, subscribed by
    %`InstrumentController.AddInstrumentControl`.

    %% Properties (Public, Private Set)
    properties(GetAccess = public, SetAccess = private)
        State Palladium.Enums.LoopState = "Ready";  %State of the measurement loop: Ready, Running, Pausing, Paused or Stopping (see LoopState) - assigned as text, e.g. "Running"
        TargetUpdateTime = 0.1;     %Target time between ticks (s) - the timer's period, set with SetUpdateTime
    end

    %% Properties (Private)
    properties(Access = private)
        Timer;          %MATLAB timer that calls Update every TargetUpdateTime seconds, created by Initialise
        Controller;     %The Palladium.Core.Controller that created this
    end

    %% Events
    events
        MeasurementsInitialised;    %Raised when measurements start, after the instruments connect and the headers are made, with a MeasurementsInitialisedEventData
        Started;                    %Raised when Start begins starting measurements, before the instruments connect
        Paused;                     %Raised when the loop has paused, at the first tick after Pause
        Resumed;                    %Raised by OnResumed, when Resume restarts the loop after a pause
        Stopped;                    %Raised when the loop has stopped and the instruments are closed - also when starting fails
        UpdateTimeChanged;          %Raised every tick, with a ValueChangedEventData of the time since the last tick (s)
        TargetUpdateTimeChanged;    %Raised when the target update time is changed in the GUI (or programmatically), with a ValueChangedEventData of the new time (s)
    end

    %% Constructor
    methods
        function this = TimingLoopController(controller)
            %Create the timing loop controller - the timer itself is made by Initialise.
            %
            %Inputs:
            %   controller - the Palladium.Core.Controller creating it

            this.Controller = controller;
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function CloseTimer(this)
            %Stop and delete the timer, when Palladium closes.
            %Safe to call more than once - it can be reached from both the
            %shutdown path and the timer error path

            if isempty(this.Timer) || ~isvalid(this.Timer)
                return;
            end
            this.Timer.stop();
            delete(this.Timer);
        end

        function Initialise(this)
            %Create the timer that runs the measurement loop - called by Controller.Initialise.
            %The timer runs at a fixed rate, calling Update. Its period is set
            %from TargetUpdateTime, raising TargetUpdateTimeChanged so the GUI
            %shows it

            %Create a Timer object that will schedule all the
            %measurement loop calls
            %ErrorFcn is the last resort for an error escaping Update
            %entirely, which the timer would otherwise turn into a warning
            %and silently stop
            this.Timer = timer('TimerFcn', @this.Update, 'ErrorFcn', @this.HandleTimerError, 'ExecutionMode', 'fixedRate', 'Period', 0.1, 'ObjectVisibility','off');

            %Cause an update/refresh of the GUI so it matches the
            %TargetUpdateTime property
            this.SetUpdateTime(this.TargetUpdateTime);
        end

        function OnPaused(this)
            %Stop the timer and raise Paused - called by Update on the first tick after Pause.
            %The instruments stay connected, and nothing is reset, so Resume
            %can carry on where the loop left off

            this.Timer.stop();
            this.State = "Paused";

            %Log some information
            this.Controller.Log("Debug", "Measurements paused", "Yellow", "Paused");

            %Fire event
            notify(this, "Paused");
        end

        function OnResumed(this)
            %Set the state to Running, restart the timer and raise Resumed.
            %Called by Resume

            %Log some information
            this.Controller.Log("Debug", "Measurements resumed", "Green", "Running");

            this.State = "Running";
            this.RunMeasurementLoop();

            %Fire event
            notify(this, "Resumed");
        end

        function OnStarted(this)
            %Set the state to Running and raise Started - called by Start.

            this.State = "Running";

            %Fire event
            notify(this, "Started");
        end

        function OnStopped(this)
            %Stop the timer, close all instruments, return to Ready and raise Stopped.
            %Called by Update on the first tick after Stop, by Stop directly
            %when paused, when starting fails, and by the Controller when
            %the user stops measurements from an error dialogue. Closes the
            %instruments through `Controller.OnMeasurementsStopped`. The
            %timer may already have been deleted (CloseTimer, on an error
            %while Palladium closes) - the instruments are still closed

            if ~isempty(this.Timer) && isvalid(this.Timer)
                this.Timer.stop();
            end
            this.Controller.OnMeasurementsStopped();
            this.State = "Ready";

            %Log some information
            this.Controller.Log("Info", "Measurements stopped", "Green", "Ready");
            this.Controller.ShowStatus("Green", "Ready");

            %Fire event
            notify(this, "Stopped");
        end

        function Pause(this)
            %Ask the loop to pause, by setting the state to Pausing.
            %The tick in progress finishes, then the next tick calls
            %OnPaused. Only when Running - otherwise warns and does nothing

            switch string(this.State)
                case "Running"     % Carry on below
                case {"Pausing", "Paused"};     this.WarnInvalidStateChange("pause", "measurements are already paused"); return;
                case "Ready";                   this.WarnInvalidStateChange("pause", "measurements are not running"); return;
                case "Stopping";                this.WarnInvalidStateChange("pause", "measurements are stopping"); return;
            end

            %Display a status message in the logger
            this.Controller.ShowStatus("Yellow", "Pausing");

            this.State = "Pausing";
        end

        function Resume(this)
            %Restart the loop after a pause, without connecting the instruments again.
            %Unlike Start, nothing is reset first. Raises Resumed (see
            %OnResumed). Only when Paused - while Pausing (the pause has not
            %taken effect yet) it cancels the pause instead, and otherwise
            %it warns and does nothing

            switch string(this.State)
                case "Paused"      % Carry on below
                case "Pausing"
                    %The tick in progress hasn't finished yet, so the loop
                    %never actually stopped - just cancel the pause
                    this.State = "Running";
                    this.Controller.Log("Info", "Pause cancelled", "Green", "Running");
                    return;
                case "Running";     this.WarnInvalidStateChange("resume", "measurements are already running"); return;
                case "Ready";       this.WarnInvalidStateChange("resume", "measurements have not been started - use Start"); return;
                case "Stopping";    this.WarnInvalidStateChange("resume", "measurements are stopping"); return;
            end

            this.OnResumed();
        end

        function SetUpdateTime(this, targetTime_s)
            %Set the target time between ticks, and raise TargetUpdateTimeChanged.
            %Can be called while the loop is running: the timer is stopped,
            %its period changed and the timer restarted. Errors go to the
            %Controller's error handling
            %
            %Inputs:
            %   targetTime_s - the new period of the timer (s)

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
                args = Palladium.Events.ValueChangedEventData(targetTime_s);
                notify(this, "TargetUpdateTimeChanged", args);
            catch err
                this.Controller.HandleError("Error setting update time", err);
            end
        end

        function Start(this)
            %Begin measurements: set up the data file, connect the instruments, and start the timer.
            %Raises Started, then MeasurementsInitialised once the instruments
            %have connected. If the data file path is invalid or an
            %instrument cannot connect, warns the user and returns to Ready
            %instead. Only when Ready - otherwise warns and does nothing. See
            %the class help for the steps

            switch string(this.State)
                case "Ready"       % Carry on below
                case {"Running", "Pausing"};    this.WarnInvalidStateChange("start", "measurements are already running"); return;
                case "Paused";                  this.WarnInvalidStateChange("start", "measurements are paused - use Resume, or Stop first"); return;
                case "Stopping";                this.WarnInvalidStateChange("start", "measurements are still stopping"); return;
            end

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

        function Stop(this)
            %Ask the loop to stop, by setting the state to Stopping.
            %The tick in progress finishes, then the next tick calls
            %OnStopped, which closes the instruments. When paused, there are
            %no ticks, so OnStopped is called straight away. Only when
            %Running, Pausing or Paused - otherwise warns and does nothing

            switch string(this.State)
                case {"Running", "Pausing", "Paused"}  % Carry on below
                case "Ready";       this.WarnInvalidStateChange("stop", "measurements are already stopped"); return;
                case "Stopping";    this.WarnInvalidStateChange("stop", "measurements are already stopping"); return;
            end

            this.StopMeasurements();
        end

    end

    %% Methods (Private)
    methods(Access=private)

        function AbortStart(this, msg, title)
            %Show a warning that starting failed, and return to the Ready state.
            %No warning dialogue when msg is empty: the user has just seen
            %(and answered) an error dialogue about it already

            %Display a status message in the logger
            this.Controller.Log("Info", "Initialisation aborted", "Red", "Initialisation aborted");

            if strlength(string(msg)) > 0
                %Build out full string to print
                msg = msg + newline + newline + "Initialisation has been aborted.";

                this.Controller.HandleWarning(msg, title);
            end

            this.OnStopped();
        end

        function HandleTimerError(this, ~, evnt)
            %Log an error that escaped Update, return to Ready, and warn the user.
            %Called by the timer (its ErrorFcn). A fixedRate timer has already
            %stopped itself by now. Deliberately do NOT restart it - the
            %programme is in an unknown state, and auto-restarting risks an
            %error-restart-error loop against real hardware

            try
                msg = "Measurement loop timer error";
                try
                    msg = msg + ": " + string(evnt.Data.message);
                catch
                    %Event data not in the expected form, use the generic message
                end

                if isvalid(this.Controller) && ~this.Controller.IsClosing()
                    Palladium.Logging.Logger.Log("Error", msg);
                    if this.State ~= "Ready"
                        this.OnStopped();
                    end
                    this.Controller.HandleWarning(msg + newline + newline + "Measurements have been stopped.", "Measurement loop error");
                end
            catch e
                warning("HandleTimerErrorWarning:HandlingFailed", "%s", "Error while handling a timer error: " + string(e.message));
            end
        end

        function OnMeasurementsInitialised(this, headers)
            %Raise MeasurementsInitialised, once the instruments have connected and the headers are fixed.

            %Fire event
            args = Palladium.Events.MeasurementsInitialisedEventData(headers);
            notify(this, "MeasurementsInitialised", args);
        end

        function RunMeasurementLoop(this)
            %Start the timer that calls Update each tick.

            %Display a status message in the logger
            this.Controller.Log("Info", "Measurement Loop started", "Green", "Running");

            %Start the Timer object that calls the loop updates
            this.Timer.start();
        end

        function StopMeasurements(this)
            %Set the state to Stopping, calling OnStopped at once if paused.

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

        function Update(this, ~, ~)
            %Run one tick of the measurement loop - the timer's callback.
            %First acts on a Pause or Stop (calling OnPaused or OnStopped).
            %Then, if Running, calls `Controller.Measure` - which runs queued
            %commands, collects a data row from every instrument, and writes
            %and plots it - and raises UpdateTimeChanged. Errors go to
            %`Controller.HandleCallbackError`

            %Process GUI events like button presses and force the async
            %timer to check in with the GUI - get hangs without this if
            %update time is set too short
            drawnow();

            try
                %Check for exit conditions from the measurement loop - are we
                %trying to Pause or Stop the loop?
                switch(this.State)
                    case("Stopping");   this.OnStopped();
                    case("Pausing");    this.OnPaused();
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
                        args = Palladium.Events.ValueChangedEventData(elapsedTimeSinceLastTick_s);
                        notify(this, "UpdateTimeChanged", args);
                    catch e
                        warning("UpdateWarning:TimeUpdateFailed", "%s", "Measurement time update failed: " + string(e.message));
                    end
                otherwise
                    %Do nothing if not Running

            end

            %Want to catch the error pretty locally, so the rest of the
            %stuff in the Update Loop still happens in the expected order
            %if we choose to Ignore or Suppress. This is just a private
            %function here to avoid duplicating the code of handling an
            %error specifically in the Measurement Loop
            function CatchMeasurementLoopError(this, e)
                %Show error message and ask if we want to stop measurements
                this.Controller.HandleCallbackError("Error in main measurement loop", e);
            end
        end

        function WarnInvalidStateChange(this, action, reason)
            %Warn that Start, Pause, Resume or Stop was ignored, as it doesn't apply in the current state.
            %Logged as a warning (Command Window, log file and status strip)
            %
            %Inputs:
            %   action - what was asked for, e.g. "pause"
            %   reason - why it was ignored, e.g. "measurements are not running"

            this.Controller.Log("Warning", "Cannot " + action + ": " + reason + ". Ignored.", "Yellow", "Cannot " + action + " - " + reason);
        end
    end

end
