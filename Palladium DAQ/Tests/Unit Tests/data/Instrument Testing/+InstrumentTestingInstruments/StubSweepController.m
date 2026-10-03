classdef StubSweepController < Palladium.Instruments.Controls.SweepController
    %StubSweepController - Minimal concrete SweepController, to test the
    %logic in the SweepController base class without any GUI

    properties (Access = public)
        ThrowOnSetup = false;   %Make OnSweepRun fail, as if the sweep couldn't be set up
        SetupCount = 0;
        AbortCount = 0;
        AbortThrows = false;    %Make OnSweepAbort fail too
    end

    methods
        function sweepDetails = Calculate(~, sweepDetailsIn)
            sweepDetails = sweepDetailsIn;
        end

        function valueToSet = Update(~)
            valueToSet = [];
        end

        function CreateInstrumentControlGUI(~, ~, ~, ~)
        end

        function RemoveControl(~, ~)
        end

        function OnSweepRun(this)
            this.SetupCount = this.SetupCount + 1;
            if this.ThrowOnSetup
                error("StubSweepController:SetupFailed", "Sweep setup failed");
            end
        end

        function OnSweepAbort(this)
            this.AbortCount = this.AbortCount + 1;
            if this.AbortThrows
                error("StubSweepController:AbortFailed", "Abort failed");
            end
        end
    end
end
