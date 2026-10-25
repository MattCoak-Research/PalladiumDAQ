classdef FakeScanView < handle
    %FakeScanView - Stand-in for ScanFileSetupControlPanel (the GUI of a
    %ScanController), recording the state changes it is told to make

    properties (Access = public)
        ScanDetails = struct("SaveSweepFile", true, "FileName", " - Sweep File");
        Running = false;
        ReadyCount = 0;
        RunAction = [];         %Function handle Run calls, standing in for what the panel's RunPushed event does - empty to do nothing
        AbortAction = [];       %The same for Abort
        RunCount = 0;           %How many times Run was called
        AbortCount = 0;         %How many times Abort was called
        Continuous = false;     %Set by SetContinuous
        SaveToFile = true;      %Set by SetSaveToFile
        SweepName = "";         %Set by SetNewSweepName
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

        function Run(this)
            this.RunCount = this.RunCount + 1;
            if ~isempty(this.RunAction)
                this.RunAction();
            end
        end

        function Abort(this)
            this.AbortCount = this.AbortCount + 1;
            if ~isempty(this.AbortAction)
                this.AbortAction();
            end
        end

        function SetContinuous(this, tf);       this.Continuous = tf;   end
        function SetSaveToFile(this, tf);       this.SaveToFile = tf;   end
        function SetNewSweepName(this, name);   this.SweepName = name;  end

        function HideDataColumnAddPanel(~)
        end

        function cont = IsContinuousSelected(~)
            cont = false;
        end
    end
end
