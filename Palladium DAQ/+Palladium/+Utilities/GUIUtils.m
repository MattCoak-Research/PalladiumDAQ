classdef GUIUtils
    %GUIUTILS Static methods for helping with GUI creation and functions,
    %mainly the automatic GUI for adjusting object properties

    methods (Static)

        %% ComputePropertyList
        function propertyList = ComputePropertyList(instrument, exposeSubClassProperties)
            %Handle case of empty reference
            if(isempty(instrument))
                propertyList = [];
                return;
            end

            % Returns a string array of the properties to show.
            objectClass = string(class(instrument));

            % If we're exposing subclass properties this is trivial.
            if exposeSubClassProperties
                propertyList = string.empty(0);
                metaClass = metaclass(instrument);

                for i=1:length(metaClass.PropertyList)
                    prop = metaClass.PropertyList(i);
                    % Add to the list only non-hidden publicly settable
                    % properties defined in this class. SetObservable are
                    % the proeprties we label to trigger events when they
                    % change - use that to indicate proeprties that should
                    % appear in the GUI too.
                    if( prop.SetAccess == "public" && ~prop.Hidden && prop.SetObservable)
                        if Palladium.Utilities.GUIUtils.IsPropertyValidToUse(prop.Name)
                            propertyList(end+1, 1) = prop.Name;
                        end
                    end
                end
            else
                % If we only want to expose properties defined in this
                % class, and not its subclasses, it's more complicated. We
                % can use the metaclass, but be wary of exposing private or
                % hidden properties.
                propertyList = string.empty(0);
                metaClass = metaclass(instrument);

                for i=1:length(metaClass.PropertyList)
                    prop = metaClass.PropertyList(i);
                    % Add to the list only non-hidden publicly settable
                    % properties defined in this class. SetObservable are
                    % the proeprties we label to trigger events when they
                    % change - use that to indicate proeprties that should
                    % appear in the GUI too.
                    if( prop.SetAccess == "public" && prop.DefiningClass.Name == objectClass && ~prop.Hidden && prop.SetObservable)
                        if Palladium.Utilities.GUIUtils.IsPropertyValidToUse(prop.Name)
                            propertyList(end+1, 1) = prop.Name;
                        end
                    end
                end
            end

            %Remove any properties from this list that the instrument
            %specifies, e.g. ConnectionSettings that do not apply to the
            %selected ConnectionType
            for i = length(propertyList) : -1 : 1
                if(~instrument.ShowProperty(propertyList{i}))
                    propertyList(i) = [];
                end
            end

        end

        %% IsPropertyControlSignifier
        function tf = IsPropertyValidToUse(propName)
            tf = true;
        end

        %% ToDoubleArrayFromScalarString
        function [da, conversionSuccessful] = ToDoubleArrayFromScalarString(str, delimiter)
            arguments
                str {mustBeTextScalar}
                delimiter = {' ', ','};
            end
            %Undoes the ToScalarString function below. Turns a string like
            %'200 300 400' into an array of doubles. If any element fails
            %conversion (gives NaN) the original string is returned and
            %the conversionSuccessful flag is set to false.

            conversionSuccessful = true;

            %Trim leading and trailing whitespace
            str = strtrim(str);

            %Remove any [,] bracket characters, not required
            str = replace(str, '[', '');
            str = replace(str, ']', '');

            %Split the string and convert each element to double
            da =  str2double(strsplit(str, delimiter));

            %Verify that it worked - no NaNs
            if any(isnan(da))
                da = str;
                conversionSuccessful = false;
                return;
            end
        end

        %% ToScalarString
        function str = ToScalarString(value)
            % Returns a scalar string from something which might be a char array, or a
            % numeric multi-element vector.
            str = string(value);

            if ~ismatrix(value)
                error("Value isn't a scalar or vector so it's a high-dimensional array," + ...
                    " that's probably bad news.") ;
            end

            if ~isscalar(str)
                str = join(str, " ");
            end


        end

        %% RunFunctionWithTimeOut
        function varargout = RunFunctionWithTimeOut(f, t, varargin)
            %
            % [out1, out2, ...] = timeout(f, t, arg1, arg2, ...)
            %
            % INPUTS:
            %    f    : function or function handle.
            %    t    : length of time before timeout
            %    arg1 : first input to f
            %    ...
            %    argN : Nth input to f
            %
            % OUTPUTS:
            %    out1 : first output from f
            %    ...
            %    outM : Mth output from f
            %
            % This function is used to evaluate a function but with a given time
            % constraint - will terminate and error after the given timeout to prevent the code hanging. Uses the parallel computing toolbox and is very slow, so only
            % use for things that will take a few seconds to execute


            % Check the local cluster.
            c = parcluster();
            % Create a job.
            j = batch(c, f, nargout, varargin);

            % Call the job and block input for a period.
            wait(j, 'finished', t)

            % Check for completion.
            if isempty(j.FinishTime)
                % Delete the job.
                delete(j);

                % Throw a timeout error.
                error('MATLAB:timeout', 'Evaluation timed out.');
            else
                % Get the outputs from the batch.
                r = fetchOutputs(j);
                % Delete the job now that outputs have been collected.
                delete(j);
                % Extract the outputs.
                if numel(r) < nargout
                    % Too many outputs.
                    error('MATLAB:maxlhs', 'Too many outputs.')
                else
                    % Assign first outputs.
                    varargout = r(1:nargout);
                end
            end
        end
    end
end

