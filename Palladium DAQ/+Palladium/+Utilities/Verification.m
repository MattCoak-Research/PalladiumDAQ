classdef Verification
    %Verification - Static functions for checks: duplicate names, and the MATLAB version and toolboxes needed.

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function [duplicates, combinedString] = CheckForDuplicatesInCellArrayOfStrings(cellArrayOfStrings)
            %Find the text that appears more than once in a cell array, e.g. repeated instrument names.
            %
            %Inputs:
            %   cellArrayOfStrings - cell array of text (char or string)
            %
            %Outputs:
            %   duplicates     - each repeated value once (string array), or [] if none
            %   combinedString - the repeated values listed for a message, e.g. "K2000_1, PPMS_1"

            duplicates = [];
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
            %Find the data column headers that appear more than once.
            %Used when measurements start (`InstrumentController.InitialiseHeaders`),
            %as every column must have its own header
            %
            %Inputs:
            %   headers - the column headers (string array or cell array)
            %
            %Outputs:
            %   duplicates     - each repeated header once, or [] if none
            %   combinedString - the repeated headers listed for a message, e.g. "Time (mins), Field (T)"

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
            %Check the MATLAB version and toolboxes Palladium DAQ needs, showing an error dialogue for any missing.
            %Called first thing by `Palladium`, before the Logger exists, so
            %problems are shown with `errordlg` rather than logged. Doesn't
            %stop start-up itself
            %
            %Inputs (name-value):
            %   MatlabVersion - the oldest release that will do. Default "R2026b"
            %   ToolboxNames  - names of the toolboxes needed, as `ver` lists them. Default {"Instrument Control Toolbox"}

            arguments
                Settings.MatlabVersion = "R2026b";
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
            %Error if this MATLAB is older than the release given, e.g. "R2026b".

            if isMATLABReleaseOlderThan(releaseStr)
                error("VerifyMatlabVersionError:UnsupportedVersion", "%s", "Unsupported Matlab version, please upgrade to at least version " + releaseStr);
            end
        end

        function VerifyToolboxInstalled(toolboxName)
            %Error if a toolbox isn't installed.
            %
            %Inputs:
            %   toolboxName - its name, as `ver` lists it, e.g. "Instrument Control Toolbox"

            v_= ver;
            [installedToolboxes{1:length(v_)}] = deal(v_.Name);
            result = all(ismember(toolboxName,installedToolboxes));
            assert(result, "VerifyToolboxError:ToolboxNotInstalled", "%s", "Error! " + string(toolboxName) + " is not installed");
        end

    end
end
