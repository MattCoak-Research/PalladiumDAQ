classdef FakeDeviceHandle < handle
    %FakeDeviceHandle - Stand-in for the visadev/tcpclient/serialport object
    %an Instrument keeps in DeviceHandle. Defines query/fprintf/fscanf as
    %methods so that Instrument's QueryString, WriteCommand etc. can run
    %without any hardware, and records what they were sent.

    properties (Access = public)
        QueryResponse = "";     %What query() returns
        ReadResponse = "";      %What fscanf() returns
        QueriedCommands (1,:) string = strings(1, 0);
        WrittenCommands (1,:) string = strings(1, 0);
        ReadCount = 0;
    end

    methods (Access = public)

        function response = query(this, command)
            this.QueriedCommands(end + 1) = string(command);
            response = char(this.QueryResponse);
        end

        function fprintf(this, command)
            this.WrittenCommands(end + 1) = string(command);
        end

        function response = fscanf(this)
            this.ReadCount = this.ReadCount + 1;
            response = char(this.ReadResponse);
        end

    end
end
