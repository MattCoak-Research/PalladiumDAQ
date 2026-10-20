classdef RecordingLakeshore331 < Palladium.Instruments.Lakeshore331
    %RecordingLakeshore331 - A Lakeshore331 that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end
    end
end
