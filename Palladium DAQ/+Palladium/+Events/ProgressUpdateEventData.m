classdef (ConstructOnLoad) ProgressUpdateEventData < event.EventData
   properties
      Progress;
      Message;
   end
   
   methods
       function data = ProgressUpdateEventData(progress, message)
           arguments
               progress (1,1) double;
               message {mustBeTextScalar};
           end
           
         data.Progress = progress;
         data.Message = message;
      end
   end
end
