classdef test_QCoDeSCatalog < matlab.unittest.TestCase
    %TEST_QCODESCATALOG Tests finding QCoDeS drivers by reading their files (PalladiumPythonCore/QCoDeSCatalog.py)
    %The drivers are read as text, never imported, so these tests need
    %neither qcodes nor any instrument.

    %% Properties
    properties
        Catalog;    %The QCoDeSCatalog Python module
        Folder;     %A fresh folder for each test, standing in for the user's QCoDeS Drivers folder
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function importCatalog(testCase)
            here = fileparts(mfilename("fullpath"));
            sourceRoot = fileparts(fileparts(fileparts(here)));     %Holds PalladiumPythonCore

            %Don't let Python write __pycache__ folders into the source folder
            oldSetting = pyrun("import sys; old = sys.dont_write_bytecode; sys.dont_write_bytecode = True", "old");
            testCase.addTeardown(@() pyrun("import sys; sys.dont_write_bytecode = setting", setting=oldSetting));

            py.sys.path().insert(int32(0), string(sourceRoot));
            testCase.addTeardown(@() py.sys.path().remove(string(sourceRoot)));

            testCase.Catalog = py.importlib.reload(py.importlib.import_module("PalladiumPythonCore.QCoDeSCatalog"));
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function makeFolder(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = string(fixture.Folder);
        end
    end

    %% Methods (Test)
    methods (Test)

        function InstrumentClassesAreFoundFromTheirBasesTest(testCase)
            %A class is an instrument if it inherits from QCoDeS's, directly or through another class. Helpers, private
            %and abstract-looking classes, and classes that aren't instruments are left out
            testCase.writeDriver("MyDevice.py", [
                "from qcodes.instrument import VisaInstrument"
                "class MyDevice(VisaInstrument): pass"
                "class MyOtherDevice(MyDevice): pass"
                "class _Private(VisaInstrument): pass"
                "class MyDeviceBase(VisaInstrument): pass"
                "class Basel(VisaInstrument): pass"
                "class NotAnInstrument: pass"
                ]);

            entries = testCase.userEntries();

            testCase.verifyEqual(sort(string({entries.name})), ["Basel", "MyDevice", "MyOtherDevice"]);
        end

        function EntriesNameTheDriverAndWhereToImportItTest(testCase)
            testCase.writeDriver("MyDevice.py", ["from qcodes.instrument import VisaInstrument", "class MyDevice(VisaInstrument): pass"]);

            entry = testCase.userEntries();

            testCase.verifyEqual(string(entry.entry), "QCoDeS: MyDevice");
            testCase.verifyEqual(string(entry.class_path), "MyDevice.MyDevice");
            testCase.verifyEqual(string(entry.source), "user");
            testCase.verifyEqual(string(entry.folder), testCase.Folder);
        end

        function DriverFilesAreNotRunTest(testCase)
            %Scanning must not import (run) a driver: it may be slow, or need packages that aren't installed
            testCase.writeDriver("Explodes.py", [
                "raise RuntimeError('this file was imported')"
                "class Explodes(VisaInstrument): pass"
                ]);

            entry = testCase.userEntries();

            testCase.verifyEqual(string(entry.name), "Explodes");
        end

        function SameClassNameInTwoFilesGivesUniqueEntriesTest(testCase)
            testCase.writeDriver("one.py", ["from qcodes.instrument import VisaInstrument", "class Same(VisaInstrument): pass"]);
            testCase.writeDriver("two.py", ["from qcodes.instrument import VisaInstrument", "class Same(VisaInstrument): pass"]);

            entries = testCase.userEntries();

            testCase.verifyNumElements(entries, 2);
            testCase.verifyNumElements(unique(string({entries.entry})), 2);
        end

        function BrokenFilesAreSkippedTest(testCase)
            testCase.writeDriver("Broken.py", "class Broken(VisaInstrument:");
            testCase.writeDriver("Fine.py", ["from qcodes.instrument import VisaInstrument", "class Fine(VisaInstrument): pass"]);

            entry = testCase.userEntries();

            testCase.verifyEqual(string(entry.name), "Fine");
        end

        function ClassInheritingFromAnInstalledDriverIsFoundTest(testCase)
            %A dropped-in driver that builds on a driver from the installed packages, which is in another file
            hasQcodes = logical(pyrun("import importlib.util; found = importlib.util.find_spec('qcodes') is not None", "found"));
            testCase.assumeTrue(hasQcodes, "qcodes isn't installed in the Python MATLAB uses");
            testCase.writeDriver("MyKeithley.py", [
                "from qcodes.instrument_drivers.Keithley import Keithley2450"
                "class MyKeithley(Keithley2450): pass"
                ]);

            entry = testCase.userEntries();

            testCase.verifyEqual(string(entry.name), "MyKeithley");
        end

        function MissingFolderGivesNoUserDriversTest(testCase)
            catalog = jsondecode(string(testCase.Catalog.build_catalog_json(char(fullfile(testCase.Folder, "NotThere")))));

            if ~isempty(catalog)
                testCase.verifyFalse(any(string({catalog.source}) == "user"));
            end
        end

    end

    %% Methods (Private)
    methods (Access = private)
        function writeDriver(testCase, fileName, lines)
            %Write a driver file into the folder
            fid = fopen(fullfile(testCase.Folder, fileName), "w");
            fprintf(fid, "%s\n", lines);
            fclose(fid);
        end

        function entries = userEntries(testCase)
            %The catalog's entries from the folder (not the installed qcodes ones), as a struct array
            catalog = jsondecode(string(testCase.Catalog.build_catalog_json(char(testCase.Folder))));
            entries = catalog(string({catalog.source}) == "user");
        end
    end
end
