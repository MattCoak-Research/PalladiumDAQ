classdef TestableScanController < Palladium.Instruments.Controls.ScanController
    %TestableScanController - ScanController with hooks to attach a fake
    %GUI and Instrument, instead of building the real GUI

    methods
        function AttachForTest(this, view, instrument)
            this.GUIView = view;
            this.Instrument = instrument;
            this.ControlDetailsStruct = struct("Name", "Scan");
        end
    end
end
