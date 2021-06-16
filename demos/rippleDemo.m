%% Ripple recording Demo
%
% BK - May 2017, Nov 2019

import neurostim.*;
%% Setup CIC and the stimuli.
c = neurostim.myRig;
c.screen.color.text = [1 0 0];  % A red text 
c.screen.color.background = [0 0 0]; % 
c.screen.type = 'GENERIC';
c.trialDuration = 1000;
c.iti           = 150;
c.paradigm      = 'rippleDemo';
c.subjectNr      =  0;
c.dirs.output = 'c:\temp\'; %This directory needs to exist on the Trellis computer.


% To use the cic.messenger to close the loop between Ripple analysis and 
% the PTB stimuli, uncomment this to instruct CIC to update parameters
% based on messsages received from a remote computer 
% c.messenger.host = 'localhost';
% fun = @(x) (updateLocal(x.messenger));  
% c.addScript('BeforeFrame',fun);   %beforeTrial, or beforeFrame, depending
% on need.
% See tools/rippleClosedLoop for the remote processing part.


t= plugins.ripple(c);
t.trialBit = 3; % At the start of each trial this bit goes high. Use to align times.


% Convpoly to create the target patch
ptch = stimuli.convPoly(c,'patch');
ptch.radius       = 5;
ptch.X            = 0;
ptch.Y            = 0;
ptch.nSides       = 10;
ptch.filled       = true;
ptch.color        = 0;
ptch.on           = 0;



%% Define conditions and blocks
lm =design('lum');
% In this block we want to vary the luminance of a grey patch across trials.
% Assigning a single luminance value is actually enough; PTB interprets a
% single color (x) as [x x x].
lum = (0.5:2:30);
lm.fac1.patch.color = lum; 
lm.randomization  ='sequential'; % Sequence through luminance. Press 'n' to go to the next.
lmBlck=block('lmBlock',lm);
lmBlck.nrRepeats  = 1;

%% Run the demo
c.run(lmBlck);
