classdef rogueReward < neurostim.plugin
    properties (SetAccess = public)
        portName@char  = 'COM4';
        baudRate@double = 9600;
        newLine = 13; % CR
       
    end
    properties (SetAccess =private)
        s@serial;
    end
    
    properties (Dependent)
        settings
        isOpen
        isOK
        availableDegrees;
    end
    
    methods
        function v = get.settings(o)
            fprintf(o.s,'Read');
            response = fgetl(o.s);
            v = cellfun(@str2double,strsplit(response,'_'));
        end
        
        function v = get.isOpen(o)
            v = strcmpi(get(o.s,'Status'),'Open');
        end
        
        function v = get.isOK(o)
            if ~o.isOpen
                o.cic.error('STOPEXPERIMENT','No connection with RRR device');
                v =false;
                return;
            end
            
            % Status check
            fprintf(o.s,'RRD1');
            response = fgetl(o.s);
            v = strcmpi(response,'OK');
        end
        
        function v = get.availableDegrees(o)
            v = linspace(-90,90,o.nrPositions);
        end
        
    end
    methods
        function delete(o)
            fclose(o.s);
        end
        function o =rogueReward(c)
            o = o@neurostim.plugin(c,'rogueReward');
            o.addProperty('position',[]);
            o.addProperty('nrPositions',11);
            o.addProperty('initialPosition',5);
            o.addProperty('speed',150);                         
        end
        
        function beforeExperiment(o)
            % Check that we can find the device.
            objS  = instrfind('Port',o.portName,'Status','open');
            if ~isempty(objS)
                % Already a connected and open port.
                % Maybe this is the RRR?
                fprintf(objS,'RRD1');
                response = fgetl(objS);
                if ~strcmpi(response,'OK')
                    o.cic.error(['Port ' o.portName ' does not connect with the Rogue Rotary Reward. Use instrfind to get a list of ports in this system: ']);
                else
                    o.s = objS;
                end                
            else
                % Create a new serial object
                o.s = serial(o.portName);
                set(o.s,'BaudRate',o.baudRate,'Terminator',o.newLine);
                fopen(o.s);
            end
            
            if ~o.isOK
                o.cic.error('STOPEXPERIMENT',['Could not connect to the Rogue Rotary Reward system on port ' o.portName] );
            end
            %writeToFeed(o,sprintf('Connected to RRR with defaults: %d position, initial position %d, speed %d', o.settings));
            setup(o);
        end
        
        function afterExperiment(o)
            fclose(o);
        end
        
        function setup(o)
            if ~o.isOK
                o.cic.error('STOPEXPERIMENT','Lost connection with RRR device');
            end
            [~,newSpeedIx] = min(abs(o.speed-(50:50:400)));
            newSpeed =50+(newSpeedIx-1)*50;
            if o.speed ~=newSpeed
                writeToFeed(o,['RRR Speed should be in 50:50:400, not ' num2str(o.speed) '. Now set to ' num2str(newSpeed)]);
                o.speed = newSpeed;
            end
            if iseven(o.nrPositions)
                o.nrPositions = o.nrPositions+1;
                writeToFeed(o,['RRR number of positions set to an odd number: ' num2str(o.nrPositions)]);
            end
            
            setupString = sprintf('Setup_%d_%d_%d_1E',o.nrPositions,o.initialPosition,o.speed);
            fprintf(o.s, setupString);
            
            v =o.settings;
            requested = [o.nrPositions o.initialPosition o.speed];
            writeToFeed(o,sprintf('New RRR settings: %d positions, initial position %d, speed %d', v)); %#ok<*SPWRN>
            
            if any(v ~=requested )
                o.cic.error('STOPEXPERIMENT',['Settings (' num2str(requested) ' not accepted by RRR, which now has: ' num2str(v)]);
            end
            moveTo(o,0);
        end
        
        function reset(o)
            % This goes to position 1 at 300 RPM, and then to the initial
            % position at o.speed.
            if ~o.isOpen
                o.cic.error('STOPEXPERIMENT','Lost connection with RRR device');
            end
            fprintf(o.s, 'RST');
            if ~o.isOK
                o.cic.error('STOPEXPERIMENT','RRR Reset failed');
            end
            o.position = o.availableDegrees(o.initialPosition);
        end
        
        function moveTo(o,degrees)
            % Specify a position in degrees. 0 = straight ahead
            % find the closest one
            [delta,posNr] = min(abs(o.availableDegrees-degrees));
            if delta>0
                writeToFeed(o,sprintf('RRR cannot move to %f exactly, going to %f instead',degrees,o.availableDegrees(posNr)))
            end
            if (moveToNr(o,posNr))
                o.position = o.availableDegrees(posNr); % Log it
            else
                writeToFeed(o,sprintf('RRR could not move to %f (position %d)', degrees,posNr))
            end
        end
    end
    
    methods (Access=private)
        function ok = moveToNr(o,positionNr)
            posString = sprintf('R_%d_1E',positionNr);
            fprintf(o.s, posString);
            response= fgetl(o.s);
            ok = strcmpi(response,'done');            
        end
    end
end

