% Code calculates the width of the North Atlantic ocean in the LRG double
% gyre model domain (mwidth) and the real ocean (owidth), using the IHO
% shapefile available at: 
% https://marineregions.org/gazetteer.php?p=details&id=1912
%
% Requires lldistkm.m (included; available on MathWorks File Exchange)
%
% March 15, 2022 - JCG

%% Add path to function
addpath('./Functions/');

%% Read in shape file
s = shaperead('iho.shp');

%% Plot to show outline
figure(1)
clf
hold on
plot(s(8).X, s(8).Y, 'k', 'linewidth', 1)

%% Calculate ocean width at every 1/2 point of latitude
lat = 0:0.5:68;
owidth = NaN(length(lat), 1);
mwidth = NaN(length(lat), 1);

for ilat = 1:length(lat)
    
    ipt = find(round(s(8).Y*10)/10 == lat(ilat));
    
    [d1km ~] = lldistkm([lat(ilat) max(s(8).X(ipt))], ...
        [lat(ilat) min(s(8).X(ipt))]);
    
    owidth(ilat) = d1km * 1000; 
    
    % Calculated on globe but should compare with spherical projection
    [d1km ~] = lldistkm([lat(ilat) -55], ...
        [lat(ilat) -15]);
    
    mwidth(ilat) = d1km * 1000; 
    
    figure(1)
    if rem(ilat, 10) == 0
        plot([min(s(8).X(ipt)) max(s(8).X(ipt))], ...
            [lat(ilat),lat(ilat)], 'm', 'linewidth', 2)
    end
    
    xlabel('Longitude')
    ylabel('Latitude')
    
    set(gca, 'fontsize', 14, 'linewidth', 2, 'box', 'on')
    
end

%% Plot ratio
m2o = mwidth ./ owidth;
o2m = owidth ./ mwidth;

figure(2)
plot(m2o, lat)
plot(1 ./ o2m, lat, 'r')

ylim([17 67])
xlim([0.5 1.5])

xlabel('Ratio model/ocean')
ylabel('Latitude')

%% Save netcdf information
netcdf.setDefaultFormat('NC_FORMAT_CLASSIC') ;
ncid = netcdf.create('model_ocean_widths.nc','NC_WRITE');
dimid = netcdf.defDim(ncid, 'lat', length(lat));
var1 = netcdf.defVar(ncid,'lat','NC_FLOAT', dimid);
var2 = netcdf.defVar(ncid,'mwidth','NC_FLOAT', dimid);
var3 = netcdf.defVar(ncid,'owidth','NC_FLOAT', dimid);
netcdf.endDef(ncid);
netcdf.putVar(ncid, var1, lat);
netcdf.putVar(ncid, var2, mwidth);
netcdf.putVar(ncid, var3, owidth);
netcdf.close(ncid);
