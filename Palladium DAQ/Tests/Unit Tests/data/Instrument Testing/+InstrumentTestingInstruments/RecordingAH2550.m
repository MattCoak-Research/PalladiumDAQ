classdef RecordingAH2550 < Palladium.Instruments.AH2550_Bridge
    %RecordingAH2550 - An AH2550_Bridge that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent and gives set replies.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end

        function settings = GetConnectionSettingsForTest(this)
            settings = this.ConnectionSettings;
        end

        function OnConnectedForTest(this)
            %Do what connecting does once the connection is open (OnConnected is protected)
            this.OnConnected();
        end
    end
end
