classdef RecordingHP8722ES < Palladium.Instruments.HP_8722ES_NetworkAnalyser
    %RecordingHP8722ES - An HP_8722ES_NetworkAnalyser that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent and gives set replies.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end
    end
end
