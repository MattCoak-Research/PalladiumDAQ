classdef CallRecorder < handle
    %CallRecorder - Shared log that StubInstrument and StubControl both
    %write to, so tests can check the order calls happened in

    properties (Access = public)
        Entries (1,:) string = strings(1, 0);
    end

    methods (Access = public)

        function Record(this, entry)
            this.Entries(end + 1) = string(entry);
        end

    end
end
