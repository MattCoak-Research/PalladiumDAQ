classdef (ConstructOnLoad) MessageEventData < event.EventData
   properties
      Message;
      Title;
   end
   
   methods
       function data = MessageEventData(message, title)
           arguments
               message {mustBeTextScalar};
               title = "";
           end
           
         data.Message = message;
         data.Title = title;
      end
   end
end
