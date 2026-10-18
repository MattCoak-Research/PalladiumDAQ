classdef RecordingSR7265 < Palladium.Instruments.SR7265_Lockin
    %RecordingSR7265 - An SR7265_Lockin that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent and gives set replies.

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
