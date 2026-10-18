classdef RecordingZI_MFLI < Palladium.Instruments.ZI_MFLI
    %RecordingZI_MFLI - A ZI_MFLI that can be given a device ID as if connected - for tests with the fake ziDAQ (data/ZI Testing).

    methods (Access = public)
        function SetDeviceHandleForTest(this, deviceID)
            this.DeviceHandle = deviceID;
        end
    end
end
