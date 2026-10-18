classdef FakeDeviceHandle < handle
    %FakeDeviceHandle - Stand-in for the visadev/tcpclient/serialport object
    %an Instrument keeps in DeviceHandle. Defines query/fprintf/fscanf as
    %methods so that Instrument's QueryString, WriteCommand etc. can run
    %without any hardware, and records what they were sent.

    properties (Access = public)
        QueryResponse = "";     %What query() returns - unless QueryResponses has a reply for that command
        QueryResponses = dictionary(string.empty, string.empty);   %Replies to particular commands, e.g. QueryResponses("MAG") = "100"
        ReadResponse = "";      %What fscanf() returns - once ReadQueue is empty
        ReadQueue (1,:) string = strings(1, 0);     %Lines waiting to be read, as a serial port's input buffer holds them - fscanf takes the first
        QueriedCommands (1,:) string = strings(1, 0);
        WrittenCommands (1,:) string = strings(1, 0);
        ReadCount = 0;
        Terminators (1,:) string = strings(1, 0);   %What configureTerminator was last given (read, then write)
        FlushCount = 0;                             %How many times the input was flushed
    end

    properties (Dependent)
        NumBytesAvailable;      %Bytes waiting to be read, as on a serialport: the lines in ReadQueue
    end

    methods
        function n = get.NumBytesAvailable(this)
            n = sum(strlength(this.ReadQueue));
        end
    end

    methods (Access = public)

        function response = query(this, command)
            this.QueriedCommands(end + 1) = string(command);
            if isConfigured(this.QueryResponses) && isKey(this.QueryResponses, string(command))
                response = char(this.QueryResponses(string(command)));
            else
                response = char(this.QueryResponse);
            end
        end

        function fprintf(this, command)
            this.WrittenCommands(end + 1) = string(command);
        end

        function response = fscanf(this)
            this.ReadCount = this.ReadCount + 1;
            if ~isempty(this.ReadQueue)
                response = char(this.ReadQueue(1));
                this.ReadQueue(1) = [];
            else
                response = char(this.ReadResponse);
            end
        end

        function configureTerminator(this, varargin)
            this.Terminators = string(varargin);
        end

        function flush(this, ~)
            this.FlushCount = this.FlushCount + 1;
            this.ReadQueue = strings(1, 0);
        end

    end
end
