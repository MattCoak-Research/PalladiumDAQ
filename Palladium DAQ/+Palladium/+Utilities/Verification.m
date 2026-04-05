classdef Verification
    %Static class to expose methods for verification/checking of various things
    
    %% Methods (Static, Public)
    methods (Static, Access = public)

        function [duplicates, combinedString] = CheckForDuplicatesInCellArrayOfStrings(cellArrayOfStrings)
            duplicates = {};
            combinedString = "";

            %handle edge cases
            if isempty(cellArrayOfStrings)
                return;
            end
            if length(cellArrayOfStrings) < 2
                return;
            end

            %Convert
            strArray = string(cellArrayOfStrings);

            % Find the indices of the unique strings
            [~, uniqueIdx] = unique(strArray);

            % remove the unique strings, anything left is a duplicate
            strArray(uniqueIdx) = [];

            % find the unique duplicates
            duplicates = unique(strArray);

            %Write the duplicates out in a nice string, to print in error
            %messages: one, two, three
            for i = 1 : length(duplicates)
                if i == 1
                    combinedString = combinedString + string(duplicates(i));
                else
                    combinedString = combinedString + ", " + string(duplicates(i));
                end
            end
        end

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
            [~, uniqueIdx] = unique(headers);

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

        function ValidateInstall(Settings)
            arguments
                Settings.MatlabVersion = "R2025b";
                Settings.ToolboxNames = {"Instrument Control Toolbox"};
            end

            try
                %Make sure user has the required matlab version first of all
                Palladium.Utilities.Verification.VerifyMatlabVersion(Settings.MatlabVersion);
            catch err
                %Throw error message - note we don't have a Logger yet, and
                %need to use simpler functions
                errordlg(err.message, "Matlab version out of date! Cannot run.");
            end

            try
                %Make sure the user has the required toolboxes installed
                if ~isempty(Settings.ToolboxNames)
                    for i = 1 : length(Settings.ToolboxNames)
                        Palladium.Utilities.Verification.VerifyToolboxInstalled(Settings.ToolboxNames{i});
                    end
                end

            catch err
                %Throw error message - note we don't have a Logger yet, and
                %need to use simpler functions
                errordlg(err.message, "Required Matlab Toolbox not installed, please install Toolbox");
            end
        end

        function VerifyMatlabVersion(releaseStr)
            %Throw an error if the installed Matlab version is lower than the
            %specified release, eg "R2023b"
            if isMATLABReleaseOlderThan(releaseStr)
                error("Unsupported Matlab version, please upgrade to at least version " + releaseStr);
            end
        end
        
        function VerifyToolboxInstalled(toolboxName)
            % Find the toolbox and give proper output
            v_= ver;
            [installedToolboxes{1:length(v_)}] = deal(v_.Name);
            result = all(ismember(toolboxName,installedToolboxes));
            assert(result, "Error! " + string(toolboxName) + " is not installed");
        end       
        
    end
end

