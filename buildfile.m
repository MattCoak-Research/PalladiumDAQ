function plan = buildfile
    plan = buildplan(localfunctions);
    plan("test").Dependencies = "check";
    plan("package").Dependencies = "test";
end

function checkTask(~)
    issues = codeIssues(["Palladium DAQ/+Palladium/", "Palladium DAQ/Tests/"], IncludeSubfolders=true);
 %   assert(isempty(issues.Issues), "Code issues found.");
end

function testTask(~)
    results = runtests("Palladium DAQ/Tests/Unit Tests/", "IncludeSubfolders", true);
    assertSuccess(results);
end

function packageTask(~)
    matlab.addons.toolbox.packageToolbox("PalladiumDAQ.prj");
end