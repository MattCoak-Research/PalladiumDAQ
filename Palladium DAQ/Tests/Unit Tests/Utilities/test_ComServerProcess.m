classdef test_ComServerProcess < matlab.unittest.TestCase
    %TEST_COMSERVERPROCESS Tests running a COM object in a background PowerShell process: calls, background calls and errors
    %Windows only. The object is a PowerShell stand-in for a COM library,
    %given through CreateObjectScript. Replies are text as char, as a COM
    %call returns it.

    %% Properties (Constant, Private)
    properties(Constant, Access = private)
        FakeObjectScript = strjoin([
            "$o = New-Object PSObject"
            "$o | Add-Member ScriptMethod Echo { param($x) $x }"
            "$o | Add-Member ScriptMethod Add { param($a, $b) $a + $b }"
            "$o | Add-Member ScriptMethod Slow { param($s) Start-Sleep -Seconds $s; 'done' }"
            "$o | Add-Member ScriptMethod Fail { throw 'boom' }"
            "$o | Add-Member ScriptMethod Nothing { }"
            "$o | Add-Member ScriptMethod Crash { [Environment]::Exit(-1073741819) }"
            "$o"
            ], newline);
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function windowsOnly(testCase)
            testCase.assumeTrue(ispc, "COM objects are only available on Windows");
        end
    end

    %% Methods (Test)
    methods (Test)
        function CallReturnsTheReplyTest(testCase)
            server = testCase.startServer();
            testCase.verifyEqual(server.Call("Echo", "abc"), 'abc');
            testCase.verifyEqual(server.Call("Add", 2, 3.5), 5.5);
            testCase.verifyEqual(server.Call("Echo", "C:\folder\file.txt"), 'C:\folder\file.txt', "Backslashes survive");
            testCase.verifyEmpty(server.Call("Nothing"), "A method with no reply");
        end

        function CallAsyncReturnsAtOnceTest(testCase)
            server = testCase.startServer();

            timer = tic();
            server.CallAsync("Slow", 2);
            started_s = toc(timer);

            testCase.verifyLessThan(started_s, 1, "Returns without waiting for the call");
            testCase.verifyTrue(server.IsBusy(), "Still running");
            testCase.waitUntilFree(server);
            testCase.verifyEqual(server.GetAsyncReply(), 'done');
        end

        function ACallWaitsForTheBackgroundCallBeforeItTest(testCase)
            %One request at a time - and the background call's reply is kept
            server = testCase.startServer();
            server.CallAsync("Slow", 1);

            testCase.verifyEqual(server.Call("Echo", "x"), 'x');

            testCase.verifyFalse(server.IsBusy());
            testCase.verifyEqual(server.GetAsyncReply(), 'done');
        end

        function FailedCallErrorsWithTheMessageTest(testCase)
            server = testCase.startServer();
            testCase.verifyError(@() server.Call("Fail"), "ComServerProcess:CallFailed");
            testCase.verifyEqual(server.Call("Echo", "still working"), 'still working', "The server carries on");

            server.CallAsync("Fail");
            testCase.waitUntilFree(server);
            testCase.verifyError(@() server.GetAsyncReply(), "ComServerProcess:CallFailed");
        end

        function NoBackgroundCallErrorsTest(testCase)
            server = testCase.startServer();
            testCase.verifyFalse(server.IsBusy());
            testCase.verifyError(@() server.GetAsyncReply(), "ComServerProcess:NoCall");
        end

        function ObjectThatCannotBeCreatedErrorsTest(testCase)
            testCase.verifyError(@() Palladium.Utilities.ComServerProcess("Fake", CreateObjectScript = "throw 'no such library'"), ...
                "ComServerProcess:StartFailed");
            testCase.verifyError(@() Palladium.Utilities.ComServerProcess("No.Such.ComClass"), "ComServerProcess:StartFailed");
        end

        function ACrashReportsTheExitCodeAndTheRequestTest(testCase)
            %A crash in a COM library ends the helper process, not MATLAB - and the error says how, and during which call
            server = testCase.startServer();

            testCase.verifyError(@() server.Call("Crash"), "ComServerProcess:ProcessExited");
            try
                server.Call("Echo", "x");
            catch err
                message = string(err.message);
            end

            testCase.verifyTrue(contains(message, "0xC0000005"), "The exit code");
            testCase.verifyTrue(contains(message, "Crash"), "The call it died in");
        end

        function DeletingStopsTheProcessEvenWhenBusyTest(testCase)
            server = testCase.startServer();
            server.CallAsync("Slow", 30);

            timer = tic();
            delete(server);     %Stops the process even though it is busy

            testCase.verifyFalse(isvalid(server));
            testCase.verifyLessThan(toc(timer), 10, "Doesn't wait for the 30 s call");
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function server = startServer(testCase)
            %A server for the stand-in object, deleted (stopped) at the end of the test.
            server = Palladium.Utilities.ComServerProcess("Fake", CreateObjectScript = testCase.FakeObjectScript);
            testCase.addTeardown(@() delete(server(isvalid(server))));
        end

        function waitUntilFree(testCase, server)
            %Until the background call finishes - up to 20 s.
            timer = tic();
            while server.IsBusy() && toc(timer) < 20
                pause(0.05);
            end
            testCase.assertFalse(server.IsBusy(), "The background call didn't finish");
        end
    end
end
