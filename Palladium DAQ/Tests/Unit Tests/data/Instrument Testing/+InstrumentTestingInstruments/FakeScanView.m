classdef FakeScanView < handle
    %FakeScanView - Stand-in for ScanFileSetupControlPanel (the GUI of a
    %ScanController), recording the state changes it is told to make

    properties (Access = public)
        ScanDetails = struct("SaveSweepFile", true, "FileName", " - Sweep File");
        Running = false;
        ReadyCount = 0;
    end

    methods
        function scanDetails = CollectScanDetails(this)
            scanDetails = this.ScanDetails;
        end

        function SetRunning(this)
            this.Running = true;
        end

        function SetReady(this)
            this.Running = false;
            this.ReadyCount = this.ReadyCount + 1;
        end

        function HideDataColumnAddPanel(~)
        end

        function cont = IsContinuousSelected(~)
            cont = false;
        end
    end
end
