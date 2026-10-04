classdef test_DataFileSwitch < matlab.unittest.TestCase
    %TEST_DATAFILESWITCH Tests switching data file while measuring, as a sequence's [DATAFILE] command does (Controller.SetFilePathWhileRunning)

    %% Properties
    properties
        ConfigPath;     %Test config, relative to the Palladium.m folder
        DataDir;        %Where the programme writes its data files (from TestingConfig.json)
        Programme;      %The Palladium instance under test
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function fixturesSetup(testCase)
            %Palladium writes its data files, sequences and logs to the
            %Data, Sequences and Logs folders in Testing Data Files (see
            %TestingConfig.json). The fixture removes them again afterwards.
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename('fullpath')), "..", "Helpers")));
            testCase.applyFixture(TestHelpers.ProgrammeOutputFixture);
            testCase.ConfigPath = fullfile("Tests", "TestingConfig.json");
            testCase.DataDir = fullfile(string(fileparts(which("Palladium"))), "Tests", "Testing Data Files", "Data");
        end
    end

    %% Methods (Test)
    methods (Test)
        function NewFileStartsWithHeader(testCase)
            %[DATAFILE] 1 : <path> - the new file gets the same header as
            %a file started with Start, followed by data
            testCase.startMeasuring();
            ctrl = testCase.Programme.Controller;
            firstPath = ctrl.DataWriter.FileWriteDetails.FilePath;
            firstLines = readlines(firstPath);
            headerLength = find(firstLines == Palladium.DataWriting.DataWriter.END_METADATA_LINES_STRING) + 2;

            ctrl.SetFilePathWhileRunning(fullfile(testCase.DataDir, "Second.dat"), true);
            secondPath = ctrl.DataWriter.FileWriteDetails.FilePath;
            pause(1);
            testCase.Programme.Stop();

            testCase.verifyNotEqual(secondPath, firstPath);
            testCase.verifySubstring(secondPath, "Second");
            lines = readlines(secondPath);
            testCase.verifyEqual(lines(1), "<<< Palladium DAQ data file 3.0 >>>");
            testCase.verifyEqual(lines(headerLength), firstLines(headerLength), "Column headers should match the first file's");
            dataRows = lines(headerLength + 1 : end);
            dataRows = dataRows(dataRows ~= "");
            testCase.verifyNotEmpty(dataRows, "Data should be written after the header");
            testCase.verifyFalse(any(contains(dataRows, "<<<")), "Only data should follow the header");
        end

        function WriteDisableStopsWriting(testCase)
            %[DATAFILE] 0 - no path: rows stop being added, and the file
            %name and folder are kept
            testCase.startMeasuring();
            ctrl = testCase.Programme.Controller;
            details = ctrl.FileWriteDetails;
            path = ctrl.DataWriter.FileWriteDetails.FilePath;

            ctrl.SetFilePathWhileRunning(string.empty, false);
            linesAtDisable = numel(readlines(path));
            pause(1);

            testCase.verifyEqual(numel(readlines(path)), linesAtDisable, "No rows should be written once saving is switched off");
            testCase.verifyFalse(ctrl.FileWriteDetails.SaveFile);
            testCase.verifyEqual(ctrl.FileWriteDetails.FileName, details.FileName);
            testCase.verifyEqual(ctrl.FileWriteDetails.Directory, details.Directory);
        end

        function SavingTurnedOnMidRunStartsWithHeader(testCase)
            %Started with Write to File unticked, then [DATAFILE] 1 : <path>
            %- the file it starts still gets the full header
            filesBefore = numel(dir(fullfile(testCase.DataDir, "*.dat")));     %Other tests' files may be there too
            testCase.startMeasuring(SaveFile=false);
            ctrl = testCase.Programme.Controller;
            testCase.verifyNumElements(dir(fullfile(testCase.DataDir, "*.dat")), filesBefore, "Nothing should be written while saving is off");

            ctrl.SetFilePathWhileRunning(fullfile(testCase.DataDir, "Second.dat"), true);
            path = ctrl.DataWriter.FileWriteDetails.FilePath;
            pause(1);
            testCase.Programme.Stop();

            lines = readlines(path);
            testCase.verifyEqual(lines(1), "<<< Palladium DAQ data file 3.0 >>>");
            headerEnd = find(lines == Palladium.DataWriting.DataWriter.END_METADATA_LINES_STRING);
            testCase.verifyNotEmpty(headerEnd, "The file should have the full header");
            testCase.verifySubstring(lines(headerEnd + 2), "K2000_1", "Column headers should follow the metadata");
            dataRows = lines(headerEnd + 3 : end);
            testCase.verifyNotEmpty(dataRows(dataRows ~= ""), "Data should be written after the header");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function startMeasuring(testCase, Settings)
            %Start a headless programme measuring a simulated instrument
            arguments
                testCase;
                Settings.SaveFile (1,1) logical = true;     %Write to File ticked
            end
            pd = Palladium(View=[], ConfigFilePath=testCase.ConfigPath);
            testCase.addTeardown(@() pd.Close());
            pd.AddInstrument("Keithley2000", ConnectionType="Debug");
            pd.SetFileName("First");
            pd.SetSaveFileBool(Settings.SaveFile);
            pd.SetUpdateTime(0.2);
            pd.Start();
            testCase.addTeardown(@() pd.Stop());
            pause(1);
            testCase.Programme = pd;
        end
    end
end
