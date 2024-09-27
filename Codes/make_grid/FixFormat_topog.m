% Add functions used by Enhui
% Requires spheric_dist and create_ncall (other dependencies?)
addpath('./Functions/EnhuiFunctions/')

% Clear all
clear; close all

% Specify resolution
resol = 1/27

% Original and Matlab filenames
if resol == 1
    fin   = '../DG_1deg/DG_topog_1deg_py.nc';
    fout  = '../DG_1deg/DG_topog_1deg.nc';
elseif resol == 1/9
    fin   = '../DG_011deg/DG_topog_011deg_py.nc';
    fout  = '../DG_011deg/DG_topog_011deg.nc';
elseif resol == 1/27
    fin   = '../DG_0037deg/DG_topog_0037deg_py.nc';
    fout  = '../DG_0037deg/DG_topog_0037deg.nc';
end 

% Set depth variability to zero
depth_model  = ncread(fin,'depth')';
mask_model   = ncread(fin,'wet')';
[jm,im]      = size(depth_model);
depth2_model = zeros(jm,im);

nx = im
ny = jm;

% Write new file
delete(fout);
create_ncall('fn',fout,'xn','nx','yn','ny','vn',{'depth','meter','topographic depth at T-cell centers'},'xd',[1:nx],'yd',[1:ny],'vd',depth_model');
create_ncall('fn',fout,'xn','nx','yn','ny','vn',{'h2','meter','Variance of sub-grid scale topography'},'xd',[1:nx],'yd',[1:ny],'vd',depth2_model');
create_ncall('fn',fout,'xn','nx','yn','ny','vn',{'wet','none','land=0 ocean=1 mask'},'xd',[1:nx],'yd',[1:ny],'vd',mask_model');
nccreate(fout,'ntiles','Dimensions',{'ntiles',1});




