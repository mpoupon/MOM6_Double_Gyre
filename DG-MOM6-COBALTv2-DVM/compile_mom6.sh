#!/bin/bash
module purge

module load intel/2021.1.2
module load intel-mpi/intel/2021.3.1
module load hdf5/intel-2021.1/intel-mpi/1.10.6
module load netcdf/intel-2021.1/hdf5-1.10.6/intel-mpi/4.7.4

#link datasets to current MOM6
#ln -sf /tigress/GEOCLIM/LRGROUP/datasets_2020_Jan .datasets

if [ ! -e .datasets ]
then
    ln -s /scratch/cimes/GEOCLIM/LRGROUP/Liao/datasets_2020_Jan .datasets
fi

# compile label for bio or ocean-ice
# be careful with the compile label (clab) here, there are only three options: ocean_ice_bgc, ocean_ice, ocean_only 
clab='ocean_ice_bgc'; #only three options: ocean_ice_bgc, ocean_ice, ocean_only

regional_bgc='false'; # true or false to open regional cobalt, the exe_name will be clab_regional

tide='false'; # true or false to open tide, the exe_name will be clab_tide

kw_dm18='false'; # true or false to turn on kw_dm18 which should only work for global bgc
                # kw_dm18 uses Luc's method to compute dic_kw

#can rename the exename
EXENAME=$clab #"_tide" #"mom6_lrgroup_bio"
BASEDIR=$(pwd);
MKF_TEMPLATE="$BASEDIR/stellar-amd.mk"

#set the default branch in the begining compile
cd src/MOM6;       git checkout lrgroup/default
cd ../SIS2;        git checkout lrgroup/default
cd ../ocean_BGC;   git checkout lrgroup/default
cd ../FMS1;        git checkout origin/release/2019.01 # GFDL MOM6-examples default version and change one line to speed up BGC 
cd ../coupler;     git checkout lrgroup/default; git checkout 14578f0 #GFDL MOM6-examples default version (14578f0)
cd ../atmos_null;  git checkout lrgroup/default; git checkout aeac506 #GFDL MOM6-examples default version (aeac506)
cd ../../

if $regional_bgc; then #[[ "$clab" = *"regional"* ]]; then
   # get andrews MOM6 source code to handle BGC open boundary conditions
   echo "switching src/MOM6 to Andrew's branch..."
   cd src/MOM6; git checkout lrgroup/andrew-merge-bgc-obc; git checkout 9734d97

   # get Niki's new BGC code with Charlie's modifications for Indian Ocean
   echo "switching src/ocean_BGC to Niki's modified branch for regional Indian Ocean..."
   cd ../ocean_BGC; git checkout lrgroup/regional_default; 

   # get FMS version with Andrew's fast OBC speed
   echo "switching src/FMS to origin/release/2021.03 branch..." #2021 03 version is an suggested version by Andrew
   cd ../FMS1;  git checkout lrgroup/default; git checkout 8883101 #This is the version right after origin/release/2021.03 
   #git checkout origin/release/2021.03 #this branch disappear when updating code
   # add in temp fix for compile issues to revert to old source code

   echo "switching src/SIS2 to old release until new code merge is fixed."
   cd ../SIS2; git checkout 7b1749b
   
   # go back to main directory
   cd ../../
   EXENAME=$EXENAME"_regional" #add regional to exe_name
fi

if $tide; then #[[ "$clab" = *"tide"* ]]; then
   echo "switching src/coupler to revised version including gregorian calendar..."
   cd src/coupler; git checkout lrgroup/tide_gregorian_14578f0
   cd ../../
   EXENAME=$EXENAME"_tide" #add tide to exe_name
fi

if $kw_dm18 && [[ "$clab" = *"ocean_ice_bgc"* ]]; then 
   echo "switching src/atmos_null to kw_dm18 version including hs computation..."
   cd src/atmos_null; git checkout lrgroup/kw_dm18

   echo "switching src/coupler to kw_dm18 version including hs computation..."
   cd ../coupler;     git checkout lrgroup/kw_dm18

   echo "switching src/FMS1 to kw_dm18 version including hs computation..."
   cd ../FMS1;        git checkout lrgroup/kw_dm18
   EXENAME=$EXENAME"_kw_dm18" #add kw_name to exe_name
   cd ../../
   if $tide || $regional_bgc; then
      echo "kw_dm18 only test for global ocean, not for regional bgc or tide"
      exit
   fi
fi

 
echo "Compile FMS"
mkdir -p build/intel/shared/repro/
(cd build/intel/shared/repro/; rm -f path_names; \
"$BASEDIR/src/mkmf/bin/list_paths" -l "$BASEDIR/src/FMS"; \
"$BASEDIR/src/mkmf/bin/mkmf" -t $MKF_TEMPLATE -p libfms.a -c "-Duse_libMPI -Duse_netCDF -DSPMD -DMAXFIELDMETHODS_=500" path_names)

echo "Make NETCDF "
(cd build/intel/shared/repro/; source ../../env; make clean; make NETCDF=3 REPRO=1 libfms.a -j)

echo "List Model Code paths"
BUILDDIR="build/intel/$EXENAME/repro/"
mkdir -p $BUILDDIR

if [[ "$clab" = "ocean_only" ]]; then
   (cd $BUILDDIR; rm -f path_names; \
   "$BASEDIR/src/mkmf/bin/list_paths" -v -v -v ./ $BASEDIR/src/MOM6/config_src/{infra/FMS1,memory/dynamic_symmetric,drivers/solo_driver,external} $BASEDIR/src/MOM6/pkg/GSW-Fortran/{modules,scripts,toolbox} $BASEDIR/src/MOM6/src/{*,*/*}/)

   echo "Compile Model ocean_only and make executable file"
   (cd $BUILDDIR; \
   "$BASEDIR/src/mkmf/bin/mkmf" -t $MKF_TEMPLATE -o '-I../../shared/repro' -p $EXENAME -l '-L../../shared/repro -lfms' -c '-Duse_libMPI -Duse_netCDF -DSPMD -D_USE_MOM6_DIAG -DUSE_PRECISION=2' path_names )

elif [[ "$clab" = "ocean_ice" ]]; then
   # this is the default compile for ocean-ice model which is non-bio and non-symmetrical
   (cd $BUILDDIR; rm -f path_names; \
   "$BASEDIR/src/mkmf/bin/list_paths" -v -v -v ./ $BASEDIR/src/MOM6/config_src/{infra/FMS1,memory/dynamic_symmetric,drivers/FMS_cap,external} $BASEDIR/src/MOM6/pkg/GSW-Fortran/{modules,scripts,toolbox} $BASEDIR/src/MOM6/src/{*,*/*}/ $BASEDIR/src/{atmos_null,coupler,land_null,ice_param,icebergs,SIS2,FMS/coupler,FMS/include}/) 

   echo "Compile Model ocean_ice and make executable file"
   (cd $BUILDDIR; \
   "$BASEDIR/src/mkmf/bin/mkmf" -t $MKF_TEMPLATE -o '-I../../shared/repro' -p $EXENAME -l '-L../../shared/repro -lfms' -c '-Duse_libMPI -Duse_netCDF -DSPMD -Duse_AM3_physics -D_USE_LEGACY_LAND_ -D_USE_MOM6_DIAG -DUSE_PRECISION=2' path_names )

elif [[ "$clab" = *"ocean_ice_bgc"* ]]; then
   # compile MOM6-SIS2-COBALT bgc module
   #is there a reason why we are listing all the src/external paths separately here??
   (cd $BUILDDIR; rm -f path_names; \
   "$BASEDIR/src/mkmf/bin/list_paths" -v -v -v ./ $BASEDIR/src/MOM6/config_src/{infra/FMS1,memory/dynamic_symmetric,drivers/FMS_cap,external/ODA_hooks,external/drifters,external/stochastic_physics,external/database_comms} $BASEDIR/src/MOM6/pkg/GSW-Fortran/{modules,scripts,toolbox} $BASEDIR/src/MOM6/src/{*,*/*}/ $BASEDIR/src/{atmos_null,coupler,land_null,ice_param,icebergs,SIS2,FMS/coupler,FMS/include}/ $BASEDIR/src/ocean_BGC/{generic_tracers,mocsy/src})

   echo "Compile Model ocean_ice_bgc and make executable file"
   (cd $BUILDDIR; \
   "$BASEDIR/src/mkmf/bin/mkmf" -t $MKF_TEMPLATE -o '-I../../shared/repro' -p $EXENAME -l '-L../../shared/repro -lfms' -c '-Duse_libMPI -Duse_netCDF -DSPMD -Duse_AM3_physics -D_USE_LEGACY_LAND_ -D_USE_MOM6_DIAG -D_USE_GENERIC_TRACER -DUSE_PRECISION=2' path_names )
fi

(cd $BUILDDIR; source ../../env;make clean; make NETCDF=3 $EXENAME -j)





