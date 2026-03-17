classdef MathsUtils
    %MATHSUTILS Static methods for helping with maths or science things
        
    methods(Static)

        %% ConvertExponentToSIPrefix
        function prefixStr = ConvertExponentToSIPrefix(log103Max)
            switch (log103Max)
                case(-30)
                    prefixStr = 'q';
                case(-27)
                    prefixStr = 'r';
                case(-24)
                    prefixStr = 'y';
                case(-21)
                    prefixStr = 'z';
                case(-18)
                    prefixStr = 'a';
                case(-15)
                    prefixStr = 'f';
                case(-12)
                    prefixStr = 'p';
                case(-9)
                    prefixStr = 'n';
                case(-6)
                    prefixStr = '$\mu$';
                case(-3)
                    prefixStr = 'm';
                case(0)
                    prefixStr = '';
                case(3)
                    prefixStr = 'k';
                case(6)
                    prefixStr = 'M';
                case(9)
                    prefixStr = 'G';
                case(12)
                    prefixStr = 'T';
                case(15)
                    prefixStr = 'P';
                case(18)
                    prefixStr = 'E';
                case(21)
                    prefixStr = 'Z';
                case(24)
                    prefixStr = 'Y';
                case(27)
                    prefixStr = 'R';
                case(30)
                    prefixStr = 'Q';
                otherwise
                    prefixStr = '';
                    warning("Cannot convert value to SI prefix, value not supported: 10^" + num2str(log103Max));
            end
        end
    end
end

