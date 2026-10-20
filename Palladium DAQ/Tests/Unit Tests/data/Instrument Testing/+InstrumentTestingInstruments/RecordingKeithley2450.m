classdef RecordingKeithley2450 < Palladium.Instruments.Keithley2450
    %RecordingKeithley2450 - A Keithley2450 that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end

        function SetSourceModeForTest(this, mode)
            %Set SourceMode, e.g. "Voltage" - on some drivers it is read from the instrument, and can't be set directly
            this.SourceMode = this.SourceType(mode);
        end
    end
end
