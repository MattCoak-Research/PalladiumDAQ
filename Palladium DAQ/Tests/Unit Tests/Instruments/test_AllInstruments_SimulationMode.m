classdef test_AllInstruments_SimulationMode < matlab.unittest.TestCase
    %TEST_ALLINSTRUMENTS_SIMULATIONMODE Tests every built-in instrument driver, and the template, in simulation (Debug): it constructs with no hardware, connects, and Measure returns one value per header
    %One test per driver file in +Palladium/+Instruments, so a new
    %driver is tested automatically, plus the template for new drivers in
    %ExamplesAndTemplates/Instruments.

    %% Properties (TestParameter)
    properties (TestParameter)
        Driver = driverNames();     %Class names of the drivers to test
    end

    %% Methods (Test)
    methods (Test)
        function MeasureMatchesHeaders(testCase, Driver)
            %PPMS simulates through Quantum Design's own .NET libraries:
            %QDInterface.dll (bundled) and QDInstrument.dll, which users
            %install from Quantum Design - so it can't be run here
            testCase.assumeFalse(Driver == "PPMS", "PPMS needs Quantum Design's QDInstrument.dll (installed separately, Windows only), even in simulation");

            if Driver == "TemplateInstrumentClass"
                %The template isn't in a namespace folder - it becomes a
                %Palladium.Instruments driver when copied to a user files folder
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(sourceRoot(), "ExamplesAndTemplates", "Instruments")));
                instr = TemplateInstrumentClass();
            else
                instr = feval("Palladium.Instruments." + Driver);
            end
            testCase.addTeardown(@() instr.Close());

            instr.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            instr.Connect();
            [headers, units] = instr.GetHeaders();
            dataRow = instr.Measure();

            %Drivers that record only through a Scan Control (network
            %analysers) have no per-tick columns: 0 headers and 0 values
            %is consistent too
            testCase.verifyNumElements(units, numel(headers), "GetHeaders should return one unit per header");
            testCase.verifyNumElements(dataRow, numel(headers), "Measure should return one value per header");
            testCase.verifyClass(dataRow, "double");
        end
    end
end

function names = driverNames()
%Class names of the driver files in +Palladium/+Instruments, and the
%template, as a cell array for the TestParameter, leaving out the
%prototyping instrument
excluded = "TestInstrument";    %Scratch instrument for prototyping new features (not shipped) - its Measure currently errors on the first call

files = dir(fullfile(sourceRoot(), "+Palladium", "+Instruments", "*.m"));
names = erase(string({files.name}), ".m");
names = cellstr([setdiff(names, excluded), "TemplateInstrumentClass"]);
end

function folder = sourceRoot()
%The source root folder, holding Palladium.m
folder = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));     %Tests/Unit Tests/Instruments -> source root
end
