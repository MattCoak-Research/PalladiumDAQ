classdef RecordingKeithley6220 < Palladium.Instruments.Keithley6220
    %RecordingKeithley6220 - A Keithley6220 that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent and gives set replies.

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
