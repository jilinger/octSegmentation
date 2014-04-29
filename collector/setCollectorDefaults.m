function options = setCollectorDefaults(options,params,files,folderData,folderLabels)
% setCollectorDefaults - sets defauls values for variables used in the collectors; variables from params, used in a CV, can overwrite the standard values e.g. for the patch size
%  
% Syntax:	
%   options = setCollectorDefaults(options,params,files,folderData,folderLabels)
%
% Inputs:
%   options      - [struct] options struct
%       .width               - [int] patch width in px (has to be odd number). Default: [15]
%       .height              - [int] patch height in px. Default: [15]
%       .clip                - [boolean] determines whether to clip parts of the scan before segmentation; useful for example to remove the nerve head. Default: [false]
%       .clipRange           - [array](2) left and right boundary for clipping. Default: [1 scan-width]
%       .preprocessing       - [struct] struct with fields 'patchLevel' and 'scanLevel'; for each field cell array of methods and their parameters; Default: [options.preprocessing.patchLevel = {{@projToEigenspace,20}}]
%       .loadRoutineData     - [string] user-defined routine to load a B-Scan; see loadData.m for details. Default: ['spectralis'] 
%       .loadRoutineLabels   - [string] user-defined routine to load ground truth; see loadLabels.m for details. Default: ['LabelsFromLabelingTool']
%       .labelIDs            - [array](numFiles,numRegionsPerVolume) holds ids to idenity the scans used in a 3-D volume 
%       .BScanRegions        - [array](2,numBScanRegions) can be used to divide each B-Scan into regions with seperate appearance models; left and right boundaries of each reagion. Default: [[1 numColumns]]
%       .numRegionsPerBScan  - [int] number of regions in each B-Scan, automatically determined from BScanRegions
%       .numRegionsPerVolume - [int] for 3-D volumes, the number of B-Scans; for 2-D set = 1
%       .calcOnGPU           - [boolean] move parts of the calculation onto the GPU. Default: [false]
%       .numPatches          - [int] number of patches to draw from each file for each appearance class. Default: [30]
%       .patchPosition       - [string] draw patches for layer-classes randomly ('random') or from the middle ('middle') for each column. Default: ['middle']
%       .centerPatches       - [boolean] subtract mean of each patch. Default: [true]
%       .columnsShape        - [cell-array](1,numRegionsPerVolume) holds an array for each region; indicates which columns of the B-Scan are used for the shape-prior (intermediate columns are interpolated). Default: columnsShape{i} = [1:2:scan-width]
%       .columnsPred         - [array](2) determines for which columns predictions are made. Will be applied to each scan in the volume. Default: [1:2:scan-width]
%       .printTimings        - [boolean] print cpu/gpu timings of the different modules. Default: [false]
%       .saveAppearanceTerms - [boolean] return appearance model predictions for each pixel. Default: [0]
%       .verbose             - [int] the amount of printed information while runnning the programm (0 (nothing) - 2 (maximal)). Default: [1]
%   params       - [struct] holds params used for example in cross-validation 
%   files        - [struct] training set, output of Matlabs dir function
%   folderData   - [string] path with mat-files containing the OCT scans 
%   folderLabels - [string] path with mat-files containing ground truth
%
% Outputs:
%   options - [struct] options struct with default values set
%
% See also: collectTestData, collectTrnData, loadLabels, loadData, fetchPatches

% Author: Fabian Rathke
% email: frathke@googlemail.com
% Website: https://github.com/FabianRathke/octSegmentation
% Last Revision: 18-Dec-2013

options.folder_data = folderData;
options.folder_labels = folderLabels;

% patch width and height
options = checkFields(options,params,15,'width');
options = checkFields(options,params,15,'height');

if ~isfield(options,'preprocessing') options.preprocessing = struct(); end
% preprocessing on patch-Level (performed in trainAppearance and predictAppearance)
if ~isfield(options.preprocessing,'patchLevel')
	options.preprocessing.patchLevel = {{@projToEigenspace,20}};
end

% preprocessing on scan-Level (performed on loadData)
if ~isfield(options.preprocessing,'scanLevel')
	options.preprocessing.scanLevel = {};
end

% the amount of information output
if ~isfield(options,'verbose') options.verbose = 1; end

% define loading routines for labels and data sets
if ~isfield(options,'loadRoutineData') options.loadRoutineData = 'spectralis'; end
if ~isfield(options,'loadRoutineLabels') options.loadRoutineLabels = 'LabelsFromLabelingTool'; end

% the number of regions per file/volume, 1 ==  2-D Scan, > 1 == 3-D Volume
if ~isfield(options,'numRegionsPerVolume') 
	if ~isfield(options,'labelIDs')
		options.numRegionsPerVolume = 1;
	else
		options.numRegionsPerVolume = size(options.labelIDs,2);
	end
end
% ids for single scans of a volume  (used in functions loadLabels and loadData)
if ~isfield(options,'labelIDs') options.labelIDs = zeros(length(files),options.numRegionsPerVolume); end

if ~isfield(options,'clip') 
	options.clip = 0; 
else
	if options.clip
		if ~isfield(options,'clipRange') 
			error('Please specify the clip range in options.clipRange');
		end
	end
end

% pull a sample scan and set its dimensions
options.labelID = options.labelIDs(1);
B0 = loadData(files(1).name,options);
if isfield(options,'clipRange')
	options.X = options.clipRange(2) - options.clipRange(1) + 1;
else
	options.X = size(B0,2);
end
options.Y = size(B0,1);

% enables to clip the width of B-Scans; i.e. useful for volumnes to remove the part containing the nerve head

% pull sample ground truth
segmentation = loadLabels(files(1).name,options);
options = rmfield(options,'labelID');

numBoundaries = size(segmentation,1); numLayers = numBoundaries + 1;
% edges and layers used for training and prediction
options.EdgesTrain = 1:numBoundaries;
options.LayersTrain = 1:numLayers;
options.EdgesPred = 1:numBoundaries;
options.LayersPred = 1:numLayers;

% can be used to divide each B-Scan into regions, which use seperate appearance models
if ~isfield(options,'BScanRegions') options.BScanRegions = [1 options.X]; end
options.numRegionsPerBScan = size(options.BScanRegions,1);

% default behavior is to perform all calculations on the CPU
if ~isfield(options,'calcOnGPU') options.calcOnGPU = 0; end
% the datatype for those variables that are moved onto the GPU has to be variable
if options.calcOnGPU
	options.dataType = 'GPUsingle';
	options.dataTypeCast = 'GPUsingle';
else
	options.dataType = '''double''';
	options.dataTypeCast = 'double';
end

% most probably deprecated (05-12-2013)
%if ~isfield(options,'columns')
%	options.columns = round(linspace(1,options.X,options.X));
%end

% number of patches to draw for training; per class and file
if ~isfield(options,'numPatches') options.numPatches = 30; end
% substract the patch mean from each patch; make appearance terms less vulnerable to variations of intensity between and within OCT scans
if ~isfield(options,'centerPatches') options.centerPatches = 1; end


% which columns are part of the shape prior p(b) and are used for q_b (allows for sparse representations; intermediate columns are interpolated);
% can be set for each region within the volume separately
if ~isfield(options,'columnsShape') 
	options.columnsShape = cell(1,options.numRegionsPerVolume);
	for i = 1:options.numRegionsPerVolume
		options.columnsShape{i} = round(linspace(1,options.X,options.X/2));
	end
end
% which columns are to be predicted, i.e. are used in q_c
if ~isfield(options,'columnsPred') options.columnsPred = round(linspace(1,options.X,options.X/2)); end

% patches are drawn from the center of their layer
if ~isfield(options,'patchPosition') options.patchPosition = 'middle'; end

% print Timings during prediction
if ~isfield(options,'printTimings') options.printTimings = 0; end
options.numLayers = length(options.LayersTrain);

if ~isfield(options,'saveAppearanceTerms') options.saveAppearanceTerms = 0; end
