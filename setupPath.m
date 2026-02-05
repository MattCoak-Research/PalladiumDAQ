function setupPath()
% Set up the MATLAB path for CoakView.

% Select which folders should be on the path.
dirNames = {'CoakView','CoakView\+CoakView\+Components\Graphics'};
for k = 1:numel(dirNames)
    addpath(genpath(dirNames{k}));
end

% Remove any folders not required to be on path.
%warning('off', 'MATLAB:rmpath:DirNotFound')
%rmpath('Test_Data')
%warning('on', 'MATLAB:rmpath:DirNotFound')

end % setupPath
