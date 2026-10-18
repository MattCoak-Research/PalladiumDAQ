function varargout = ziDAQ(varargin)
%ziDAQ - Fake of the LabOne MATLAB API's ziDAQ, for testing the ZI_MFLI driver without the API or an instrument.
%Put this folder first on the path (a PathFixture) to use it instead of
%the real one. Records every call, and answers getDouble/getInt with set
%replies (0 otherwise). Modules ('sweep', 'scopeModule',
%'dataAcquisitionModule') return a placeholder handle. Controlled by:
%   ziDAQ("fake_reset")                - forget the calls and replies
%   calls = ziDAQ("fake_calls")        - every call so far, as a cell array of argument cell arrays
%   ziDAQ("fake_reply", path, value)   - getDouble/getInt of path (e.g. '/dev1234/sigouts/0/offset') returns value

    %(A Map with no entries counts as empty, so check initialised, not replies)
    persistent calls replies initialised
    if isempty(initialised)
        initialised = true;
        calls = {};
        replies = containers.Map("KeyType", "char", "ValueType", "any");
    end

    command = string(varargin{1});
    switch command
        case "fake_reset"
            calls = {};
            replies = containers.Map("KeyType", "char", "ValueType", "any");
            return;
        case "fake_calls"
            varargout{1} = calls;
            return;
        case "fake_reply"
            replies(char(varargin{2})) = varargin{3};
            return;
    end

    calls{end+1} = varargin;
    switch command
        case {"getDouble", "getInt"}
            path = char(varargin{2});
            if isKey(replies, path)
                varargout{1} = replies(path);
            else
                varargout{1} = 0;
            end
        case {"sweep", "scopeModule", "dataAcquisitionModule"}
            varargout{1} = "fake_module";
        otherwise
            if nargout > 0
                varargout{1} = [];
            end
    end
end
