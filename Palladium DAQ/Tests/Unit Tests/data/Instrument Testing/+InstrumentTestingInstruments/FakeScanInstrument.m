classdef FakeScanInstrument < handle
    %FakeScanInstrument - Stand-in for an instrument a ScanController scans with, for what happens when a scan is aborted or its data can't be collected.

    %% Properties (Public)
    properties (Access = public)
        AbortCount = 0;         %How many times AbortScan was called
        AbortError = false;     %True to make AbortScan error
        CollectError = false;   %True to make GetCompletedScanData error
    end

    %% Methods (Public)
    methods (Access = public)
        function AbortScan(this)
            this.AbortCount = this.AbortCount + 1;
            if this.AbortError
                error("FakeScanInstrument:AbortFailed", "Could not stop it");
            end
        end

        function data = GetCompletedScanData(this)
            if this.CollectError
                error("FakeScanInstrument:CollectFailed", "No data");
            end
            data = [1 2];
        end
    end
end
