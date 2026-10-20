classdef RecordingLakeshore370 < Palladium.Instruments.Lakeshore370
    %RecordingLakeshore370 - A Lakeshore370 that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent.

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
