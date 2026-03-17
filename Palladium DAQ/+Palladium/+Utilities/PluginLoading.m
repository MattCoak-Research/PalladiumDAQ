classdef PluginLoading
    %PluginLoading - Static class to expose helper methods for

    methods (Static)

        %% CheckForExistingInstrName
        function existsAlready = CheckForExistingInstrName(newName, itemsData)
            %Check the list itemsData - presumed to be a list of
            %Instruments - and see if any have the Name newName
           
            %Check if the instruments array is empty, that's an easy false
            if(isempty(itemsData))
                existsAlready = false;
                return;
            end

            %Get names of existing instruments
            for n = 1 : length(itemsData)
                existingNames(n) = string(itemsData{n}.Name);
            end

            %Check for duplicate
            if(any(strcmp(existingNames, newName)))
                existsAlready = true;
                return;
            end

            %Assign output - we got to the end without returning
            existsAlready = false;
        end

        %% GetIncrementedInstrName
        function NewName = GetIncrementedInstrName(instr, itemsData)
            %Prevent duplicate instrument names by appending 1,2,3 to the end
            %of them (can always be edited by user later) on instrument
            %creation
            %Preallocate name
            NewName = instr.Name;

            %Check if the instruments array is empty, just append 1 if so
            if(isempty(itemsData))
                NewName = NewName + "_1";
                return;
            end

            %Get names of existing instruments
            for n = 1 : length(itemsData)
                existingNames(n) = string(itemsData{n}.Name);
            end

            %Initialise some variables
            i = 1;
            tmpName = NewName + "_" + num2str(i);

            %Loop while we have duplicates, incrementing the number each
            %time, until name+i is not an existing name
            while(any(strcmp(existingNames, tmpName)))
                i = i + 1;
                tmpName = NewName + "_" + num2str(i);
            end

            %Assign output
            NewName = tmpName;
        end

        %% InstantiateClass
        function classInstance = InstantiateClass(namespace, className)
            %Instantiate an isntance of the named class (empty constructor)

            if(isempty(namespace))
                classPath = className;
            else
                classPath = namespace + "." + className;
            end

            fnHandle = str2func(classPath);
            classInstance = fnHandle();
        end

        %% InstantiateEnum
        function classInstance = InstantiateEnum(namespace, className, enumValueString)
            %Instantiate an isntance of the named enum

            if(isempty(namespace))
                classPath = className;
            else
                classPath = namespace + "." + className;
            end

            fnHandle = str2func(classPath);
            classInstance = fnHandle(enumValueString);
        end

        %% InstantiatePreset
        function presetFn = InstantiatePreset(namespace, presetName)
            %Instantiate an isntance of the named Preset (matlab function file, not a class)

            if(isempty(namespace))
                presetPath = presetName;
            else
                presetPath = namespace + "." + presetName;
            end

            presetFn = str2func(presetPath);
        end

        %% LoadPluginNames
        function classNames = LoadPluginNames(directory)
            %Get the names of all the classes in a plugin directory
            classNames = dir(fullfile(directory, '*.m'));
            classNames = string({classNames.name}');
            classNames = classNames.extractBefore(".m");    %Remove the .m at the end
        end
    end
end

