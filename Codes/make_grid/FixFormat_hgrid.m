% Add functions used by Enhui
% Requires spheric_dist and create_ncall (other dependencies?)
addpath('./Functions/EnhuiFunctions/')

% Clear all
clear; close all

% Specify resolution
resol = 1/27

% Original and Matlab filenames
if resol == 1
    fin   = '../DG_1deg/DG_hgrid_1deg_py.nc';
    fout  = '../DG_1deg/DG_hgrid_1deg.nc';
elseif resol == 1/9
    fin   = '../DG_011deg/DG_hgrid_011deg_py.nc';
    fout  = '../DG_011deg/DG_hgrid_011deg.nc';
elseif resol == 1/27
    fin   = '../DG_0037deg/DG_hgrid_0037deg_py.nc';
    fout  = '../DG_0037deg/DG_hgrid_0037deg.nc';
end 

% Load coordinates from fin
x         = ncread(fin,'x')';   
y         = ncread(fin,'y')';
angle_dx0 = ncread(fin,'angle_dx')';

% Re-compute angle (should be the same but avoids adjusting script)
% Theoretically, angle of dx (xi direction vs east direction) should be zero
[nyp,nxp] = size(x);
nx        = nxp-1; 
ny        = nyp-1;
angle_dx  = zeros(nyp,nxp);
dy        = y(:,2:nxp)-y(:,1:nxp-1);
dx        = (x(:,2:nxp)-x(:,1:nxp-1)).*cos(y(:,2:nxp)*pi/180);
angle_dx(:,2:nxp) = atan(dy./dx);
angle_dx(:,1)     = angle_dx(:,2);
angle_dx(:,nxp)   = angle_dx(:,nxp-1);
angle_dx          = angle_dx*180/pi;

% Compute dx and dy in meter (again should be the same)
dx            = zeros(nyp,nxp-1);
dy            = zeros(nyp-1,nxp);
dx(:,1:nxp-1) = spheric_dist(y(:,1:nxp-1),y(:,2:nxp),x(:,1:nxp-1),x(:,2:nxp));
dy(1:nyp-1,:) = spheric_dist(y(1:nyp-1,:),y(2:nyp,:),x(1:nyp-1,:),x(2:nyp,:));
area          = dx(1:nyp-1,1:nxp-1).*dy(1:nyp-1,1:nxp-1);

% Prepare variable information
vars_all      = {'angle_dx','area','dx','dy','x','y'};
vars_units    = {'degrees','m2','meters','meters','degrees','degrees'};

% Write new file
delete(fout);
create_ncall('fn',fout,'xn','nxp','yn','nyp','vn',{'x','degree','super grid x'},'xd',[1:nxp],'yd',[1:nyp],'vd',x');
create_ncall('fn',fout,'xn','nxp','yn','nyp','vn',{'y','degree','super grid y'},'xd',[1:nxp],'yd',[1:nyp],'vd',y');
create_ncall('fn',fout,'xn','nx','yn','nyp','vn',{'dx','meter','super grid length dx'},'xd',[1:nx],'yd',[1:nyp],'vd',dx');
create_ncall('fn',fout,'xn','nxp','yn','ny','vn',{'dy','meter','super grid length dy'},'xd',[1:nxp],'yd',[1:ny],'vd',dy');
create_ncall('fn',fout,'xn','nx','yn','ny','vn',{'area','m2','super grid area'},'xd',[1:nx],'yd',[1:ny],'vd',area');
create_ncall('fn',fout,'xn','nxp','yn','nyp','vn',{'angle_dx','degree','grid cell angle of xi and east'},'xd',[1:nxp],'yd',[1:nyp],'vd',angle_dx');

data = 'tile1';
nccreate(fout,'tile','Datatype','char','Dimensions',{'string',255});
ncwrite(fout,'tile',data)





