classdef test_Controller < matlab.unittest.TestCase
    % TEST_CONTROLLER Tests for Palladium.Core.Controller's helper methods
    % that don't need a running Palladium DAQ - the system tests cover the
    % rest.

    %% Properties
    properties
        ApplicationDir;     %An absolute folder to stand in for the folder Palladium.m is in - nothing is written to it
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function DirectorySetup(testCase)
            testCase.ApplicationDir = string(fileparts(mfilename("fullpath")));
        end
    end

    %% Tests
    methods (Test)

        %% MakeAbsoluteFromApplicationDir (private)
        function RelativeConfigPathIsMadeAbsolute(testCase)
            path = testCase.verifyWarningFree(@() Palladium.Core.Controller.MakeAbsoluteFromApplicationDir("Data", testCase.ApplicationDir, false));
            testCase.verifyEqual(path, fullfile(testCase.ApplicationDir, "Data"));
        end

        function AbsoluteConfigPathIsUnchanged(testCase)
            %Even in an installed copy - a full path is the right thing there
            absolutePath = fullfile(testCase.ApplicationDir, "Elsewhere", "Data");
            path = testCase.verifyWarningFree(@() Palladium.Core.Controller.MakeAbsoluteFromApplicationDir(absolutePath, testCase.ApplicationDir, true));
            testCase.verifyEqual(path, absolutePath);
        end

        function RelativeConfigPathInInstalledCopyWarns(testCase)
            %In an installed copy the installation folder may not be
            %writable, and is replaced by updates
            path = testCase.verifyWarning(@() Palladium.Core.Controller.MakeAbsoluteFromApplicationDir("Data", testCase.ApplicationDir, true), "LoadSettingsWarning:RelativePathInInstalledCopy");
            testCase.verifyEqual(path, fullfile(testCase.ApplicationDir, "Data"), "The path should still be made absolute");
        end

    end
end
