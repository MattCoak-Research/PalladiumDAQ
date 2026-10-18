classdef RecordingKeithley2410 < Palladium.Instruments.Keithley2410
    %RecordingKeithley2410 - A Keithley2410 that can be given a fake connection (a FakeDeviceHandle), which records the commands it is sent.

    methods (Access = public)
        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end

        function ConfigureReadingsForTest(this)
            %What connecting sets on the instrument (ConfigureReadings is protected)
            this.ConfigureReadings();
        end

        function SetSourceModeForTest(this, mode)
            %Set SourceMode, e.g. "Voltage" - on some drivers it is read from the instrument, and can't be set directly
            this.SourceMode = this.SourceType(mode);
        end
    end
end
