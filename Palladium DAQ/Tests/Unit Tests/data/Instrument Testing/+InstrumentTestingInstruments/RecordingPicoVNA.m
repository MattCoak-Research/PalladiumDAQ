classdef RecordingPicoVNA < Palladium.Instruments.PicoVNA_NetworkAnalyser
    %RecordingPicoVNA - A PicoVNA_NetworkAnalyser that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent and gives set replies.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end

        function CloseForTest(this)
            %Close the connection, as Disconnect does (CloseConnection is protected)
            this.CloseConnection();
        end
    end
end
