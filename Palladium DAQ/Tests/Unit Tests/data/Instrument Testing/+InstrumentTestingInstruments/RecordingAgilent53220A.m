classdef RecordingAgilent53220A < Palladium.Instruments.Agilent_53220A_FreqCounter
    %RecordingAgilent53220A - An Agilent_53220A_FreqCounter that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end
    end
end
