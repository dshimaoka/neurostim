% Command and Intelligence Center for Neurostim using PsychToolBox.
% See demos directory for examples
%  BK, AM, TK, 2015


classdef cic < neurostim.plugin
    %% Events
    % All communication with plugins is through events. CIC generates events
    % to notify plugins (which includes stimuli) about the current stage of
    % the experiment. Plugins tell CIC that they want to listen to a subset
    % of all events (plugin.listenToEvent()), and plugins have the code to
    % respond to the events (plugin.events()).
    % Note that plugins are completely free to do what they want in the
    % event handlers. For stimuli, however, each event is first processed
    % by the base @stimulus class and only then passed to the derived
    % class. This helps neurostim to generate consistent behavior.
    events
        
        %% Experiment Flow
        % Events to which the @stimulus class responds (internal)
        BASEBEFOREEXPERIMENT;
        BASEAFTEREXPERIMENT;
        BASEBEFORETRIAL;
        BASEAFTERTRIAL;
        BASEBEFOREFRAME;
        BASEAFTERFRAME;
        
    
        FIRSTFRAME;       
        GIVEREWARD;
        
    end
    
    %% Constants
    properties (Constant)
        PROFILE@logical = false; % Using a const to allow JIT to compile away profiler code
        SETUP   = 0;
        RUNNING = 1;
        POST    = 2;       
    end
    
    %% Public properties
    % These can be set in a script by a user to setup the
    % experiment
    properties (GetAccess=public, SetAccess =public)
        mirrorPixels@double   = []; % Window coordinates.[left top width height].
        
        dirs                    = struct('root','',... 
                                         'output','')  % Output is the directory where files will be written
        subjectNr@double        = [];
        paradigm@char           = 'test';
        clear@double            = 1;   % Clear backbuffer after each swap. double not logical
        
        screen                  = struct('xpixels',[],'ypixels',[],'xorigin',0,'yorigin',0,...
            'width',[],'height',[],...
            'color',struct('text',[1/3 1/3 50],...
            'background',[1/3 1/3 5]),...
            'colorMode','xyL',...
            'frameRate',60,'number',[]);    %screen-related parameters.
        
        flipTime;   % storing the frame flip time.
        getFlipTime@logical = false; %flag to notify whether to get the frame flip time.
        requiredSlack = 0;  % required slack time in frame loop (stops all plugins after this time has passed)
        
        guiFlipEvery=[]; % if gui is on, and there are different framerates: set to 2+
        guiOn@logical=false; %flag. Is GUI on?
        mirror =[]; % The experimenters copy        
        ticTime = -Inf;
    end
    
    %% Protected properties.
    % These are set internally
    properties (GetAccess=public, SetAccess =protected)
        %% Program Flow
        window =[]; % The PTB window
        onscreenWindow=[]; % The display/onscreen window
        
        stage@double;
        flags = struct('trial',true,'experiment',true,'block',true); % Flow flags
        
        frame = 0;      % Current frame
        cursorVisible = false; % Set it through c.cursor =
     
        %% Internal lists to keep track of stimuli, , and blocks.
        stimuli;    % Cell array of char with stimulus names.        
        blocks@neurostim.block;     % Struct array with .nrRepeats .randomization .conditions
        blockFlow;
        plugins;    % Cell array of char with names of plugins.
        responseKeys; % Map of keys to actions.(See addResponse)
        
        %% Logging and Saving
        startTime@double    = 0; % The time when the experiment started running
        stopTime = [];
        frameStart = 0;
        frameDeadline;
        %data@sib;
        
        %% Profiling information.
        
        %% Keyboard interaction
        allKeyStrokes          = []; % PTB numbers for each key that is handled.
        allKeyHelp             = {}; % Help info for key
        keyDeviceIndex          = []; % Use the first device by default
        keyHandlers             = {}; % Handles for the plugins that handle the keys.
        
        
        pluginOrder = {};
        EscPressedTime;      
        lastFrameDrop=1;
        propsToInform={'file','paradigm','startTimeStr'};%TODO,'currentBlock/Name','nrConditions','condition','trial','blockTrial/nrTrials','trial/fullNrTrials'};
        
        profile=struct('cic',struct('FRAMELOOP',[]));
 
        guiWindow;
    
    end
    
    %% Dependent Properties
    % Calculated on the fly
    properties (Dependent)
        nrStimuli;      % The number of stimuli currently in CIC
        nrConditions;   % The number of conditions in this experiment
        nrTrials;       % The number of trials in this experiment
        center;         % Where is the center of the display window.
        file;           % Target file name
        fullFile;       % Target file name including path
        subject@char;   % Subject
        startTimeStr@char;  % Start time as a HH:MM:SS string
        cursor;         % Cursor 'none','arrow'; see ShowCursor
        conditionName;  % The name of the current condition.
        blockName;      % Name of the current block
        defaultPluginOrder;
        trialTime;       % Time elapsed (ms) since the start of the trial
        fullNrTrials;   % Number of trials total (all blocks)
        
    end
    
    %% Public methods
    % set and get methods for dependent properties
    methods
        function v=get.fullNrTrials(c)
            v= sum(c.blocks.nrTrials);
        end
        
        function v= get.nrStimuli(c)
            v= length(c.stimuli);
        end
        function v= get.nrTrials(c)
            v= c.blocks(c.block).nrTrials;         
        end
        function v= get.nrConditions(c)
            v = sum(c.blocks.nrConditions);
        end
        function v = get.center(c)
            [x,y] = RectCenter([0 0 c.screen.xpixels c.screen.ypixels]);
            v=[x y];
        end
        function v= get.startTimeStr(c)
            v = datestr(c.startTime,'HH:MM:SS');
        end
        function v = get.file(c)
            v = [c.subject '.' c.paradigm '.' datestr(c.startTime,'HHMMSS') ];
        end
        function v = get.fullFile(c)
            v = fullfile(c.dirs.output,datestr(c.startTime,'YYYY/mm/DD'),c.file);
        end
        function v=get.subject(c)
            if length(c.subjectNr)>1
                % Initials stored as ASCII codes
                v = char(c.subjectNr);
            else
                % True subject numbers
                v= num2str(c.subjectNr);
            end
        end
        
        function v = get.conditionName(c)
            v = c.blocks(c.block).conditionName;
        end
        
        function v = get.blockName(c)
            v = c.blocks(c.block).name;
        end
        
        function set.subject(c,value)           
            if ischar(value)
                asDouble = str2double(value);          
                if isnan(asDouble)                     
                    % Someone using initials 
                    c.subjectNr = double(value);
                else
                    c.subjectNr = asDouble;
                end
            else
                c.subjectNr = value;
            end
        end
        
        % Allow thngs like c.('lldots.X')
        function v = getProp(c,prop)
            ix = strfind(prop,'.');
            if isempty(ix)
                v =c.(prop);
            else
                o= getProp(c,prop(1:ix-1));
                v= o.(prop(ix+1:end));
            end
        end
        
        
        function set.cursor(c,value)
            if ischar(value) && strcmpi(value,'none')
                value = -1;
            end
            if value==-1  % neurostim convention -1 or 'none'
                HideCursor(c.onscreenWindow);
                c.cursorVisible = false;
            else
                ShowCursor(value,c.onscreenWindow);
                c.cursorVisible = true;
            end
        end
        
        function setupScreen(c,value)
            if isempty(c.screen.number)
                value.number = max(Screen('screens'));
            end
            
            windowPixels = Screen('Rect',c.screen.number); % Full screen
            if ~isfield(c.screen,'xpixels') || isempty(c.screen.xpixels)            
                c.screen.xpixels  = windowPixels(3)-windowPixels(1); % Width in pixels
            end
            if ~isfield(c.screen,'ypixels') || isempty(c.screen.ypixels)  
                c.screen.ypixels  = windowPixels(4)-windowPixels(2); % Height in pixels
            end
            
            screenPixels = Screen('GlobalRect',c.screen.number); % Full screen
            if ~isfield(c.screen,'xorigin') || isempty(c.screen.xorigin)  
                c.screen.xorigin = screenPixels(1);
            end
            if ~isfield(c.screen,'yorigin') || isempty(c.screen.yorigin)  
                c.screen.yorigin = screenPixels(2);
            end            
            
            if ~isfield(c.screen,'width') || isempty(c.screen.width)  
                % Assuming code is in pixels
                c.screen.width = c.screen.xpixels;
            end
            if ~isfield(c.screen,'height') || isempty(c.screen.height)  
                % Assuming code is in pixels
                c.screen.height = c.screen.ypixels;
            end
            if ~isequal(c.screen.xpixels/c.screen.ypixels,c.screen.width/c.screen.height)
                warning('Physical aspect ratio and Pixel aspect ration are  not the same...');
            end
         end
        
        function v=get.defaultPluginOrder(c)
            v = [fliplr(c.stimuli) fliplr(c.plugins)];
        end
        
        function v= get.trialTime(c)
            v = (c.frame-1)*1000/c.screen.frameRate;
        end
        
    end
    
    methods (Access=private)
        function checkFrameRate(c)
            
            if isempty(c.screen.frameRate)
                error('frameRate not specified');
            end
            
            frInterval = Screen('GetFlipInterval',c.onscreenWindow)*1000;
            percError = abs(frInterval-(1000/c.screen.frameRate))/frInterval*100;
            if percError > 5
                error('Actual frame rate doesn''t match the requested rate');
            else
                c.screen.frameRate = 1000/frInterval;                
            end
            
            if ~isempty(c.pluginsByClass('gui'))
                frInterval=Screen('GetFlipInterval',c.guiWindow)*1000;
                 if isempty(c.guiFlipEvery)
                    c.guiFlipEvery=ceil(frInterval*0.95/(1000/c.screen.frameRate));
                elseif c.guiFlipEvery<ceil(frInterval*0.95/(1000/c.screen.frameRate));
                    error('GUI flip interval is too small; this will cause frame drops in experimental window.')
                end
            end
        end
        
        function createEventListeners(c)
            % creates all Event Listeners
            if isempty(c.pluginOrder)
                c.pluginOrder = c.defaultPluginOrder;
            end
            for a = 1:numel(c.pluginOrder)
                o = c.(c.pluginOrder{a});
                
                for i=1:length(o.evts)
                    if isa(o,'neurostim.plugin')
                        % base events allow housekeeping before events
                        % trigger, but giveReward and firstFrame do not require a
                        % baseEvent.
                        if strcmpi(o.evts{i},'GIVEREWARD')
                            h=@(c,evt)(o.giveReward(o.cic,evt));
                        elseif strcmpi(o.evts{i},'FIRSTFRAME')
                            h=@(c,evt)(o.firstFrame(o.cic,evt));
                        else
                            addlistener(c,['BASE' o.evts{i}],@o.baseEvents);
                            switch upper(o.evts{i})
                                case 'BEFOREEXPERIMENT'
                                    h= @(c,evt)(o.beforeExperiment(o.cic,evt));
                                case 'BEFORETRIAL'
                                    h= @(c,evt)(o.beforeTrial(o.cic,evt));
                                case 'BEFOREFRAME'
                                    h= @(c,evt)(o.beforeFrame(o.cic,evt));
                                case 'AFTERFRAME'
                                    h= @(c,evt)(o.afterFrame(o.cic,evt));
                                case 'AFTERTRIAL'
                                    h= @(c,evt)(o.afterTrial(o.cic,evt));
                                case 'AFTEREXPERIMENT'
                                    h= @(c,evt)(o.afterExperiment(o.cic,evt));
                            end
                        end
                        % Install a listener in the derived class so that it
                        % can respond to notify calls in the base class
                        addlistener(o,o.evts{i},h);
                    end
                end
            end
        end
        
        function out=collectPropMessage(c)
            out='\n';
            for i=1:numel(c.propsToInform)
                str=strsplit(c.propsToInform{i},'/');
                for j=1:numel(str)
                    tmp = getProp(c,str{j}); % getProp allows calls like c.(stim.value)
                    if isnumeric(tmp)
                        tmp = num2str(tmp);
                    elseif islogical(tmp)
                        if (tmp);tmp = 'true';else tmp='false';end
                    end
                    if numel(str)>1
                        if j==1
                            out=[out c.propsToInform{i} ': ' tmp];
                        else
                            out=[out '/' tmp];
                        end
                    else
                        out = [out c.propsToInform{i} ': ' tmp];
                    end
                end
                out=[out '\n'];
            end
        end
    end
    
    
    methods (Access=public)
        % Constructor.
        function c= cic
            c = c@neurostim.plugin([],'cic');
            % Some very basic PTB settings that are enforced for all
            KbName('UnifyKeyNames'); % Same key names across OS.
            c.cursor = 'none';
            c.stage  = neurostim.cic.SETUP;
            % Initialize empty
            c.startTime     = now;
            c.stimuli       = {};
            c.plugins       = {};
            c.cic           = c; % Need a reference to self to match plugins. This makes the use of functions much easier (see plugin.m)
           
            % The root directory is the directory that contains the
            % +neurostim folder. 
            c.dirs.root     = strrep(fileparts(mfilename('fullpath')),'+neurostim','');
            c.dirs.output   = getenv('TEMP');
            
            % Setup the keyboard handling
            c.responseKeys  = neurostim.map;
            c.allKeyStrokes = [];
            c.allKeyHelp  = {};
            % Keys handled by CIC
            c.addProperty('frameDrop',[],[],[],'private');
            c.addProperty('trialStartTime',[],[],[],'private');
            c.addProperty('trialEndTime',[],[],[],'private');
            c.addProperty('condition',[],[],[],'private');
            c.addProperty('block',0,[],[],'private');
            c.addProperty('blockTrial',0,[],[],'private');
            c.addProperty('trial',0,[],[],'private');
            c.addProperty('iti',1000,[],@double); %inter-trial interval (ms)
            c.addProperty('trialDuration',1000,[],@double); % duration (ms)
            neurostim.plugins.output(c);
            c.addKey('ESCAPE',@keyboardResponse,'Quit');
            c.addKey('n',@keyboardResponse,'Next Trial');
        end
        
        function addScript(c,when, fun,keys)
            % It may sometimes be more convenient to specify a function m-file
            % as the basic control script (rather than write a plugin that does
            % the same).
            % when = when should this script be run
            % fun = function handle to the script. The script will be called
            % with cic as its sole argument.
            if nargin <4
                keys = {};
            end
            if ismember('eScript',c.plugins)
                plg = c.eScript;
            else
                plg = neurostim.plugins.eScript;
                
            end
            plg.addScript(when,fun,keys);
            % Add or update the plugin (must call after adding script
            % so that all events are listened to
            c.add(plg);
        end
        
             
        function keyboardResponse(c,key)
            %             CIC Responses to keystrokes.
            %             q = quit experiment
            switch (key)
                case 'q'
                    c.flags.experiment = false;
                    c.flags.trial = false;
                case 'n'
                    c.flags.trial = false;
                case 'ESCAPE'
                    if c.EscPressedTime+1>GetSecs
                        c.flags.experiment = false;
                        c.flags.trial = false;
                    else
                        c.EscPressedTime=GetSecs;
                    end
                otherwise
                    % Respond to the keys added by cic.addResponse
                    actions = c.responseKeys(key);
                    if c.frame >= actions.after && c.frame <= actions.before
                        c.write(key,actions.write)
                        disp([key ':' num2str(actions.write)]);
                        if actions.nextTrial
                            c.nextTrial;
                        end
                    end
            end
        end
        
        function [x,y,buttons] = getMouse(c)
            [x,y,buttons] = GetMouse(c.onscreenWindow);
            [x,y] = c.pixel2Physical(x,y);
        end
        
        
        function glScreenSetup(c,window)
            Screen('glLoadIdentity', window);
            Screen('glTranslate', window,c.screen.xpixels/2,c.screen.ypixels/2);
            Screen('glScale', window,c.screen.xpixels/c.screen.width, -c.screen.ypixels/c.screen.height);
        end
        
        
        function restoreTextPrefs(c)
            
            defaultfont = Screen('Preference','DefaultFontName');
            defaultsize = Screen('Preference','DefaultFontSize');
            defaultstyle = Screen('Preference','DefaultFontStyle');
            Screen('TextFont', c.window, defaultfont);
            Screen('TextSize', c.window, defaultsize);
            Screen('TextStyle', c.window, defaultstyle);
            
        end
        
        

        
        
        function pluginOrder = order(c,varargin)
            % pluginOrder = c.order([plugin1] [,plugin2] [,...])
            % Returns pluginOrder when no input is given.
            % Inputs: lists name of plugins in the order they are requested
            % to be executed in.
            if isempty(c.pluginOrder)
                c.pluginOrder = c.defaultPluginOrder;
            end
            
            if nargin>1
                if iscellstr(varargin)
                    a = varargin;
                else
                    for j = 1:nargin-1
                        a{j} = varargin{j}.name;
                    end
                end                
                [~,indpos]=ismember(c.pluginOrder,a);
                reorder=c.pluginOrder(logical(indpos));
                [~,i]=sort(indpos(indpos>0));
                reorder=fliplr(reorder(i));
                neworder=cell(size(c.pluginOrder));
                neworder(~indpos)=c.pluginOrder(~indpos);
                neworder(logical(indpos))=reorder;
                c.pluginOrder=neworder;                
            end
            
            if ~strcmp(c.pluginOrder(1),'gui') && any(strcmp(c.pluginOrder,'gui'))
                c.pluginOrder = ['gui' c.pluginOrder(~strcmp(c.pluginOrder,'gui'))];
            end
            if numel(c.pluginOrder)<numel(c.defaultPluginOrder)
                b=ismember(c.defaultPluginOrder,c.pluginOrder);
                index=find(~b);
                c.pluginOrder=[c.pluginOrder(1:index-1) c.defaultPluginOrder(index) c.pluginOrder(index:end)];
            end
            pluginOrder = c.pluginOrder;
        end
        
        function plgs = pluginsByClass(c,classType)            
            %Return pointers to all active plugins of the specified class type.
            ind=1; plgs = [];
            for i=1:numel(c.plugins)
                thisPlg = c.(c.plugins{i});
                if isa(thisPlg,horzcat('neurostim.plugins.',classType));
                    plgs{ind} = thisPlg;
                    ind=ind+1;
                end
            end
        end
        
        function disp(c)
            % Provide basic information about the CIC
            disp(char(['CIC. Started at ' datestr(c.startTime,'HH:MM:SS') ],...
                ['Stimuli:' num2str(c.nrStimuli) ' Conditions:' num2str(c.nrConditions) ' Trials:' num2str(c.nrTrials) ]));
        end
        
        function nextTrial(c)
            % Move to the next trial asap.
            c.flags.trial =false;
        end
        
        function o = add(c,o)
            % Add a plugin.
            if ~isa(o,'neurostim.plugin')
                error('Only plugin derived classes can be added to CIC');
            end
            
            % Add to the appropriate list
            if isa(o,'neurostim.stimulus')
                nm   = 'stimuli';
            else
                nm = 'plugins';
            end
            
            if ismember(o.name,c.(nm))
                warning(['This name (' o.name ') already exists in CIC. Updating...']);
                % Update existing
            elseif  isprop(c,o.name)
                error(['Please use a different name for your stimulus. ' o.name ' is reserved'])
            else
                h = c.addprop(o.name); % Make it a dynamic property
                c.(o.name) = o;
                h.SetObservable = false; % No events
                c.(nm) = cat(2,c.(nm),o.name);
                % Set a pointer to CIC in the plugin
                o.cic = c;
                if strcmp(nm,'plugins') && c.PROFILE
                    c.profile.(o.name)=struct('BEFORETRIAL',[],'AFTERTRIAL',[],'BEFOREFRAME',[],'AFTERFRAME',[]);
                end
            end
            
            % Call the keystroke function
            for i=1:length(o.keyStrokes)
                addKeyStroke(c,o.keyStrokes{i},o.keyHelp{i},o);
            end
            
        end
        
        
        
        %% -- Specify conditions -- %%
        function setupExperiment(c,varargin)
            % setupExperiment(c,block1,...blockEnd,'input',...)
            % Creates an experimental session
            % Inputs:
            % blocks - input blocks directly created from block('name')
            % 'randomization' - 'SEQUENTIAL' or 'RANDOMWITHOUTREPLACEMENT'
            % 'nrRepeats' - number of repeats total
            % 'weights' - weighting of blocks
            p=inputParser;
            p.addParameter('randomization','SEQUENTIAL',@(x)any(strcmpi(x,{'SEQUENTIAL','RANDOMWITHOUTREPLACEMENT'})));
            p.addParameter('nrRepeats',1,@isnumeric);
            p.addParameter('weights',[],@isnumeric);
            
            %% First create the blocks and blockFlow 
            isblock = cellfun(@(x) isa(x,'neurostim.block'),varargin);
            c.blocks = [varargin{isblock}];
            args = varargin(~isblock);
            parse(p,args{:});
           if isempty(p.Results.weights)
            c.blockFlow.weights = ones(size(c.blocks));
           else
               c.blockFlow.weights = p.Results.weights;
           end
           c.blockFlow.nrRepeats = p.Results.nrRepeats;
           c.blockFlow.randomization = p.Results.randomization;
           c.blockFlow.list =neurostim.utils.repeat((1:numel(c.blocks)),c.blockFlow.weights);
           switch(c.blockFlow.randomization)
               case 'SEQUENTIAL'
                     %c.blockFlow.list
                case 'RANDOMWITHREPLACEMENT'
                     c.blockFlow.list =Shuffle(c.blockFlow.list);
                case 'RANDOMWITHOUTREPLACEMENT'
                     c.blockFlow.list=datasample(c.blockFlow.list,numel(c.blockFlow.list));
           end
           %% Then let each block set itself up
           for blk = c.blocks
                setupExperiment(blk);
           end
        end
        
        function beforeTrial(c)
            % Assign values specified in the design to each of the stimuli.
            specs = c.blocks(c.block).condition;
            nrParms = length(specs)/3;
            for p =1:nrParms
                stimName =specs{3*(p-1)+1};
                varName = specs{3*(p-1)+2};
                value   = specs{3*(p-1)+3};
                if strcmpi(stimName,'CIC')
                    % This condition changes one of the CIC properties
                    c.(varName) = value;
                else
                    % Change a stimulus or plugin property
                    stim  = c.(stimName);
                    stim.(varName) = value;
                end
            end
            if ~c.guiOn
                message=collectPropMessage(c);
                c.writeToFeed(message);
            end
        end
        
        
        function afterTrial(c)
            c.collectFrameDrops;
        end
        
        function error(c,command,msg)
            switch (command)
                case 'STOPEXPERIMENT'
                    fprintf(2,msg);
                    fprintf(2,'\n');
                    c.flags.experiment = false;
                case 'CONTINUE'
                    fprintf(2,msg);
                    fprintf(2,'\n');
                otherwise
                    error('?');
            end
            
        end
        
        %% Main function to run an experiment. All input args are passed to
        % setupExperiment.
        function run(c,varargin)            
             if isempty(c.subject)
                response = input('Subject code?','s');                
                c.subject = response;                
            end
           
            c.stage = neurostim.cic.RUNNING; % Enter RUNNING stage; property functions, validation, and postprocessig  will now be active
                        
            %% Set up order and event listeners
            c.order;
            c.createEventListeners;
            c.setupExperiment(varargin{:});
            
            % %Setup PTB
            PsychImaging(c);
            c.KbQueueCreate;
            c.KbQueueStart;
            c.checkFrameRate;
            %% Start preparation in all plugins.
            notify(c,'BASEBEFOREEXPERIMENT');
            DrawFormattedText(c.onscreenWindow, 'Press any key to start...', c.center(1), 'center', WhiteIndex(c.onscreenWindow));
            Screen('Flip', c.onscreenWindow);
            KbWait();
            c.flags.experiment = true;
            nrBlocks = numel(c.blocks);
            for blockNr=1:nrBlocks
                c.flags.block = true;
                c.block = c.blockFlow.list(blockNr); % Logged.                
                
                waitforkey=false;
                if ~isempty(c.blocks(c.block).beforeMessage)
                    waitforkey=true;
                    DrawFormattedText(c.window,c.blocks(c.block).beforeMessage,'center','center',c.screen.color.text);
                elseif ~isempty(c.blocks(c.block).beforeFunction)
                    waitforkey=c.blocks(c.block).beforeFunction(c);
                end
                Screen('DrawTexture',c.onscreenWindow,c.window,[0 0 c.screen.xpixels c.screen.ypixels],[0 0 c.screen.xpixels c.screen.ypixels],[],0);
                Screen('Flip',c.onscreenWindow);
                if waitforkey
                    KbWait([],2);
                end
                c.blocks(c.block).trial=0;
                while c.blockTrial<numel(c.blocks(c.block).list)
                    c.trial = c.trial+1;
                    c.blocks(c.block).trial=c.blocks(c.block).trial+1;                                       
                    beforeTrial(c);
                    notify(c,'BASEBEFORETRIAL');
                    
                    %ITI - wait 
                    if c.trial>1
                        nFramesToWait = c.ms2frames(c.iti - (c.clockTime-c.trialEndTime));
                        for i=1:nFramesToWait
                            Screen('Flip',c.onscreenWindow,0,1);     % WaitSecs seems to desync flip intervals; Screen('Flip') keeps frame drawing loop on target.
                        end
                    end
                    c.frame=0;
                    c.flags.trial = true;
                    PsychHID('KbQueueFlush');
                    c.frameStart=c.clockTime;

                    while (c.flags.trial && c.flags.experiment)
                        c.frame = c.frame+1;
                        notify(c,'BASEBEFOREFRAME');
                        Screen('DrawingFinished',c.window);
                        Screen('DrawTexture',c.onscreenWindow,c.window,[0 0 c.screen.xpixels c.screen.ypixels],[0 0 c.screen.xpixels c.screen.ypixels],[],0);
                        Screen('DrawingFinished',c.onscreenWindow);
                        notify(c,'BASEAFTERFRAME');
                        c.KbQueueCheck;
                        
                        if c.frame > 1 && c.PROFILE
                            c.addProfile('FRAMELOOP',c.name,c.toc);
                        end
%                         
                        [vbl,stimOn,flip,~] = Screen('Flip', c.onscreenWindow,0,1-c.clear); %#ok<ASGLU>
                         c.tic;
                        
                        if c.frame == 1
                            notify(c,'FIRSTFRAME');
                            c.trialStartTime = stimOn*1000; % for trialDuration check
                            c.flipTime=0;
                        end
                        if c.frame>1 && ((vbl*1000-c.frameDeadline) > (0.1*(1000/c.screen.frameRate)))
                            c.frameDrop = c.frame;
                            if c.guiOn
                                c.writeToFeed('Missed Frame');
                            end
                        elseif c.getFlipTime
                            c.flipTime = stimOn*1000-c.trialStartTime;
                            c.getFlipTime=false;
                        end
                        
                        c.frameStart = vbl*1000;
                        c.frameDeadline = (vbl*1000)+(1000/c.screen.frameRate);
                        
                        if c.frame-1 >= c.ms2frames(c.trialDuration)  % if trialDuration has been reached, minus one frame for clearing screen
                            c.flags.trial=false;
                        end
                        if c.clear
                            Screen('FillRect',c.window,c.screen.color.background);
                        end
                        if c.guiOn
                            if mod(c.frame,c.guiFlipEvery)==0
                                    Screen('Flip',c.guiWindow,0,[],2);
                            end
                        end
                    end % Trial running
                    
                    if ~c.flags.experiment || ~ c.flags.block ;break;end
                    Screen('DrawTexture',c.onscreenWindow,c.window,[0 0 c.screen.xpixels c.screen.ypixels],[0 0 c.screen.xpixels c.screen.ypixels],[],0);
                    Screen('FillRect',c.window,c.screen.color.background);
                    
                    [vbl,stimOn,flip,~]=Screen('Flip', c.onscreenWindow,0,1-c.clear);%#ok<ASGLU>
                    c.trialEndTime = stimOn*1000;
                    c.frame = c.frame+1;
                    notify(c,'BASEAFTERTRIAL');
                    afterTrial(c);
                end %conditions in block
                
                if ~c.flags.experiment;break;end
                waitforkey=false;
                if ~isempty(c.blocks(blockNr).afterMessage)
                    waitforkey=true;
                    DrawFormattedText(c.window,c.blocks(blockNr).afterMessage,'center','center',c.screen.color.text);
                elseif ~isempty(c.blocks(blockNr).afterFunction)
                    waitforkey=c.blocks(blockNr).afterFunction(c);
                end
                Screen('DrawTexture',c.onscreenWindow,c.window,[0 0 c.screen.xpixels c.screen.ypixels],[0 0 c.screen.xpixels c.screen.ypixels],[],0);
                Screen('Flip',c.onscreenWindow);
                if waitforkey
                    KbWait([],2);
                end
            end %blocks
            c.trialEndTime = c.clockTime;
            c.stopTime = now;
            DrawFormattedText(c.onscreenWindow, 'This is the end...', 'center', 'center', c.screen.color.text);
            Screen('Flip', c.onscreenWindow);
            notify(c,'BASEAFTEREXPERIMENT');
            Screen('glLoadIdentity',c.window);
            c.KbQueueStop;
            KbWait;
            Screen('CloseAll');
            if c.PROFILE; report(c);end
        end
        
        function delete(c)
            %Destructor. Release all resources. Maybe more to add here?
            Screen('CloseAll');
        end
        
        %% Keyboard handling routines
        %
        function addKeyStroke(c,key,keyHelp,p)
            if ischar(key)
                key = KbName(key);
            end
            if ~isnumeric(key) || key <1 || key>256
                error('Please use KbName to add keys to keyhandlers')
            end
            if ismember(key,c.allKeyStrokes)
                error(['The ' key ' key is in use. You cannot add it again...']);
            else
                c.allKeyStrokes = cat(2,c.allKeyStrokes,key);
                c.keyHandlers{end+1}  = p;
                c.allKeyHelp{end+1} = keyHelp;
            end
        end
        
        function removeKeyStrokes(c,key)
            % removeKeyStrokes(c,key)
            % removes keys (cell array of strings) from cic. These keys are
            % no longer listened to.
            if ischar(key) || iscellstr(key)
                key = KbName(key);
            end
            if ~isnumeric(key) || any(key <1) || any(key>256)
                error('Please use KbName to add keys to keyhandlers')
            end
            if any(~ismember(key,c.allKeyStrokes))
                error(['The ' key(~ismember(key,c.allKeyStrokes)) ' key is not in use. You cannot remove it...']);
            else
                index = ismember(c.allKeyStrokes,key);
                c.allKeyStrokes(index) = [];
                c.keyHandlers(index)  = [];
                c.allKeyHelp(index) = [];
            end
        end
        
        function [a,b] = pixel2Physical(c,x,y)
            % converts from pixel dimensions to physical ones.
            a = (x./c.screen.xpixels-0.5)*c.screen.width;
            b = -(y./c.screen.ypixels-0.5)*c.screen.height;
        end
        
        function [a,b] = physical2Pixel(c,x,y)
            a = c.screen.xpixels.*(0.5+x./c.screen.width);
            b = c.screen.ypixels.*(0.5-y./c.screen.height);
        end
        
        function fr = ms2frames(c,ms,rounded)
            %Set rounded to false to get number of frames as a non-integer 
            if nargin<3
                rounded=true;
            end            
            fr = ms.*c.screen.frameRate/1000;            
            if rounded
                fr = round(fr);
            end
        end
        
        function ms = frames2ms(c,frames)
            ms = frames*(1000/c.screen.frameRate);
        end
        
        %% GUI Functions
        function writeToFeed(c,message)
            if c.guiOn
                c.gui.writeToFeed(message);
            else
                message=[num2str(c.trial) ': ' message '\n'];
                fprintf(message);
            end
        end
        
        function collectFrameDrops(c)
            framedrop=strcmpi(c.log.parms,'frameDrop');
            frames=sum(framedrop)-c.lastFrameDrop;
            if frames>=1
                percent=round(frames/c.frame*100);
                c.writeToFeed(['Missed Frames: ' num2str(frames) ', ' num2str(percent) '%%'])
                c.lastFrameDrop=c.lastFrameDrop+frames;
            end
        end
            
    end
    
    
    methods (Access=public)
        
        %% Keyboard handling routines(protected). Basically light wrappers
        % around the PTB core functions
        function KbQueueCreate(c,device)
            if nargin>1
                c.keyDeviceIndex = device;
            end
            keyList = zeros(1,256);
            keyList(c.allKeyStrokes) = 1;
            KbQueueCreate(c.keyDeviceIndex,keyList);
        end
        
        function KbQueueStart(c)
            KbQueueStart(c.keyDeviceIndex);
        end
        
        
        
    end
    
    methods (Access=private)
        
        function KbQueueStop(c)
            KbQueueStop(c.keyDeviceIndex);
        end
        
        function KbQueueCheck(c)
            [pressed, firstPress, firstRelease, lastPress, lastRelease]= KbQueueCheck(c.keyDeviceIndex);
            if pressed
                % Some key was pressed, pass it to the plugin that wants
                % it.
                %                 firstRelease(out)=[]; not using right now
                %                 lastPress(out) =[];
                %                 lastRelease(out)=[];
                ks = find(firstPress);
                for k=ks
                    ix = find(c.allKeyStrokes==k);% should be only one.
                    if length(ix) >1;error(['More than one plugin (or derived class) is listening to  ' KbName(k) '??']);end
                    % Call the keyboard member function in the relevant
                    % class
                    c.keyHandlers{ix}.keyboard(KbName(k),firstPress(k));
                end
            end
        end
        
        
        %% PTB Imaging Pipeline Setup
        function PsychImaging(c)
            AssertOpenGL;
            
            
            c.setupScreen;
            
            PsychImaging('PrepareConfiguration');
            % 32 bit frame buffer values
            PsychImaging('AddTask', 'General', 'FloatingPoint32Bit');
            % Unrestricted color range
            PsychImaging('AddTask', 'General', 'NormalizedHighresColorRange');
            
            switch upper(c.screen.colorMode)
                case 'XYL'
                    % Use builtin xyYToXYZ() plugin for xyY -> XYZ conversion:
                    PsychImaging('AddTask', 'AllViews', 'DisplayColorCorrection', 'xyYToXYZ');
                    % Use builtin SensorToPrimary() plugin:
                    PsychImaging('AddTask', 'AllViews', 'DisplayColorCorrection', 'SensorToPrimary');
                    % Check color validity
                    PsychImaging('AddTask', 'AllViews', 'DisplayColorCorrection', 'CheckOnly');
                    
                    cal = LoadCalFile('PTB3TestCal');
                    load T_xyz1931
                    T_xyz1931 = 683*T_xyz1931; %#ok<NODEF>
                    cal = SetSensorColorSpace(cal,T_xyz1931,S_xyz1931);
                    cal = SetGammaMethod(cal,0);
                    
                case 'RGB'
                    cal = []; %Placeholder. Nothing implemented.
            end
            
            
            % if bitspp
            %                PsychImaging('AddTask', 'General', 'EnableBits++Mono++OutputWithOverlay');
            PsychImaging('AddTask','General','UseFastOffscreenWindows');
            
             c.onscreenWindow = PsychImaging('OpenWindow',c.screen.number, c.screen.color.background,[c.screen.xorigin c.screen.yorigin c.screen.xorigin+c.screen.xpixels c.screen.yorigin+c.screen.ypixels],[],[],[],[],kPsychNeedFastOffscreenWindows);
            c.window=Screen('OpenOffscreenWindow',c.onscreenWindow,c.screen.color.background,[0 0 c.screen.xpixels c.screen.ypixels],[],2);
            switch upper(c.screen.colorMode)
                case 'XYL'
                    PsychColorCorrection('SetSensorToPrimary', c.onscreenWindow, cal);
                    %                     PsychColorCorrection('SetSensorToPrimary',c.mirror,cal);
                case 'RGB'
                    Screen(c.window,'BlendFunction',GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            end
            
            
            if any(strcmpi(c.plugins,'gui'))%if gui is added
                 
                guiScreen = setdiff(Screen('screens'),[c.screen.number 0]);
            if isempty(guiScreen)
%                    error('You need two screens to show a gui...');
                guiScreen = 0;
                guiRect = [800 0 1600 600];

            else
                guiRect  = Screen('GlobalRect',guiScreen);
%                 if ~isempty(.screen.xorigin)
%                     guiRect(1) =o.screen.xorigin;
%                 end
%                 if ~isempty(o.screen.yorigin)
%                     guiRect(2) =o.screen.yorigin;
%                 end
%                 if ~isempty(o.screen.xpixels)
%                     guiRect(3) =guiRect(1)+ o.screen.xpixels;
%                 end                
%                 if ~isempty(o.screen.ypixels)
%                     guiRect(4) =guiRect(2)+ o.screen.ypixels;
%                 end
            end
            if isempty(c.mirrorPixels)
                    c.mirrorPixels=Screen('Rect',guiScreen);
                end
                c.guiWindow  = PsychImaging('OpenWindow',guiScreen,c.screen.color.background,guiRect);
                    switch upper(c.screen.colorMode)
                        case 'XYL'
                            PsychColorCorrection('SetSensorToPrimary', c.guiWindow, cal);
                            %                     PsychColorCorrection('SetSensorToPrimary',c.mirror,cal);
                        case 'RGB'
                            %                         Screen(c.window,'BlendFunction',GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
                    end
                    
                    
                
            end
            
            
            
        end
        
        
        
        end
    
    
    
    methods (Static)
        function v = clockTime
            v = GetSecs*1000;
        end
    end
    
    methods
        function report(c)
            plugins = fieldnames(c.profile);
            for i=1:numel(plugins)
                figure('Name',plugins{i});
                
                items = fieldnames(c.profile.(plugins{i}));
                nPlots = numel(items);
                nPerRow = ceil(sqrt(nPlots));
                
                for j=1:nPlots
                    subplot(nPerRow,nPerRow,j)
                    hist(c.profile.(plugins{i}).(items{j}),100);
                    xlabel 'Time (ms)'; ylabel '#'
                    title(items{j});
                end
            end
        end
        
        function addProfile(c,what,name,duration)
            c.profile.(name).(what) = [c.profile.(name).(what) duration];
        end
        
        function tic(c)
            c.ticTime = GetSecs*1000;
        end
        
        function elapsed = toc(c)
            elapsed = GetSecs*1000 - c.ticTime;
        end
    end
    
end