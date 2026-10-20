classdef RecordingPNA_L < Palladium.Instruments.PNA_L_NetworkAnalyser
    %RecordingPNA_L - A PNA_L_NetworkAnalyser that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent and gives set replies.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end
    end
end
