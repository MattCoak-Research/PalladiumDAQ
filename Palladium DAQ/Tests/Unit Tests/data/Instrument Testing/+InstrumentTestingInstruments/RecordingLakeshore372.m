classdef RecordingLakeshore372 < Palladium.Instruments.Lakeshore372
    %RecordingLakeshore372 - A Lakeshore372 that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end
    end
end
