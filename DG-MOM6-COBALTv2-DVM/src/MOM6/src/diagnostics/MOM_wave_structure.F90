!> Vertical structure functions for first baroclinic mode wave speed
module MOM_wave_structure

! This file is part of MOM6. See LICENSE.md for the license.

!  By Benjamin Mater & Robert Hallberg, 2015

! The subroutine in this module calculates the vertical structure
! functions of the first baroclinic mode internal wave speed.
! Calculation of interface values is the same as done in
! MOM_wave_speed by Hallberg, 2008.

use MOM_debugging,     only : isnan => is_NaN
use MOM_checksums,     only : chksum0, hchksum
use MOM_diag_mediator, only : post_data, query_averaging_enabled, diag_ctrl
use MOM_diag_mediator, only : register_diag_field, safe_alloc_ptr, time_type
use MOM_EOS,           only : calculate_density_derivs
use MOM_error_handler, only : MOM_error, FATAL, WARNING
use MOM_file_parser,   only : log_version, param_file_type, get_param
use MOM_grid,          only : ocean_grid_type
use MOM_unit_scaling,  only : unit_scale_type
use MOM_variables,     only : thermo_var_ptrs
use MOM_verticalGrid,  only : verticalGrid_type
use regrid_solvers, only : solve_diag_dominant_tridiag

implicit none ; private

#include <MOM_memory.h>

public wave_structure, wave_structure_init

! A note on unit descriptions in comments: MOM6 uses units that can be rescaled for dimensional
! consistency testing. These are noted in comments with units like Z, H, L, and T, along with
! their mks counterparts with notation like "a velocity [Z T-1 ~> m s-1]".  If the units
! vary with the Boussinesq approximation, the Boussinesq variant is given first.

!> The control structure for the MOM_wave_structure module
type, public :: wave_structure_CS ; !private
  logical :: initialized = .false. !< True if this control structure has been initialized.
  type(diag_ctrl), pointer :: diag => NULL() !< A structure that is used to
                                   !! regulate the timing of diagnostic output.
  real, allocatable, dimension(:,:,:) :: w_strct
                                   !< Vertical structure of vertical velocity (normalized) [nondim].
  real, allocatable, dimension(:,:,:) :: u_strct
                                   !< Vertical structure of horizontal velocity (normalized and
                                   !! divided by layer thicknesses) [Z-1 ~> m-1].
  real, allocatable, dimension(:,:,:) :: W_profile
                                   !< Vertical profile of w_hat(z), where
                                   !! w(x,y,z,t) = w_hat(z)*exp(i(kx+ly-freq*t)) is the full time-
                                   !! varying vertical velocity with w_hat(z) = W0*w_strct(z) [Z T-1 ~> m s-1].
  real, allocatable, dimension(:,:,:) :: Uavg_profile
                                   !< Vertical profile of the magnitude of horizontal velocity,
                                   !! (u^2+v^2)^0.5, averaged over a period [L T-1 ~> m s-1].
  real, allocatable, dimension(:,:,:) :: z_depths
                                   !< Depths of layer interfaces [Z ~> m].
  real, allocatable, dimension(:,:,:) :: N2
                                   !< Squared buoyancy frequency at each interface [T-2 ~> s-2].
  integer, allocatable, dimension(:,:):: num_intfaces
                                   !< Number of layer interfaces (including surface and bottom) [nondim].
  real    :: int_tide_source_x     !< X Location of generation site
                                   !! for internal tide for testing (BDM)
  real    :: int_tide_source_y     !< Y Location of generation site
                                   !! for internal tide for testing (BDM)
  logical :: debug                 !< debugging prints

end type wave_structure_CS

contains

!>  This subroutine determines the internal wave velocity structure for any mode.
!!
!! This subroutine solves for the eigen vector [vertical structure, e(k)] associated with
!! the first baroclinic mode speed [i.e., smallest eigen value (lam = 1/c^2)] of the
!! system d2e/dz2 = -(N2/cn2)e, or (A-lam*I)e = 0, where A = -(1/N2)(d2/dz2), lam = 1/c^2,
!! and I is the identity matrix. 2nd order discretization in the vertical lets this system
!! be represented as
!!
!!   -Igu(k)*e(k-1) + (Igu(k)+Igl(k)-lam)*e(k) - Igl(k)*e(k+1) = 0.0
!!
!! with rigid lid boundary conditions e(1) = e(nz+1) = 0.0 giving
!!
!!   (Igu(2)+Igl(2)-lam)*e(2) - Igl(2)*e(3) = 0.0
!!   -Igu(nz)*e(nz-1) + (Igu(nz)+Igl(nz)-lam)*e(nz) = 0.0
!!
!! where, upon noting N2 = reduced gravity/layer thickness, we get
!!    Igl(k) = 1.0/(gprime(k)*H(k)) ; Igu(k) = 1.0/(gprime(k)*H(k-1))
!!
!! The eigen value for this system is approximated using "wave_speed." This subroutine uses
!! these eigen values (mode speeds) to estimate the corresponding eigen vectors (velocity
!! structure) using the "inverse iteration with shift" method. The algorithm is
!!
!!   Pick a starting vector reasonably close to mode structure and with unit magnitude, b_guess
!!   For n=1,2,3,...
!!     Solve (A-lam*I)e = e_guess for e
!!     Set e_guess=e/|e| and repeat, with each iteration refining the estimate of e
subroutine wave_structure(h, tv, G, GV, US, cn, ModeNum, freq, CS, En, full_halos)
  type(ocean_grid_type),                    intent(in)  :: G  !< The ocean's grid structure.
  type(verticalGrid_type),                  intent(in)  :: GV !< The ocean's vertical grid structure.
  type(unit_scale_type),                    intent(in)  :: US !< A dimensional unit scaling type
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)  :: h  !< Layer thicknesses [H ~> m or kg m-2]
  type(thermo_var_ptrs),                    intent(in)  :: tv !< A structure pointing to various
                                                              !! thermodynamic variables.
  real, dimension(SZI_(G),SZJ_(G)),         intent(in)  :: cn !< The (non-rotational) mode internal
                                                              !! gravity wave speed [L T-1 ~> m s-1].
  integer,                                  intent(in)  :: ModeNum !< Mode number
  real,                                     intent(in)  :: freq !< Intrinsic wave frequency [T-1 ~> s-1].
  type(wave_structure_CS),                  intent(inout) :: CS !< Wave structure control struct
  real, dimension(SZI_(G),SZJ_(G)), &
                                  optional, intent(in)  :: En !< Internal wave energy density [R Z3 T-2 ~> J m-2]
  logical,                        optional, intent(in)  :: full_halos !< If true, do the calculation
                                                              !! over the entire computational domain.
  ! Local variables
  real, dimension(SZK_(GV)+1) :: &
    dRho_dT, &    !< Partial derivative of density with temperature [R C-1 ~> kg m-3 degC-1]
    dRho_dS, &    !< Partial derivative of density with salinity [R S-1 ~> kg m-3 ppt-1]
    pres, &       !< Interface pressure [R L2 T-2 ~> Pa]
    T_int, &      !< Temperature interpolated to interfaces [C ~> degC]
    S_int, &      !< Salinity interpolated to interfaces [S ~> ppt]
    gprime        !< The reduced gravity across each interface [L2 Z-1 T-2 ~> m s-2].
  real, dimension(SZK_(GV)) :: &
    Igl, Igu      !< The inverse of the reduced gravity across an interface times
                  !< the thickness of the layer below (Igl) or above (Igu) it [T2 L-2 ~> s2 m-2].
  real, dimension(SZK_(GV),SZI_(G)) :: &
    Hf, &         !< Layer thicknesses after very thin layers are combined [Z ~> m]
    Tf, &         !< Layer temperatures after very thin layers are combined [C ~> degC]
    Sf, &         !< Layer salinities after very thin layers are combined [S ~> ppt]
    Rf            !< Layer densities after very thin layers are combined [R ~> kg m-3]
  real, dimension(SZK_(GV)) :: &
    Hc, &         !< A column of layer thicknesses after convective instabilities are removed [Z ~> m]
    Tc, &         !< A column of layer temperatures after convective instabilities are removed [C ~> degC]
    Sc, &         !< A column of layer salinities after convective instabilities are removed [S ~> ppt]
    Rc            !< A column of layer densities after convective instabilities are removed [R ~> kg m-3]
  real, dimension(SZI_(G),SZJ_(G)) :: &
    htot              !< The vertical sum of the thicknesses [Z ~> m]
  real :: lam         !< inverse of wave speed squared [T2 L-2 ~> s2 m-2]
  real :: min_h_frac  !< fractional (per layer) minimum thickness [nondim]
  real :: Z_to_pres   !< A conversion factor from thicknesses to pressure [R L2 T-2 Z-1 ~> Pa m-1]
  real, dimension(SZI_(G)) :: &
    hmin, &        !< Thicknesses [Z ~> m]
    H_here, &      !< A thickness [Z ~> m]
    HxT_here, &    !< A layer integrated temperature [C Z ~> degC m]
    HxS_here, &    !< A layer integrated salinity [S Z ~> ppt m]
    HxR_here       !< A layer integrated density [R Z ~> kg m-2]
  real :: I_Hnew   !< The inverse of a new layer thickness [Z-1 ~> m-1]
  real :: drxh_sum !< The sum of density differences across interfaces times thicknesses [R Z ~> kg m-2]
  real, parameter :: tol1  = 0.0001, tol2 = 0.001
  real :: g_Rho0  !< G_Earth/Rho0 in [L2 Z-1 T-2 R-1 ~> m4 s-2 kg-1].
  ! real :: rescale, I_rescale
  integer :: kf(SZI_(G))
  integer, parameter :: max_itt = 1 !< number of times to iterate in solving for eigenvector
  real :: cg_subRO        !< A tiny wave speed to prevent division by zero [L T-1 ~> m s-1]
  real, parameter    :: a_int = 0.5 !< value of normalized integral: \int(w_strct^2)dz = a_int [nondim]
  real               :: I_a_int     !< inverse of a_int [nondim]
  real               :: f2          !< squared Coriolis frequency [T-2 ~> s-2]
  real               :: Kmag2       !< magnitude of horizontal wave number squared [L-2 ~> m-2]
  real               :: emag2       ! The sum of the squared magnitudes of the guesses [nondim]
  real               :: pi_htot     ! The gravest vertical wavenumber in this column [Z-1 ~> m-1]
  real               :: renorm      ! A renormalization factor [nondim]
  logical            :: use_EOS     !< If true, density is calculated from T & S using an
                                    !! equation of state.

  ! local representations of variables in CS; note,
  ! not all rows will be filled if layers get merged!
  real, dimension(SZK_(GV)+1) :: w_strct      !< Vertical structure of vertical velocity (normalized) [nondim].
  real, dimension(SZK_(GV)+1) :: u_strct      !< Vertical structure of horizontal velocity (normalized and
                                              !! divided by layer thicknesses) [Z-1 ~> m-1].
  real, dimension(SZK_(GV)+1) :: W_profile    !< Vertical profile of w_hat(z) = W0*w_strct(z) [Z T-1 ~> m s-1].
  real, dimension(SZK_(GV)+1) :: Uavg_profile !< Vertical profile of the magnitude of
                                              !! horizontal velocity [L T-1 ~> m s-1].
  real, dimension(SZK_(GV)+1) :: z_int        !< Integrated depth [Z ~> m]
  real, dimension(SZK_(GV)+1) :: N2           !< Squared buoyancy frequency at each interface [T-2 ~> s-2].
  real, dimension(SZK_(GV)+1) :: w_strct2     !< squared values [nondim]
  real, dimension(SZK_(GV)+1) :: u_strct2     !< squared values [Z-2 ~> m-2]
  real, dimension(SZK_(GV))   :: dz           !< thicknesses of merged layers (same as Hc I hope) [Z ~> m]
  ! real, dimension(SZK_(GV)+1) :: dWdz_profile !< profile of dW/dz times total depth [Z T-1 ~> m s-1]
  real                        :: w2avg   !< average of squared vertical velocity structure function [Z ~> m]
  real                        :: int_dwdz2 !< Vertical integral of the square of u_strct [Z-1 ~> m-1]
  real                        :: int_w2   !< Vertical integral of the square of w_strct [Z ~> m]
  real                        :: int_N2w2 !< Vertical integral of N2 [Z T-2 ~> m s-2]
  real                        :: KE_term !< terms in vertically averaged energy equation [R Z ~> kg m-2]
  real                        :: PE_term !< terms in vertically averaged energy equation [R Z ~> kg m-2]
  real                        :: W0      !< A vertical velocity magnitude [Z T-1 ~> m s-1]
  real                        :: U_mag   !< A horizontal velocity magnitude times the depth of the
                                         !! ocean [Z L T-1 ~> m2 s-1]
  real, dimension(SZK_(GV)-1) :: lam_z   !< product of eigen value and gprime(k); one value for each
                                         !< interface (excluding surface and bottom) [Z-1 ~> m-1]
  real, dimension(SZK_(GV)-1) :: a_diag  !< upper diagonal of tridiagonal matrix; one value for each
                                         !< interface (excluding surface and bottom) [Z-1 ~> m-1]
  real, dimension(SZK_(GV)-1) :: c_diag  !< lower diagonal of tridiagonal matrix; one value for each
                                         !< interface (excluding surface and bottom) [Z-1 ~> m-1]
  real, dimension(SZK_(GV)-1) :: b_dom   !< Matrix center diagonal offset from a_diag + c_diag; one value
                                         !< for each interface (excluding surface and bottom) [Z-1 ~> m-1]
  real, dimension(SZK_(GV)-1) :: e_guess !< guess at eigen vector with unit amplitude (for TDMA) [nondim]
  real, dimension(SZK_(GV)-1) :: e_itt   !< improved guess at eigen vector (from TDMA) [nondim]
  real    :: Pi   ! 3.1415926535... [nondim]
  integer :: i, j, k, k2, kc, itt, is, ie, js, je, nz, nzm, row, ig, jg, ig_stop, jg_stop

  is = G%isc ; ie = G%iec ; js = G%jsc ; je = G%jec ; nz = GV%ke
  I_a_int = 1/a_int

  if (.not. CS%initialized) call MOM_error(FATAL, "MOM_wave_structure: "// &
         "Module must be initialized before it is used.")

  if (present(full_halos)) then ; if (full_halos) then
    is = G%isd ; ie = G%ied ; js = G%jsd ; je = G%jed
  endif ; endif

  Pi = (4.0*atan(1.0))

  g_Rho0 = GV%g_Earth / GV%Rho0

  !if (CS%debug) call chksum0(g_Rho0, "g/rho0 in wave struct", &
  !                           scale=(US%L_to_m**2)*US%m_to_Z*(US%s_to_T**2)*US%kg_m3_to_R)

  if (CS%debug) call chksum0(freq, "freq in wave_struct", scale=US%s_to_T)

  cg_subRO = 1e-100*US%m_s_to_L_T  ! The hard-coded value here might need to increase.
  use_EOS = associated(tv%eqn_of_state)

  ! Simplifying the following could change answers at roundoff.
  Z_to_pres = GV%Z_to_H * (GV%H_to_RZ * GV%g_Earth)
  ! rescale = 1024.0**4 ; I_rescale = 1.0/rescale

  min_h_frac = tol1 / real(nz)

  do j=js,je
    !   First merge very thin layers with the one above (or below if they are
    ! at the top).  This also transposes the row order so that columns can
    ! be worked upon one at a time.
    do i=is,ie ; htot(i,j) = 0.0 ; enddo
    do k=1,nz ; do i=is,ie ; htot(i,j) = htot(i,j) + h(i,j,k)*GV%H_to_Z ; enddo ; enddo

    do i=is,ie
      hmin(i) = htot(i,j)*min_h_frac ; kf(i) = 1 ; H_here(i) = 0.0
      HxT_here(i) = 0.0 ; HxS_here(i) = 0.0 ; HxR_here(i) = 0.0
    enddo
    if (use_EOS) then
      do k=1,nz ; do i=is,ie
        if ((H_here(i) > hmin(i)) .and. (h(i,j,k)*GV%H_to_Z > hmin(i))) then
          Hf(kf(i),i) = H_here(i)
          Tf(kf(i),i) = HxT_here(i) / H_here(i)
          Sf(kf(i),i) = HxS_here(i) / H_here(i)
          kf(i) = kf(i) + 1

          ! Start a new layer
          H_here(i) = h(i,j,k)*GV%H_to_Z
          HxT_here(i) = (h(i,j,k) * GV%H_to_Z) * tv%T(i,j,k)
          HxS_here(i) = (h(i,j,k) * GV%H_to_Z) * tv%S(i,j,k)
        else
          H_here(i) = H_here(i) + h(i,j,k)*GV%H_to_Z
          HxT_here(i) = HxT_here(i) + (h(i,j,k) * GV%H_to_Z) * tv%T(i,j,k)
          HxS_here(i) = HxS_here(i) + (h(i,j,k) * GV%H_to_Z) * tv%S(i,j,k)
        endif
      enddo ; enddo
      do i=is,ie ; if (H_here(i) > 0.0) then
        Hf(kf(i),i) = H_here(i)
        Tf(kf(i),i) = HxT_here(i) / H_here(i)
        Sf(kf(i),i) = HxS_here(i) / H_here(i)
      endif ; enddo
    else
      do k=1,nz ; do i=is,ie
        if ((H_here(i) > hmin(i)) .and. (h(i,j,k)*GV%H_to_Z > hmin(i))) then
          Hf(kf(i),i) = H_here(i) ; Rf(kf(i),i) = HxR_here(i) / H_here(i)
          kf(i) = kf(i) + 1

          ! Start a new layer
          H_here(i) = h(i,j,k)*GV%H_to_Z
          HxR_here(i) = (h(i,j,k)*GV%H_to_Z)*GV%Rlay(k)
        else
          H_here(i) = H_here(i) + h(i,j,k)*GV%H_to_Z
          HxR_here(i) = HxR_here(i) + (h(i,j,k)*GV%H_to_Z)*GV%Rlay(k)
        endif
      enddo ; enddo
      do i=is,ie ; if (H_here(i) > 0.0) then
        Hf(kf(i),i) = H_here(i) ; Rf(kf(i),i) = HxR_here(i) / H_here(i)
      endif ; enddo
    endif ! use_EOS?

    ! From this point, we can work on individual columns without causing memory
    ! to have page faults.
    do i=is,ie ; if (cn(i,j) > 0.0) then
      !----for debugging, remove later----
      ig = i + G%idg_offset ; jg = j + G%jdg_offset
      !if (ig == CS%int_tide_source_x .and. jg == CS%int_tide_source_y) then
      !-----------------------------------
      if (G%mask2dT(i,j) > 0.0) then

        gprime(:) = 0.0 ! init gprime
        pres(:) = 0.0 ! init pres
        lam = 1/(cn(i,j)**2)

        ! Calculate drxh_sum
        if (use_EOS) then
          pres(1) = 0.0
          do k=2,kf(i)
            pres(k) = pres(k-1) + Z_to_pres*Hf(k-1,i)
            T_int(k) = 0.5*(Tf(k,i)+Tf(k-1,i))
            S_int(k) = 0.5*(Sf(k,i)+Sf(k-1,i))
          enddo
          call calculate_density_derivs(T_int, S_int, pres, drho_dT, drho_dS, &
                                        tv%eqn_of_state, (/2,kf(i)/) )

          ! Sum the reduced gravities to find out how small a density difference
          ! is negligibly small.
          drxh_sum = 0.0
          do k=2,kf(i)
            drxh_sum = drxh_sum + 0.5*(Hf(k-1,i)+Hf(k,i)) * &
                max(0.0,dRho_dT(k)*(Tf(k,i)-Tf(k-1,i)) + &
                        dRho_dS(k)*(Sf(k,i)-Sf(k-1,i)))
          enddo
        else
          drxh_sum = 0.0
          do k=2,kf(i)
            drxh_sum = drxh_sum + 0.5*(Hf(k-1,i)+Hf(k,i)) * &
                              max(0.0,Rf(k,i)-Rf(k-1,i))
          enddo
        endif ! use_EOS?

        !   Find gprime across each internal interface, taking care of convective
        ! instabilities by merging layers.
        if (drxh_sum >= 0.0) then
          ! Merge layers to eliminate convective instabilities or exceedingly
          ! small reduced gravities.
          if (use_EOS) then
            kc = 1
            Hc(1) = Hf(1,i) ; Tc(1) = Tf(1,i) ; Sc(1) = Sf(1,i)
            do k=2,kf(i)
              if ((dRho_dT(k)*(Tf(k,i)-Tc(kc)) + dRho_dS(k)*(Sf(k,i)-Sc(kc))) * &
                  (Hc(kc) + Hf(k,i)) < 2.0 * tol2*drxh_sum) then
                ! Merge this layer with the one above and backtrack.
                I_Hnew = 1.0 / (Hc(kc) + Hf(k,i))
                Tc(kc) = (Hc(kc)*Tc(kc) + Hf(k,i)*Tf(k,i)) * I_Hnew
                Sc(kc) = (Hc(kc)*Sc(kc) + Hf(k,i)*Sf(k,i)) * I_Hnew
                Hc(kc) = (Hc(kc) + Hf(k,i))
                ! Backtrack to remove any convective instabilities above...  Note
                ! that the tolerance is a factor of two larger, to avoid limit how
                ! far back we go.
                do k2=kc,2,-1
                  if ((dRho_dT(k2)*(Tc(k2)-Tc(k2-1)) + dRho_dS(k2)*(Sc(k2)-Sc(k2-1))) * &
                      (Hc(k2) + Hc(k2-1)) < tol2*drxh_sum) then
                    ! Merge the two bottommost layers.  At this point kc = k2.
                    I_Hnew = 1.0 / (Hc(kc) + Hc(kc-1))
                    Tc(kc-1) = (Hc(kc)*Tc(kc) + Hc(kc-1)*Tc(kc-1)) * I_Hnew
                    Sc(kc-1) = (Hc(kc)*Sc(kc) + Hc(kc-1)*Sc(kc-1)) * I_Hnew
                    Hc(kc-1) = (Hc(kc) + Hc(kc-1))
                    kc = kc - 1
                  else ; exit ; endif
                enddo
              else
                ! Add a new layer to the column.
                kc = kc + 1
                drho_dS(kc) = drho_dS(k) ; drho_dT(kc) = drho_dT(k)
                Tc(kc) = Tf(k,i) ; Sc(kc) = Sf(k,i) ; Hc(kc) = Hf(k,i)
              endif
            enddo
            ! At this point there are kc layers and the gprimes should be positive.
            do k=2,kc ! Revisit this if non-Boussinesq.
              gprime(k) = g_Rho0 * (dRho_dT(k)*(Tc(k)-Tc(k-1)) + &
                                    dRho_dS(k)*(Sc(k)-Sc(k-1)))
            enddo
          else  ! .not.use_EOS
            ! Do the same with density directly...
            kc = 1
            Hc(1) = Hf(1,i) ; Rc(1) = Rf(1,i)
            do k=2,kf(i)
              if ((Rf(k,i) - Rc(kc)) * (Hc(kc) + Hf(k,i)) < 2.0*tol2*drxh_sum) then
                ! Merge this layer with the one above and backtrack.
                Rc(kc) = (Hc(kc)*Rc(kc) + Hf(k,i)*Rf(k,i)) / (Hc(kc) + Hf(k,i))
                Hc(kc) = (Hc(kc) + Hf(k,i))
                ! Backtrack to remove any convective instabilities above...  Note
                ! that the tolerance is a factor of two larger, to avoid limit how
                ! far back we go.
                do k2=kc,2,-1
                  if ((Rc(k2)-Rc(k2-1)) * (Hc(k2)+Hc(k2-1)) < tol2*drxh_sum) then
                    ! Merge the two bottommost layers.  At this point kc = k2.
                    Rc(kc-1) = (Hc(kc)*Rc(kc) + Hc(kc-1)*Rc(kc-1)) / (Hc(kc) + Hc(kc-1))
                    Hc(kc-1) = (Hc(kc) + Hc(kc-1))
                    kc = kc - 1
                  else ; exit ; endif
                enddo
              else
                ! Add a new layer to the column.
                kc = kc + 1
                Rc(kc) = Rf(k,i) ; Hc(kc) = Hf(k,i)
              endif
            enddo
            ! At this point there are kc layers and the gprimes should be positive.
            do k=2,kc ! Revisit this if non-Boussinesq.
              gprime(k) = g_Rho0 * (Rc(k)-Rc(k-1))
            enddo
          endif  ! use_EOS?

          !-----------------NOW FIND WAVE STRUCTURE-------------------------------------
          ! Construct and solve tridiagonal system for the interior interfaces
          ! Note that kc   = number of layers,
          !           kc+1 = nzm = number of interfaces,
          !           kc-1 = number of interior interfaces (excluding surface and bottom)
          ! Also, note that "K" refers to an interface, while "k" refers to the layer below.
          ! Need at least 3 layers (2 internal interfaces) to generate a matrix, also
          ! need number of layers to be greater than the mode number
          if (kc >= max(3, ModeNum + 1)) then
            ! Set depth at surface
            z_int(1) = 0.0
            ! Calculate Igu, Igl, depth, and N2 at each interior interface
            ! [excludes surface (K=1) and bottom (K=kc+1)]
            do K=2,kc
              Igl(K) = 1.0/(gprime(K)*Hc(k)) ; Igu(K) = 1.0/(gprime(K)*Hc(k-1))
              z_int(K) = z_int(K-1) + Hc(k-1)
              N2(K) = US%L_to_Z**2*gprime(K)/(0.5*(Hc(k)+Hc(k-1)))
            enddo
            ! Set stratification for surface and bottom (setting equal to nearest interface for now)
            N2(1) = N2(2) ; N2(kc+1) = N2(kc)
            ! Calcualte depth at bottom
            z_int(kc+1) = z_int(kc)+Hc(kc)
            ! check that thicknesses sum to total depth
            if (abs(z_int(kc+1)-htot(i,j)) > 1.e-14*htot(i,j)) then
              call MOM_error(FATAL, "wave_structure: mismatch in total depths")
            endif

            ! Populate interior rows of tridiagonal matrix; must multiply through by
            ! gprime to get tridiagonal matrix to the symmetrical form:
            ! [-1/H(k-1)]e(k-1) + [1/H(k-1)+1/H(k)-lam_z]e(k) + [-1/H(k)]e(k+1) = 0,
            ! where lam_z = lam*gprime is now a function of depth.
            ! First, populate interior rows

            ! init the values in matrix: since number of layers is variable, values need to be reset
            lam_z(:) = 0.0
            a_diag(:) = 0.0
            b_dom(:) = 0.0
            c_diag(:) = 0.0
            e_guess(:) = 0.0
            e_itt(:) = 0.0
            w_strct(:) = 0.0
            do K=3,kc-1
              row = K-1 ! indexing for TD matrix rows
              lam_z(row) = lam*gprime(K)
              a_diag(row) = gprime(K)*(-Igu(K))
              b_dom(row) = 2.0*gprime(K)*(Igu(K)+Igl(K)) - lam_z(row)
              c_diag(row) = gprime(K)*(-Igl(K))
            enddo
            if (CS%debug) then ; do row=2,kc-2
              if (isnan(lam_z(row)))then  ; print *, "Wave_structure: lam_z(row) is NAN" ; endif
              if (isnan(a_diag(row)))then ; print *, "Wave_structure: a(k) is NAN" ; endif
              if (isnan(c_diag(row)))then ; print *, "Wave_structure: c(k) is NAN" ; endif
            enddo ; endif
            ! Populate top row of tridiagonal matrix
            K=2 ; row = K-1 ;
            lam_z(row) = lam*gprime(K)
            a_diag(row) = 0.0
            b_dom(row) = gprime(K)*(Igu(K)+2.0*Igl(K)) - lam_z(row)
            c_diag(row) = gprime(K)*(-Igl(K))
            ! Populate bottom row of tridiagonal matrix
            K=kc ; row = K-1
            lam_z(row) = lam*gprime(K)
            a_diag(row) = gprime(K)*(-Igu(K))
            b_dom(row) = gprime(K)*(2.0*Igu(K) + Igl(K)) - lam_z(row)
            c_diag(row) = 0.0

            ! Guess a normalized vector shape to start with (excludes surface and bottom)
            emag2 = 0.0
            pi_htot = Pi / htot(i,j)
            do K=2,kc
              e_guess(K-1) = sin(pi_htot * z_int(K))
              emag2 = emag2 + e_guess(K-1)**2
            enddo
            renorm = 1.0 / sqrt(emag2)
            do K=2,kc ; e_guess(K-1) = renorm*e_guess(K-1) ; enddo

            ! Perform inverse iteration with tri-diag solver
            do itt=1,max_itt
              ! this solver becomes unstable very quickly
              ! b_diag(1:kc-1) = b_dom(1:kc-1) - (a_diag(1:kc-1) + c_diag(1:kc-1))
              !call tridiag_solver(a_diag(1:kc-1),b_diag(1:kc-1),c_diag(1:kc-1), &
              !                    -lam_z(1:kc-1),e_guess(1:kc-1),"TDMA_T",e_itt)

              call solve_diag_dominant_tridiag( c_diag, b_dom, a_diag, e_guess, e_itt, kc-1 )
              ! Renormalize the guesses of the structure.-
              emag2 = 0.0
              do K=2,kc ; emag2 = emag2 + e_itt(K-1)**2 ; enddo
              renorm = 1.0 / sqrt(emag2)
              do K=2,kc ; e_guess(K-1) = renorm*e_itt(K-1) ; enddo

              ! A test should be added here to evaluate convergence.
            enddo ! itt-loop
            do K=2,kc ; w_strct(K) = e_guess(K-1) ; enddo
            w_strct(1)    = 0.0 ! rigid lid at surface
            w_strct(kc+1) = 0.0 ! zero-flux at bottom

            ! Check to see if solver worked
            if (CS%debug) then
              ig_stop = 0 ; jg_stop = 0
              if (isnan(sum(w_strct(1:kc+1)))) then
                print *, "Wave_structure: w_strct has a NAN at ig=", ig, ", jg=", jg
                if (i<G%isc .or. i>G%iec .or. j<G%jsc .or. j>G%jec)then
                  print *, "This is occuring at a halo point."
                endif
                ig_stop = ig ; jg_stop = jg
              endif
            endif

            ! Normalize vertical structure function of w such that
            ! \int(w_strct)^2dz = a_int (a_int could be any value, e.g., 0.5)
            nzm = kc+1 ! number of layer interfaces after merging
                       !(including surface and bottom)
            w2avg = 0.0
            do k=1,nzm-1
              dz(k) = Hc(k)
              w2avg = w2avg + 0.5*(w_strct(K)**2+w_strct(K+1)**2)*dz(k)
            enddo
            ! correct renormalization:
            renorm = sqrt(htot(i,j)*a_int/w2avg)
            do K=1,kc+1 ; w_strct(K) = renorm * w_strct(K) ; enddo

            ! Calculate vertical structure function of u (i.e. dw/dz)
            do K=2,nzm-1
              u_strct(K) = 0.5*((w_strct(K-1) - w_strct(K)  )/dz(k-1) + &
                                (w_strct(K)   - w_strct(K+1))/dz(k))
            enddo
            u_strct(1)   = (w_strct(1)   -  w_strct(2) )/dz(1)
            u_strct(nzm) = (w_strct(nzm-1)-  w_strct(nzm))/dz(nzm-1)

            ! Calculate wavenumber magnitude
            f2 = (0.25*(G%CoriolisBu(I,J) + G%CoriolisBu(max(I-1,1),max(J-1,1)) + &
                        G%CoriolisBu(I,max(J-1,1)) + G%CoriolisBu(max(I-1,1),J)))**2
            Kmag2 = (freq**2 - f2) / (cn(i,j)**2 + cg_subRO**2)

            ! Calculate terms in vertically integrated energy equation
            int_dwdz2 = 0.0 ; int_w2 = 0.0 ; int_N2w2 = 0.0
            do K=1,nzm
              u_strct2(K) = u_strct(K)**2
              w_strct2(K) = w_strct(K)**2
            enddo
            ! vertical integration with Trapezoidal rule
            do k=1,nzm-1
              int_dwdz2 = int_dwdz2 + 0.5*(u_strct2(K)+u_strct2(K+1)) * dz(k)
              int_w2    = int_w2    + 0.5*(w_strct2(K)+w_strct2(K+1)) * dz(k)
              int_N2w2  = int_N2w2  + 0.5*(w_strct2(K)*N2(K)+w_strct2(K+1)*N2(K+1)) * dz(k)
            enddo

            ! Back-calculate amplitude from energy equation
            if (present(En) .and. (freq**2*Kmag2 > 0.0)) then
              ! Units here are [R Z ~> kg m-2]
              KE_term = 0.25*GV%Rho0*( ((freq**2 + f2) / (freq**2*Kmag2))*US%L_to_Z**2*int_dwdz2 + int_w2 )
              PE_term = 0.25*GV%Rho0*( int_N2w2 / freq**2 )
              if (En(i,j) >= 0.0) then
                W0 = sqrt( En(i,j) / (KE_term + PE_term) )
              else
                call MOM_error(WARNING, "wave_structure: En < 0.0; setting to W0 to 0.0")
                print *, "En(i,j)=", En(i,j), " at ig=", ig, ", jg=", jg
                W0 = 0.0
              endif
              ! Calculate actual vertical velocity profile and derivative
              U_mag = W0 * sqrt((freq**2 + f2) / (2.0*freq**2*Kmag2))
              do K=1,nzm
                W_profile(K) = W0*w_strct(K)
                ! dWdz_profile(K) = W0*u_strct(K)
                ! Calculate average magnitude of actual horizontal velocity over a period
                Uavg_profile(K) = abs(U_mag * u_strct(K))
              enddo
            else
              do K=1,nzm
                W_profile(K)    = 0.0
                ! dWdz_profile(K) = 0.0
                Uavg_profile(K) = 0.0
              enddo
            endif

            ! Store values in control structure
            do K=1,nzm
              CS%w_strct(i,j,K)      = w_strct(K)
              CS%u_strct(i,j,K)      = u_strct(K)
              CS%W_profile(i,j,K)    = W_profile(K)
              CS%Uavg_profile(i,j,K) = Uavg_profile(K)
              CS%z_depths(i,j,K)     = z_int(K)
              CS%N2(i,j,K)           = N2(K)
            enddo
            CS%num_intfaces(i,j) = nzm
          else
            ! If not enough layers, default to zero
            nzm = kc+1
            do K=1,nzm
              CS%w_strct(i,j,K)      = 0.0
              CS%u_strct(i,j,K)      = 0.0
              CS%W_profile(i,j,K)    = 0.0
              CS%Uavg_profile(i,j,K) = 0.0
              CS%z_depths(i,j,K)     = 0.0 ! could use actual values
              CS%N2(i,j,K)           = 0.0 ! could use with actual values
            enddo
            CS%num_intfaces(i,j) = nzm
          endif  ! kc >= 3 and kc > ModeNum + 1?
        endif ! drxh_sum >= 0?
      !else     ! if at test point - delete later
      !  return ! if at test point - delete later
      !endif    ! if at test point - delete later
      endif ! mask2dT > 0.0?
    else
      ! if cn=0.0, default to zero
      nzm                       = nz+1 ! could use actual values
      do K=1,nzm
        CS%w_strct(i,j,K)      = 0.0
        CS%u_strct(i,j,K)      = 0.0
        CS%W_profile(i,j,K)    = 0.0
        CS%Uavg_profile(i,j,K) = 0.0
        CS%z_depths(i,j,K)     = 0.0 ! could use actual values
        CS%N2(i,j,K)           = 0.0 ! could use with actual values
      enddo
      CS%num_intfaces(i,j) = nzm
    endif ; enddo ! if cn>0.0? ; i-loop
  enddo ! j-loop

  if (CS%debug) call hchksum(CS%N2, 'N2 in wave_struct', G%HI, scale=US%s_to_T**2)
  if (CS%debug) call hchksum(cn, 'cn in wave_struct', G%HI, scale=US%L_T_to_m_s)
  if (CS%debug) call hchksum(CS%W_profile, 'Wprofile in wave_struct', G%HI, scale=US%Z_to_L*US%L_T_to_m_s)
  if (CS%debug) call hchksum(CS%Uavg_profile, 'Uavg_profile in wave_struct', G%HI, scale=US%L_T_to_m_s)

end subroutine wave_structure

! The subroutine tridiag_solver is never used and could perhaps be deleted.

!> Solves a tri-diagonal system Ax=y using either the standard
!! Thomas algorithm (TDMA_T) or its more stable variant that invokes the
!! "Hallberg substitution" (TDMA_H).
subroutine tridiag_solver(a, b, c, h, y, method, x)
  real, dimension(:), intent(in)  :: a !< lower diagonal with first entry equal to zero.
  real, dimension(:), intent(in)  :: b !< middle diagonal.
  real, dimension(:), intent(in)  :: c !< upper diagonal with last entry equal to zero.
  real, dimension(:), intent(in)  :: h !< vector of values that have already been added to b; used
           !! for systems of the form (e.g. average layer thickness in vertical diffusion case):
           !! [ -alpha(k-1/2) ]                       * e(k-1) +
           !! [  alpha(k-1/2) + alpha(k+1/2) + h(k) ] * e(k)   +
           !! [ -alpha(k+1/2) ]                       * e(k+1) = y(k)
           !! where a(k)=[-alpha(k-1/2)], b(k)=[alpha(k-1/2)+alpha(k+1/2) + h(k)],
           !! and c(k)=[-alpha(k+1/2)]. Only used with TDMA_H method.
  real, dimension(:), intent(in)  :: y !< vector of known values on right hand side.
  character(len=*),   intent(in)  :: method !< A string describing the algorithm to use
  real, dimension(:), intent(out) :: x !< vector of unknown values to solve for.
  ! Local variables
  integer :: nrow                         ! number of rows in A matrix
!  real, allocatable, dimension(:,:) :: A_check ! for solution checking
!  real, allocatable, dimension(:)   :: y_check ! for solution checking
  real, allocatable, dimension(:) :: c_prime, y_prime, q, alpha
                                          ! intermediate values for solvers
  real    :: Q_prime, beta                ! intermediate values for solver
  integer :: k                            ! row (e.g. interface) index

  nrow = size(y)
  allocate(c_prime(nrow))
  allocate(y_prime(nrow))
  allocate(q(nrow))
  allocate(alpha(nrow))
!  allocate(A_check(nrow,nrow))
!  allocate(y_check(nrow))

  if (method == 'TDMA_T') then
    ! Standard Thomas algoritim (4th variant).
    ! Note: Requires A to be non-singular for accuracy/stability
    c_prime(:) = 0.0       ; y_prime(:) = 0.0
    c_prime(1) = c(1)/b(1) ; y_prime(1) = y(1)/b(1)

    ! Forward sweep
    do k=2,nrow-1
      c_prime(k) = c(k)/(b(k)-a(k)*c_prime(k-1))
    enddo
    !print *, 'c_prime=', c_prime(1:nrow)
    do k=2,nrow
      y_prime(k) = (y(k)-a(k)*y_prime(k-1))/(b(k)-a(k)*c_prime(k-1))
    enddo
    !print *, 'y_prime=', y_prime(1:nrow)
    x(nrow) = y_prime(nrow)

    ! Backward sweep
    do k=nrow-1,1,-1
      x(k) = y_prime(k)-c_prime(k)*x(k+1)
    enddo
    !print *, 'x=',x(1:nrow)

    ! Check results - delete later
    !do j=1,nrow ; do i=1,nrow
    !  if (i==j)then ;       A_check(i,j) = b(i)
    !  elseif (i==j+1)then ; A_check(i,j) = a(i)
    !  elseif (i==j-1)then ; A_check(i,j) = c(i)
    !  endif
    !enddo ; enddo
    !print *, 'A(2,1),A(2,2),A(1,2)=', A_check(2,1), A_check(2,2), A_check(1,2)
    !y_check = matmul(A_check,x)
    !if (all(y_check /= y))then
    !  print *, "tridiag_solver: Uh oh, something's not right!"
    !  print *, "y=", y
    !  print *, "y_check=", y_check
    !endif

  elseif (method == 'TDMA_H') then
    ! Thomas algoritim (4th variant) w/ Hallberg substitution.
    ! For a layered system where k is at interfaces, alpha{k+1/2} refers to
    ! some property (e.g. inverse thickness for mode-structure problem) of the
    ! layer below and alpha{k-1/2} refers to the layer above.
    ! Here, alpha(k)=alpha{k+1/2} and alpha(k-1)=alpha{k-1/2}.
    ! Strictly speaking, this formulation requires A to be a non-singular,
    ! symmetric, diagonally dominant matrix, with h>0.
    ! Need to add a check for these conditions.
    do k=1,nrow-1
      if (abs(a(k+1)-c(k)) > 1.e-10*(abs(a(k+1))+abs(c(k)))) then
        call MOM_error(FATAL, "tridiag_solver: matrix not symmetric; need symmetry when invoking TDMA_H")
      endif
    enddo
    alpha = -c
    ! Alpha of the bottom-most layer is not necessarily zero. Therefore,
    ! back out the value from the provided b(nrow and h(nrow) values
    alpha(nrow)   = b(nrow)-h(nrow)-alpha(nrow-1)
    ! Prime other variables
    beta       = 1/b(1)
    y_prime(:) = 0.0       ; q(:) = 0.0
    y_prime(1) = beta*y(1) ; q(1) = beta*alpha(1)
    Q_prime    = 1-q(1)

    ! Forward sweep
    do k=2,nrow-1
      beta = 1/(h(k)+alpha(k-1)*Q_prime+alpha(k))
      if (isnan(beta))then ; print *, "Tridiag_solver: beta is NAN" ; endif
      q(k) = beta*alpha(k)
      y_prime(k) = beta*(y(k)+alpha(k-1)*y_prime(k-1))
      Q_prime = beta*(h(k)+alpha(k-1)*Q_prime)
    enddo
    if ((h(nrow)+alpha(nrow-1)*Q_prime+alpha(nrow)) == 0.0)then
      call MOM_error(FATAL, "Tridiag_solver: this system is not stable.") ! ; overriding beta(nrow)
      ! This has hard-coded dimensions: beta = 1/(1e-15) ! place holder for unstable systems - delete later
    else
      beta = 1/(h(nrow)+alpha(nrow-1)*Q_prime+alpha(nrow))
    endif
    y_prime(nrow) = beta*(y(nrow)+alpha(nrow-1)*y_prime(nrow-1))
    x(nrow) = y_prime(nrow)
    ! Backward sweep
    do k=nrow-1,1,-1
      x(k) = y_prime(k)+q(k)*x(k+1)
    enddo
    !print *, 'yprime=',y_prime(1:nrow)
    !print *, 'x=',x(1:nrow)
  endif

  deallocate(c_prime,y_prime,q,alpha)
! deallocate(A_check,y_check)

end subroutine tridiag_solver

!> Allocate memory associated with the wave structure module and read parameters.
subroutine wave_structure_init(Time, G, GV, param_file, diag, CS)
  type(time_type),         intent(in) :: Time !< The current model time.
  type(ocean_grid_type),   intent(in) :: G    !< The ocean's grid structure.
  type(verticalGrid_type), intent(in) :: GV    !< The ocean's vertical grid structure.
  type(param_file_type),   intent(in) :: param_file !< A structure to parse for run-time
                                              !! parameters.
  type(diag_ctrl), target, intent(in) :: diag !< A structure that is used to regulate
                                              !! diagnostic output.
  type(wave_structure_CS), intent(inout) :: CS  !< Wave structure control struct

  ! This include declares and sets the variable "version".
# include "version_variable.h"
  character(len=40)  :: mdl = "MOM_wave_structure"  ! This module's name.
  integer :: isd, ied, jsd, jed, nz

  isd = G%isd ; ied = G%ied ; jsd = G%jsd ; jed = G%jed ; nz = GV%ke

  CS%initialized = .true.

  call get_param(param_file, mdl, "INTERNAL_TIDE_SOURCE_X", CS%int_tide_source_x, &
                 "X Location of generation site for internal tide", default=1.)
  call get_param(param_file, mdl, "INTERNAL_TIDE_SOURCE_Y", CS%int_tide_source_y, &
                 "Y Location of generation site for internal tide", default=1.)
  call get_param(param_file, mdl, "DEBUG", CS%debug, &
                 "debugging prints", default=.false.)

  CS%diag => diag

  ! Allocate memory for variable in control structure; note,
  ! not all rows will be filled if layers get merged!
  allocate(CS%w_strct(isd:ied,jsd:jed,nz+1))
  allocate(CS%u_strct(isd:ied,jsd:jed,nz+1))
  allocate(CS%W_profile(isd:ied,jsd:jed,nz+1))
  allocate(CS%Uavg_profile(isd:ied,jsd:jed,nz+1))
  allocate(CS%z_depths(isd:ied,jsd:jed,nz+1))
  allocate(CS%N2(isd:ied,jsd:jed,nz+1))
  allocate(CS%num_intfaces(isd:ied,jsd:jed))

  ! Write all relevant parameters to the model log.
  call log_version(param_file, mdl, version, "")

end subroutine wave_structure_init

end module MOM_wave_structure
