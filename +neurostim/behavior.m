classdef (Abstract) behavior <  neurostim.plugin
    % This abstract class implements a finite state machine to
    % define behaviors. Derived classes are needed to implement specific
    % behavioral sequences. See for example behaviors.fixate or
    % behaviors.keyResponse.
    %
    % This base class only implements two states:
    % FAIL - the final state of the machine indicating that the behavioral
    %           constraints defined by the machine were not met.
    % SUCCESS - the final state of the machine indicating tha that the
    % behavioral constraints defined by the machine were met.
    %
    % Derived classes should define their states such that the machine ends
    % in either the FAIL or SUCCESS endstate.
    % To learn how to do this, look at the behaviors.fixate class which
    % implements one complete state machine for steady fixation in a trial.
    % Then look at behaviors.saccade and behaviors.fixateThenChoose to see
    % how behaviors can build on each other. In all cases, if you find
    % yourself adding many if/then constructs to see where you are in the
    % flow of the behavior, then you're probably doing something wrong and
    % should think about adding a state instead.
    %
    % Also, make sure that no state can transition into itself (that would
    % lead to an infinite recursion). 
    % 
    % Another example of inheritance is the keyResponse (single key
    % press per trial) and multiKeyResponse (multiple presses that allow a
    % subject to change their mind during the trial). This could be
    % achieved by adding various flags and if/thens in the keyResponse
    % behavior, but adding states (as in multikeyResponse) leads to cleaner
    % and less error prone code.
    %
    % For more background information on the advantages of finite state machines
    % see
    % https://en.wikipedia.org/wiki/UML_state_machine
    % https://barrgroup.com/Embedded-Systems/How-To/State-Machines-Event-Driven-Systems
    %
    % Parameters:
    % failEndsTrial  - a trial ends when the FAIL state is reached [true]
    % successEndsTrial - a trial ends when the SUCCESS state is reached  [false]
    % verbose - Write output about each state change to the command line [true]
    % stateName - the name of the current state of the machine.
    % isOn -  Logical to indicate whether the machine is currently active.
    % stopTime - the trial time when the machine reached either the FAIL or
    %                   SUCCESS state in the current trial
    % required - If this is true, then this behaviors end state is used to
    % determine the success of an entire trail (which may have other
    % behaviors too) [true]
    %
    % transitionFunction - This is a user defined function (a function_handle) that will be called with
    %                       cic as the first argument and the states as the 2nd and third (fromState,toState).
    %                       This provides some flexibility to do something in response to transitions, without
    %                       definng a new state machine). This function should not
    %                       change anything about the state (just react to the
    %                       transition). 
    % Functions to be used in experiment designs:
    %
    % startTime(o,state) - returns the time in the current trial when the
    % specified state started.
    % duration(o,state,t) - returns how long the machine has been in state s at time t
    %                       of the current trial (or the current time if t is not provide).
    %
    %
    %    
    % BK  - July 2018
    properties (SetAccess=public,GetAccess=public)
        failEndsTrial       = true;          % Does reaching the fail state end the trial?
        successEndsTrial    = false;         % Does reaching the success state end the trial?
        verbose             = true;
        required            = true;
        transitionFunction  = [];           % An optional function_handle that is called for each transition (e.g to respond to it in user code)
                                            % This function will be called
                                            % with CiC  as
                                            % the first argument, and the
                                            % from and to state names as the
                                            % second and third.
    end
    
    properties (SetAccess=protected,GetAccess=public)
        currentState; % Function handle that represents the current state.
        beforeTrialState;  % Must be non-empty
        iStartTime;  % containers.Map object to store state startTimes for quick access
        previousStateName; % Used to detect recursion.
        
    end
    properties (Dependent)
        stateName;
        isOn;
        stopTime; % time when fail or success state was reached.
        isSuccess;
        duration;
    end
    
    methods %get/set
        function v = get.isSuccess(o)
            v= strcmpi(o.stateName,'SUCCESS');
        end
        
        function v = get.isOn(o)
            t= o.cic.trialTime;
            v= t>=o.on & t < o.off;
        end
        
        
        function v=get.duration(o)
            % Duration of the current state
            v= o.cic.trialTime -startTime(o,o.stateName);
        end
        
        function v = get.stateName(o)
            v = neurostim.behavior.state2name(o.currentState);
        end
        
        function v = get.stopTime(o)
            v = min(startTime(o,'FAIL'),startTime(o,'SUCCESS')); % At least one will be inf
        end
        
        
    end
    
    
    methods (Access=public)
        function [stateName,trial,trialTime] = getStateStarts(o)
            % Loop over all states in the behavior and return a cell array 
            % of times when they started and in which trial.
            % Note that 'all states' currently means all states that did
            % occur at least once (states that were never visited are not
            % included).
            % OUTPUT
            % stateName = cell array of state names
            % trial  = cell array of vectors of trials
            % trialTime = cell array of vectors of time in the trial
            % (relative to first frame).
            
            [data,tr,trTime] = get(o.prms.state);            
            out  = cellfun(@isempty,data);
            data(out) = [];
            tr(out)=[];
            trTime(out)=[];
            
            [stateName,~,ix] = unique(data);            
            nrStates = numel(stateName);            
            trialTime = cell(1,nrStates);
            trial = cell(1,nrStates);
            for i=1:nrStates
                stay = ix==i;
                trialTime{i} = trTime(stay);
                trial{i} = tr(stay);
            end                                    
        end
        
        function [trialTime,time,block,frame] =  find(o,state,n,firstLast)
            % In each trial, find up to n time points when the behavior
            % reached the specified state.
            % The function returns a matrix [nrTrials n] with
            % Nans for trials wher the state was never reached.
            % INPUT
            % o = a neurostim.behavior
            % state = The state as a char (e.g. 'FIXATION')
            % n =  The maximum number of state starts to look for.
            %           (Defaults to 1) 
            % firstLast = Whether to look for the 'first' n or the 'last' n. 
            %           Defaults to 'first'.
            %
            % OUTPUT
            % trialTime = time relative to firstframe in the trial
            % time = time relative to start of the experiment
            % block = block in which the event occurred  (one column only)
            % frame = frame at which the event occurred                           
            [data,trial,trTime,expTime,blk,frm] = get(o.prms.state);            
            if nargin<4
                firstLast = 'first';
                if nargin < 3
                    n =1;
                end
            end
            maxTrial = o.cic.prms.trial.cntr-1; % trial 0 is logged as well, so -1
            trialTime = nan(maxTrial,n);
            time = nan(maxTrial,n);   
            block = nan(maxTrial,1);   
            frame = nan(maxTrial,n);
            for tr =1:maxTrial
                ix = find(strcmpi(data,state) & trial==tr,n,firstLast);
                nrThis = numel(ix);
                if nrThis>0
                    trialTime(tr,1:nrThis) = trTime(ix);
                    time(tr,1:nrThis) = expTime(ix);
                    frame(tr,1:nrThis) = frm(ix);
                    block(tr) = blk(ix(1));
                end                    
            end                
        end
        
        % Users should add functionality by defining new states, or
        % if a different response modailty (touchbar, keypress, eye) is
        % needed, by overloading the getEvent function.
        % When overloading the regular plugin functions beforeXXX/afterXXX,
        % make sure to also call the functions defined here.
        
        function beforeExperiment(o)
            assert(~isempty(o.beforeTrialState),['Behavior ' o.name '''s beforeTrialState has not been defined']);
        end
        
        
        function beforeTrial(o)
            % Reset the internal record of state start times
            o.iStartTime = containers.Map('keyType','char','ValueType','double');
            transition(o,o.beforeTrialState,neurostim.event(neurostim.event.NOOP));
        end
        
        function afterTrial(o)
            % Send an afterTrial  event
            o.currentState(o.cic.trialTime,neurostim.event(neurostim.event.AFTERTRIAL))
        end
        function beforeFrame(o)
            % Not using cic.trialTime or o.isOn here to squeeze the last
            % microseconds out of the code.
            t = (o.cic.frame-1)*1000/o.cic.screen.frameRate;            
            if t>o.on && t < o.off
                e= getEvent(o);% Get current events
                if e.isRegular
                    % Only regular events are sent out by this dispatcher,
                    % ENTRY/EXIT events are generated and dispatched by
                    % transition, and NOOP events are ignored.
                    % Derived classes can use NOOP events to indicate they
                    % should not be distributed to states (i.e. a no-op
                    % instruction).
                    o.currentState(t,e);  % Each state is a member function- just pass the event
                end
            end
        end
        
        
        
        
        % Constructor. In the non-abstract derived clases, the user must
        % set currentState to an existing state.
        function o = behavior(c,name)
            o = o@neurostim.plugin(c,name);
            o.addProperty('on',0,'validate',@isnumeric);
            o.addProperty('off',Inf,'validate',@isnumeric);
            o.addProperty('from',0,'validate',@isnumeric);
            o.addProperty('to',Inf,'validate',@isnumeric);
            o.addProperty('state','','validate',@ischar);
            o.addProperty('event',neurostim.event(neurostim.event.NOOP));
            o.feedStyle = 'blue';
            o.iStartTime = containers.Map('keyType','char','ValueType','double');
        end
        
        % This function must return a neurostim.event, typically of the
        % REGULAR type, although derived classes can use the NOOP type to
        % indicate that the event should not be sent to the states.
        function e = getEvent(~)
            % The base-class does not generate any specific events.
            e = neurostim.event(neurostim.event.NOOP);
            % For testing purposes this could be commented out
            % [e.X,e.Y,e.key] = GetMouse;
        end
        
    end
    
    methods (Sealed)
        % To avoid the temptation to overload these member functions, they
        % sealed,.
        function transition(o,futureState,e)
            % state = the state to transition into
            % e = the event that triggered this transition. This event is
            % sent to the old and new state as an entry/exit signal to
            % allow teardown/setup code to use the information in the
            % event.
            
            o.event = e; % Log the event driving the transition.
           
            
            
            currentStateName = neurostim.behavior.state2name(o.currentState);
            futureStateName =  neurostim.behavior.state2name(futureState);
            
            if ~isempty(o.previousStateName) && strcmpi(o.previousStateName,currentStateName)
                % The previous transition tried to get out of the same
                % state...that means the machince has a A->A
                % transition (which is not allowed and leads to recursion).
                o.cic.error('STOPEXPERIMENT',['State ' currentStateName ' calls itself recursiuvely... that cannot end well!']);
                keyboard; % Stop the recursion.
                % If you got to this piece of code, you probably created
                % a state machine in which a state transitions into itself.
                % One way in which this can happen is if the EXIT event is
                % treated as a normal event. So check that your code that 
                % implements transitions does not handle the .ENTRY or
                % .EXIT events. Maybe use if ~e.isRegular;return;end at the
                % start of each state to simply ignore entry/exit events. 
            else
                o.previousStateName = currentStateName;
            end
            
            %Tear down old state (send EXIT event)
            if ~isempty(currentStateName)
                e.type = neurostim.event.EXIT; % Change the type
                o.currentState(0,e); % Send the EXIT signal
            end
                        
            % Setup new state  (send ENTRY event)
            e.type = neurostim.event.ENTRY;
            futureState([],e); % Send the ENTRY signal to the new state.
            
            if ~isempty(o.transitionFunction)
                % Call a user defined function  (provides some flexibility
                % to do something in response to transitions, without
                % definng a new state machine). This function should not
                % change anything about the state (just react to the
                % transition). 
                o.transitionFunction(o.cic,currentStateName,futureStateName);
            end
            % Switch to new state and log the new name
            o.currentState = futureState; % Change the state           
            o.state = futureStateName; % Log time/state transition
            o.iStartTime(futureStateName) = o.cic.trialTime;
            
            if o.verbose
                o.writeToFeed(['Transition to ' o.state]);
            end
        end
        
        
        
        
    end
    
    %% States
    % These two generic states should be the endpoint for every derived
    % class. success or fail.
    methods
        function fail(o,~,e)
            % This state responds to the entry signal to end the trial (if
            % requested)
            if e.isEntry && o.failEndsTrial
                o.cic.endTrial();
            end
        end
        
        function success(o,~,e)
            % This state responds to the entry signal to end the trial (if
            % requested)
            if e.isEntry && o.successEndsTrial
                o.cic.endTrial();
            end
        end
        
    end
    
    %% Helper functions
    methods
        
        
        
        function v = startTime(o,s)
            s = upper(s);
            if isKey(o.iStartTime,s)
                % This state's startTime was logged
                v = o.iStartTime(s);
            else
                v= Inf;
            end
        end
    end
    
    methods (Static)
        
        function v= state2name(st)
            pattern = '@\(varargin\)o\.(?<name>[\w\d]+)\(varargin{:}\)'; % This is what a state function looks like when using func2str : @(varargin)o.freeViewing(varargin{:})
            if isempty(st)
                v= '';
            else
                match = regexp(func2str(st),pattern,'names');
                if isempty(match)
                    error('State name extraction failed');
                else
                    v= upper(match.name);
                end
            end
        end
    end
    
end