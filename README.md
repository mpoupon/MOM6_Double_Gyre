# MOM6 Double Gyre

This project includes multiple versions of a double-gyre ocean configuration forced by idealized atmospheric conditions and reproducing the physical and biogeochemical dynamics characteristic of the North Atlantic. The physical model used is MOM6 ([Adcroft et al. 2019](
https://doi.org/10.1029/2019MS001726)) and the biogeochemical module can be used in the original version (COBALTv2, [Stock et al. 2020](https://doi.org/10.1029/2019MS002043)) or in the version including zooplankton vertical migration (COBALTv2-DVM, Poupon et al. in review). The configuration is available at three different horizontal resolutions (85 km, 9.4 km and 3.1 km).

**The directories contain:**

- `DG-MOM6-COBALTv2`: The double gyre configuration **without** zooplankton vertical migration
- `DG-MOM6-COBALTv2-DVM`: The double gyre configuration **with** zooplankton vertical migration
- `Codes`: Codes for creating the grid, initial conditions and boundary forcing ([see below](#codes-description)).

## Directory description

Each directory has a similar structure:

- `ice_ocean_SIS2/OM4_DG_COBALT`: Contains the double-gyre configuration ([see below](#ice_ocean_sis2om4_dg_cobalt-description)).
- `src`: Source code. The physical model is located in `src/MOM6` and the biogeochemical model in `src/ocean_BGC/generic_tracers/generic_COBALT.F90`
- `compile_mom6.sh`: Bash script for compiling source code.
- `stellar-amd.mk`and `tigercpu-intel.mk`: Makefiles for automated compilation of source code. Depending on your processors, you can use one of these two files by changing the filename on line 31 in `compile_mom6.sh` (`MKF_TEMPLATE=‘$BASEDIR/filename’`).
- `tools`: sets of functions useful for analyzing the model.

## Getting started
### Choose the model
Select the model directory: `DG-MOM6-COBALTv2-DVM` file if you want to model zooplankton vertical migration  (more expensive), otherwise select `DG-MOM6-COBALTv2` (less expensive).

### Compile the code
In the model directory, make sure that the `clab` variable (line 19 in `mom6_compile.sh`) is equal to `'ocean_ice_bgc'` to model biogeochemistry. Compile the code by running the command line:
```
$ ./compile_mom6.sh
```
A new directory (`build`) should be created. To confirm that compiling was successful, check that a folder with the executable file name (`ocean_ice_bgc`) has been created (in `./build/intel/ocean_ice_bgc/repro/`).

### Set up the configuration

Navigate to the `/ice_ocean_sis2/OM4_DG_COBALT/` folder. The structure of this folder is detailed below.

1. **Copy the default model code into the main simulation folder:**
```
$ cp model_code/* .
```

The default model code is set for a horizontal resolution of 9.4 km. If you want to change to 85 km or 3.1 km, you need to replace the `MOM_input` and `SIS_input` files with those of the appropriate resolutions available in the `model_code/85km_MOMSIS` or `model_code/3km_MOMSIS folders`. You can modify the diagnostics output from the model and their frequency in the `diag_table` file.

2. **Add the required inputs (grid, initialisation and forcing) in the `./INPUT folder`:**

You can download the inputs corresponding to the model resolution from [Zenodo](https://zenodo.org/records/13847760?preview=1&token=eyJhbGciOiJIUzUxMiJ9.eyJpZCI6ImVjZGI5NjI0LTJlZjUtNGRjMi05YTVmLTNlZTZlNDRhMGMxZSIsImRhdGEiOnt9LCJyYW5kb20iOiIwZjAzZGM1Mjc2YTI1Nzg0YmJiMjM3YTYwMWE1Yjg2MiJ9.iZ9Lk5_WoRF0wc5LmT16HKlepEvsMNeSXP3Ea-Scx-wBtu9IrDN4q2CAlwSBSDgb8GFSGsQDkKptDGr-3gUbTg), or generate them yourself using the functions in `Codes` ([see section](#codes-description)). To save space if you are running multiple simulations, you can also store the input files in another folder and only use symbolic links in the `./INPUT` folder.

3. **Configure the slurm job in `slurmjob.sh`:**

Provide a simulation name, the number of nodes and tasks per node, the execution time and the amount of memory required, and an e-mail address for information about the run. e.g:
```
#SBATCH --job-name simulation_name    # job name
#SBATCH --nodes 8                # node number 
#SBATCH --ntasks-per-node=128    # how many tasks per node
#SBATCH --time 6:00:00           # requested time duration for job
#SBATCH --mem 500G
#SBATCH --mail-user=name@email.edu
```

Provide the executable file name (`'ocean_ice_bgc'`). If you initialize your simulation from the input files: the start year. If you initialize your simulation from the restart files: the year from which to start again. In both cases: the end year of the simulation, the number of months, days and hours to run and the output frequency of the restart files.

### Run a simulation

4. If you initialize your simulation from the input files.  In `/ice_ocean_sis2/OM4_DG_COBALT/` run:
```
$ sbatch slurmjob resetwoa
```

5. If you initialize your simulation from the restart files. In `/ice_ocean_sis2/OM4_DG_COBALT/` run:
```
$ sbatch slurmjob resetyear
```

## `ice_ocean_sis2/OM4_DG_COBALT` description:

#### `./INPUT/`
Folder where all input files are added.

#### `./LOG_HIST/`
Output folder for slurm logs
 
#### `./RESTART/`
Output folder for model restart files

#### `./model_code/`
Contains the model code specific to each simulation (grid resolution, with and without COBALT, lower-resolution spin up and higher-resolution simulations).

The default files are for the 9km double gyre simulation. You can find the MOM_input and SIS_input files for each resolution in their respective folders, various options for diag_table in the diag_tables folder and for field_table in the field_tables folder.

**`MOM_input`**: Specifies model parameters (SIS_input is for the ice model)

**`diag_table`**: Specifies the model output and its frequency

**`field_table`**: Specifies the initialization fields for COBALT (average profiles for spin up; spin up output for subsequent simulations) 

**`MOM_cobalt_on`** & **`MOM_cobalt_off`**: Contain the MOM_input parameters that differ when COBALT is turned on or off, including shading by plankton. Which file to use is specified in input.nml, and slurmjob.sh automatically makes the change based on the executable file specified.

**`data_table `**: Specifies the atmospheric forcing and deposition for MOM6 and COBALT

**`input.nml`**:
Specifies which models to couple and higher level options. The only options I have needed to change are as follows: 
- `input_filename`: `r` for a restart run, `n` for a new run; slurmjob.sh automatically makes the changes when not running interactively 
- `current_date`: good habit to change the date when re-initializing simulations from a spin up to keep track of the model year 
- `restart_interval`: can be changed to output restart files less frequently (an option in slurmjob.sh) 
- `calendar`: because this is an idealized simulation, every year has 365 days
- `generic_tracer_nml`: turns COBALT on and off (see relevant setting in slurmjob.sh) 

**`*_layout`** & **`*_override`**: not typically used

#### `./slurmjob.sh`

## `Codes` description:

Contains the Python Notebooks and functions required to generate all the input files for this configuration (grid, initialization, forcings). These files can also be downloaded from [Zenodo](https://zenodo.org/records/13847760?preview=1&token=eyJhbGciOiJIUzUxMiJ9.eyJpZCI6ImVjZGI5NjI0LTJlZjUtNGRjMi05YTVmLTNlZTZlNDRhMGMxZSIsImRhdGEiOnt9LCJyYW5kb20iOiIwZjAzZGM1Mjc2YTI1Nzg0YmJiMjM3YTYwMWE1Yjg2MiJ9.iZ9Lk5_WoRF0wc5LmT16HKlepEvsMNeSXP3Ea-Scx-wBtu9IrDN4q2CAlwSBSDgb8GFSGsQDkKptDGr-3gUbTg). These input files need to be added to the `ice_ocean_SIS2/OM4_DG_COBALT/INPUTS` folder.

#### `make_forcings`

- **`DG_MakeForcing_JRA.ipynb`**: Create the pressure, temperature, humidity, snow, rain and radiation forcing with a time resolution of 3 hours from the JRA55-do-v1.5 reanalysis.

- **`DG_MakeForcing_Idealized.ipynb`**: Create an idealised sinusoidal zonal wind forcing.

- **`DG_MakeForcing_ESM.ipynb`**: Create atmospheric chemical deposition forcings from ESM4 simulation outputs.

- **`DG_MakeForcing_ERA.ipynb`**: Create the high-resolution (1hr) radiation forcings needed to model the vertical migration of zooplankton from the ERA5 reanalysis.


#### `make_grid`
- **`DG_MakeGrids.ipynb`**: Create a horizontal grid with a resolution of 85km, 9.4km or 3.1km.

- **`DG_MakeHighResVertCoord.ipynb`**: Create the vertical grid for high-resolution simulations (9.4km and 3.1km).

#### `make_init`
- **`make_init_DG_init_file.ipynb`**: Create initialization files from the output of a spin-up simulation.

- **`make_init_WOA-SOCAT-ESM.ipynb`**: Create initialization files from World Ocean Atlas, SOCAT and ESM4 outputs.
