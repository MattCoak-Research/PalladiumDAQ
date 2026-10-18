classdef RecordingKeysight4284A < Palladium.Instruments.Keysight4284A_LCR_Meter
    %RecordingKeysight4284A - A Keysight4284A_LCR_Meter that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent and gives set replies.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end

        function OnConnectedForTest(this)
            %Do what connecting does once the connection is open (OnConnected is protected)
            this.OnConnected();
        end
    end
end
