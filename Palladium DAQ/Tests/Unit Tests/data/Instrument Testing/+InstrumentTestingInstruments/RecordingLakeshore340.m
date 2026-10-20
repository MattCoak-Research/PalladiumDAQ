classdef RecordingLakeshore340 < Palladium.Instruments.Lakeshore340
    %RecordingLakeshore340 - A Lakeshore340 that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end
    end
end
