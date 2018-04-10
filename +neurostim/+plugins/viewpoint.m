classdef viewpoint < neurostim.plugins.eyetracker
  % Wrapper for the Viewpoint eye tracker from Arrington Research.
  %
  % Properties:
  %
  %   getSamples - if true, stores eye position/sample validity on every frame.
  %   getEvents - if true, stores eye event data in eyeEvts.
  %   eyeEvts - saves eye tracking data in its original structure format.
  %
  %   doTrackerSetup - do setup before next trial (default: true).
  %   doDriftCorrect - do drift correction before next trial (default: false).
  %
  % Keyboard hotkeys:
  %
  %   F8  - do tracker setup/calibration before next trial
  %   F9  - do drift correction immediately (assumes a target is present
  %         at (0,0). Press the space bar to indicate correct fixation, or
  %         press Esc to abort drift correction and continue.
  %
  %   F10 - do drift correction before the next trial. (Viewpoint will draw
  %         a target).
  %
  % See also: neurostim.plugins.eyetracker
  
  % 2018-04-09 - Shaun L. Cloherty <s.cloherty@ieee.org>
    
  properties
    vp@struct;
    eye = 'LEFT'; % LEFT, RIGHT or BOTH

    valid;
        
    % default viewpoint config commands...
    %
    % maybe something like:
    % 'vpx_ConnectToViewPoint('192.168.1.2',5000)' and/or 'videoMirror H'?
    %
    % note: 'smoothingPoints = 1' uses no smoothing (that is probably what we want?)
    %       'GazeSpace_MouseAction Simulation' for debugging?
    commands = {'dataFile_includeRawData Yes','datafile_includeEvents Yes','smoothingPoints 1'};
        
    vpxFile@char = 'test.vpx';
        
    getSamples@logical = true;
    getEvents@logical = false;
  
    doTrackerSetup@logical = true; % do setup/calibration before the next trial
    doDriftCorrect@logical = false; % do drift correction before the next trial
  end
    
  properties (Dependent)
    isConnected@double;
    isRecording@logical;
  end
    
  methods % get/set methods
    function v = get.isRecording(~)
      % check if viewpoint data file is open and *not* paused
      v = vpx_GetStatus(3) && ~vpx_GetStatus(4);
    end
        
    function v = get.isConnected(~)
      % check if viewpoint is running
            
      % FIXME: see p.25 of the viewpoint toolbox documenttion. what are the possible return values...?

      v = vpx_GetStatus(1);
    end
  end
  
  methods % public methods
    function o = viewpoint(c)
      % confirm that the ViewpointToolBox is available...
      assert(exist('ViewPoint_EyeTracker_Toolbox','file') == 7, ...
                   'The Viewpoint toolbox is not available?');
            
      o = o@neurostim.plugins.eyetracker(c);
      o.addKey('F8','ViewpointSetup');
      o.addKey('F9','QuickDriftCorrect');
      o.addKey('F10','FullDriftCorrect');
            
      o.addProperty('eyeEvts',struct);
      o.addProperty('clbTargetInnerSize',[]); % inner diameter (?) of annulus
    end
        
    function beforeExperiment(o)
      if ~o.useMouse
        vpx_Initialize(); % warning should be given in vpx_Initialize
      end
            
      % initalise default Viewpoint parameters in the vp structure
      o.vp = ViewpointInitDefaults(o.cic.mainWindow);
           
      if isempty(o.backgroundColor)
        % no background colour specified... use the screen background
        o.backgroundColor = o.cic.screen.color.background;
      end

      % overide default calibration parameters
      o.vp.backgroundcolour = o.backgroundColor;
      o.vp.calibrationtargetcolour = o.clbTargetColor;
      o.vp.msgfontcolour = o.cic.screen.color.text;

      o.vp.calibrationtargetsize = 100*o.clbTargetSize./o.cic.screen.width; % percentage of screen width
      if isempty(o.clbTargetInnerSize)
        % no target inner size specified... use half the target size
        o.clbTargetInnerSize = o.clbTargetSize/2;
      end
      o.vp.calibrationtargetwidth = 100*o.clbTargetInnerSize/o.cic.screen.width;
      
      %  overide the screen number, screen width and screen height
      o.vp.ScrNum = o.cic.screen.number;
      o.vp.Pwidth = o.cic.screen.width;
      o.vp.Pheight = o.cic.screen.height;
            
      % initialise connection to viewpoint toolbox
%       if ~o.useMouse
%         vpx_Initialize(); % warning should be given in vpx_Initialize
%       end
      
      % tell Eyelink about the pixel coordinates
%     rect = Screen(o.window,'Rect');
%     Eyelink('Command', 'screen_pixel_coords = %d %d %d %d',rect(1),rect(2),rect(3)-1,rect(4)-1);

      % setup sample rate
      if ~any(o.sampleRate == [220])
        c.error('STOPEXPERIMENT','Requested sample rate is invalid.');
      end
            
      % open file to record data (will be renamed on copy?)
      [~,tmpFile] = fileparts(tempname);
      o.vpxFile = [tmpFile '.vpx'];

      vpx_SendCommandString('dataFile_UnPauseUponClose 0'); % recording is paused by default
      vpx_SendCommandString('dataFile_Pause 1');
      vpx_SendCommandString('datafile_includeEvents 1');
            
%       fname = fullfile(o.cic.fullPath,o.vpxFile);
%       vpx_SendCommandString(sprintf('dataFile_NewName "%s"',fname));
      vpx_SendCommandString(sprintf('dataFile_NewName "%s"',o.vpxFile));
            
      switch upper(o.eye)
        case 'LEFT'
          vpx_SendCommandString('dataFile_InsertString "EYE_USED 0"');
        case 'RIGHT'
          vpx_SendCommandString('dataFile_InsertString "EYE_USED 1"');
        case {'BOTH','BINOCULAR'}
          vpx_SendCommandString('dataFile_InsertString "EYE_USED 2"');
      end
            
      % send any other commands to Viewpoint
      for ii = 1:length(o.commands)
        result = vpx_SendCommandString(o.commands{ii}); % TODO: handle results
        
        if result ~=0
          writeToFeed(o,['Eyelink Command: ' o.commands{i} ' failed!']);
        end
      end
            
      % can do later ch 19.19
%       if o.keepExperimentSetup
%         restoreExperimentSetup(o);
%       else
%         viewpointSetup(o);
%       end
            
%       Eyelink('Command','add_file_preamble_text',['RECORDED BY ' o.cic.experiment]);
%       Eyelink('Command','add_file_preamble_text',['NEUROSTIM FILE ' o.cic.fullFile]);
            
%       Eyelink('Message','DISPLAY_COORDS %d %d %d %d',0, 0, o.cic.screen.xpixels,o.cic.screen.ypixels);
%       Eyelink('Message','%s',['DISPLAY_SIZE ' num2str(o.cic.screen.width) ' ' num2str(o.cic.screen.height)]);
%       Eyelink('Message','%s', ['FRAMERATE ' num2str(o.cic.screen.frameRate) ' Hz.']);
      msg = { ...
        sprintf('dataFile_InsertString "RECORDED BY %s"',o.cic.experiment);
        sprintf('dataFile_InsertString "NEUROSTIM FILE %s"',o.cic.fullFile);
        sprintf('dataFile_InsertString "DISPLAY_COORDS %d %d %d %d"',0, 0, o.cic.screen.xpixels,o.cic.screen.ypixels);
        sprintf('dataFile_InsertString "DISPLAY_SIZE %.2f %.2f"',o.cic.screen.width,o.cic.screen.height);
        sprintf('dataFile_InsertString "FRAMERATE %d Hz."',o.cic.screen.frameRate) };
      vpx_SendCommandString(strjoin(msg,';'));
    end
        
    function afterExperiment(o)
            
      vpx_SendCommandString('dataFile_Pause 1'); % stop recording
      vpx_SendCommandString('DataFile_Close'); % close data File
      
%             try  %for viewpoint just say in 'beforeexperiment' where data
%                  %should be saved
%                 writeToFeed(o,'Attempting to receive Viewpoint edf file');
%                 newFileName = [o.cic.fullFile '.edf'];
%                 status=Eyelink('ReceiveFile',o.edfFile,newFileName); %change to OUTPUT dir
%                 if status>0
%                     o.edfFile = newFileName;
%                     writeToFeed(o,['Success: transferred ' num2str(status) ' bytes']);
%                 else
%                     writeToFeed(o,['Fail: EDF file did not transfer ' num2str(status)]);
%                 end
%             catch
%                 error(horzcat('Eyelink file transfer failed. Saved on Eyelink PC as ',o.edfFile));
%             end

      vpx_Unload; % Eyelink('Shutdown');
    end
        
    function beforeTrial(o)
      %o.trackedEye; %This doesn't currently do anything for Eyelink??
      %update trial number so that correct coordinate system is used
      %in Calibration.m
      o.vp.trialnum = o.cic.trial;
            
      % Do re-calibration if requested
      if ~o.useMouse && (o.doTrackerSetup || o.doDriftCorrect)
%         if ~o.keepExperimentSetup
%           viewpointSetup(o);
%         end

        if o.doTrackerSetup
          ViewpointDoTrackerSetup(o.vp); % FIXME: need to modify to allow ns to control the background RGB/lum CIE etc.
          o.doTrackerSetup = false;
%           restoreExperimentSetup(o);
        end
        
        if o.doDriftCorrect
%           o.vp.TERMINATE_KEY = o.vp.ESC_KEY;  % quit using ESC
          ViewpointDoDriftCorrection(o.vp); % actually using slip correction ch 8.9 in User Guide
          o.doDriftCorrect = false;
%           restoreExperimentSetup(o);
        end
      end            
            
      if ~o.isRecording
        vpx_SendCommandString('dataFile_Resume'); % start recording
%         available = o.eye; % get eye that's tracked
%         if available == o.el.BINOCULAR
%           o.eye = o.el.LEFT_EYE;
%         elseif available == -1
%           o.eye = available;
%           o.eye = o.el.LEFT_EYE;
%           o.cic.error('STOPEXPERIMENT','eye not available')
%         else
%           o.eye = available;
%         end
      end
            
%       Eyelink('Command','record_status_message %s%s%s',o.cic.paradigm, '_TRIAL:',num2str(o.cic.trial));
      
%       Eyelink('Message','%s',['TR:' num2str(o.cic.trial)]); % used to align clocks later
      vpx_SendCommandString(sprintf('dataFile_InsertString "TR: %d"',o.cic.trial));

%       Eyelink('Message','TRIALID %d-%d',o.cic.condition,o.cic.trial);
      vpx_SendCommandString(sprintf('dataFile_InsertString "TRIALID %d-%d"',o.cic.condition,o.cic.trial));
                        
%       Eyelink('TrackerTime');
      o.eyeClockTime = vpx_GetDataTime(0);            
    end
        
    function afterFrame(o)
            
      if ~o.isRecording
        o.cic.error('STOPEXPERIMENT','Viewpoint is not recording...');
        return;
      end
            
      if o.getSamples
        % continuous samples requested
%         if Eyelink('NewFloatSampleAvailable') > 0
          % sample the eye position
          [xV,yV] = vpx_GetGazePoint();

%         ViewToNeuro(o,xV,yV)  
          o.x = xV;
          o.y = yV;
                    
%           sprintf('xV: %.4f yV: %.4f\n',xV,yV)
%           sprintf('xN: %.4f yN: %.4f\n',o.x,o.y)

          o.pupilSize = vpx_GetPupilSize();
          
%           o.valid = isnumeric(o.x) && isnumeric(o.y) && o.pupilSize >0; % FIXME: only if configured to measure pupil size...
          o.valid = isnumeric(o.x) && isnumeric(o.y);
%         end
      end
            
      % TODO: figure out how we should configure/handle Viewpoint events...
      if o.getEvents
        warning('Viewpoint events are not supported yet.');
%                 % only events requested
%                 switch o.isConnected
%                     case o.vp.connected
%                         evtype = Eyelink('getnextdatatype');
%                         if any(ismember(evtype, ...
%                                [o.el.ENDSACC, o.el.ENDFIX, o.el.STARTBLINK,...
%                                 o.el.ENDBLINK,o.el.STARTSACC,o.el.STARTFIX,...
%                                 o.el.FIXUPDATE, o.el.INPUTEVENT,o.el.MESSAGEEVENT,...
%                                 o.el.BUTTONEVENT, o.el.STARTPARSE, o.el.ENDPARSE]))
%                             o.eyeEvts = Eyelink('GetFloatData',evtype);
%                         else
%%                            o.cic.error('STOPEXPERIMENT','Eyelink is not connected');
%                         end
%                 end
%                 % x and y
      end
    end
        
    function keyboard(o,key,~)
      switch upper(key)
        case 'F8'
          % do tracker setup before next trial
          o.doTrackerSetup = true;
        case 'F9'
          % do drift correct right now
%           Eyelink('StopRecording');
          vpx_SendCommandString('dataFile_Pause 1');
     
          [tx,ty] = o.cic.physical2Pixel(0,0);
          draw = 0; % assume neurostim has drawn a target
          allowSetup = 0; % If it fails it fails..(we coudl be in the middle of a trial; dont want to mess up the flow)
          ViewpointDoDriftCorrect(o.vp,tx,ty,draw,allowSetup);

          Eyelink('StartRecording');
          vpx_SendCommandString('dataFile_Resume');
        case 'F10'
          % do drift correct before next trial
          o.doDriftCorrect = true;
      end
    end
        
  end % public methods
    
%   methods (Access=protected)
%     function restoreExperimentSetup(o)
%       % restores neurostim background/foreground colours
%       o.vp.backgroundcolour = o.cic.screen.color.background;
%       o.vp.foregroundcolour = o.cic.screen.color.text;
%             
% %       PsychViewpointDispatchCallback(o.vp);
%       ViewpointClearCalDisplay(o.vp);
%             
%       % TODO: see 'settingsFile_Load filename'/'settingsFile_Save filename'
%     end
%         
%     function viewpointSetup(o)
%       % sets up Viewpoint background/foreground colours
%       o.vp.backgroundcolour = o.backgroundColor;
%       o.vp.foregroundcolour = o.foregroundColor;
%  %      PsychViewpointDispatchCallback(o.vp);
%     end
% 
%     function ViewToNeuro(o,xV,yV)
%       % convert Viewpoint normalized coords to neurostim coords
% %       o.x = o.cic.screen.width*(vX-0.5);
% %       o.y =-1*o.cic.screen.height*(yV-0.5);
%       [o.x,o.y] = vp2ns(o,xV,yV);
%     end
%         
%     function [xN,yN] = vp2ns(o,xV,yV)
%       % convert Viewpoint normalized coords to neurostim coords
%       xN =    o.cic.screen.width*(xV-0.5);
%       yN = -1*o.cic.screen.height*(yV-0.5);
%     end  
%   end % protected methods
  
end % classdef