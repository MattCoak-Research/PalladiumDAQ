classdef RecordingMercuryITC < Palladium.Instruments.MercuryITC
    %RecordingMercuryITC - A MercuryITC that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent and gives set replies.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end

        function settings = GetConnectionSettingsForTest(this)
            settings = this.ConnectionSettings;
        end
    end
end
