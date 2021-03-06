function DISC = FLYNN( pathToConfigFile, pathToLocsFile )
%FLYNN 3.5.2 Takes a config file pathname and a locations file pathname, then loads, organizes, and
%analyzes continuous or epoched EEG data.
%
% C. Hassall and O. Krigolson
% December, 2017
%
% FLYNN 3.0 .mat input (EEGLAB format), multiple .mat output
% FLYNN 2.0 trial eeg text file input, multiple .mat output
% FLYNN 1.0 average eeg text file input, single .mat output
% Requires: disc.wav, flynn.jpg, stats toolbox
%
% Example
% myDISC = FLYNN('FLYNNConfiguration.txt','Standard-10-20-NEL-62.locs');
% save('DISC.mat','myDISC');
% plotdisc(myDISC);

% FLYNN version number (major, minor, revision)
version = '3.5.2';

% Load config file
configFileId = fopen(pathToConfigFile);
C = textscan(configFileId, '%q','CommentStyle','%');
fclose(configFileId);
answer = C{1};

% Load locs file
userLocsFile = readlocs(pathToLocsFile, 'filetype', 'locs');
userLocsFile = rmfield(userLocsFile,{'sph_theta_besa','sph_phi_besa'});

% Parse ANSWER
basefilename = answer{1};
subjectnumbers = strsplit(answer{2},',');
numberofsubjects = length(subjectnumbers);
baselinesettings = str2num(answer{3});
artifactsettings = str2num(answer{4});
outfile = answer{5};

% Determine which ERP/FFT/WVLT to do
numAnalyses = length(answer)-5;
if numAnalyses == 0
    disp('Error: No analysis specified');
    return;
end

% ERP variables
ERP.markers = {};
ERP.startTime = [];
ERP.endTime = [];
ERP.conditions = {};
numErpConditions = 0;
numErpMarkersByCondition = [];

% ALL variables
ALL.markers = {};
ALL.startTime = [];
ALL.endTime = [];
ALL.conditions = {};
numAllConditions = 0;
numAllMarkersByCondition = [];
ALL.whichMarker = {};
ALL.isArtifact = {};

% FFT variables
FFT.markers = {};
FFT.startTime = [];
FFT.endTime = [];
FFT.conditions = {};
numFftConditions = 0;
numFftMarkersByCondition = [];

% WAV variables
WAV.markers = {};
WAV.startTime = [];
WAV.endTime = [];
WAV.baselineStart = [];
WAV.baselineEnd = [];
WAV.frequencyStart = [];
WAV.frequencyEnd = [];
WAV.frequencySteps = [];
WAV.rangeCycles = [];
WAV.conditions = {};
numWavConditions = 0;
numWavMarkersByCondition = [];

for i = 1:length(answer)-5
    thisAnalysis = answer{5+i};
    temp = strsplit(thisAnalysis,',');
    if strcmp(temp{1},'ERP')
        numErpConditions = numErpConditions + 1;
        numMarkers = length(temp) - 4;
        numErpMarkersByCondition(numErpConditions) = numMarkers;
        for k = 1:numMarkers
            ERP.markers{k,numErpConditions} = temp{1+k};
        end
        ERP.startTime{numErpConditions} = temp{2 + numMarkers};
        ERP.endTime{numErpConditions} = temp{3 + numMarkers};
        ERP.conditions{numErpConditions} = temp{4+numMarkers};
    elseif strcmp(temp{1},'ALL')
        numAllConditions = numAllConditions + 1;
        numMarkers = length(temp) - 4;
        numAllMarkersByCondition(numAllConditions) = numMarkers;
        for k = 1:numMarkers
            ALL.markers{k,numAllConditions} = temp{1+k};
        end
        ALL.startTime{numAllConditions} = temp{2 + numMarkers};
        ALL.endTime{numAllConditions} = temp{3 + numMarkers};
        ALL.conditions{numAllConditions} = temp{4+numMarkers};
    elseif strcmp(temp{1},'FFT')
        
        numFftConditions = numFftConditions + 1;
        numFftMarkers = length(temp) - 4;
        numFftMarkersByCondition(numFftConditions) = numFftMarkers;
        for k = 1:numFftMarkers
            FFT.markers{k,numFftConditions} = temp{1+k};
        end
        FFT.startTime{numFftConditions} = temp{2 + numFftMarkers};
        FFT.endTime{numFftConditions} = temp{3 + numFftMarkers};
        FFT.conditions{numFftConditions} = temp{4+numFftMarkers};
        
    elseif strcmp(temp{1},'WAV')
        
        numWavConditions = numWavConditions + 1;
        numWavMarkers = length(temp) - 10;
        numWavMarkersByCondition(numWavConditions) = numWavMarkers;
        for k = 1:numWavMarkers
            WAV.markers{k,numWavConditions} = temp{1+k};
        end
        WAV.startTime{numWavConditions} = temp{2 + numWavMarkers};
        WAV.endTime{numWavConditions} = temp{3 + numWavMarkers};
        WAV.baselineStart{numWavConditions} = temp{4+numWavMarkers};
        WAV.baselineEnd{numWavConditions} = temp{5+numWavMarkers};
        WAV.frequencyStart{numWavConditions} = temp{6+numWavMarkers};
        WAV.frequencyEnd{numWavConditions} = temp{7+numWavMarkers};
        WAV.frequencySteps{numWavConditions} = temp{8+numWavMarkers};
        WAV.rangeCycles{numWavConditions} = temp{9+numWavMarkers};
        WAV.conditions{numWavConditions} = temp{10+numWavMarkers};
    else
        disp('Error: Unknown analysis');
        return;
    end
end

% DISC will hold participant summaries
DISC.version = version;
DISC.participants = subjectnumbers;
DISC.N = numberofsubjects;
DISC.EEGSum = []; % EEG Summary (participant, channels, datapoints)
DISC.ALLSum = []; % ALL Summary (participant, channels, datapoints)
DISC.ERPSum = []; % ERP Summary (participant, kept epochs, removed epochs)
DISC.FFTSum = []; % FFT Summary (participant, kept epochs, removed epochs)
DISC.WAVSum = []; % WAV Summary (participant, kept epochs, removed epochs)

firstLocsFile = [];

% Do analysis for each participant (ERP, FFT, WVLT)
for p = 1:numberofsubjects
    if isempty(subjectnumbers{p})
        disp('Error: No participants present');
        return;
    end
    % Data Import
    disp(['Current Subject Being Loaded: ' subjectnumbers{p}]);
    filename = [basefilename subjectnumbers{p} '.mat'];
    load(filename);
    
    % Add in some empty fields
    EEG.icasphere = [];
    EEG.icawinv = [];
    EEG.icaweights = [];
    EEG.icaact = [];
    
    % Check to see if the data have been epoched (i.e. channels X samples
    % X trials) or if the data are continuous
    dataEpoched = 0;
    if length(size(EEG.data)) == 3
        dataEpoched = 1;
    end
    
    % Interpolate missing channels and reorder (based on code by Marco Simões)
    % Check to see if there are any channels in the EEG file that are not
    % in the locs file
    if any(ismember({EEG.chanlocs.labels}, {userLocsFile.labels})  == 0)
        disp('Warning: EEG contains channels that are missing from the user-specified locs file');
        return;
    end
    missingIDs = [];
    for i=1:length(userLocsFile)
        if isempty(find(ismember({EEG.chanlocs.labels}, userLocsFile(i).labels) == 1, 1))
            missingIDs = [missingIDs i];
        end
    end
    interpolated{p} =  {userLocsFile(missingIDs).labels};
    if ~isempty(missingIDs)
        EEG = pop_interp(EEG, userLocsFile(missingIDs), 'spherical'); % Interpolate missing channels
    end
    newOrder = nan(1, length(userLocsFile));
    for c=1:length(userLocsFile)
        newOrder(c) = find(ismember({EEG.chanlocs.labels}, userLocsFile(c).labels) == 1, 1);
    end
    EEG.data(:,:,:) = EEG.data(newOrder,:,:); % Reorder data (should word whether EEG.data is 2D or 3D)
    EEG.chanlocs = EEG.chanlocs(newOrder);  % Reorder chanlocs
    
    %     %% Sort the data
    %     newOrder = nan(1,length(EEG.chanlocs)); % New channel order
    %     % Compare user channels to actual channels - if there is a match,
    %     % record in which position it was found
    %     for i = 1:length(userLocsFile)
    %         for k = 1:length(EEG.chanlocs)
    %             if strcmp(userLocsFile(i).labels,EEG.chanlocs(k).labels)
    %                 newOrder(i) = k;
    %             end
    %         end
    %     end
    %     % Error checking
    %     if length(userLocsFile) ~= length(EEG.chanlocs) || any(isnan(newOrder))
    %         disp('Error: Locs file mismatch');
    %         return;
    %     else
    %         EEG.chanlocs = userLocsFile; % Use the user-defined locs file
    %         EEG.data = EEG.data(newOrder,:,:); % Reorder data
    %     end
    
    % chanlocs = EEG.chanlocs; % This may lead to slightly different locs parameters due to interpolation
    chanlocs = userLocsFile;
    srate = EEG.srate;
    times = EEG.xmin*1000:1000/EEG.srate:EEG.xmax*1000;
    thisParticipantNumber = str2num(cell2mat(regexp(subjectnumbers{p},'\d','match'))); % Remove non-digits first
    
    %% Epoching
    if dataEpoched
        allMarkers = {EEG.epoch.eventtype}; % Markers within each epoch
        
        % Problem: epochs contain multiple markers - to know which one is at 0 ms, we need to check latencies
        latencies = {EEG.epoch.eventlatency}; % Latencies of all events within each epoch
        actualMarkers = {}; % Marker of interest for each epoch
        for m = 1:length(allMarkers)
            thisSetOfMarkers = allMarkers{m};
            if ~iscell(thisSetOfMarkers) % NEW November 27 - need this in case there is only one marker in epoch
                actualMarkers{m} = thisSetOfMarkers;
            else
                theseLatencies = cell2mat(latencies{m});
                [~, whichOne] = min(abs(theseLatencies - abs(EEG.xmin)*1000000)); % Find the latency (in nanoseconds?) closest to 0 ms
                if isempty(whichOne)
                    disp('Error: Timing error in EEGLAB file');
                    return;
                end
                actualMarkers{m} = thisSetOfMarkers{whichOne};
            end
        end
    else
        allMarkers = {EEG.event.type};
        latencies = cell2mat({EEG.event.latency}');
        actualMarkers = allMarkers;
    end
    
    %% ERP Analysis
    for c = 1:length(ERP.conditions)
        
        isThisCondition = false(1,length(actualMarkers));
        % Make a logical vector so that all relevant markers are inccluded
        for m = 1:numErpMarkersByCondition(c)
            isThisCondition = isThisCondition | strcmp(actualMarkers,ERP.markers{m,c});
        end
        
        if sum(isThisCondition) == 0
            ERP.timepoints{c} = [];
            ERP.data{c} = [];
            ERP.nAccepted{c} = NaN;
            ERP.nRejected{c} = NaN;
            disp(['No ERP epochs found: ' ERP.conditions{c}]);
        else
            
            ERP.timepoints{c} = str2num(ERP.startTime{c}):1000/EEG.srate:str2num(ERP.endTime{c});
            ERP.data{c} = nan(EEG.nbchan,length(ERP.timepoints{c}));
            if dataEpoched
                erpPoints = dsearchn(times', [str2num(ERP.startTime{c}) str2num(ERP.endTime{c})]');
                erpEEG = EEG.data(:,erpPoints(1):erpPoints(2),:);
            else
                theseLatencies = latencies(isThisCondition);
                erpEEG = [];
                for m = 1:length(theseLatencies)
                    erpPoints = dsearchn(times',theseLatencies(m)*1000/EEG.srate + [str2num(ERP.startTime{c}) str2num(ERP.endTime{c})]');
                    
                    % Had to add this in case an epoch goes past the end of the
                    % recording
                    if erpPoints(2)-erpPoints(1)+1 == length(ERP.timepoints{c})
                        erpEEG(:,:,m) = EEG.data(:,erpPoints(1):erpPoints(2));
                    end
                    
                end
            end
            
            % Do baseline correction
            if ~isempty(baselinesettings)
                baselinePoints = dsearchn(ERP.timepoints{c}',baselinesettings(:)); % Find the baseline indices
                baseline = mean(erpEEG(:,baselinePoints(1):baselinePoints(2) ,:),2);
                erpEEG = erpEEG - repmat(baseline,[1,length(ERP.timepoints{c}),1]); % EEG data, with baseline correction applied
            end
            
            % ERP Artifact Rejection TODO: Make this a function
            % Artifact Rejection - Gradient
            maxAllowedStep = artifactsettings(1)*(1000/EEG.srate); % E.g. 10 uV/ms ~= 40 uV/4 ms... Equivalent to Analyzer?
            gradient = abs(erpEEG(:,2:end,:) - erpEEG(:,1:end-1,:));
            gradientViolation = squeeze(any(gradient > maxAllowedStep,2));
            
            % Artifact Rejection - Difference
            maxAllowedDifference = artifactsettings(2);
            diffEEG = max(erpEEG,[],2) - min(erpEEG,[],2);
            differenceViolations = squeeze(diffEEG > maxAllowedDifference);
            
            allViolations = sum(gradientViolation) + sum(differenceViolations);
            isArtifact = allViolations ~= 0;
            
            if dataEpoched
                ERP.nAccepted{c} = sum(~isArtifact & isThisCondition);
                ERP.nRejected{c} = sum(isArtifact & isThisCondition);
                thisAverage = mean(erpEEG(:,:,~isArtifact & isThisCondition),3);
            else
                ERP.nAccepted{c} = sum(~isArtifact);
                ERP.nRejected{c} = sum(isArtifact);
                thisAverage = mean(erpEEG(:,:,~isArtifact),3);
            end
            
            %         plot(thisAverage(34,:));
            %         hold on;
            ERP.data{c} = thisAverage;
            
        end
        
        DISC.ERPSum = [DISC.ERPSum; thisParticipantNumber c ERP.nAccepted{c} ERP.nRejected{c}];
    end
    
    %% ALL Analysis (will store all trials of a certain type)
    for c = 1:length(ALL.conditions)
        
        isThisCondition = false(numAllMarkersByCondition(c),length(actualMarkers));
        % Make a logical vector so that all relevant markers are inccluded
        for m = 1:numAllMarkersByCondition(c)
            isThisCondition(m,:) = strcmp(actualMarkers,ALL.markers{m,c});
        end
        isAnyCondition = sum([isThisCondition; zeros(1,length(isThisCondition))]) ~= 0;
        
        if sum(isAnyCondition) == 0
            ALL.timepoints{c} = [];
            ALL.data{c} = [];
            ALL.nAccepted{c} = NaN;
            ALL.nRejected{c} = NaN;
            disp(['No ALL epochs found: ' ALL.conditions{c}]);
        else
        
        ALL.timepoints{c} = str2num(ALL.startTime{c}):1000/EEG.srate:str2num(ALL.endTime{c});
        %ALL.data{c} = nan(EEG.nbchan,length(ALL.timepoints{c}),);
        
        if dataEpoched
            allPoints = dsearchn(times', [str2num(ALL.startTime{c}) str2num(ALL.endTime{c})]');
            allEEG = EEG.data(:,allPoints(1):allPoints(2),:);
        else
            theseLatencies = latencies(isAnyCondition);
            allEEG = [];
            for m = 1:length(theseLatencies)
                allPoints = dsearchn(times',theseLatencies(m)*1000/EEG.srate + [str2num(ALL.startTime{c}) str2num(ALL.endTime{c})]');
                
                % Had to add this in case an epoch goes past the end of the
                % recording
                if allPoints(2)-allPoints(1)+1 == length(ALL.timepoints{c})
                    allEEG(:,:,m) = EEG.data(:,allPoints(1):allPoints(2));
                end
                
            end
        end
        
        % Do baseline correction
        if ~isempty(baselinesettings)
            baselinePoints = dsearchn(ALL.timepoints{c}',baselinesettings(:)); % Find the baseline indices
            baseline = mean(allEEG(:,baselinePoints(1):baselinePoints(2) ,:),2);
            allEEG = allEEG - repmat(baseline,[1,length(ALL.timepoints{c}),1]); % EEG data, with baseline correction applied
        end
        
        % ERP Artifact Rejection TODO: Make this a function
        % Artifact Rejection - Gradient
        maxAllowedStep = artifactsettings(1)*(1000/EEG.srate); % E.g. 10 uV/ms ~= 40 uV/4 ms... Equivalent to Analyzer?
        gradient = abs(allEEG(:,2:end,:) - allEEG(:,1:end-1,:));
        gradientViolation = squeeze(any(gradient > maxAllowedStep,2));
        
        % Artifact Rejection - Difference
        maxAllowedDifference = artifactsettings(2);
        diffEEG = max(allEEG,[],2) - min(allEEG,[],2);
        differenceViolations = squeeze(diffEEG > maxAllowedDifference);
        
        allViolations = sum(gradientViolation) + sum(differenceViolations);
        isArtifact = allViolations ~= 0;
        
        if dataEpoched
            isArtifact = isArtifact(isAnyCondition);
            ALL.nAccepted{c} = sum(~isArtifact);
            ALL.nRejected{c} = sum(isArtifact);
            ALL.data{c} = allEEG(:,:,isAnyCondition);
        else
            ALL.nAccepted{c} = sum(~isArtifact);
            ALL.nRejected{c} = sum(isArtifact);
            ALL.data{c} = allEEG;
        end
        
        ALL.whichMarker{c} = isThisCondition(:,isAnyCondition); % Marker for each trial
        ALL.isArtifact{c} = isArtifact;
        
        end
        
        DISC.ALLSum = [DISC.ALLSum; thisParticipantNumber c ALL.nAccepted{c} ALL.nRejected{c}];
    end
    
    %% FFT Analysis
    for c = 1:length(FFT.conditions)
        
        % Contruct a boolean indicating if an epoch should be included
        isThisCondition = false(1,length(actualMarkers));
        % Make a logical vector so that all relevant markers are inccluded
        for m = 1:numFftMarkersByCondition(c)
            isThisCondition = isThisCondition | strcmp(actualMarkers,FFT.markers{m,c});
        end
        
        if sum(isThisCondition) == 0
            FFT.timepoints{c} = [];
            FFT.data{c} = [];
            FFT.nAccepted{c} = NaN;
            FFT.nRejected{c} = NaN;
            disp(['No FFT epochs found: ' FFT.conditions{c}]);
        else
        
        FFT.timepoints{c} = str2num(FFT.startTime{c}):1000/EEG.srate:str2num(FFT.endTime{c});
        FFT.frequencyResolution{c} = EEG.srate / length(FFT.timepoints{c});
        
        if dataEpoched
            fftPoints = dsearchn(times', [str2num(FFT.startTime{c}) str2num(FFT.endTime{c})]');
            fftEEG = EEG.data(:,fftPoints(1):fftPoints(2),:);
        else
            theseLatencies = latencies(isThisCondition);
            fftEEG = [];
            for m = 1:length(theseLatencies)
                fftPoints = dsearchn(times',theseLatencies(m)*1000/EEG.srate + [str2num(FFT.startTime{c}) str2num(FFT.endTime{c})]');
                
                % Had to add this in case an epoch goes past the end of the
                % recording
                if fftPoints(2)-fftPoints(1) + 1 == length(FFT.timepoints{c})
                    fftEEG(:,:,m) = EEG.data(:,fftPoints(1):fftPoints(2));
                end
                
            end
        end
        
        % Do baseline correction
        if ~isempty(baselinesettings)
            baselinePoints = dsearchn(FFT.timepoints{c}',baselinesettings(:)); % Find the baseline indices
            baseline = mean(fftEEG(:,baselinePoints(1):baselinePoints(2) ,:),2);
            fftEEG = fftEEG - repmat(baseline,[1,length(FFT.timepoints{c}),1]); % EEG data, with baseline correction applied
        end
        
        % ERP Artifact Rejection
        % Artifact Rejection - Gradient
        maxAllowedStep = artifactsettings(1)*(1000/EEG.srate); % E.g. 10 uV/ms ~= 40 uV/4 ms... Equivalent to Analyzer?
        gradient = abs(fftEEG(:,2:end,:) - fftEEG(:,1:end-1,:));
        gradientViolation = squeeze(any(gradient > maxAllowedStep,2));
        
        % Artifact Rejection - Difference
        maxAllowedDifference = artifactsettings(2);
        diffEEG = max(fftEEG,[],2) - min(fftEEG,[],2);
        differenceViolations = squeeze(diffEEG > maxAllowedDifference);
        %         diffEEG = movmax(fftEEG,800/(1000/EEG.srate),2,'Endpoints','discard') - movmin(fftEEG,800/(1000/EEG.srate),2,'Endpoints','discard'); % e.g., 800 ms moving window
        %         differenceViolations = squeeze(any(diffEEG > maxAllowedDifference,2));
        
        allViolations = sum(gradientViolation) + sum(differenceViolations);
        isArtifact = allViolations ~= 0;
        
        % Store the number of good epochs for this condition and the
        % proportion rejected
        if dataEpoched
            FFT.nAccepted{c} = sum(~isArtifact & isThisCondition);
            FFT.nRejected{c} = sum(isArtifact & isThisCondition);
            trimmedEEG.data = fftEEG(:,:,~isArtifact & isThisCondition);
        else
            FFT.nAccepted{c} = sum(~isArtifact);
            FFT.nRejected{c} = sum(isArtifact);
            trimmedEEG.data = fftEEG(:,:,~isArtifact);
        end
        % Prepare the EEG on which the FFT will be run
        trimmedEEG.pnts = length(fftPoints(1):fftPoints(2));
        trimmedEEG.srate = EEG.srate;
        
        % Call doFFT
        [FFT.data{c},FFT.frequencies{c}] = doFFT(trimmedEEG);
        
        end
        
        DISC.FFTSum = [DISC.FFTSum; thisParticipantNumber c FFT.nAccepted{c} FFT.nRejected{c}];
    end
    
    %% Wavelet Analysis (TODO)
    for c = 1:length(WAV.conditions)
        
        % Contruct a boolean indicating if an epoch should be included
        isThisCondition = false(1,length(actualMarkers));
        % Make a logical vector so that all relevant markers are inccluded
        for m = 1:numWavMarkersByCondition(c)
            isThisCondition = isThisCondition | strcmp(actualMarkers,WAV.markers{m,c});
        end
        
        if sum(isThisCondition) == 0
            WAV.timepoints{c} = [];
            WAV.data{c} = [];
            WAV.nAccepted{c} = NaN;
            WAV.nRejected{c} = NaN;
            disp(['No WAV epochs found: ' WAV.conditions{c}]);
        else
        
        WAV.timepoints{c} = str2num(WAV.startTime{c}):1000/EEG.srate:str2num(WAV.endTime{c});
        WAV.frequencyResolution{c} = EEG.srate / length(WAV.timepoints{c});
        
        if dataEpoched
            wavPoints = dsearchn(times', [str2num(WAV.startTime{c}) str2num(WAV.endTime{c})]');
            wavEEG = EEG.data(:,wavPoints(1):wavPoints(2),:);
        else
            theseLatencies = latencies(isThisCondition);
            wavEEG = [];
            for m = 1:length(theseLatencies)
                wavPoints = dsearchn(times',theseLatencies(m)*1000/EEG.srate + [str2num(WAV.startTime{c}) str2num(WAV.endTime{c})]');
                
                % Had to add this in case an epoch goes past the end of the
                % recording
                if wavPoints(2)-wavPoints(1) + 1 == length(WAV.timepoints{c})
                    wavEEG(:,:,m) = EEG.data(:,wavPoints(1):wavPoints(2));
                end
                
            end
        end
        
        % Do baseline correction
        if ~isempty(baselinesettings)
            baselinePoints = dsearchn(WAV.timepoints{c}',baselinesettings(:)); % Find the baseline indices
            baseline = mean(wavEEG(:,baselinePoints(1):baselinePoints(2) ,:),2);
            wavEEG = wavEEG - repmat(baseline,[1,length(WAV.timepoints{c}),1]); % EEG data, with baseline correction applied
        end
        
        % Artifact Rejection - Gradient
        maxAllowedStep = artifactsettings(1)*(1000/EEG.srate); % E.g. 10 uV/ms ~= 40 uV/4 ms... Equivalent to Analyzer?
        gradient = abs(wavEEG(:,2:end,:) - wavEEG(:,1:end-1,:));
        gradientViolation = squeeze(any(gradient > maxAllowedStep,2));
        
        % Artifact Rejection - Difference
        maxAllowedDifference = artifactsettings(2);
        diffEEG = max(wavEEG,[],2) - min(wavEEG,[],2);
        differenceViolations = squeeze(diffEEG > maxAllowedDifference);
        %diffEEG = movmax(wavEEG,800/(1000/EEG.srate),2,'Endpoints','discard') - movmin(wavEEG,800/(1000/EEG.srate),2,'Endpoints','discard'); % e.g., 800 ms moving window
        %differenceViolations = squeeze(any(diffEEG > maxAllowedDifference,2));
        
        allViolations = sum(gradientViolation) + sum(differenceViolations);
        isArtifact = allViolations ~= 0;
        
        if dataEpoched
            WAV.nAccepted{c} = sum(~isArtifact & isThisCondition);
            WAV.nRejected{c} = sum(isArtifact & isThisCondition);
            trimmedEEG.data = wavEEG(:,:,~isArtifact & isThisCondition);
        else
            WAV.nAccepted{c} = sum(~isArtifact);
            WAV.nRejected{c} = sum(isArtifact);
            trimmedEEG.data = wavEEG(:,:,~isArtifact);
        end
        [~,~,trimmedEEG.trials] = size(trimmedEEG.data);
        trimmedEEG.times = WAV.timepoints{c};
        trimmedEEG.srate = EEG.srate;
        trimmedEEG.pnts =  length(WAV.timepoints{c});
        
        baseline_windows = [str2num(WAV.baselineStart{c}) str2num(WAV.baselineEnd{c})];
        min_freq = str2num(WAV.frequencyStart{c});
        max_freq = str2num(WAV.frequencyEnd{c});
        num_frex = str2num(WAV.frequencySteps{c});
        range_cycles = str2num(WAV.rangeCycles{c});
        [WAV.data{c},WAV.dataPercent{c},WAV.frequencies{c}] = doWavelet(trimmedEEG,baseline_windows,min_freq,max_freq,num_frex,range_cycles);
        
        end
        
        DISC.WAVSum = [DISC.WAVSum; thisParticipantNumber c WAV.nAccepted{c} WAV.nRejected{c}];
    end
    %% Data Export
    outfilename = [outfile subjectnumbers{p} '.mat'];
    save(outfilename,'version','srate','chanlocs','ERP','ALL','FFT','WAV');
end

% Store condition names in the DISC
DISC.ALLConditions = ALL.conditions;
DISC.ERPConditions = ERP.conditions;
DISC.FFTConditions = FFT.conditions;
DISC.WAVConditions = WAV.conditions;

% Record interpolated channel names
DISC.interpolated = interpolated;

%% Visualization
plotdisc(DISC);

end

% Use the commented-out code below to display results (condition 1, channel 1)
% plot(FFT.frequencies{1},FFT.data{1}(1,:));
% contourf(WAV.timepoints{1}, WAV.frequencies{1}, squeeze(WAV.data{1}(1,:,:)),'linecolor','none');