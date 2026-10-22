classdef FakeBackend < Palladium.Instruments.PicoVNA.Backend
    %FakeBackend - A stand-in for a PicoVNA backend, for testing how the driver finds the software: Open either works or fails with a set message. Nothing else is used.

    %% Properties (Public)
    properties (Access = public)
        OpenError = "";         %If not empty, Open errors with this message
        FakeDescription = "";   %What Open sets as the Description
        Opened = false;         %True once Open has worked
        Closed = false;         %True once Close has been called
    end

    %% Methods (Public)
    methods (Access = public)
        function Open(this)
            if strlength(this.OpenError) > 0
                error("FakeBackend:OpenFailed", "%s", this.OpenError);
            end
            this.Opened = true;
            this.Description = this.FakeDescription;
        end

        function Close(this);                                   this.Closed = true; end
        function plan = ReadPlan(~);                            plan = struct("StartFrequency_Hz", 1e6, "StopFrequency_Hz", 2e6, "NumPoints", 11); end
        function settings = ReadSweepSettings(this);            settings = this.ReadPlan(); settings.Power_dBm = 0; settings.Bandwidth_Hz = 1000; settings.CalType = "Fake"; end
        function SetFrequencyPlan(~, ~, ~, ~);                  end
        function StartSweep(~, ~, ~, ~);                        end
        function done = IsSweepDone(~);                         done = true; end
        function data = CollectSweep(~);                        data = [1e6, 0]; end
        function AbortSweep(~);                                 end
        function LoadCalibration(~, ~);                         end
    end
end
