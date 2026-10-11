classdef test_PluginLoading < matlab.unittest.TestCase
    % TEST_PLUGINLOADING Tests for Palladium utilities functions -
    % PluginLoading static class

    %% Properties
    properties
        TestingDir = fullfile("..", "data", "PluginLoading Testing");
        ItemsData;
        NamespaceName = "TestNamespace";
        EmptyNamespaceName = "EmptyTestNamespace";
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)

        function PathSetup(testCase)% Shared setup for the entire test class
            % Set up shared state for all tests.
            % Add PluginLoading Testing folder to the Path temporarily
            %Because we're using this fixture tooling, it will get
            %automatically removed on test completion
            import matlab.unittest.fixtures.PathFixture
            import matlab.unittest.constraints.ContainsSubstring
            f = testCase.applyFixture(PathFixture(testCase.TestingDir, IncludeSubfolders=true));
            testCase.verifyThat(path,ContainsSubstring(f.Folders(1)));
        end

        function ItemsDataInstrumentSetup(testCase)
            inst1 = Palladium.Instruments.Keithley2000(); inst1.Name = "Name1";
            inst2 = Palladium.Instruments.Keithley2000(); inst2.Name = "Name2";
            inst3 = Palladium.Instruments.Keithley2410(); inst3.Name = "Name3";
            testCase.ItemsData = {inst1, inst2, inst3};
        end

    end

    %% Tests
    methods (Test)

        %% CheckClassExistsInNamespace
        function test_CheckClassExistsInNamespace(testCase)
            namespaceName = testCase.NamespaceName; % Example namespace
            className = "TestClass1";   % Example class
            expectedExists = true;     % Adjust based on actual existence

            actualExists = Palladium.Utilities.PluginLoading.CheckClassExistsInNamespace(namespaceName, className);

            testCase.verifyEqual(actualExists, expectedExists);
        end

        function test_CheckClassExistsInNamespace_ClassDoesntExist(testCase)
            namespaceName = testCase.NamespaceName; 
            className = "ObviouslyWrongTestClass";   
            expectedExists = false;     

            actualExists = Palladium.Utilities.PluginLoading.CheckClassExistsInNamespace(namespaceName, className);

            testCase.verifyEqual(actualExists, expectedExists);
        end

        function test_CheckClassExistsInNamespace_EmptyNamespace(testCase)
            namespaceName = testCase.EmptyNamespaceName; 
            className = "TestClass1";  
            expectedErrorID = "CheckClassExistsInNameSpace:EmptyNamespace";

            testCase.verifyError(@() Palladium.Utilities.PluginLoading.CheckClassExistsInNamespace(namespaceName, className), expectedErrorID);
        end

        function test_CheckClassExistsInNamespace_WrongNamespace(testCase)
            namespaceName = "ObviouslyWrongNamespace"; % Example namespace
            className = "TestClass1";   % Example class
            expectedErrorID = "CheckClassExistsInNameSpace:NoSuchNamespace";

            testCase.verifyError(@() Palladium.Utilities.PluginLoading.CheckClassExistsInNamespace(namespaceName, className), expectedErrorID);
        end


        %% CheckForExistingInstrName
        function test_CheckForExistingInstrName(testCase)
            newName = 'NameNotAlreadyInList';
            itemsData = testCase.ItemsData;
            expectedExists = false;

            actualExists = Palladium.Utilities.PluginLoading.CheckForExistingInstrName(newName, itemsData);
            testCase.verifyEqual(actualExists, expectedExists);
        end

        function test_CheckForExistingInstrName_Duplicate(testCase)
            newName = 'Name2';
            itemsData = testCase.ItemsData;
            expectedExists = true;

            actualExists = Palladium.Utilities.PluginLoading.CheckForExistingInstrName(newName, itemsData);
            testCase.verifyEqual(actualExists, expectedExists);
        end

        %% CheckNamespaceExists
        function test_CheckNamespaceExists(testCase)
            %This test is covered more fully in the
            %test_CheckClassExistsInNamespace ones above, so only basic
            %check here
            namespaceName = testCase.NamespaceName;
            expectedExists = true;     % Adjust based on actual existence

            actualExists = Palladium.Utilities.PluginLoading.CheckNamespaceExists(namespaceName);

            testCase.verifyEqual(actualExists, expectedExists);
        end


        %% GetIncrementedInstrName
        function test_GetIncrementedInstrName(testCase)
            instr = struct('Name', 'Guitar');
            itemsData = {struct('Name', 'Guitar_1'), struct('Name', 'Guitar_2'), struct('Name', 'Viol_1'), struct('Name', 'Guitar')}; % Example data
            expectedNewName = "Guitar_3";

            actualNewName = Palladium.Utilities.PluginLoading.GetIncrementedInstrName(instr, itemsData);

            testCase.verifyEqual(actualNewName, expectedNewName);
        end

        function test_GetIncrementedInstrName_NoPreviousEntries(testCase)
            instr = struct('Name', 'Guitar');
            itemsData = {}; % Example data
            expectedNewName = "Guitar_1";

            actualNewName = Palladium.Utilities.PluginLoading.GetIncrementedInstrName(instr, itemsData);

            testCase.verifyEqual(actualNewName, expectedNewName);
        end


        %% InstantiateClass
        function test_InstantiateClass(testCase)
            namespace = testCase.NamespaceName;
            className = "TestClass2";
            actualInstance = Palladium.Utilities.PluginLoading.InstantiateClass(namespace, className);

            testCase.verifyInstanceOf(actualInstance, testCase.NamespaceName + ".TestClass2");
        end

        %% InstantiateEnum
        function test_InstantiateEnum(testCase)
            namespace = "Palladium.Enums";
            className = "ConnectionType";
            value = "Debug";

            actualInstance = Palladium.Utilities.PluginLoading.InstantiateEnum(namespace, className, value);

            testCase.verifyInstanceOf(actualInstance, namespace + "." + className);
        end

    end

end