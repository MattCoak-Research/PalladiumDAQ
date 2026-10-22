classdef FakeComServer < handle
    %FakeComServer - A stand-in for ComServerProcess, for testing a driver that uses a COM library: records every call and answers from set replies.
    %Each call is recorded as text in Calls, e.g. "SetFreqPlan(10, 9.9, 101, 0, 1000)",
    %with " [background]" after those made with CallAsync. A reply is looked
    %up by the call's name and arguments joined by "|" (e.g.
    %"GetData|S11|logmag|0"), then by its name alone, and is "OK" if
    %neither is in Replies. A background call stays busy for BusyChecks
    %calls of IsBusy.

    %% Properties (Public)
    properties (Access = public)
        Calls = strings(1, 0);                                  %Every call made, in order
        Replies = dictionary(string.empty, string.empty);       %Replies by call, as described above
        BusyChecks = 0;                                         %How many times IsBusy says true for a background call, before it says it has finished
        Shared;                                                 %A containers.Map, which outlives the server being deleted (stopped): "Deleted" is true once it has been, and "Calls" has all the calls made
    end

    %% Properties (Private)
    properties (Access = private)
        PendingKey = [];                                        %Reply key of the background call in progress
        ChecksLeft = 0;
        PendingFinished = false;
    end

    %% Constructor
    methods
        function this = FakeComServer()
            this.Shared = containers.Map();
            this.Shared("Deleted") = false;
            this.Shared("Calls") = strings(1, 0);
        end
    end

    %% Methods (Public)
    methods (Access = public)
        function reply = Call(this, functionName, varargin)
            this.Record(functionName, varargin, "");
            reply = this.Lookup(functionName, varargin);
        end

        function CallAsync(this, functionName, varargin)
            this.Record(functionName, varargin, " [background]");
            this.PendingKey = {functionName, varargin};
            this.ChecksLeft = this.BusyChecks;
            this.PendingFinished = false;
        end

        function reply = GetAsyncReply(this)
            assert(this.PendingFinished, "FakeComServer:NotFinished", "The background call has not finished.");
            reply = this.Lookup(this.PendingKey{:});
            this.PendingFinished = false;
        end

        function busy = IsBusy(this)
            busy = false;
            if isempty(this.PendingKey) || this.PendingFinished
                return;
            end
            if this.ChecksLeft > 0
                this.ChecksLeft = this.ChecksLeft - 1;
                busy = true;
            else
                this.PendingFinished = true;
            end
        end

        function delete(this)
            this.Shared("Deleted") = true;
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function args = ArgumentsAsText(~, arguments)
            args = string(cellfun(@(a) string(a), arguments));
        end

        function Record(this, functionName, arguments, suffix)
            this.Calls(end + 1) = string(functionName) + "(" + strjoin(this.ArgumentsAsText(arguments), ", ") + ")" + suffix;
            this.Shared("Calls") = this.Calls;
        end

        function reply = Lookup(this, functionName, arguments)
            exactKey = strjoin([string(functionName), this.ArgumentsAsText(arguments)], "|");
            if isKey(this.Replies, exactKey)
                reply = char(this.Replies(exactKey));
            elseif isKey(this.Replies, string(functionName))
                reply = char(this.Replies(string(functionName)));
            else
                reply = 'OK';
            end
        end
    end
end
