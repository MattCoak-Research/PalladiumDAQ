classdef RecordingKeithley6430 < Palladium.Instruments.Keithley6430
    %RecordingKeithley6430 - A Keithley6430 that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent.

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
