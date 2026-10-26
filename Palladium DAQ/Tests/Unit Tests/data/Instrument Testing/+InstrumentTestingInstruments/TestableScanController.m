classdef TestableScanController < Palladium.Instruments.Controls.ScanController
    %TestableScanController - ScanController with hooks to attach a fake
    %GUI and Instrument, instead of building the real GUI

    methods
        function AttachForTest(this, view, instrument)
            this.GUIView = view;
            this.Instrument = instrument;
            this.ControlDetailsStruct = struct("Name", "Scan");
        end

        function PressRunForTest(this)
            %What the panel's RunPushed event does (the handler is protected, and a guarded listener would swallow its errors)
            this.OnRunPushed([], []);
        end

        function PressAbortForTest(this)
            %What the panel's AbortPushed event does
            this.OnAbortPushed([], []);
        end
    end
end
