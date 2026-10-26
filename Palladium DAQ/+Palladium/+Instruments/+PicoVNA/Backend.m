classdef (Abstract) Backend < handle
    %Backend - What PicoVNA_NetworkAnalyser needs from the PicoVNA software it talks to - one subclass for each (PicoVNA 5, PicoVNA 3).
    %The driver does the same things whichever software is under it: set
    %the frequency plan, start a sweep without waiting for it, check
    %whether it has finished, and collect the data. A backend does each in
    %its software's own way (SCPI over TCP for PicoVNA 5, Pico's COM
    %library for PicoVNA 3), and raises an error with a message for the
    %user if its software isn't there. Frequencies are in Hz throughout.

    %% Properties (Public, Protected Set)
    properties(GetAccess = public, SetAccess = protected)
        Description = "";       %What it is connected to, set by Open - e.g. "PicoVNA 5 software at 127.0.0.1:5025 (PicoVNA-108)"
    end

    %% Methods (Abstract, Public)
    methods(Abstract, Access = public)
        %Connect to the software (and the analyser), setting Description.
        %Errors, saying why, if it isn't available
        Open(this);

        %Stop any sweep, disconnect and release everything
        Close(this);

        %The frequency plan: a struct with StartFrequency_Hz,
        %StopFrequency_Hz and NumPoints
        plan = ReadPlan(this);

        %The plan, plus Power_dBm, Bandwidth_Hz and CalType (the
        %calibration, as text): a struct, for the data-file metadata
        settings = ReadSweepSettings(this);

        %Set the sweep to numPoints points evenly spaced from start_Hz
        %to stop_Hz
        SetFrequencyPlan(this, start_Hz, stop_Hz, numPoints);

        %Start one sweep of sParameter ("S11", "S21", "S12" or "S22") and
        %return at once, to be collected with CollectSweep. unit is "dB" or
        %"Absolute"; plan is the frequency plan it runs with (a struct,
        %as ReadPlan)
        StartSweep(this, sParameter, unit, plan);

        %True once the sweep started by StartSweep has finished (also
        %true if it failed), checked without waiting
        done = IsSweepDone(this);

        %The finished sweep: one row per point, [frequency (Hz), value].
        %Errors, with the software's message, if the sweep failed
        data = CollectSweep(this);

        %Give up on a sweep started and not collected, stopping it if the
        %software can. Does nothing if there isn't one
        AbortSweep(this);

        %Load and apply a calibration file made in the software
        LoadCalibration(this, fileName);
    end

    %% Methods (Public)
    methods(Access = public)

        function SetSweepOptions(~, ~, ~)
            %Give the backend the driver's power and bandwidth settings - ignored unless the software can't be set by the user itself.
            %Called before each sweep's plan is set. Does nothing by default
            %
            %Inputs:
            %   power_dBm    - test signal power
            %   bandwidth_Hz - measurement bandwidth
        end

        function Calibrate(this) %#ok<MANU>
            %Calibrate the analyser, if the software can do it from here - by default it can't, and says where it is done.
            error("PicoVNA_NetworkAnalyser:CalibrateInTheSoftware", "%s", "Calibrate the analyser in the PicoVNA software, then load the calibration (LoadCalibration, or the CalibrationFile setting).");
        end

        function SaveCalibration(this, ~) %#ok<MANU>
            %Save the calibration, if the software can do it from here - by default it can't, and says where it is done.
            error("PicoVNA_NetworkAnalyser:CalibrateInTheSoftware", "%s", "Save calibrations in the PicoVNA software.");
        end

    end
end
