classdef test_PythonUtils < matlab.unittest.TestCase
    % TEST_PythonUTILS Tests for Palladium utilities functions - PythonUtils
    % static class

    %% Properties
    properties
        TempDir = fullfile("..", "data", "Python Testing");
    end

    %% Tests
    methods (Test)

        function test_AppendFolderToPythonPath(testCase)
            % Test to verify that a directory is appended to the Python path

            % Call the method to append the directory to the Python path
            Palladium.Utilities.PythonUtils.AppendFolderToPythonPath(testCase.TempDir);

            % Verify that the directory is in the Python path by running
            % the little Python test function saved in there
            inputVal = 12;
            expectedVal = 120;
            val = py.pythontest.foo(inputVal);
            
            %Test code file just multiplies input by 10 - expect 120 as the output
            convertedVal = double(val);
            testCase.verifyEqual(convertedVal, expectedVal);
        end

        function test_CheckPythonSetup(testCase)
            % Assumes Python is installed, as for test_VerifyPythonInstall
            status = Palladium.Utilities.PythonUtils.CheckPythonSetup();
            testCase.verifyTrue(ismember(status.Status, ["OK", "PackagesMissing"]), "Python setup status was " + status.Status + ": " + status.ErrorMessage);
            testCase.verifyNotEqual(status.Version, "");
            testCase.verifyNotEqual(status.Executable, "");
            testCase.verifyEqual(status.Status == "PackagesMissing", ~isempty(status.MissingPackages));
        end

        function test_MakeSetupStatus(testCase)
            status = Palladium.Utilities.PythonUtils.MakeSetupStatus("LoadFailed", Executable="C:\Python\python.exe", ErrorMessage="Oops");
            testCase.verifyEqual(status.Status, "LoadFailed");
            testCase.verifyEqual(status.Version, "");
            testCase.verifyEqual(status.Executable, "C:\Python\python.exe");
            testCase.verifyEqual(status.ErrorMessage, "Oops");
            testCase.verifyEmpty(status.MissingPackages);
        end

        function test_SetupHelpMessage(testCase)
            % NotFound: install instructions, with links, and where to set PythonExecutable
            status = Palladium.Utilities.PythonUtils.MakeSetupStatus("NotFound");
            [title, msg] = Palladium.Utilities.PythonUtils.SetupHelpMessage(status, ConfigFilePath="C:\Config.json");
            testCase.verifyEqual(title, "Python instruments are unavailable");
            testCase.verifySubstring(msg, "https://www.python.org/downloads/");
            testCase.verifySubstring(msg, "pip install pyvisa pyserial");
            testCase.verifySubstring(msg, "PythonSettings.PythonExecutable");
            testCase.verifySubstring(msg, "C:\Config.json");

            % LoadFailed: the error message, with HTML special characters escaped
            status = Palladium.Utilities.PythonUtils.MakeSetupStatus("LoadFailed", Executable="C:\Py\python.exe", ErrorMessage="Version <3.9> & older");
            [~, msg] = Palladium.Utilities.PythonUtils.SetupHelpMessage(status);
            testCase.verifySubstring(msg, "Version &lt;3.9&gt; &amp; older");
            testCase.verifyFalse(contains(msg, "PythonSettings.PythonExecutable")); %No config file given

            % PackagesMissing: a pip command for the Python in use, for just the missing packages
            status = Palladium.Utilities.PythonUtils.MakeSetupStatus("PackagesMissing", Executable="C:\Py\python.exe", MissingPackages="pyserial");
            [title, msg] = Palladium.Utilities.PythonUtils.SetupHelpMessage(status);
            testCase.verifyEqual(title, "Python packages missing");
            testCase.verifySubstring(msg, """C:\Py\python.exe"" -m pip install pyserial");

            % OK: nothing to say
            [title, msg] = Palladium.Utilities.PythonUtils.SetupHelpMessage(Palladium.Utilities.PythonUtils.MakeSetupStatus("OK"));
            testCase.verifyEqual(title, "");
            testCase.verifyEqual(msg, "");
        end

        function test_UsePythonExecutable(testCase)
            % The Python already in use is accepted
            env = pyenv;
            [success, message] = Palladium.Utilities.PythonUtils.UsePythonExecutable(env.Executable);
            testCase.verifyTrue(success);
            testCase.verifyEqual(message, "");

            % A Python that doesn't exist is not
            [success, message] = Palladium.Utilities.PythonUtils.UsePythonExecutable(fullfile(tempdir, "NoSuchFolder", "python.exe"));
            testCase.verifyFalse(success);
            testCase.verifyNotEqual(message, "");
        end

        function test_VerifyPythonInstall(testCase)
            installed = Palladium.Utilities.PythonUtils.VerifyPythonInstall();
            testCase.verifyTrue(installed);%Assuming that python IS in fact installed

            installed = Palladium.Utilities.PythonUtils.VerifyPythonInstall(MinimumMainVersionNumber = 5);
            testCase.verifyFalse(installed);%Assuming that python 5, which does not yet exist, is not in fact installed

            installed = Palladium.Utilities.PythonUtils.VerifyPythonInstall(MinimumMainVersionNumber = 3, MinimumSubVersionNumber = 10);
            testCase.verifyTrue(installed);%Assuming that python IS in fact installed
        end

        function test_VerifyPythonPackageInstalled(testCase)
            installed = Palladium.Utilities.PythonUtils.VerifyPythonPackageInstalled("sys");
            testCase.verifyTrue(installed);

            installed = Palladium.Utilities.PythonUtils.VerifyPythonPackageInstalled("obviouslywrongpackagename");
            testCase.verifyFalse(installed);
        end

    end

end