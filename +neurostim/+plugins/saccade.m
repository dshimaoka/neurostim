classdef saccade < neurostim.plugins.behavior
    % saccade subclass in behaviour class. 
    % saccade(name,fixation1,fixation2)
    % Creates a saccade from fixation1 to fixation2, adjusting start and
    % end points accordingly, and also adjusts fixation2's startTime to be 
    % equal to the end of the saccade. 
    %
    properties  (Access=private)
        fix1;
        fix2;
        vector;
        allowable;
    end
    
        
    
    methods
        function o=saccade(name,varargin)
            o=o@neurostim.plugins.behavior(name);
            o.continuous = true;
            o.addProperty('startX',0);
            o.addProperty('startY',0);
            o.addProperty('endX',[5 -5]);   % end possibilities - calculated as an OR
            o.addProperty('endY',[5 5]);
            o.addProperty('minLatency',80);
            o.addProperty('maxLatency',500);
            if nargin == 3   % two fixation inputs
                o.fix1 = varargin{1};
                o.fix2 = varargin{2};
                o.listenToEvent('BEFOREEXPERIMENT');
            elseif nargin == 2
                error('Only one fixation object supplied.')
            end
        end
        
        function beforeExperiment(o,c,evt)
            o.duration = o.maxLatency;
            o.startX = o.fix1.X;
            o.startY = o.fix1.Y;
            o.endX = o.fix2.X;
            o.endY = o.fix2.Y;
            o.from = ['@(' o.fix1.name ', cic) ' o.fix1.name '.endTime - cic.trialStartTime(cic.trial)'];
%             o.from = ['@(' o.fix1.name ') 'o.fix1.name '.endTime'];
            f2name = o.fix2.name;
            c.(f2name).from = ['@(' o.name ') ' o.name '.endTime'];
        end
        
        function on = validateBehavior(o)
            % calculates the validity of a saccade. This is done through
            % creating a convex hull around the two fixation points and
            % checking whether the eye position is within these parameters.
            X = o.cic.eye.x;
            Y = o.cic.eye.y;
            for a = 1:numel(o.endX)
                xvec = [o.startX; o.endX(a)];
                yvec = [o.startY; o.endY(a)];
                if sqrt((X-o.startX)^2+(Y-o.startY)^2)<=o.tolerance && (GetSecs*1000)<=o.startTime+o.minLatency
                    % if point is within tolerance of start position
                    on = true;
                    break;
                elseif sqrt((X-o.endX(a))^2+(Y-o.endY(a))^2)<=o.tolerance && (GetSecs*1000)>=o.startTime+o.minLatency
                    % if point is within tolerance of end position
                    % after min latency has passed
                    on = true;
                    o.endTime = GetSecs*1000;
                    break;
                elseif Y>=min(yvec) && Y<=max(yvec)
                    distance = abs((yvec(2)-yvec(1))*X - (xvec(2)-xvec(1))*Y...
                        + xvec(2)*yvec(1) - yvec(2)*xvec(1))/(sqrt(yvec(2)-yvec(1))^2+(xvec(2)-xvec(1))^2);
                    on = distance<=o.tolerance;
                    if on
                        break;
                    end
                elseif X>=min(xvec) && X<=max(xvec) % else if point is within these two points
                    distance = abs((yvec(2)-yvec(1))*X - (xvec(2)-xvec(1))*Y...
                        + xvec(2)*yvec(1) - yvec(2)*xvec(1))/(sqrt(yvec(2)-yvec(1))^2+(xvec(2)-xvec(1))^2);
                    on = distance<=o.tolerance;
                    if on
                        break;
                    end
                else on=false;
                end
            end
            
        end
        
    end
    
    
    
end