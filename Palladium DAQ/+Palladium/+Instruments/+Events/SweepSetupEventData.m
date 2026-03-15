classdef (ConstructOnLoad) SweepSetupEventData < event.EventData
   properties
      SweepDetails;
   end
   
   methods
       function data = SweepSetupEventData(sweepDetails)
         data.SweepDetails = sweepDetails;
      end
   end
end
