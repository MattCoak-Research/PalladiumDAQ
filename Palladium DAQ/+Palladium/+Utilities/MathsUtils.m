classdef MathsUtils
    %MathsUtils - Static functions for maths and units, such as SI prefixes for plot axis labels.

    %% Methods (Static, Public)
    methods(Static, Access = public)

        function prefixStr = ConvertExponentToSIPrefix(log103Max)
            %The SI prefix for a power of ten, e.g. `k` for 3 or `$\mu$` for -6.
            %Used to label plot axes in scaled units. Micro is returned as
            %TeX (`$\mu$`), for axis labels. A power that isn't a multiple
            %of 3 between -30 and 30 gives "" and a warning
            %
            %Inputs:
            %   log103Max - the power of ten, e.g. 3 for kilo
            %
            %Outputs:
            %   prefixStr - the prefix, e.g. 'k' ('' for 0)

            switch (log103Max)
                case(-30);  prefixStr = 'q';
                case(-27);  prefixStr = 'r';
                case(-24);  prefixStr = 'y';
                case(-21);  prefixStr = 'z';
                case(-18);  prefixStr = 'a';
                case(-15);  prefixStr = 'f';
                case(-12);  prefixStr = 'p';
                case(-9);   prefixStr = 'n';
                case(-6);   prefixStr = '$\mu$';
                case(-3);   prefixStr = 'm';
                case(0);    prefixStr = '';
                case(3);    prefixStr = 'k';
                case(6);    prefixStr = 'M';
                case(9);    prefixStr = 'G';
                case(12);   prefixStr = 'T';
                case(15);   prefixStr = 'P';
                case(18);   prefixStr = 'E';
                case(21);   prefixStr = 'Z';
                case(24);   prefixStr = 'Y';
                case(27);   prefixStr = 'R';
                case(30);   prefixStr = 'Q';
                otherwise
                    prefixStr = '';
                    warning("MathsUtilsWarning:InvalidExponent", "%s", "Cannot convert value to SI prefix, value not supported: 10^" + num2str(log103Max));
            end
        end
    end
end
