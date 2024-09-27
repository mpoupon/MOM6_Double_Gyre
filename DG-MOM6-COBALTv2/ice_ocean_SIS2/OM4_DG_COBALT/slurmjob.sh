#!/bin/bash 
#SBATCH --job-name simulation_name    # job name
#SBATCH --nodes 8                # node number 
#SBATCH --ntasks-per-node=128    # how many tasks per node
#SBATCH --exclusive              # don't share nodes with other users
#SBATCH --time 6:00:00           # requested time duration for job
#SBATCH --mem 500G
#SBATCH --output=LOG_HIST/slurm-%j.out  # path to save slurm log file
#SBATCH --mail-type=begin        # send email when job begins
#SBATCH --mail-type=end          # send email when job ends
#SBATCH --mail-type=fail         # send email if job fails
#SBATCH --mail-user=name@email.edu

clab='ocean_ice_bgc'  # Specify executable file (ocean_ice or ocean_ice_bgc)

year_start=2000   # Year the model should begin running. Only applies if argument 'resetwoa' is supplied.

year_end=2050     # Year the model should continue running to, inclusive. 
                  # Note that depending on months and res_months, the model could run for additional years.

months=1         # Number of months to run.
days=0            # Number of days to run.
hours=0           # Number of hours to run.

res_months=1      # Number of months between restart file output.

reset_year="2000" # Year to initiate restart run from. Only applies if argument 'resetyear' is supplied.
reset_month="01"
reset_day="001"

# List of all possible restart files for physical+bio double-gyre configuration 
# The number of MOM.res_*.nc file will change with resolution; adjust the lists as needed

rfiles_all=("coupler.intermediate.res" "coupler.res" 
            "calving.res.nc" "icebergs.res.nc" "ice_model.res.nc" 
            "ice_cobalt.res.nc" "ocean_cobalt_airsea_flux.res.nc" 
            "MOM.res_1.nc" "MOM.res_2.nc" "MOM.res_3.nc" "MOM.res_4.nc" "MOM.res_5.nc"
            "MOM.res_6.nc" "MOM.res_7.nc" "MOM.res_8.nc" "MOM.res_9.nc" "MOM.res_10.nc"
            "MOM.res_11.nc" "MOM.res_12.nc" "MOM.res_13.nc" "MOM.res_14.nc" "MOM.res_15.nc"
            "MOM.res.nc")  # all files (without timestamp)
            
rfiles_coupler=("coupler.intermediate.res" "coupler.res" 
            "calving.res.nc" "icebergs.res.nc" "ice_model.res.nc" 
            "ice_cobalt.res.nc" "ocean_cobalt_airsea_flux.res.nc")  # single coupler files 
            
rfiles_MOM=("_1.nc" "_2.nc" "_3.nc" "_4.nc" "_5.nc"
            "_6.nc" "_7.nc" "_8.nc" "_9.nc" "_10.nc"
            "_11.nc" "_12.nc" "_13.nc" "_14.nc" "_15.nc"
            ".nc")  # numbers for MOM files

############################### should be no need to edit below this line #############################################

# load module and set up environment for MOM6 running
module purge
module load intel/2021.1.2
module load intel-mpi/intel/2021.3.1
module load hdf5/intel-2021.1/intel-mpi/1.10.6
module load netcdf/intel-2021.1/hdf5-1.10.6/intel-mpi/4.7.4

# copy executable file to the current folder and srun exe file
EXECPATH=./$clab
ln -sf ../../build/intel/$clab/repro/$clab .

if [[ ! -e "RESTART" ]]; then
   mkdir -p RESTART
fi

# Set appropriate settings and namelists in input.nml based on with or without COBALT
if [ "$clab" = "ocean_ice_bgc" ]; then
        # set run with COBALT
        sed -i "/do_generic_tracer/c\            do_generic_tracer=.true." input.nml
        sed -i "/do_generic_COBALT/c\            do_generic_COBALT=.true." input.nml
        sed -i "/force_update_fluxes/c\            force_update_fluxes=.true." input.nml
        sed -i "/MOM_cobalt/c\                              'MOM_cobalt_on' /" input.nml
        echo 'running simulation with COBALT'

elif [ "$clab" = "ocean_ice" ]; then
        # set run without COBALT (ocean only)
        sed -i "/do_generic_tracer/c\            do_generic_tracer=.false." input.nml
        sed -i "/do_generic_COBALT/c\            do_generic_COBALT=.false." input.nml
        sed -i "/force_update_fluxes/c\            force_update_fluxes=.false." input.nml
        sed -i "/MOM_cobalt/c\                              'MOM_cobalt_off' /" input.nml
        echo 'running simulation with physics only'
fi

# set start date in input.nml using year_start
# make sure numbers of months is correct from months variable
sed -i "/restart_interval /c\            restart_interval = 0,${res_months},0,0,0,0" "input.nml"
sed -i "/months /c\            months = ${months}" "input.nml"
sed -i "/days /c\            days = ${days}" "input.nml"
sed -i "/hours /c\            hours = ${hours}" "input.nml"

# Prepare files to run MOM6
# Three running options: resetwoa (new start), resetyear (start from a specific MOM6 restart file), else (restart from last MOM6 simulation)
if [ "$1" = "resetwoa" ]; then
        # determine a restart run or new run in input.nml (this option is a new run)
        # n is clean new run, read initial files from WOA (path is defined in MOM_input)
        # r is restart run, read initial files from MOM6 results
        sed -i "/input_filename /c\         input_filename = 'n'" input.nml
        
        # set start date in input.nml using year_start
        sed -i "/current_date /c\            current_date = ${year_start},1,1,0,0,0" "input.nml"

        # Remove 11 restart files from INPUT folder (particularly important to remove `coupler.res`)
        for fcp in ${rfiles_all[@]}; do
            echo "remove file" $fcp "from INPUT folder"
            rm INPUT/$fcp 
        done
        rm {ocean_static.nc,ocean.stats.nc,ocean_geometry.nc,ocean.stats,sea_ice_geometry.nc,seaice.stats}        

        #prepare restart fold
        rm RESTART/*

elif [ "$1" = "resetyear" ]; then
        # determine a restart run or new run in input.nml (this option is a restart run)
        sed -i "/input_filename /c\         input_filename = 'r'" input.nml

        # Remove 11 restart files from INPUT folder (particularly important to remove `coupler.res`)
        for fcp in ${rfiles_all[@]}; do
            echo "remove file" $fcp "from INPUT folder"
            rm INPUT/$fcp 
        done
        rm {ocean_static.nc,ocean.stats.nc,ocean_geometry.nc,ocean.stats,sea_ice_geometry.nc,seaice.stats}        

        # Rename and copy appropriate restart files from RESTART folder to INPUT folder
        # Restart files for a specific year have a time stamp like: 20080101.000000.ice_model.res.nc and MOM.res_Y2008_D001_S00000_2.nc. MOM6 needs: ice_cobalt.res.nc and MOM.res_1.nc. 
        label1="${reset_year}${reset_month}01.000000"; label2="Y${reset_year}_D${reset_day}_S00000"
        # Rename and copy coupler restart files
        for fcp in ${rfiles_coupler[@]}; do
            fname_restart=$label1.$fcp; fname_input=$fcp
            echo "copy file" $fname_restart "from RESTART to" $fname_input "INPUT"
            cp RESTART/$fname_restart INPUT/$fname_input
        done
        # Rename and copy MOM6 restart files
        for fcp in ${rfiles_MOM[@]}; do
            fname_restart=MOM.res_$label2$fcp; fname_input=MOM.res$fcp
            echo "copy file" $fname_restart "from RESTART to" $fname_input "INPUT"
            cp RESTART/$fname_restart INPUT/$fname_input
        done
else
        # determine a restart run or new run in input.nml (this option is a restart run)
        sed -i "/input_filename /c\        input_filename = 'r'" input.nml

        # Copy restart files from RESTART folder to INPUT folder
        # The restart files from last simulation don't have time stamp and no need to rename them.
        for fcp in ${rfiles_all[@]}; do
            echo "copy file" $fcp "from RESTART to INPUT"
            cp RESTART/$fcp INPUT/
        done
fi
        ### start JCG - commented find_jra because I do not need the files to update ###
        # Run find_jra to edit data_table for the specific year forcing (find year from INPUT/coupler.res which is copied from RESTART folder)
        # need to edit for woa run
        #./find_jra_regional.sh
        #if [ $? -ne 0 ]; then
        #    echo "find_jra_regional.sh is wrong!"
        #    exit 1
        #fi
        ### end JCG

        # run MOM6
        srun $EXECPATH

        # report error if restart too frequently
        log_dir='LOG_HIST'
        current_dir=$(pwd)
        cd $log_dir
        #logfile=(`find -name 'slurm-*'  -mmin -30`)
        logfile=(`find -name 'slurm-*'  -mmin -15`)  # changed bc simulation 9 min - JCG
        cd $current_dir
        log_num=${#logfile[@]}
        if (( $log_num >= 3 )); then
           echo "restart too frequently, something wrong with model and please check"
           exit 1;
        fi

        # Some times the MOM6 could not write the restart files with time stamp. To solve this issue, the below script is to build new folder for restart files in each year to avoid a overwrite. Uncomment them if this issue appears
#        resfile1='RESTART/coupler.res'
#        if [ -f "$resfile1" ]; then
#           while IFS=" " read -r col1 col2 col3 remainder; do
#             year_restart=$col1; month_restart=$col2; day_restart=$col3;
#           done < $resfile1
#        else
#           echo "‘RESTART/coupler.res’: No such file or directory"
#           echo "No restart files are created in this run, please check"; exit 1;
#        fi
#        f_restart=RESTART_"$year_restart"_"$month_restart"_"$day_restart"
#        mkdir RESTART/$f_restart
#        for fcp in ${rfiles_all[@]}; do
#            echo "copy file" $fcp "from RESTART to time_stample folder"
#            cp RESTART/$fcp RESTART/$f_restart/
#        done


### Modified Jenna's addition to accommodate variable months ###
# Continue the runs by submitting a new job 
resfile1='RESTART/coupler.res'
if [ -f "$resfile1" ];then
   while IFS=" " read -r col1 col2 remainder
   do
         # Extract upcoming year from restart file (saves the first time step in upcoming year)
         year_start=$col1
   done < $resfile1
   
   # Rename the ice files as the standard output is incorrect (no longer necessary)
   echo "renaming ice_mode.res.nc"${year_start}"0101.000000.nc to "${year_start}"0101.000000.ice_model.res.nc"
   mv RESTART/ice_model.res.nc${year_start}0101.000000.nc RESTART/${year_start}0101.000000.ice_model.res.nc

    # If the last year ran (year_start - 1) is >= than year_end stop 
   if [ "$(($year_start - 1))" -ge "$year_end" ]; then
       echo "Simulation complete."
   else
       echo "Submitting new slurmjob.sh to continue simulation for year ${year_start}."

       # Submit job for new simulation
       sbatch slurmjob.sh
   fi

fi
