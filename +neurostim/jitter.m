classdef jitter < neurostim.adaptive
    properties
        value;
        parms;
        distribution;
        bounds;
        size;
        
    end
    
    methods
        function o=jitter(c,parms,varargin)
           %jitter(c,parms,varargin)
            %
            %Randomize a property value from trial-to-trial.
            %A value is drawn from a specified probability distribution at
            %the start of each trial. Default: uniform distribution with
            %lower and upper bounds as parms(1) and parms(2).
            %
            %The work is done by Matlab's random/cdf/icdf functions and all
            %distributions supported therein are available.
            %
            %Required arguments:
            %'parms'             - parameters for the N-parameter pdf, as an N-length cell array (see RANDOM)
            %
            %Optional param/value pairs:
            %'distribution'     - the name of a built-in pdf [default = 'uniform'], or a handle to a custom function, f(parms) (all parameters except 'parms' are ignored for custom functions)
            %'bounds'           - 2-element vector specifying lower and upper bounds to truncate the distribution (default = [], i.e., unbounded). Bounds cannot be Inf.
            %'size'             - 2-element vector, [m,n], specifying the size of the output (i.e. number of samples). Behaves as for "sz" in Matlab's ones() and zeros()
            %
            %Examples:
            %               1) Randomize between -5 and 5.
            %                  jitter(c,{-5,5});
            %
            %               2) Draw from Gaussian with [mean,sd] = [0,4], but accept only values within +/- 5 (i.e., truncated Gaussian)
            %                  jitter(c,{0,4},'distribution','normal','bounds',[-5 5]);
            %
            %   See also RANDOM.
            
            p = inputParser;
            p.addRequired('parms',@(x) iscell(x));
            p.addParameter('distribution','uniform');
            p.addParameter('bounds',[], @(x) isempty(x) || (numel(x)==2 && ~any(isinf(x)) && diff(x) > 0));
            p.addParameter('size',1);
            p.parse(parms,varargin{:});
            
            o=o@neurostim.adaptive(c,'@0'); % The result fun is not used so just put something that evals to 0 always.
            o.parms = p.Results.parms;
            o.distribution = p.Results.distribution;
            o.bounds = p.Results.bounds;
            o.size = p.Results.size;
            update(o); % Call it once now to initialize.
        end
        
        function update(o,~)
            % This is called after each trial. Update the internal value            
                if isa(o.distribution,'function_handle')
                    %User-defined function. Call it.
                    o.value = o.distribution(o.parms{:});
                else
                    %Name of a standard distribution (i.e. known to Matlab's random,cdf,etc.)
                    if isempty(o.bounds)
                        %Sample from specified distribution (unbounded)
                        if ~iscell(o.size)
                            sz = num2cell(o.size);
                        else
                            sz = o.size;
                        end                        
                        o.value = random(o.distribution,o.parms{:},sz{:});
                    else
                        %Sample within the bounds via the (inverse) cumulative distribution
                        %Find range on Y
                        ybounds = cdf(o.distribution,o.bounds,o.parms{:});                        
                        %Return the samples
                        o.value = icdf(o.distribution,ybounds(1)+diff(ybounds)*rand(o.size),o.parms{:});
                    end
                end            
        end
        
        function v =getValue(o)
            % Just return the currently stored value.
            v=o.value;
        end
    end
    
end