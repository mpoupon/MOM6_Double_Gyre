# MOM6 Double Gyre

This project includes multiple versions of a double-gyre ocean configuration forced by idealized atmospheric conditions and reproducing the physical and biogeochemical dynamics characteristic of the North Atlantic. The physical model used is MOM6 ([Adcroft et al. 2019](
https://doi.org/10.1029/2019MS001726)) and the biogeochemical module can be used in the original version (COBALTv2, [Stock et al. 2020](https://doi.org/10.1029/2019MS002043)) or in the version including zooplankton vertical migration (COBALTv2-DVM, Poupon et al. in review). The configuration is available at three different horizontal resolutions (85 km, 9.4 km and 3.1 km).

**The directories contain:**

- `DG-MOM6-COBALTv2`: The double gyre configuration **without** zooplankton vertical migration
- `DG-MOM6-COBALTv2-DVM`: The double gyre configuration **with** zooplankton vertical migration
- `Codes`: Codes for creating the grid, initial conditions and boundary forcing.

## Directory description

Each directory has a similar structure:

- `ice_ocean_SIS2/OM4_DG_COBALT`: Contains the double-gyre configuration ([see below](#structure) for details).
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

You can download the inputs corresponding to the model resolution from [Zenodo](https://doi.org/10.5281/zenodo.13847760), or generate them yourself using the code available in `INPUT/code`. To save space if you are running multiple simulations, you can also store the input files in another folder and only use symbolic links in the `./INPUT` folder.

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

## `ice_ocean_sis2/OM4_DG_COBALT` structure:
<a name="structure"></a>

#### `./INPUT/`

#### `./INPUT/code/`
Contains the Python Notebooks and functions required to generate all the input files for this configuration:

`DG_CalcForcings.ipynb`
Calculates the monthly/3-hourly zonal averages to create the forcing files 
zonal averages are saved in `./INPUT/ZonalMeans/ `

`DG_GridForcings.ipynb `
Grids the zonal averages by repeating them at every point of longitude. It must be preceded by `DG_CalcForcings.ipynb`. Note that precipitation is scaled by the ratio of ocean in our model vs. in the North Atlantic Ocean, which uses `model_ocean_widths.nc` (calculated using `DG_CalcOceWidth_ModAtl.m`) gridded forcing files are saved in `./INPUT/`, where they will be read by the model

`DG_InitializationFiles.ipynb`
Creates initialization files for the 1° spin up run by calculating averaged profiles and repeating them throughout the domain

`DG_InitializationFiles_HiResRuns.ipynb`
Creates initialization files for the higher resolution runs using output from the spin up. 

`DG_MakeGrids.ipynb`
Creates the grids required for the 1°, 1/9° and 1/27° simulations. An untraceable formatting issue in the Python code prevents the files from being used with FMS to generate the additional and necessary grid files. DG_MakeGrids.ipynb must therefore be followed by two Matlab scripts: `FixFormat_hgrid.m` and `FixFormat_topog.m`.

`DG_MakeGrids.ipynb`
The initial grid files (`DG_hgrid_*deg*.nc`, `DG_topog_*deg*.nc`, and `DG_geothermal0_*deg_py.nc`) are saved in `./INPUT/DG_*deg/make_mask_mosaic_DG_*deg.sh` must then be run from within `./INPUT/DG_*deg/`: 
```
$ ./make_mask_mosaic_DG_*deg.sh
```

`DG_MakeHighResVertCoord.ipynb`

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
