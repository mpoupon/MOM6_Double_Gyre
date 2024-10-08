!> Interface to background mixing schemes, including the Bryan and Lewis (1979)
!! which is applied via CVMix.

module MOM_bkgnd_mixing

! This file is part of MOM6. See LICENSE.md for the license.

use MOM_debugging,       only : hchksum
use MOM_diag_mediator,   only : diag_ctrl, time_type, register_diag_field
use MOM_diag_mediator,   only : post_data
use MOM_error_handler,   only : MOM_error, FATAL, WARNING, NOTE
use MOM_file_parser,     only : get_param, log_version, param_file_type
use MOM_file_parser,     only : openParameterBlock, closeParameterBlock
use MOM_forcing_type,    only : forcing
use MOM_grid,            only : ocean_grid_type
use MOM_unit_scaling,    only : unit_scale_type
use MOM_verticalGrid,    only : verticalGrid_type
use MOM_variables,       only : thermo_var_ptrs,  vertvisc_type
use MOM_intrinsic_functions, only : invcosh
use CVMix_background,    only : CVMix_init_bkgnd, CVMix_coeffs_bkgnd

implicit none ; private

#include <MOM_memory.h>

public bkgnd_mixing_init
public bkgnd_mixing_end
public calculate_bkgnd_mixing

! A note on unit descriptions in comments: MOM6 uses units that can be rescaled for dimensional
! consistency testing. These are noted in comments with units like Z, H, L, and T, along with
! their mks counterparts with notation like "a velocity [Z T-1 ~> m s-1]".  If the units
! vary with the Boussinesq approximation, the Boussinesq variant is given first.

!> Control structure including parameters for this module.
type, public :: bkgnd_mixing_cs ; private

  ! Parameters
  real    :: Bryan_Lewis_c1         !< The vertical diffusivity values for  Bryan-Lewis profile
                                    !! at |z|=D [m2 s-1]
  real    :: Bryan_Lewis_c2         !< The amplitude of variation in diffusivity for the
                                    !! Bryan-Lewis diffusivity profile [m2 s-1]
  real    :: Bryan_Lewis_c3         !< The inverse length scale for transition region in the
                                    !! Bryan-Lewis diffusivity profile [m-1]
  real    :: Bryan_Lewis_c4         !< The depth where diffusivity is Bryan_Lewis_bl1 in the
                                    !! Bryan-Lewis profile [m]
  real    :: bckgrnd_vdc1           !< Background diffusivity (Ledwell) when
                                    !! horiz_varying_background=.true. [Z2 T-1 ~> m2 s-1]
  real    :: bckgrnd_vdc_eq         !< Equatorial diffusivity (Gregg) when
                                    !! horiz_varying_background=.true. [Z2 T-1 ~> m2 s-1]
  real    :: bckgrnd_vdc_psim       !< Max. PSI induced diffusivity (MacKinnon) when
                                    !! horiz_varying_background=.true. [Z2 T-1 ~> m2 s-1]
  real    :: bckgrnd_vdc_Banda      !< Banda Sea diffusivity (Gordon) when
                                    !! horiz_varying_background=.true. [Z2 T-1 ~> m2 s-1]
  real    :: Kd_min                 !< minimum diapycnal diffusivity [Z2 T-1 ~> m2 s-1]
  real    :: Kd                     !< interior diapycnal diffusivity [Z2 T-1 ~> m2 s-1]
  real    :: omega                  !< The Earth's rotation rate [T-1 ~> s-1].
  real    :: N0_2Omega              !< ratio of the typical Buoyancy frequency to
                                    !! twice the Earth's rotation period, used with the
                                    !! Henyey scaling from the mixing
  real    :: prandtl_bkgnd          !< Turbulent Prandtl number used to convert
                                    !! vertical background diffusivity into viscosity
  real    :: Kd_tanh_lat_scale      !< A nondimensional scaling for the range of
                                    !! diffusivities with Kd_tanh_lat_fn. Valid values
                                    !! are in the range of -2 to 2; 0.4 reproduces CM2M.
  real    :: Kdml                   !< mixed layer diapycnal diffusivity [Z2 T-1 ~> m2 s-1]
                                    !! when bulkmixedlayer==.false.
  real    :: Hmix                   !< mixed layer thickness [Z ~> m] when bulkmixedlayer==.false.
  logical :: Kd_tanh_lat_fn         !< If true, use the tanh dependence of Kd_sfc on
                                    !! latitude, like GFDL CM2.1/CM2M.  There is no
                                    !! physical justification for this form, and it can
                                    !! not be used with Henyey_IGW_background.
  logical :: Bryan_Lewis_diffusivity!< If true, background vertical diffusivity
                                    !! uses Bryan-Lewis (1979) like tanh profile.
  logical :: horiz_varying_background !< If true, apply vertically uniform, latitude-dependent
                                    !! background diffusivity, as described in Danabasoglu et al., 2012
  logical :: Henyey_IGW_background  !< If true, use a simplified variant of the
             !! Henyey et al, JGR (1986) latitudinal scaling for the background diapycnal diffusivity,
             !! which gives a marked decrease in the diffusivity near the equator.  The simplification
             !! here is to assume that the in-situ stratification is the same as the reference stratificaiton.
  logical :: Henyey_IGW_background_new !< same as Henyey_IGW_background
             !! but incorporate the effect of stratification on TKE dissipation,
             !! e = f/f_0 * acosh(N/f) / acosh(N_0/f_0) * e_0
             !! where e is the TKE dissipation, and N_0 and f_0
             !! are the reference buoyancy frequency and inertial frequencies respectively.
             !! e_0 is the reference dissipation at (N_0,f_0). In the previous version, N=N_0.
             !! Additionally, the squared inverse relationship between  diapycnal diffusivities
             !! and stratification is included:
             !!
             !! kd = e/N^2
             !!
             !! where kd is the diapycnal diffusivity. This approach assumes that work done
             !! against gravity is uniformly distributed throughout the column. Whereas, kd=kd_0*e,
             !! as in the original version, concentrates buoyancy work in regions of strong stratification.
  logical :: bulkmixedlayer !< If true, a refined bulk mixed layer scheme is used
  logical :: Kd_via_Kdml_bug !< If true and KDML /= KD and a number of other higher precedence
                   !! options are not used, the background diffusivity is set incorrectly using a
                   !! bug that was introduced in March, 2018.
  logical :: debug !< If true, turn on debugging in this module
  ! Diagnostic handles and pointers
  type(diag_ctrl), pointer :: diag => NULL() !< A structure that regulates diagnostic output

  character(len=40)  :: bkgnd_scheme_str = "none" !< Background scheme identifier

end type bkgnd_mixing_cs

character(len=40)  :: mdl = "MOM_bkgnd_mixing" !< This module's name.

contains

!> Initialize the background mixing routine.
subroutine bkgnd_mixing_init(Time, G, GV, US, param_file, diag, CS)

  type(time_type),         intent(in)    :: Time       !< The current time.
  type(ocean_grid_type),   intent(in)    :: G          !< Grid structure.
  type(verticalGrid_type), intent(in)    :: GV         !< Vertical grid structure.
  type(unit_scale_type),   intent(in)    :: US         !< A dimensional unit scaling type
  type(param_file_type),   intent(in)    :: param_file !< Run-time parameter file handle
  type(diag_ctrl), target, intent(inout) :: diag       !< Diagnostics control structure.
  type(bkgnd_mixing_cs),    pointer      :: CS         !< This module's control structure.

  ! Local variables
  real :: Kv                    ! The interior vertical viscosity [Z2 T-1 ~> m2 s-1] - read to set Prandtl
                                ! number unless it is provided as a parameter
  real :: prandtl_bkgnd_comp    ! Kv/CS%Kd. Gets compared with user-specified prandtl_bkgnd.

! This include declares and sets the variable "version".
#include "version_variable.h"

  if (associated(CS)) then
    call MOM_error(WARNING, "bkgnd_mixing_init called with an associated "// &
                            "control structure.")
    return
  endif
  allocate(CS)

  ! Read parameters
  call log_version(param_file, mdl, version, &
    "Adding static vertical background mixing coefficients")

  call get_param(param_file, mdl, "KD", CS%Kd, &
                 "The background diapycnal diffusivity of density in the "//&
                 "interior. Zero or the molecular value, ~1e-7 m2 s-1, "//&
                 "may be used.", default=0.0, units="m2 s-1", scale=US%m2_s_to_Z2_T)

  call get_param(param_file, mdl, "KV", Kv, &
                 "The background kinematic viscosity in the interior. "//&
                 "The molecular value, ~1e-6 m2 s-1, may be used.", &
                 units="m2 s-1", scale=US%m2_s_to_Z2_T, fail_if_missing=.true.)

  call get_param(param_file, mdl, "KD_MIN", CS%Kd_min, &
                 "The minimum diapycnal diffusivity.", &
                 units="m2 s-1", default=0.01*CS%Kd*US%Z2_T_to_m2_s, scale=US%m2_s_to_Z2_T)

  ! The following is needed to set one of the choices of vertical background mixing

  ! BULKMIXEDLAYER is not always defined (e.g., CM2G63L), so the following line by passes
  ! the need to include BULKMIXEDLAYER in MOM_input
  CS%bulkmixedlayer = (GV%nkml > 0)
  if (CS%bulkmixedlayer) then
    ! Check that Kdml is not set when using bulk mixed layer
    call get_param(param_file, mdl, "KDML", CS%Kdml, default=-1.)
    if (CS%Kdml>0.) call MOM_error(FATAL, &
                 "bkgnd_mixing_init: KDML cannot be set when using bulk mixed layer.")
    CS%Kdml = CS%Kd ! This is not used with a bulk mixed layer, but also cannot be a NaN.
  else
    call get_param(param_file, mdl, "KDML", CS%Kdml, &
                 "If BULKMIXEDLAYER is false, KDML is the elevated "//&
                 "diapycnal diffusivity in the topmost HMIX of fluid. "//&
                 "KDML is only used if BULKMIXEDLAYER is false.", &
                 units="m2 s-1", default=CS%Kd*US%Z2_T_to_m2_s, scale=US%m2_s_to_Z2_T)
    call get_param(param_file, mdl, "HMIX_FIXED", CS%Hmix, &
                 "The prescribed depth over which the near-surface "//&
                 "viscosity and diffusivity are elevated when the bulk "//&
                 "mixed layer is not used.", units="m", scale=US%m_to_Z, fail_if_missing=.true.)
  endif

  call get_param(param_file, mdl, 'DEBUG', CS%debug, default=.False., do_not_log=.True.)

!  call openParameterBlock(param_file,'MOM_BACKGROUND_MIXING')

  call get_param(param_file, mdl, "BRYAN_LEWIS_DIFFUSIVITY", CS%Bryan_Lewis_diffusivity, &
                 "If true, use a Bryan & Lewis (JGR 1979) like tanh "//&
                 "profile of background diapycnal diffusivity with depth. "//&
                 "This is done via CVMix.", default=.false.)

  if (CS%Bryan_Lewis_diffusivity) then
    call check_bkgnd_scheme(CS, "BRYAN_LEWIS_DIFFUSIVITY")

    call get_param(param_file, mdl, "BRYAN_LEWIS_C1", CS%Bryan_Lewis_c1, &
                   "The vertical diffusivity values for Bryan-Lewis profile at |z|=D.", &
                   units="m2 s-1", fail_if_missing=.true.)

    call get_param(param_file, mdl, "BRYAN_LEWIS_C2", CS%Bryan_Lewis_c2, &
                   "The amplitude of variation in diffusivity for the Bryan-Lewis profile", &
                   units="m2 s-1", fail_if_missing=.true.)

    call get_param(param_file, mdl, "BRYAN_LEWIS_C3", CS%Bryan_Lewis_c3, &
                   "The inverse length scale for transition region in the Bryan-Lewis profile", &
                   units="m-1", fail_if_missing=.true.)

    call get_param(param_file, mdl, "BRYAN_LEWIS_C4", CS%Bryan_Lewis_c4, &
                   "The depth where diffusivity is BRYAN_LEWIS_C1 in the Bryan-Lewis profile",&
                   units="m", fail_if_missing=.true.)

  endif ! CS%Bryan_Lewis_diffusivity

  call get_param(param_file, mdl, "HORIZ_VARYING_BACKGROUND", CS%horiz_varying_background, &
                 "If true, apply vertically uniform, latitude-dependent background "//&
                 "diffusivity, as described in Danabasoglu et al., 2012", &
                 default=.false.)

  if (CS%horiz_varying_background) then
    call check_bkgnd_scheme(CS, "HORIZ_VARYING_BACKGROUND")

    call get_param(param_file, mdl, "BCKGRND_VDC1", CS%bckgrnd_vdc1, &
                   "Background diffusivity (Ledwell) when HORIZ_VARYING_BACKGROUND=True", &
                   units="m2 s-1",default = 0.16e-04, scale=US%m2_s_to_Z2_T)

    call get_param(param_file, mdl, "BCKGRND_VDC_EQ", CS%bckgrnd_vdc_eq, &
                   "Equatorial diffusivity (Gregg) when HORIZ_VARYING_BACKGROUND=True", &
                   units="m2 s-1",default = 0.01e-04, scale=US%m2_s_to_Z2_T)

    call get_param(param_file, mdl, "BCKGRND_VDC_PSIM", CS%bckgrnd_vdc_psim, &
                   "Max. PSI induced diffusivity (MacKinnon) when HORIZ_VARYING_BACKGROUND=True", &
                   units="m2 s-1",default = 0.13e-4, scale=US%m2_s_to_Z2_T)

    call get_param(param_file, mdl, "BCKGRND_VDC_BAN", CS%bckgrnd_vdc_Banda, &
                   "Banda Sea diffusivity (Gordon) when HORIZ_VARYING_BACKGROUND=True", &
                   units="m2 s-1",default = 1.0e-4, scale=US%m2_s_to_Z2_T)
  endif

  call get_param(param_file, mdl, "PRANDTL_BKGND", CS%prandtl_bkgnd, &
                 "Turbulent Prandtl number used to convert vertical "//&
                 "background diffusivities into viscosities.", &
                 units="nondim", default=1.0)

  if (CS%Bryan_Lewis_diffusivity .or. CS%horiz_varying_background) then
    prandtl_bkgnd_comp = CS%prandtl_bkgnd
    if (CS%Kd /= 0.0) prandtl_bkgnd_comp = Kv / CS%Kd

    if ( abs(CS%prandtl_bkgnd - prandtl_bkgnd_comp)>1.e-14) then
      call MOM_error(FATAL, "bkgnd_mixing_init: The provided KD, KV and PRANDTL_BKGND values "//&
                            "are incompatible. The following must hold: KD*PRANDTL_BKGND==KV")
    endif
  endif

  call get_param(param_file, mdl, "HENYEY_IGW_BACKGROUND", CS%Henyey_IGW_background, &
                 "If true, use a latitude-dependent scaling for the near "//&
                 "surface background diffusivity, as described in "//&
                 "Harrison & Hallberg, JPO 2008.", default=.false.)
  if (CS%Henyey_IGW_background) call check_bkgnd_scheme(CS, "HENYEY_IGW_BACKGROUND")


  call get_param(param_file, mdl, "HENYEY_IGW_BACKGROUND_NEW", CS%Henyey_IGW_background_new, &
                 "If true, use a better latitude-dependent scaling for the "//&
                 "background diffusivity, as described in "//&
                 "Harrison & Hallberg, JPO 2008.", default=.false.)
  if (CS%Henyey_IGW_background_new) call check_bkgnd_scheme(CS, "HENYEY_IGW_BACKGROUND_NEW")

  if (CS%Kd>0.0 .and. (trim(CS%bkgnd_scheme_str)=="BRYAN_LEWIS_DIFFUSIVITY" .or.&
                          trim(CS%bkgnd_scheme_str)=="HORIZ_VARYING_BACKGROUND" )) then
    call MOM_error(WARNING, "bkgnd_mixing_init: a nonzero constant background "//&
         "diffusivity (KD) is specified along with "//trim(CS%bkgnd_scheme_str))
  endif

  if (CS%Henyey_IGW_background) then
    call get_param(param_file, mdl, "HENYEY_N0_2OMEGA", CS%N0_2Omega, &
                  "The ratio of the typical Buoyancy frequency to twice "//&
                  "the Earth's rotation period, used with the Henyey "//&
                  "scaling from the mixing.", units="nondim", default=20.0)
    call get_param(param_file, mdl, "OMEGA", CS%omega, &
                 "The rotation rate of the earth.", units="s-1", &
                 default=7.2921e-5, scale=US%T_to_s)
  endif

  call get_param(param_file, mdl, "KD_TANH_LAT_FN", CS%Kd_tanh_lat_fn, &
                 "If true, use a tanh dependence of Kd_sfc on latitude, "//&
                 "like CM2.1/CM2M.  There is no physical justification "//&
                 "for this form, and it can not be used with "//&
                 "HENYEY_IGW_BACKGROUND.", default=.false.)

  if (CS%Kd_tanh_lat_fn) &
    call get_param(param_file, mdl, "KD_TANH_LAT_SCALE", CS%Kd_tanh_lat_scale, &
                 "A nondimensional scaling for the range ofdiffusivities "//&
                 "with KD_TANH_LAT_FN. Valid values are in the range of "//&
                 "-2 to 2; 0.4 reproduces CM2M.", units="nondim", default=0.0)

  if (CS%Henyey_IGW_background .and. CS%Kd_tanh_lat_fn) call MOM_error(FATAL, &
    "MOM_bkgnd_mixing: KD_TANH_LAT_FN can not be used with HENYEY_IGW_BACKGROUND.")

  CS%Kd_via_Kdml_bug = .false.
  if ((CS%Kd /= CS%Kdml) .and. .not.(CS%Kd_tanh_lat_fn .or. CS%bulkmixedlayer .or. &
                                     CS%Henyey_IGW_background .or. CS%Henyey_IGW_background_new .or. &
                                     CS%horiz_varying_background .or. CS%Bryan_Lewis_diffusivity)) then
    call get_param(param_file, mdl, "KD_BACKGROUND_VIA_KDML_BUG", CS%Kd_via_Kdml_bug, &
                 "If true and KDML /= KD and several other conditions apply, the background "//&
                 "diffusivity is set incorrectly using a bug that was introduced in March, 2018.", &
                 default=.true.)  ! The default should be changed to false and this parameter obsoleted.
  endif

!  call closeParameterBlock(param_file)

end subroutine bkgnd_mixing_init

!> Calculates the vertical background diffusivities/viscosities
subroutine calculate_bkgnd_mixing(h, tv, N2_lay, Kd_lay, Kd_int, Kv_bkgnd, j, G, GV, US, CS)

  type(ocean_grid_type),                     intent(in)    :: G   !< Grid structure.
  type(verticalGrid_type),                   intent(in)    :: GV  !< Vertical grid structure.
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h   !< Layer thickness [H ~> m or kg m-2].
  type(thermo_var_ptrs),                     intent(in)    :: tv  !< Thermodynamics structure.
  real, dimension(SZI_(G),SZK_(GV)),         intent(in)    :: N2_lay !< squared buoyancy frequency associated
                                                                  !! with layers [T-2 ~> s-2]
  real, dimension(SZI_(G),SZK_(GV)),         intent(out)   :: Kd_lay !< The background diapycnal diffusivity
                                                                  !! of each layer [Z2 T-1 ~> m2 s-1].
  real, dimension(SZI_(G),SZK_(GV)+1),       intent(out)   :: Kd_int !< The background diapycnal diffusivity
                                                                  !! of each interface [Z2 T-1 ~> m2 s-1].
  real, dimension(SZI_(G),SZK_(GV)+1),       intent(out)   :: Kv_bkgnd !< The background vertical viscosity at
                                                                  !! each interface [Z2 T-1 ~> m2 s-1]
  integer,                                   intent(in)    :: j   !< Meridional grid index
  type(unit_scale_type),                     intent(in)    :: US  !< A dimensional unit scaling type
  type(bkgnd_mixing_cs),                     pointer       :: CS  !< The control structure returned by
                                                                  !! a previous call to bkgnd_mixing_init.

  ! local variables
  real, dimension(SZK_(GV)+1) :: depth_int  !< Distance from surface of the interfaces [m]
  real, dimension(SZK_(GV)+1) :: Kd_col     !< Diffusivities at the interfaces [m2 s-1]
  real, dimension(SZK_(GV)+1) :: Kv_col     !< Viscosities at the interfaces [m2 s-1]
  real, dimension(SZI_(G))    :: Kd_sfc     !< Surface value of the diffusivity [Z2 T-1 ~> m2 s-1]
  real, dimension(SZI_(G))    :: depth      !< Distance from surface of an interface [Z ~> m]
  real :: depth_c    !< depth of the center of a layer [Z ~> m]
  real :: I_Hmix     !< inverse of fixed mixed layer thickness [Z-1 ~> m-1]
  real :: I_2Omega   !< 1/(2 Omega) [T ~> s]
  real :: N_2Omega   !  The ratio of the stratification to the Earth's rotation rate [nondim]
  real :: N02_N2     !  The ratio a reference stratification to the actual stratification [nondim]
  real :: I_x30      !< 2/acos(2) = 1/(sin(30 deg) * acosh(1/sin(30 deg)))
  real :: deg_to_rad !< factor converting degrees to radians, pi/180.
  real :: abs_sinlat !< absolute value of sine of latitude [nondim]
  real :: min_sinlat ! The minimum value of the sine of latitude [nondim]
  real :: bckgrnd_vdc_psin !< PSI diffusivity in northern hemisphere [Z2 T-1 ~> m2 s-1]
  real :: bckgrnd_vdc_psis !< PSI diffusivity in southern hemisphere [Z2 T-1 ~> m2 s-1]
  integer :: i, k, is, ie, js, je, nz

  is  = G%isc ; ie  = G%iec ; js  = G%jsc ; je  = G%jec ; nz = GV%ke

  ! set some parameters
  deg_to_rad = atan(1.0)/45.0 ! = PI/180
  min_sinlat = 1.e-10

  ! Start with a constant value that may be replaced below.
  Kd_lay(:,:) = CS%Kd
  Kv_bkgnd(:,:) = 0.0

  ! Set up the background diffusivity.
  if (CS%Bryan_Lewis_diffusivity) then

    do i=is,ie
      depth_int(1) = 0.0
      do k=2,nz+1
        depth_int(k) = depth_int(k-1) + GV%H_to_m*h(i,j,k-1)
      enddo

      call CVMix_init_bkgnd(max_nlev=nz, &
                            zw = depth_int(:), &  !< interface depths relative to the surface in m, must be positive.
                            bl1 = CS%Bryan_Lewis_c1, &
                            bl2 = CS%Bryan_Lewis_c2, &
                            bl3 = CS%Bryan_Lewis_c3, &
                            bl4 = CS%Bryan_Lewis_c4, &
                            prandtl = CS%prandtl_bkgnd)

      Kd_col(:) = 0.0 ; Kv_col(:) = 0.0  ! Is this line necessary?
      call CVMix_coeffs_bkgnd(Mdiff_out=Kv_col, Tdiff_out=Kd_col, nlev=nz, max_nlev=nz)

      ! Update Kd and Kv.
      do K=1,nz+1
        Kv_bkgnd(i,K) = US%m2_s_to_Z2_T*Kv_col(K)
        Kd_int(i,K) = US%m2_s_to_Z2_T*Kd_col(K)
      enddo
      do k=1,nz
        Kd_lay(i,k) = Kd_lay(i,k) + 0.5 * US%m2_s_to_Z2_T * (Kd_col(K) + Kd_col(K+1))
      enddo
    enddo ! i loop

  elseif (CS%horiz_varying_background) then
    !### Note that there are lots of hard-coded parameters (mostly latitudes and longitudes) here.
    do i=is,ie
      bckgrnd_vdc_psis = CS%bckgrnd_vdc_psim * exp(-(0.4*(G%geoLatT(i,j)+28.9))**2)
      bckgrnd_vdc_psin = CS%bckgrnd_vdc_psim * exp(-(0.4*(G%geoLatT(i,j)-28.9))**2)
      Kd_int(i,1) = (CS%bckgrnd_vdc_eq + bckgrnd_vdc_psin) + bckgrnd_vdc_psis

      if (G%geoLatT(i,j) < -10.0) then
        Kd_int(i,1) = Kd_int(i,1) + CS%bckgrnd_vdc1
      elseif (G%geoLatT(i,j) <= 10.0) then
        Kd_int(i,1) = Kd_int(i,1) + CS%bckgrnd_vdc1 * (G%geoLatT(i,j)/10.0)**2
      else
        Kd_int(i,1) = Kd_int(i,1) + CS%bckgrnd_vdc1
      endif

      ! North Banda Sea
      if ( (G%geoLatT(i,j) < -1.0)  .and. (G%geoLatT(i,j) > -4.0) .and. &
           ( mod(G%geoLonT(i,j)+360.0,360.0) > 103.0) .and. &
           ( mod(G%geoLonT(i,j)+360.0,360.0) < 134.0) ) then
        Kd_int(i,1) = CS%bckgrnd_vdc_Banda
      endif

      ! Middle Banda Sea
      if ( (G%geoLatT(i,j) <= -4.0) .and. (G%geoLatT(i,j) > -7.0) .and. &
           ( mod(G%geoLonT(i,j)+360.0,360.0) > 106.0) .and. &
           ( mod(G%geoLonT(i,j)+360.0,360.0) < 140.0) ) then
        Kd_int(i,1) = CS%bckgrnd_vdc_Banda
      endif

      ! South Banda Sea
      if ( (G%geoLatT(i,j) <= -7.0) .and. (G%geoLatT(i,j) > -8.3) .and. &
           ( mod(G%geoLonT(i,j)+360.0,360.0) > 111.0) .and. &
           ( mod(G%geoLonT(i,j)+360.0,360.0) < 142.0) ) then
        Kd_int(i,1) = CS%bckgrnd_vdc_Banda
      endif

    enddo
    ! Update interior values of Kd and Kv (uniform profile; no interpolation needed)
    do K=1,nz+1 ; do i=is,ie
      Kd_int(i,K) = Kd_int(i,1)
      Kv_bkgnd(i,K) = Kd_int(i,1) * CS%prandtl_bkgnd
    enddo ; enddo
    do k=1,nz ; do i=is,ie
      Kd_lay(i,k) = Kd_int(i,1)
    enddo ; enddo

  elseif (CS%Henyey_IGW_background_new) then
    I_x30 = 2.0 / invcosh(CS%N0_2Omega*2.0) ! This is evaluated at 30 deg.
    I_2Omega = 0.5 / CS%omega
    do k=1,nz ; do i=is,ie
      abs_sinlat = max(min_sinlat, abs(sin(G%geoLatT(i,j)*deg_to_rad)))
      N_2Omega = max(abs_sinlat, sqrt(N2_lay(i,k))*I_2Omega)
      N02_N2 = (CS%N0_2Omega/N_2Omega)**2
      Kd_lay(i,k) = max(CS%Kd_min, CS%Kd * &
           ((abs_sinlat * invcosh(N_2Omega/abs_sinlat)) * I_x30)*N02_N2)
    enddo ; enddo
    ! Update Kd_int and Kv_bkgnd, based on Kd_lay.  These might be just used for diagnostic purposes.
    do i=is,ie
      Kd_int(i,1) = 0.0; Kv_bkgnd(i,1) = 0.0
      Kd_int(i,nz+1) = 0.0; Kv_bkgnd(i,nz+1) = 0.0
    enddo
    do K=2,nz ; do i=is,ie
      Kd_int(i,K) = 0.5*(Kd_lay(i,k-1) + Kd_lay(i,k))
      Kv_bkgnd(i,K) = Kd_int(i,K) * CS%prandtl_bkgnd
    enddo ; enddo
  else
    ! Set a potentially spatially varying surface value of diffusivity.
    if (CS%Henyey_IGW_background) then
      I_x30 = 2.0 / invcosh(CS%N0_2Omega*2.0) ! This is evaluated at 30 deg.
      do i=is,ie
        abs_sinlat = abs(sin(G%geoLatT(i,j)*deg_to_rad))
        Kd_sfc(i) = max(CS%Kd_min, CS%Kd * &
             ((abs_sinlat * invcosh(CS%N0_2Omega / max(min_sinlat, abs_sinlat))) * I_x30) )
      enddo
    elseif (CS%Kd_tanh_lat_fn) then
      do i=is,ie
        !   The transition latitude and latitude range are hard-scaled here, since
        ! this is not really intended for wide-spread use, but rather for
        ! comparison with CM2M / CM2.1 settings.
        Kd_sfc(i) = max(CS%Kd_min, CS%Kd * (1.0 + &
            CS%Kd_tanh_lat_scale * 0.5*tanh((abs(G%geoLatT(i,j)) - 35.0)/5.0) ))
      enddo
    else ! Use a spatially constant surface value.
      do i=is,ie
        Kd_sfc(i) = CS%Kd
      enddo
    endif

    ! Now set background diffusivies based on these surface values, possibly with vertical structure.
    if ((.not.CS%bulkmixedlayer) .and. (CS%Kd /= CS%Kdml)) then
      ! This is a crude way to put in a diffusive boundary layer without an explicit boundary
      ! layer turbulence scheme.  It should not be used for any realistic ocean models.
      I_Hmix = 1.0 / (CS%Hmix + GV%H_subroundoff*GV%H_to_Z)
      do i=is,ie ; depth(i) = 0.0 ; enddo
      do k=1,nz ; do i=is,ie
        depth_c = depth(i) + 0.5*GV%H_to_Z*h(i,j,k)
        if (CS%Kd_via_Kdml_bug) then
          ! These two lines should update Kd_lay, not Kd_int.  They were correctly working on the
          ! same variables until MOM6 commit 7a818716 (PR#750), which was added on March 26, 2018.
          if (depth_c <= CS%Hmix) then ; Kd_int(i,K) = CS%Kdml
          elseif (depth_c >= 2.0*CS%Hmix) then ; Kd_int(i,K) = Kd_sfc(i)
          else
            Kd_lay(i,k) = ((Kd_sfc(i) - CS%Kdml) * I_Hmix) * depth_c + (2.0*CS%Kdml - Kd_sfc(i))
          endif
        else
          if (depth_c <= CS%Hmix) then ; Kd_lay(i,k) = CS%Kdml
          elseif (depth_c >= 2.0*CS%Hmix) then ; Kd_lay(i,k) = Kd_sfc(i)
          else
            Kd_lay(i,k) = ((Kd_sfc(i) - CS%Kdml) * I_Hmix) * depth_c + (2.0*CS%Kdml - Kd_sfc(i))
          endif
        endif

        depth(i) = depth(i) + GV%H_to_Z*h(i,j,k)
      enddo ; enddo

    else ! There is no vertical structure to the background diffusivity.
      do k=1,nz ; do i=is,ie
        Kd_lay(i,k) = Kd_sfc(i)
      enddo ; enddo
    endif

    ! Update Kd_int and Kv_bkgnd, based on Kd_lay.  These might be just used for diagnostic purposes.
    do i=is,ie
      Kd_int(i,1) = 0.0; Kv_bkgnd(i,1) = 0.0
      Kd_int(i,nz+1) = 0.0; Kv_bkgnd(i,nz+1) = 0.0
    enddo
    do K=2,nz ; do i=is,ie
      Kd_int(i,K) = 0.5*(Kd_lay(i,k-1) + Kd_lay(i,k))
      Kv_bkgnd(i,K) = Kd_int(i,K) * CS%prandtl_bkgnd
    enddo ; enddo
  endif

end subroutine calculate_bkgnd_mixing

!> Reads the parameter "USE_CVMix_BACKGROUND" and returns state.
!! This function allows other modules to know whether this parameterization will
!! be used without needing to duplicate the log entry.
logical function CVMix_bkgnd_is_used(param_file)
  type(param_file_type), intent(in) :: param_file !< A structure to parse for run-time parameters
  call get_param(param_file, mdl, "USE_CVMix_BACKGROUND", CVMix_bkgnd_is_used, &
                 default=.false., do_not_log=.true.)

end function CVMix_bkgnd_is_used

!> Sets CS%bkgnd_scheme_str to check whether multiple background diffusivity schemes are activated.
!! The string is also for error/log messages.
subroutine check_bkgnd_scheme(CS, str)
  type(bkgnd_mixing_cs), pointer :: CS  !< Control structure
  character(len=*), intent(in)   :: str !< Background scheme identifier deducted from MOM_input
                                        !! parameters

  if (trim(CS%bkgnd_scheme_str)=="none") then
    CS%bkgnd_scheme_str = str
  else
    call MOM_error(FATAL, "bkgnd_mixing_init: Cannot activate both "//trim(str)//" and "//&
                   trim(CS%bkgnd_scheme_str)//".")
  endif

end subroutine

!> Clear pointers and dealocate memory
subroutine bkgnd_mixing_end(CS)
  type(bkgnd_mixing_cs), pointer :: CS !< Control structure for this module that
                                       !! will be deallocated in this subroutine

  if (.not. associated(CS)) return
  deallocate(CS)

end subroutine bkgnd_mixing_end


end module MOM_bkgnd_mixing
