classdef RecordingPicoVNA < Palladium.Instruments.PicoVNA_NetworkAnalyser
    %RecordingPicoVNA - A PicoVNA_NetworkAnalyser that can be given a backend by the test, in place of finding the PicoVNA software.
    %SetBackendForTest connects it to a backend directly (e.g. a Software5
    %with a FakeDeviceHandle). To test the search for the software through
    %Connect, put fake backends in FakeBackends, by the software they stand in
    %for ("PicoVNA 5" or "PicoVNA 3"): CreateBackend then returns those, and
    %the names it was asked for are kept in BackendsRequested.

    %% Properties (Public)
    properties (Access = public)
        FakeBackends = dictionary(string.empty, cell.empty);    %Backends CreateBackend returns, by software name
        BackendsRequested = strings(1, 0);                      %The software names CreateBackend was asked for, in order
    end

    %% Methods (Public)
    methods (Access = public)
        function SetBackendForTest(this, backend)
            this.Backend = backend;
        end

        function CloseForTest(this)
            %Close the connection, as Disconnect does (CloseConnection is protected)
            this.CloseConnection();
        end
    end

    %% Methods (Protected)
    methods (Access = protected)
        function backend = CreateBackend(this, software)
            this.BackendsRequested(end + 1) = software;
            if isKey(this.FakeBackends, software)
                backend = this.FakeBackends{software};
            else
                backend = CreateBackend@Palladium.Instruments.PicoVNA_NetworkAnalyser(this, software);
            end
        end
    end
end
