classdef Verification
    %Static class to expose methods for verification/checking of various things
    
    properties (Constant)       
       DebugMode = false;   %Set to true to rethrow all handled errors and hence have a stack trace to follow in the command window - for debugging/testing purposes 
    end
    
    methods (Static)

        %% CheckForDuplicatesInHeadersArray
        function [duplicates, combinedString] = CheckForDuplicatesInHeadersArray(headers)
            combinedString = "";
            duplicates = [];

            %handle edge cases
            if isempty(headers)
                return;
            end
            if length(headers) < 2
                return;
            end

            % Find the indices of the unique strings
            [~, uniqueIdx] =unique(headers);

            % Copy the original into a duplicate array
            duplicates = headers;

            % remove the unique strings, anything left is a duplicate
            duplicates(uniqueIdx) = [];

            % find the unique duplicates
            duplicates = unique(duplicates);

            for i = 1 : length(duplicates)
                if i == 1
                    combinedString = combinedString + string(duplicates(i));
                else
                    combinedString = combinedString + ", " + string(duplicates(i));
                end
            end
        end

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

