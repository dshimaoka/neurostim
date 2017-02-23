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
        FRAMESLACK = 0.05; % Allow x% slack in screen flip time.
    end
    
    %% Public properties
    % These can be set in a script by a user to setup the
    % experiment
    properties (GetAccess=public, SetAccess =public)
        mirrorPixels@double   = []; % Window coordinates.[left top width height].
        
        dirs                    = struct('root','','output','','calibration','')  % Output is the directory where files will be written, root is where neurostim lives, calibration stores calibration files
        subjectNr@double        = [];
        paradigm@char           = 'test';
        clear@double            = 1;   % Clear backbuffer after each swap. double not logical
        
        keyDeviceIndex          = []; % Use the first device by default
        
        screen                  = struct('xpixels',[],'ypixels',[],'xorigin',0,'yorigin',0,...
            'width',[],'height',[],...
            'color',struct('text',[1 1 1],...
            'background',[1/3 1/3 5]),...
            'colorMode','xyL',...
            'colorCheck',false,...  % Check color validity- testing only
            'type','GENERIC',...
            'frameRate',60,'number',[],'viewDist',[],...
            'calibration',struct('gamma',2.2,'bias',nan(1,3),'min',nan(1,3),'max',nan(1,3),'gain',nan(1,3),'calFile','','cmf','T_xyz1931'));    %screen-related parameters.
        
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
        overlay =[]; % The color overlay for special colormodes (VPIXX-M16)
        stage@double;
        flags = struct('trial',true,'experiment',true,'block',true); % Flow flags
        
        frame = 0;      % Current frame
        cursorVisible = false; % Set it through c.cursor =
        
        %% Internal lists to keep track of stimuli, , and blocks.
        stimuli;    % Cell array of char with stimulus names.
        blocks@neurostim.block;     % Struct array with .nrRepeats .randomization .conditions
        blockFlow;
        plugins;    % Cell array of char with names of plugins.
        responseKeys; % Map of keys to actions.
        
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
        %         keyDeviceIndex          = []; % Use the first device by default
        keyHandlers             = {}; % Handles for the plugins that handle the keys.
        
        
        pluginOrder = {};
        EscPressedTime;
        lastFrameDrop=1;
        propsToInform={'file','paradigm','startTimeStr','blockName','nrConditions','trial/nrTrials','trial/fullNrTrials'};
        
        profile=struct('cic',struct('FRAMELOOP',[],'FLIPTIME',[],'cntr',0));
        
        guiWindow;
        
    end
    
    %% Dependent Properties
    % Calculated on the fly
    properties (Dependent)
        nrStimuli;      % The number of stimuli currently in CIC
        nrConditions;   % The number of conditions in this experiment
        nrTrials;       % The number of trials in the current block
        center;         % Where is the center of the display window.
        file;           % Target file name
        fullFile;       % Target file name including path
        subject@char;   % Subject
        startTimeStr@char;  % Start time as a HH:MM:SS string
        cursor;         % Cursor 'none','arrow'; see ShowCursor
        blockName;      % Name of the current block
        defaultPluginOrder;
        trialTime;      % Time elapsed (ms) since the start of the trial
        fullNrTrials;   % Number of trials total (all blocks)
        conditionID;    % Unique id for a condition - used by adaptive
        date;           % Date of the experiment.
    end
    
    %% Public methods
    % set and get methods for dependent properties
    methods
        function v=get.fullNrTrials(c)
            v= sum([c.blocks.nrTrials]);
        end
        
        function v= get.nrStimuli(c)
            v= length(c.stimuli);
        end
        function v= get.nrTrials(c)
            if c.block
                v= c.blocks(c.block).nrTrials;
            else
                v=0;
            end
        end
        function v= get.nrConditions(c)
            v = sum([c.blocks.nrConditions]);
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
        function v=get.date(c)
            v=datestr(c.startTime,'DD mmm YYYY');
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
        
        function v = get.blockName(c)
            v = c.blocks(c.block).name;
        end
        
        function set.subject(c,value)
            if isempty(value)
                c.subjectNr =0;
            elseif ischar(value)
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
                HideCursor(c.window);
                c.cursorVisible = false;
            else
                ShowCursor(value,c.window);
                c.cursorVisible = true;
            end
        end
        
        function setupScreen(c,value)
            if isempty(c.screen.number)
                value.number = max(Screen('screens',1));
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
            if ~isequal(round(c.screen.xpixels/c.screen.ypixels,2),round(c.screen.width/c.screen.height,2))
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
            
            frInterval = Screen('GetFlipInterval',c.window)*1000;
            percError = abs(frInterval-(1000/c.screen.frameRate))/frInterval*100;
            if percError > 5
                
                
                
                
                clear all
                close all
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
            out='\n======================\n';
            for i=1:numel(c.propsToInform)
                str=strsplit(c.propsToInform{i},'/');
                for j=1:numel(str)
                    tmp = getProp(c,str{j}); % getProp allows calls like c.(stim.value)
                    if isnumeric(tmp)
                        tmp = num2str(tmp);
                    elseif islogical(tmp)
                        if (tmp);tmp = 'true';else tmp='false';end
                    end
                    if isa(tmp,'function_handle')
                        tmp = func2str(tmp);
                    end
                    tmp = tmp(:)';
                    if numel(str)>1
                        if j==1
                            out=[out c.propsToInform{i} ': ' tmp]; %#ok<AGROW>
                        else
                            out=[out '/' tmp];%#ok<AGROW>
                        end
                    else
                        out = [out c.propsToInform{i} ': ' tmp]; %#ok<AGROW>
                    end
                end
                out=[out '\n']; %#ok<AGROW>
            end
        end
    end
    
    
    methods (Access=public)
        % Constructor.
        function c= cic
            
            %Check MATLAB version. Warn if using an older version.
            ver = version('-release');
            v=regexp(ver,'(?<year>\d+)(?<release>\w)','names');
            if ~((str2double(v.year) > 2015) || (str2double(v.year) == 2015 && v.release == 'b'))
                warning(['The installed version of MATLAB (' ver ') is relatively slow. Consider updating to 2015b or later for better performance (e.g. fewer frame-drops).']);
            end
            
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
            c.addKey('ESCAPE',@keyboardResponse,'Quit');
            c.addKey('n',@keyboardResponse,'Next Trial');
            
            
            c.addProperty('trial',0); % Should be the first property added (it is used to log the others).
            c.addProperty('frameDrop',[]);
            c.addProperty('trialStartTime',[]);
            c.addProperty('trialStopTime',[]);
            c.addProperty('condition',[],'AbortSet',false);
            c.addProperty('design',[],'AbortSet',false);
            c.addProperty('block',0,'AbortSet',false);
            c.addProperty('blockTrial',0);
            c.addProperty('expScript',[]);
            c.addProperty('iti',1000,'validate',@(x) isnumeric(x) & ~isnan(x)); %inter-trial interval (ms)
            c.addProperty('trialDuration',1000,'validate',@(x) isnumeric(x) & ~isnan(x)); % duration (ms)
            
            % Generate default output files
            neurostim.plugins.output(c);
            
        end
        
        function addPropsToInform(c,props)
            if ischar(props)
                props = {props};
            end
            c.propsToInform = cat(2,c.propsToInform,props);
        end
        
        function showDesign(c,factors)
            if nargin<2
                factors = [];
            end
            for b=1:numel(c.blocks)
                blockStr = ['Block: ' num2str(b) '(' c.blocks(b).name ')'];
                for d=1:numel(c.blocks(b).designs)
                    show(c.blocks(b).designs(d),factors,blockStr);
                end
            end
        end
        
        function write(c,label,value)
            if ~isfield(c.prms,label)
                c.addProperty(label,value);
            else
                c.(label) = value;
            end
        end
        function versionTracker(c,silent,push) %#ok<INUSD>
            % Git Tracking Interface
            %
            % The idea:
            % A laboratory forks the GitHub repo to add their own experiments
            % in the experiments folder.  These additions are only tracked in the
            % forked repo, so the central code maintainer does not have to be bothered
            % by it. The new laboratory can still contribute to the core code, by
            % making changes and then sending pull requests.
            %
            % The goal of the gitTracker is to log the state of the entire repo
            % for a particular laboratory at the time an experiment is run. It checks
            % whether there are any uncommitted changes, and asks/forces them to be
            % committed before the experiment runs. The hash corresponding to the final
            % commit is stored in the data file such that the complete code state can
            % easily be reproduced later.
            %
            % BK  - Apr 2016
            if nargin<3
                push =false;
                if nargin <2
                    silent = false;
                end
            end
            
            if ~exist('git.m','file')
                error('The gitTracker class depends on a wrapper for git that you can get from github.com/manur/MATLAB-git');
            end
            
            [status] = system('git --version');
            if status~=0
                error('versionTracker requires git. Please install it first.');
            end
            
            [txt] = git('status --porcelain');
            changes = regexp([txt 10],'[ \t]*[\w!?]{1,2}[ \t]+(?<mods>[\w\d /\\\.\+]+)[ \t]*\n','names');
            nrMods= numel(changes);
            if nrMods>0
                disp([num2str(nrMods) ' files have changed (or need to be added). These have to be committed before running this experiment']);
                changes.mods;
                if silent
                    msg = ['Silent commit  (' getenv('USER') ' before experiment ' datestr(now,'yyyy/mm/dd HH:MM:SS')];
                else
                    msg = input('Code has changed. Please provide a commit message','s');
                end
                [txt,status]=  git(['commit -a -m ''' msg ' ('  getenv('USER') ' ) ''']);
                if status >0
                    disp(txt);
                    error('File commit failed.');
                end
            end
            
            %% now read the commit id
            txt = git('show -s');
            hash = regexp(txt,'commit (?<id>[\w]+)\n','names');
            c.addProperty('githash',hash.id);
            [~,ptb] =PsychtoolboxVersion;
            c.addProperty('PTBVersion',ptb);
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
                plg = neurostim.plugins.eScript(c);
                
            end
            plg.addScript(when,fun,keys);
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
                    %This used to contain code for handling actions from
                    %addResponse() - no longer used I believe.
            end
        end
        
        function [x,y,buttons] = getMouse(c)
            [x,y,buttons] = GetMouse(c.window);
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
                        a{j} = varargin{j}.name; %#ok<AGROW>
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
                if isa(thisPlg,horzcat('neurostim.plugins.',lower(classType)));
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
        
        function endTrial(c)
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
                    c.profile.(o.name)=struct('BEFORETRIAL',[],'AFTERTRIAL',[],'BEFOREFRAME',[],'AFTERFRAME',[],'cntr',0);
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
            if any(isblock)
                % Store the blocks
                c.blocks = [varargin{isblock}];
            else
                % No blocks specified. Create a fake block (single
                % condition; mainly for testing purposes)
                d = neurostim.design('dummy');
                d.fac1.cic.trialDuration = c.trialDuration;
                c.blocks = neurostim.block('dummy',d);
            end
            args = varargin(~isblock);
            parse(p,args{:});
            if isempty(p.Results.weights)
                c.blockFlow.weights = ones(size(c.blocks));
            else
                c.blockFlow.weights = p.Results.weights;
            end
            c.blockFlow.nrRepeats = p.Results.nrRepeats;
            c.blockFlow.randomization = p.Results.randomization;
            c.blockFlow.list = repelem((1:numel(c.blocks)),c.blockFlow.weights);
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
        function run(c,block1,varargin)
            % Run an experimental session (i.e. one or more blocks of trials);
            %
            % Inputs:
            % list of blocks, created using myBlock = block('name');
            %
            % e.g.
            %
            % c.run(myBlock1,myBlock2,'randomization','SEQUENTIAL');
            %
            % 'randomization' - 'SEQUENTIAL' or 'RANDOMWITHOUTREPLACEMENT'
            % 'nrRepeats' - number of repeats total
            % 'weights' - weighting of blocks
            
            %Check input
            if ~(exist('block1','var') && isa(block1,'neurostim.block'))
                help('neurostim/cic/run');
                error('You must supply at least one block of trials.');
            end
            
            %Log the experimental script as a string
            try
                stack = dbstack('-completenames',1);
                c.expScript = fileread(stack(1).file);
            catch
                warning(['Tried to read experimental script  (', stack(runCaller).file ' for logging, but failed']);
            end
            
            if isempty(c.subject)
                response = input('Subject code?','s');
                c.subject = response;
            end
            
            c.stage = neurostim.cic.RUNNING; % Enter RUNNING stage; property functions, validation  will now be active
            
            %% Set up order and event listeners
            c.order;
            c.createEventListeners;
            c.setupExperiment(block1,varargin{:});
            
            % %Setup PTB
            PsychImaging(c);
            c.KbQueueCreate;
            c.KbQueueStart;
            c.checkFrameRate;
            
            %% Start preparation in all plugins.
            notify(c,'BASEBEFOREEXPERIMENT');
            DrawFormattedText(c.window, 'Press any key to start...', c.center(1), 'center', c.screen.color.text);
            Screen('Flip', c.window);
            KbWait(c.keyDeviceIndex);
            
            
            % All plugins BEFOREEXPERIMENT functions have been processed,
            % store the current parameter values as the defaults.
            for a = 1:numel(c.pluginOrder)
                o = c.(c.pluginOrder{a});
                setCurrentParmsToDefault(o);
            end
            
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
                Screen('Flip',c.window);
                if waitforkey
                    KbWait(c.keyDeviceIndex,2);
                end
                c.blockTrial =0;
                while ~c.blocks(c.block).done
                    c.trial = c.trial+1;
                    
                    % Restore default values
                    for a = 1:numel(c.pluginOrder)
                        o = c.(c.pluginOrder{a});
                        setDefaultParmsToCurrent(o);
                    end
                    
                    nextTrial(c.blocks(c.block),c);% This sets up all condition dependent stimulus properties (i.e. those in the factorial definition)
                    c.blockTrial = c.blockTrial+1;  % For logging and gui only
                    beforeTrial(c);
                    notify(c,'BASEBEFORETRIAL');
                    
                    %ITI - wait
                    if c.trial>1
                        nFramesToWait = c.ms2frames(c.iti - (c.clockTime-c.trialStopTime));
                        for i=1:nFramesToWait
                            Screen('Flip',c.window,0,1);     % WaitSecs seems to desync flip intervals; Screen('Flip') keeps frame drawing loop on target.
                        end
                    end
                    
                    c.frame=0;
                    c.flags.trial = true;
                    PsychHID('KbQueueFlush');
                    c.frameStart=c.clockTime;
                    FRAMEDURATION = 1000/c.screen.frameRate;
                    while (c.flags.trial && c.flags.experiment)
                        %%  Trial runnning -
                        c.frame = c.frame+1;
                        
                        notify(c,'BASEBEFOREFRAME');
                        
                        Screen('DrawingFinished',c.window);
                        
                        notify(c,'BASEAFTERFRAME');
                        
                        c.KbQueueCheck;
                        
                        
                        startFlipTime = c.clockTime;
                        
                        % vbl: high-precision estimate of the system time (in seconds) when the actual flip has happened
                        % stimOn: An estimate of Stimulus-onset time
                        % flip: timestamp taken at the end of Flip's execution
                        % missed: indicates if the requested presentation deadline for your stimulus has
                        %           been missed. A negative value means that dead- lines have been satisfied.
                        %            Positive values indicate a
                        %            deadline-miss. (BK: we use timing
                        %            info instead)
                        % beampos: position of the monitor scanning beam when the time measurement was taken
                        [vbl,stimOn,flip] = Screen('Flip', c.window,0,1-c.clear); %#ok<ASGLU>
                        vbl =vbl*1000; %ms.
                        if c.frame > 1 && c.PROFILE
                            c.addProfile('FRAMELOOP',c.name,c.toc);
                            c.tic
                            c.addProfile('FLIPTIME',c.name,c.clockTime-startFlipTime);
                        end
                        
                        if c.frame == 1
                            notify(c,'FIRSTFRAME');
                            c.trialStartTime = stimOn*1000; % for trialDuration check
                            c.flipTime=0;
                        end
                        
                        
                        if c.guiOn
                            if mod(c.frame,c.guiFlipEvery)==0
                                Screen('Flip',c.guiWindow,0,[],2);
                            end
                        end
                        
                        
                        %% Check Timing
                        % Delta between actual and deadline of flip;
                        deltaFlip       = (vbl-c.frameDeadline) ;
                        missed          = c.frame>1 && abs(deltaFlip) > c.FRAMESLACK*FRAMEDURATION;
                        c.frameStart    = vbl; % Not logged, but used to check drops/jumps
                        c.frameDeadline = vbl+FRAMEDURATION;
                        
                        if missed
                            c.frameDrop = [c.frame deltaFlip];
                            if c.guiOn
                                c.writeToFeed(['Missed Frame ' num2str(c.frame) ' \Delta: ' num2str(deltaFlip)]);
                            end
                        end
                        
                        if c.getFlipTime
                            c.flipTime = stimOn*1000-c.trialStartTime;% Used by stimuli to log their onset
                            c.getFlipTime=false;
                        end
                        
                        %% Check for end of trial
                        if c.frame-1 >= c.ms2frames(c.trialDuration)  % if trialDuration has been reached, minus one frame for clearing screen
                            c.flags.trial=false;
                        end
                    end % Trial running
                    
                    if ~c.flags.experiment || ~ c.flags.block ;break;end
                    
                    [~,stimOn]=Screen('Flip', c.window,0,1-c.clear);
                    c.trialStopTime = stimOn*1000;
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
                Screen('Flip',c.window);
                if waitforkey
                    KbWait(c.keyDeviceIndex,2);
                end
            end %blocks
            c.trialStopTime = c.clockTime;
            c.stopTime = now;
            DrawFormattedText(c.window, 'This is the end...', 'center', 'center', c.screen.color.text);
            Screen('Flip', c.window);
            notify(c,'BASEAFTEREXPERIMENT');
            c.KbQueueStop;
            KbWait(c.keyDeviceIndex);
            Screen('CloseAll');
            if c.PROFILE; report(c);end
        end
        
        function c = nextTrial(c)
            c.trial = c.trial+1;
        end
        
        function delete(c)%#ok<INUSD>
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
        
        function [fr,rem] = ms2frames(c,ms,rounded)
            %Convert a duration in msec to frames.
            %If rounded is true, fr is an integer, with the remainder
            %(in frames) returned as rem.
            if nargin<3, rounded=true;end
            fr = ms.*c.screen.frameRate/1000;
            if rounded
                inFr = round(fr);
                rem = fr-inFr;
                fr = inFr;
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
                message=horzcat('\n',num2str(c.trial), ': ', message, '\n');
                fprintf(message);
            end
        end
        
        function collectFrameDrops(c)
            nrFramedrops= c.prms.frameDrop.cntr-1-c.lastFrameDrop;
            if nrFramedrops>=1
                percent=round(nrFramedrops/c.frame*100);
                c.writeToFeed(['Missed Frames: ' num2str(nrFramedrops) ', ' num2str(percent) '%%'])
                c.lastFrameDrop=c.lastFrameDrop+nrFramedrops;
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
            [pressed, firstPress, firstRelease, lastPress, lastRelease]= KbQueueCheck(c.keyDeviceIndex);%#ok<ASGLU>
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
            InitializeMatlabOpenGL;
            AssertOpenGL;
            
            
            c.setupScreen;
            
            PsychImaging('PrepareConfiguration');
            PsychImaging('AddTask', 'General', 'FloatingPoint32Bit');% 32 bit frame buffer values
            PsychImaging('AddTask', 'General', 'NormalizedHighresColorRange');% Unrestricted color range
            %PsychImaging('AddTask', 'General', 'UseGPGPUCompute');
            PsychImaging('AddTask', 'General', 'UseFastOffscreenWindows');
            
            
            %% Setup pipeline for use of special monitors like the ViewPixx or CRS Bits++
            switch upper(c.screen.type)
                case 'GENERIC'
                    % Generic monitor.
                case 'VPIXX-M16'
                    PsychImaging('AddTask', 'General', 'UseDataPixx');
                    PsychImaging('AddTask', 'General', 'EnableDataPixxM16OutputWithOverlay');
                    
                otherwise
                    error(['Unknown screen type : ' c.screen.type]);
            end
            
            %%  Setup color calibration
            %
            switch upper(c.screen.colorMode)
                case 'LUM'
                    % The user specifies luminance values per gun as color.
                    PsychImaging('AddTask', 'FinalFormatting', 'DisplayColorCorrection', 'SimpleGamma');
                case 'XYZ'
                    % The user specifies tristimulus values as color.
                    PsychImaging('AddTask', 'FinalFormatting', 'DisplayColorCorrection', 'SensorToPrimary');
                case 'XYL'
                    % The user specifies CIE chromaticit and luminance (xyL) as color.
                    PsychImaging('AddTask', 'FinalFormatting', 'DisplayColorCorrection', 'xyYToXYZ');
                    PsychImaging('AddTask', 'FinalFormatting', 'DisplayColorCorrection', 'SensorToPrimary');
                case 'RGB'
                    % The user specifies "raw" RGB values as color
                    PsychImaging('AddTask', 'FinalFormatting', 'DisplayColorCorrection', 'None');
                otherwise
                    error(['Unknown color mode: ' c.screen.colorMode]);
            end
            % Check color validity
            if c.screen.colorCheck
                PsychImaging('AddTask', 'FinalFormatting', 'DisplayColorCorrection', 'CheckOnly');
            end
            %% Open the window
            c.window = PsychImaging('OpenWindow',c.screen.number, c.screen.color.background,[c.screen.xorigin c.screen.yorigin c.screen.xorigin+c.screen.xpixels c.screen.yorigin+c.screen.ypixels],[],[],[],[],kPsychNeedFastOffscreenWindows);
            
            
            %% Perform initialization that requires an open window
            switch upper(c.screen.type)
                case 'GENERIC'
                    % nothing to do
                case 'VPIXX-M16'
                    c.overlay = PsychImaging('GetOverlayWindow', c.window);
                    % Screen('LoadNormalizedGammaTable', - dont do this.
                    % Instead set up your vpixx once, using
                    % BitsPlusImagingPipelineTest(screenID);
                    % BitsPlusIdentityClutTest(screenID,1); this will
                    % create correct identity cluts.
                otherwise
                    error(['Unknown screen type : ' c.screen.type]);
            end
            
            %% Add calibration to the window
            switch upper(c.screen.colorMode)
                case 'LUM'
                    % Default gamma is set to 2.2. User can change in c.screen.calibration.gamma
                    PsychColorCorrection('SetEncodingGamma', c.window, 1./c.screen.calibration.gamma);
                    if isnan(c.screen.calibration.bias)
                        % Only gamma defined
                        PsychColorCorrection('SetColorClampingRange',c.window,0,1); % In non-extended mode, luminance is between [0 1]
                    else
                        % If the user set the calibration.bias parameters then s/he wants to perform a slightly more advanced calibration
                        % out = bias + gain * ((lum-minLum)./(maxLum-minLum)) ^1./gamma )
                        % where each parameter can be specified per gun
                        % (i.e. c.calibration.bias= [ 0 0.1 0])
                        PsychColorCorrection('SetExtendedGammaParameters', c.window, c.screen.calibration.min, c.screen.calibration.max, c.screen.calibration.gain,c.screen.calibration.bias);
                        % This mode accepts luminances between min and max
                        PsychColorCorrection('SetColorClampingRange',c.window,c.screen.calibration.min,c.screen.calibration.max); %
                    end
                case {'XYZ','XYL'}
                    % Provide calibration structure
                    cal = LoadCalFile(c.screen.calibration.calFile,Inf,c.dirs.calibration); % Retrieve the latest calibration
                    if isempty(cal)
                        error(['Could not load a PTB calibration file from: ' fullfile(c.dirs.calibration,c.screen.calibration.file)]);
                    end
                    try
                        % Apply color matching functions
                        tmpCmf = load(c.screen.calibration.cmf);
                        fn = fieldnames(tmpCmf);
                        Tix = strncmpi('T_',fn,2); % Assuming the convention that the variable starting with T_ contains the CMF
                        Six = strncmpi('S_',fn,2); % Variable starting with S_ specifies the wavelengths
                        T = tmpCmf.(fn{Tix}); % CMF
                        S = tmpCmf.(fn{Six}); % Wavelength info
                        T = 683*T;
                        cal = SetSensorColorSpace(cal,T,S);                        
                        PsychColorCorrection('SetSensorToPrimary', c.window, cal);                        
                    catch
                        error(['Could not load the Color Matching Function file: ' c.screen.calibration.cmf]);
                    end
                case 'RGB'
                    % Nothing to do
                otherwise
                    error(['Unknown color mode: ' c.screen.colorMode]);                    
            end
            PsychColorCorrection('SetColorClampingRange',c.window,0,1); % Final pixel value is between [0 1]
            
            %% Perform additional setup routines
            Screen(c.window,'BlendFunction',GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            
            %% Setup the GUI.
            %
            %             if any(strcmpi(c.plugins,'gui'))%if gui is added
            %
            %                 guiScreen = setdiff(Screen('screens'),[c.screen.number 0]);
            %                 if isempty(guiScreen)
            %                     %                    error('You need two screens to show a gui...');
            %                     guiScreen = 0;
            %                     guiRect = [800 0 1600 600];
            %
            %                 else
            %                     guiRect  = Screen('GlobalRect',guiScreen);
            %                     %                 if ~isempty(.screen.xorigin)
            %                     %                     guiRect(1) =o.screen.xorigin;
            %                     %                 end
            %                     %                 if ~isempty(o.screen.yorigin)
            %                     %                     guiRect(2) =o.screen.yorigin;
            %                     %                 end
            %                     %                 if ~isempty(o.screen.xpixels)
            %                     %                     guiRect(3) =guiRect(1)+ o.screen.xpixels;
            %                     %                 end
            %                     %                 if ~isempty(o.screen.ypixels)
            %                     %                     guiRect(4) =guiRect(2)+ o.screen.ypixels;
            %                     %                 end
            %                 end
            %                 if isempty(c.mirrorPixels)
            %                     c.mirrorPixels=Screen('Rect',guiScreen);
            %                 end
            %                 c.guiWindow  = PsychImaging('OpenWindow',guiScreen,c.screen.color.background,guiRect);
            %
            %                 % TODO should this be separate for the mirrorWindow?
            %                 switch upper(c.screen.colorMode)
            %                     case 'XYL'
            %                         PsychColorCorrection('SetSensorToPrimary', c.guiWindow, cal);
            %
            %                     case 'RGB'
            %                         Screen(c.guiWindow,'BlendFunction',GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            %                 end
            %             end
            %
            
            
            
        end
        
        
        
    end
    
    
    
    methods (Static)
        function v = clockTime
            v = GetSecs*1000;
        end
    end
    
    methods
        function report(c)
            plgns = fieldnames(c.profile);
            for i=1:numel(plgns)
                figure('Name',plgns{i});
                
                items = fieldnames(c.profile.(plgns{i}));
                items(strcmpi(items,'cntr'))=[];
                nPlots = numel(items);
                nPerRow = ceil(sqrt(nPlots));
                
                for j=1:nPlots
                    subplot(nPerRow,nPerRow,j);
                    vals = c.profile.(plgns{i}).(items{j});
                    hist(vals,100);
                    xlabel 'Time (ms)'; ylabel '#'
                    title(horzcat(items{j},'; Median = ', num2str(round(nanmedian(vals),2))));
                end
            end
        end
        
        function addProfile(c,what,name,duration)
            BLOCKSIZE = 1500;
            c.profile.(name).cntr = c.profile.(name).cntr+1;
            thisCntr = c.profile.(name).cntr;
            if thisCntr > numel(c.profile.(name).(what))
                c.profile.(name).(what) = [c.profile.(name).(what) nan(1,BLOCKSIZE)];
            end
            c.profile.(name).(what)(thisCntr) =  duration;
        end
        
        function tic(c)
            c.ticTime = GetSecs*1000;
        end
        
        function elapsed = toc(c)
            elapsed = GetSecs*1000 - c.ticTime;
        end
    end
    
end