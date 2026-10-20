classdef RecordingLakeshore350 < Palladium.Instruments.Lakeshore350
    %RecordingLakeshore350 - A Lakeshore350 that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end

        function OnConnectedForTest(this)
            this.OnConnected();
        end

        function ApplySettingsForTest(this, settings)
            this.ApplySettings(settings);
        end
    end
end
