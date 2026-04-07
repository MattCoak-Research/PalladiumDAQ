function plan = buildfile
    plan = buildplan(localfunctions);
    plan("test").Dependencies = "check";
    plan("package").Dependencies = "test";
end

function checkTask(~)
    issues = codeIssues(["Palladium DAQ/+Palladium/", "Palladium DAQ/Tests/"], IncludeSubfolders=true);
    if ~isempty(issues.Issues)
        disp(" ");
        disp("Code Issues Found:");
        disp(" ");
        disp(issues.Issues);
        disp(" ");
        disp(" ");
       % error("BuildFile:IssuesFound", "Code issues found.");
    end
end

function testTask(~)
    results = runtests("Palladium DAQ/Tests/Unit Tests/", IncludeSubfolders=true);
    assertSuccess(results);
end

function packageTask(~)
    opts = matlab.addons.toolbox.ToolboxOptions("PalladiumDAQ.prj"); 
    verStruct = Palladium.ver();    
    opts.ToolboxVersion = string(verStruct.VersionString);
    matlab.addons.toolbox.packageToolbox(opts);
end