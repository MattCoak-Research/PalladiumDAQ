classdef test_PythonUtils < matlab.unittest.TestCase
    % TEST_PythonUTILS Tests for Palladium utilities functions - PythonUtils
    % static class

    %% Properties
    properties
        TempDir = fullfile("..", "data", "Python Testing");
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function HelpersPathSetup(testCase)
            %Test helpers, which keep everything the tests write inside Testing Data Files
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(mfilename("fullpath")), "..", "..", "Helpers")));
        end
    end

    %% Tests
    methods (Test)

        function test_ImportPythonModulesInPackageFolder_ReloadsChanges(testCase)
            %Importing a package again picks up changes to its modules
            %(the reload check had its arguments the wrong way round, so an
            %edited Python instrument needed a MATLAB restart)
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            parentFolder = string(fixture.Folder);
            [~, uniqueName] = fileparts(tempname);     %A new package name each run, as Python keeps modules for the whole MATLAB session
            packageName = "ReloadTest_" + string(uniqueName);
            mkdir(fullfile(parentFolder, packageName));
            modulePath = fullfile(parentFolder, packageName, "ReloadModule.py");
            testCase.addTeardown(@() testCase.removeFromPythonPath(parentFolder));

            writelines(["def Value():", "    return 1"], modulePath);
            [~, modules] = Palladium.Utilities.PythonUtils.ImportPythonModulesInPackageFolder(parentFolder, packageName);
            testCase.verifyEqual(double(modules{1}.Value()), 1);

            %A different size too, so Python can't mistake it for the cached version
            writelines(["def Value():", "    return 2222"], modulePath);
            [~, modules] = Palladium.Utilities.PythonUtils.ImportPythonModulesInPackageFolder(parentFolder, packageName);
            testCase.verifyEqual(double(modules{1}.Value()), 2222, "The edited module should have been reloaded");
        end

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

        function test_AppendFolderToPythonPath_AddsOnlyOnce(testCase)
            %Adding the same folder again leaves one entry - each Palladium
            %start in a MATLAB session used to add another
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            folder = char(fixture.Folder);
            testCase.addTeardown(@() pyrun("import sys" + newline + "while folder in sys.path: sys.path.remove(folder)", folder=folder));

            Palladium.Utilities.PythonUtils.AppendFolderToPythonPath(folder);
            Palladium.Utilities.PythonUtils.AppendFolderToPythonPath(folder);

            testCase.verifyEqual(double(count(py.sys.path, folder)), 1);
        end

        function test_CheckPythonSetup(testCase)
            % Assumes Python is installed
            status = Palladium.Utilities.PythonUtils.CheckPythonSetup();
            testCase.verifyTrue(ismember(status.Status, ["OK", "PackagesMissing"]), "Python setup status was " + status.Status + ": " + status.ErrorMessage);
            testCase.verifyNotEqual(status.Version, "");
            testCase.verifyNotEqual(status.Executable, "");
            testCase.verifyEqual(status.Status == "PackagesMissing", ~isempty(status.MissingPackages));
        end

        function test_ProbePython(testCase)
            %Running the Python MATLAB uses in a separate process reports its version, and says what it did
            env = pyenv;
            probe = Palladium.Utilities.PythonUtils.ProbePython(env.Executable);
            testCase.verifyTrue(probe.Runnable, "Probe failed: " + probe.ErrorMessage);
            testCase.verifyEqual(probe.ErrorMessage, "");
            testCase.verifyEqual(probe.ExitCode, 0);
            testCase.verifyTrue(startsWith(probe.Version, string(env.Version) + "."), "Version should start with pyenv's");
            testCase.verifyEqual(probe.VersionNumber(1:2), double(split(string(env.Version), "."))');
            testCase.verifyNotEqual(probe.ResolvedExecutable, "");
            testCase.verifyTrue(any(contains(probe.Details, "Command:")));
            testCase.verifyTrue(any(contains(probe.Details, "Exit code 0")));
        end

        function test_ProbePython_NotPython(testCase)
            %A file that isn't there, or isn't a Python, is not runnable, with the reason
            fixture = testCase.applyFixture(TestHelpers.DataFolderFixture);
            missing = fullfile(string(fixture.Folder), "NoSuchPython", "python.exe");
            probe = Palladium.Utilities.PythonUtils.ProbePython(missing);
            testCase.verifyFalse(probe.Runnable);
            testCase.verifySubstring(probe.ErrorMessage, "There is no file at");
            testCase.verifyTrue(any(contains(probe.Details, missing)));

            notPython = fullfile(string(fixture.Folder), "NotPython.txt");
            writelines("This is not a program", notPython);
            probe = Palladium.Utilities.PythonUtils.ProbePython(notPython);
            testCase.verifyFalse(probe.Runnable);
            testCase.verifySubstring(probe.ErrorMessage, "is not a program");
        end

        function test_CheckVersionSupported(testCase)
            check = @Palladium.Utilities.PythonUtils.CheckVersionSupported;
            [ok, msg] = check([3 10 0]);
            testCase.verifyTrue(ok);
            testCase.verifyEqual(msg, "");
            testCase.verifyTrue(check([3 12 4]));
            testCase.verifyTrue(check([3 14 8]));
            [ok, msg] = check([3 9 6]);
            testCase.verifyFalse(ok);
            testCase.verifySubstring(msg, "Python 3.9.6 is not supported");
            testCase.verifyFalse(check([3 15 0]));
            testCase.verifyFalse(check([2 7 18]));
            testCase.verifyFalse(check([4 0 0]));
        end

        function test_ApplyPythonExecutable(testCase)
            %The Python already in use is accepted, and one that isn't there is refused without changing anything
            env = pyenv;
            [success, message, probe] = Palladium.Utilities.PythonUtils.ApplyPythonExecutable(env.Executable);
            testCase.verifyTrue(success, message);
            testCase.verifyTrue(probe.Runnable);
            testCase.verifyTrue(any(contains(probe.Details, "pyenv now uses")));

            missing = fullfile(tempdir, "NoSuchFolder", "python.exe");
            [success, message, probe] = Palladium.Utilities.PythonUtils.ApplyPythonExecutable(missing);
            testCase.verifyFalse(success);
            testCase.verifySubstring(message, "There is no file at");
            testCase.verifyFalse(probe.Runnable);
            testCase.verifyEqual(string(pyenv().Executable), string(env.Executable), "pyenv should be unchanged");
        end

        function test_CheckPythonSetup_Details(testCase)
            %The status says what was tried, for the Debug log, including the probe
            status = Palladium.Utilities.PythonUtils.CheckPythonSetup();
            testCase.verifyTrue(any(contains(status.Details, "Probing Python at")));
            testCase.verifyTrue(any(contains(status.Details, "Loaded in MATLAB")));
            testCase.verifyTrue(any(contains(status.Details, "pyenv:")));
        end

        function test_MakeSetupStatus(testCase)
            status = Palladium.Utilities.PythonUtils.MakeSetupStatus("LoadFailed", Executable="C:\Python\python.exe", ErrorMessage="Oops");
            testCase.verifyEqual(status.Status, "LoadFailed");
            testCase.verifyEqual(status.Version, "");
            testCase.verifyEqual(status.Executable, "C:\Python\python.exe");
            testCase.verifyEqual(status.ErrorMessage, "Oops");
            testCase.verifyEmpty(status.MissingPackages);
            testCase.verifyEmpty(status.Details);

            status = Palladium.Utilities.PythonUtils.MakeSetupStatus("NotFound", Details=["one", "two"]);
            testCase.verifyEqual(status.Details, ["one"; "two"]);
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
            testCase.verifySubstring(msg, "Browse for Python...");

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

    end

    %% Methods (Private)
    methods (Access = private)
        function removeFromPythonPath(~, folder)
            %Take a folder the test added back off Python's sys.path
            sysPath = py.sys.path;
            while count(sysPath, folder) > 0
                sysPath.remove(folder);
            end
        end
    end

end