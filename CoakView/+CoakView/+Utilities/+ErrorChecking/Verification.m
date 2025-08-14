classdef Verification
    %Static class to expose methods for verification/checking of various things
    
    properties (Constant)       
       DebugMode = false;   %Set to true to rethrow all handled errors and hence have a stack trace to follow in the command window - for debugging/testing purposes 
    end
    
    methods (Static)

        

        %% VerifyMatlabVersion
        function VerifyMatlabVersion(releaseStr)
            %Throw an error if the installed Matlab version is lower than the
            %specified release, eg "R2023b"
            if isMATLABReleaseOlderThan(releaseStr)
                error("Unsupported Matlab version, please upgrade to at least version " + releaseStr);
            end
        end
        
        %% VerifyToolboxInstalled
        function VerifyToolboxInstalled(toolboxName)
            %% Find the toolbox and give proper output
            v_= ver;
            [installedToolboxes{1:length(v_)}] = deal(v_.Name);
            result = all(ismember(toolboxName,installedToolboxes));
            assert(result,['Error! ' toolboxName ' is not installed!']);
        end
        
        
    end
end

