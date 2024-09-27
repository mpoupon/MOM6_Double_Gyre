!***********************************************************************
!*                   GNU Lesser General Public License
!*
!* This file is part of the GFDL Flexible Modeling System (FMS).
!*
!* FMS is free software: you can redistribute it and/or modify it under
!* the terms of the GNU Lesser General Public License as published by
!* the Free Software Foundation, either version 3 of the License, or (at
!* your option) any later version.
!*
!* FMS is distributed in the hope that it will be useful, but WITHOUT
!* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
!* FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
!* for more details.
!*
!* You should have received a copy of the GNU Lesser General Public
!* License along with FMS.  If not, see <http://www.gnu.org/licenses/>.
!***********************************************************************

module ocean_albedo_mod

!=======================================================================
!
!                ocean surface albedo module
!
!   routine for computing the surface albedo over the open ocean
!
!=======================================================================

use          mpp_mod, only: input_nml_file

use        fms_mod, only: error_mesg, check_nml_error, FATAL, &
                          mpp_pe, mpp_root_pe, &
                          write_version_number, stdlog

implicit none
private

public  compute_ocean_albedo, compute_ocean_albedo_new

!-----------------------------------------------------------------------
character(len=256) :: version = '$Id$'
character(len=256) :: tagname = '$Name$'
!-----------------------------------------------------------------------

real    :: const_alb           = 0.10
integer :: ocean_albedo_option = 1

namelist /ocean_albedo_nml/  ocean_albedo_option, &
                             const_alb

! ocean_albedo_option = 1 : used by GFDL Experimental Prediction Group
!                           in 80s and 90s; source not currently documented
!                           (tabulated dependence on zenith angle)
!
! ocean_albedo_option = 2 : used by GFDL Climate Dynamics Group in 80s and 90s
!                           source not currently documented
!                           (tabulated dependence on latitude)
!
! ocean_albedo_option = 3 : simple analytic dependence on zenith angle
!                           used by J. E. Taylor, et. al., 
!                           QJRMS, 1996, Vol. 122, 839-861
!                           albedo = 0.037/[1.1*(cos(Z)**1.4) + 0.15]
!
! ocean_albedo_option = 4 : constant uniform albedo 
!                           set by namelist variable const_alb
!
! ocean_albedo_option = 5 : separate treatment of dif/dir shortwave using
!                           NCAR CCMS3.0 scheme (Briegleb et al, 1986,
!                           J. Clim. and Appl. Met., v. 27, 214-226)
!
! ocean_albedo_option = 6 : separate treatment of dif/dir shortwave using
!                           NCAR CCMS3.0 scheme (Briegleb et al, 1986,
!                           J. Clim. and Appl. Met., v. 27, 214-226)
!                           with reflection from White Caps from Koepke (1984)
!                           and Brumer et al. (2017)

  interface compute_ocean_albedo
     module procedure compute_ocean_albedo_old ! obsolete - remove later
     module procedure compute_ocean_albedo_new
  end interface

!    ocean surface albedo data

!    data used for option 1

         real, dimension(21,20) :: albedo_data
         real, dimension(21)    :: trn
         real, dimension(20)    :: za
         real, dimension(19)    :: dza
         real :: rad2deg
      logical :: first = .true.

!    data used for option 2

         real, dimension(19) :: albedo_mcm
         real, allocatable, dimension(:,:) :: alb2

!=======================================================================


      data  albedo_data (1:21,1:7)                                     &
             / .061,.062,.072,.087,.115,.163,.235,.318,.395,.472,.542, &
     .604,.655,.693,.719,.732,.730,.681,.581,.453,.425,.061,.062,.070, &
     .083,.108,.145,.198,.263,.336,.415,.487,.547,.595,.631,.656,.670, &
     .652,.602,.494,.398,.370,.061,.061,.068,.079,.098,.130,.174,.228, &
     .290,.357,.424,.498,.556,.588,.603,.592,.556,.488,.393,.342,.325, &
     .061,.061,.065,.073,.086,.110,.150,.192,.248,.306,.360,.407,.444, &
     .469,.480,.474,.444,.386,.333,.301,.290,.061,.061,.065,.070,.082, &
     .101,.131,.168,.208,.252,.295,.331,.358,.375,.385,.377,.356,.320, &
     .288,.266,.255,.061,.061,.063,.068,.077,.092,.114,.143,.176,.210, &
     .242,.272,.288,.296,.300,.291,.273,.252,.237,.266,.220,.061,.061, &
     .062,.066,.072,.084,.103,.127,.151,.176,.198,.219,.236,.245,.250, &
     .246,.235,.222,.211,.205,.200 /

      data  albedo_data (1:21,8:14)                                    &
             / .061,.061,.061,.065,.071,.079,.094,.113,.134,.154,.173, &
     .185,.190,.193,.193,.190,.188,.185,.182,.180,.178,.061,.061,.061, &
     .064,.067,.072,.083,.099,.117,.135,.150,.160,.164,.165,.164,.162, &
     .160,.159,.158,.157,.157,.061,.061,.061,.062,.065,.068,.074,.084, &
     .097,.111,.121,.127,.130,.131,.131,.130,.129,.127,.126,.125,.122, &
     .061,.061,.061,.061,.062,.064,.070,.076,.085,.094,.101,.105,.107, &
     .106,.103,.100,.097,.096,.095,.095,.095,.061,.061,.061,.060,.061, &
     .062,.065,.070,.075,.081,.086,.089,.090,.088,.084,.080,.077,.075, &
     .074,.074,.074,.061,.061,.060,.060,.060,.061,.063,.065,.068,.072, &
     .076,.077,.076,.074,.071,.067,.064,.062,.061,.061,.061,.061,.061, &
     .060,.060,.060,.060,.061,.062,.065,.068,.069,.069,.068,.065,.061, &
     .058,.055,.054,.053,.052,.052 /

      data  albedo_data (1:21,15:20)                                   &
             / .061,.061,.060,.060,.060,.060,.060,.060,.062,.065,.065, &
     .063,.060,.057,.054,.050,.047,.046,.045,.044,.044,.061,.061,.060, &
     .060,.060,.059,.059,.059,.059,.059,.058,.055,.051,.047,.043,.039, &
     .035,.033,.032,.031,.031,.061,.061,.060,.060,.060,.059,.059,.058, &
     .057,.056,.054,.051,.047,.043,.039,.036,.033,.030,.028,.027,.026, &
     .061,.061,.060,.060,.060,.059,.059,.058,.057,.055,.052,.049,.045, &
     .040,.036,.032,.029,.027,.026,.025,.025,.061,.061,.060,.060,.060, &
     .059,.059,.058,.056,.053,.050,.046,.042,.038,.034,.031,.028,.026, &
     .025,.025,.025,.061,.061,.060,.060,.059,.058,.058,.057,.055,.053, &
     .050,.046,.042,.038,.034,.030,.028,.029,.025,.025,.025 /

      data  trn (1:21)                                             &
             /.00,.05,.10,.15,.20,.25,.30,.35,.40,.45,.50,.55,.60, &
              .65,.70,.75,.80,.85,.90,.95,1.00/

      data  za (1:20)                                               &
             / 90.,88.,86.,84.,82.,80.,78.,76.,74.,70.,66.,62.,58., &
               54.,50.,40.,30.,20.,10., 0. /

      data  dza (1:19) /8*2.0,6*4.0,5*10.0/

      data albedo_mcm (1:19)                                              &
         / 0.206, 0.161, 0.110, 0.097, 0.089, 0.076, 0.068, 0.063,        &
         3*0.060,  0.063, 0.068, 0.076, 0.089, 0.097, 0.110, 0.161, 0.206 / 

!=======================================================================

contains

!#######################################################################

   subroutine compute_ocean_albedo_old (ocean, coszen, albedo, lat)

!-----------------------------------------------------------------------
! input
!     ocean  = logical flag; = true if ocean point
!     coszen = cosine of zenith angle (in radians)
!     lat    = latitude (radians)
!
!  output
!     albedo = surface albedo
!-----------------------------------------------------------------------
      logical, intent(in)  ::  ocean(:,:)
      real,    intent(in)  :: coszen(:,:)
      real,    intent(out) :: albedo(:,:)
      real,    intent(in), optional :: lat(:,:)
!-----------------------------------------------------------------------

   real, dimension(size(ocean,1),size(ocean,2)) :: trans, zen,  &
                                                   dz, dt, dzdt
integer, dimension(size(ocean,1),size(ocean,2)) :: i1, j1

   real, dimension(size(ocean,1),size(ocean,2)) :: cos14

      integer :: i, j

!-----------------------------------------------------------------------
!------------ calculate surface albedo over open water -----------------
!-----------------------------------------------------------------------

   if (first) call ocean_albedo_init(ocean,lat)

if(ocean_albedo_option == 1) then

   trans = 0.537

   where (ocean)
      zen = acos(coszen) * rad2deg
   elsewhere
      zen = 0.0
   endwhere

!---- set up interpolation indices ----

   where (ocean) i1 = 20.*trans + 1.

   where (ocean .and. zen >= 74.) j1 = 0.50*(90.-zen) + 1.
   where (ocean .and. zen <  50.) j1 = 0.10*(50.-zen) + 15.

   where (ocean .and. zen <  74.  &
                .and. zen >= 50.) j1 = 0.25*(74.-zen) + 9.


!---- set albedo to zero at non-sea points ? ----

   where (.not.ocean) albedo = 0.0
   
!---- do interpolation -----

   do j = 1, size(ocean,2)
   do i = 1, size(ocean,1)

      if (ocean(i,j)) then
          dz(i,j)   = -(zen(i,j)-za(j1(i,j)))/dza(j1(i,j))
          dt(i,j)   = 20.*(trans(i,j)-trn(i1(i,j)))
          dzdt(i,j) = dz(i,j) * dt(i,j)

          albedo(i,j) = albedo_data(i1(i,j)  ,j1(i,j)  ) *            &
                                       (1.-dz(i,j)-dt(i,j)+dzdt(i,j)) &
                      + albedo_data(i1(i,j)+1,j1(i,j)  ) *            &
                                       (dt(i,j)-dzdt(i,j))            &
                      + albedo_data(i1(i,j)  ,j1(i,j)+1) *            &
                                       (dz(i,j)-dzdt(i,j))            &
                      + albedo_data(i1(i,j)+1,j1(i,j)+1) *  dzdt(i,j)
       endif

   enddo
   enddo

endif

if(ocean_albedo_option == 2) then
  albedo = alb2
endif

if(ocean_albedo_option == 3) then

   where(coszen .ne. 0.0) 
      cos14 = coszen**1.4
   elsewhere
      cos14 = 0.0
   endwhere

   where(ocean)
      albedo = 0.037/(1.1*cos14 + 0.15)
   endwhere

endif

if(ocean_albedo_option == 4) albedo = const_alb

if (ocean_albedo_option == 5) then
   call error_mesg ('ocean_albedo', &
          'ocean_albedo_option=5 requires new compute_ocean_albedo interface', &
          FATAL)
endif

where (.not.ocean) albedo = 0.0
   
!-----------------------------------------------------------------------

   end subroutine compute_ocean_albedo_old

!#######################################################################
   subroutine compute_ocean_albedo_new (ocean, coszen, albedo_vis_dir, &
                albedo_vis_dif, albedo_nir_dir, albedo_nir_dif, lat, flux_u, flux_v )

!-----------------------------------------------------------------------
! input
!     ocean  = logical flag; = true if ocean point
!     coszen = cosine of zenith angle (in radians)
!     lat    = latitude (radians)
!
!  output
!     albedo = surface albedo
!-----------------------------------------------------------------------
      logical, intent(in)  ::  ocean(:,:)
      real,    intent(in)  :: coszen(:,:)
      real,    intent(out) :: albedo_vis_dir(:,:)
      real,    intent(out) :: albedo_vis_dif(:,:)
      real,    intent(out) :: albedo_nir_dir(:,:)
      real,    intent(out) :: albedo_nir_dif(:,:)
      real,    intent(in), optional :: lat(:,:)
      real,    intent(in), optional :: flux_u(:,:) !input as stress and converted to u velocity
      real,    intent(in), optional :: flux_v(:,:) !input as stress and converted to v velocity
!-----------------------------------------------------------------------

   real, dimension(size(ocean,1),size(ocean,2)) :: trans, zen,  &
                                                   dz, dt, dzdt, ua, va, u10, white_cap_coverage
integer, dimension(size(ocean,1),size(ocean,2)) :: i1, j1

   real, dimension(size(ocean,1),size(ocean,2)) :: cos14

      integer :: i, j

!-----------------------------------------------------------------------
!------------ calculate surface albedo over open water -----------------
!-----------------------------------------------------------------------

   if (first) call ocean_albedo_init(ocean,lat)

if(ocean_albedo_option == 1) then

   trans = 0.537

   where (ocean)
      zen = acos(coszen) * rad2deg
   elsewhere
      zen = 0.0
   endwhere

!---- set up interpolation indices ----

   where (ocean) i1 = 20.*trans + 1.

   where (ocean .and. zen >= 74.) j1 = 0.50*(90.-zen) + 1.
   where (ocean .and. zen <  50.) j1 = 0.10*(50.-zen) + 15.

   where (ocean .and. zen <  74.  &
                .and. zen >= 50.) j1 = 0.25*(74.-zen) + 9.


!---- do interpolation -----

   do j = 1, size(ocean,2)
   do i = 1, size(ocean,1)

      if (ocean(i,j)) then
          dz(i,j)   = -(zen(i,j)-za(j1(i,j)))/dza(j1(i,j))
          dt(i,j)   = 20.*(trans(i,j)-trn(i1(i,j)))
          dzdt(i,j) = dz(i,j) * dt(i,j)

          albedo_vis_dir(i,j) = albedo_data(i1(i,j)  ,j1(i,j)  ) *    &
                                       (1.-dz(i,j)-dt(i,j)+dzdt(i,j)) &
                      + albedo_data(i1(i,j)+1,j1(i,j)  ) *            &
                                       (dt(i,j)-dzdt(i,j))            &
                      + albedo_data(i1(i,j)  ,j1(i,j)+1) *            &
                                       (dz(i,j)-dzdt(i,j))            &
                      + albedo_data(i1(i,j)+1,j1(i,j)+1) *  dzdt(i,j)
       else
          albedo_vis_dir(i,j) = 0.0
       endif
       albedo_vis_dif(i,j) = albedo_vis_dir(i,j)
       albedo_nir_dir(i,j) = albedo_vis_dir(i,j)
       albedo_nir_dif(i,j) = albedo_vis_dir(i,j)

   enddo
   enddo

endif

if(ocean_albedo_option == 2) then
  albedo_vis_dir = alb2
  albedo_vis_dif = alb2
  albedo_nir_dir = alb2
  albedo_nir_dif = alb2
endif

if(ocean_albedo_option == 3) then

   where(coszen .ne. 0.0) 
      cos14 = coszen**1.4
   elsewhere
      cos14 = 0.0
   endwhere

   where(ocean)
      albedo_vis_dir = 0.037/(1.1*cos14 + 0.15)
   endwhere
   albedo_vis_dif = albedo_vis_dir ! this is wrong, use albedo_option=5
   albedo_nir_dir = albedo_vis_dir
   albedo_nir_dif = albedo_vis_dir ! this is wrong, use albedo_option=5

endif

if(ocean_albedo_option == 4) then
  albedo_vis_dir = const_alb
  albedo_vis_dif = const_alb
  albedo_nir_dir = const_alb
  albedo_nir_dif = const_alb
endif

if (ocean_albedo_option == 5) then
  where (coszen .ge. 0.0)
    albedo_vis_dir = 0.026/(coszen**1.7+0.065)                  &
                    +0.15*(coszen-0.10)*(coszen-0.5)*(coszen-1.0)
  elsewhere
     !albedo_vis_dir = 0.4075 ! coszen=0 value of above expression
     !Will Cooke bug fix: albedo_vis_dir = 0.026/0.064 + 0.15*(-0.1)(-0.5)(-1)
     !                                   = 0.4 + 0.15*(-0.05) = 0.4 - 0.0075 = 0.3925
     albedo_vis_dir = 0.3925 ! coszen=0 value of above expression
  endwhere
  albedo_vis_dif = 0.06
  albedo_nir_dir = albedo_vis_dir
  albedo_nir_dif = 0.06
endif

if (ocean_albedo_option == 6) then
  if(present(flux_u) .and. present(flux_v)) then
!
!  Add white cap coverage as a function of wind speed WC = 0.0738/100*(U10-4.23)^1.42 converted from % to ratio from:
!   Brumer, Sophia E., et al. "Whitecap coverage dependence on wind and wave statistics as observed during
!   SO GasEx and HiWinGS." Journal of Physical Oceanography 47.9 (2017): 2211-2235.
!
!   and canonical albedo of White Caps = 0.22 from:
!     Koepke, Peter. "Effective reflectance of oceanic whitecaps." Applied optics 23.11 (1984): 1816-1824.
!     supported by satellite applications https://oceancolor.gsfc.nasa.gov/reprocessing/r2009/whitecap/
!     and recent work Randolph, Kaylan, et al. "Novel methods for optically measuring whitecaps under natural wave-breaking
!     conditions in the Southern Ocean." Journal of Atmospheric and Oceanic Technology 34.3 (2017): 533-554.
!
   ua=0.0;va=0.0;u10=0.0 !Initialize to avoid overflow
   where(ocean)
       ua=flux_u ! Note rough conversion from stress to speed
       va=flux_v ! Note rough conversion from stress to speed
   endwhere

   call invert_tau_for_du(ua, va) ! Note rough conversion from stress to speed

   where(ocean)
       u10 = sqrt(ua*ua + va*va)
   endwhere

   where (coszen .ge. 0.0)
     albedo_vis_dir = 0.026/(coszen**1.7+0.065)                  &
                    +0.15*(coszen-0.10)*(coszen-0.5)*(coszen-1.0)
   elsewhere
     !albedo_vis_dir = 0.4075 ! coszen=0 value of above expression
     !Will Cooke bug fix: albedo_vis_dir = 0.026/0.064 + 0.15*(-0.1)(-0.5)(-1)
     !                                   = 0.4 + 0.15*(-0.05) = 0.4 - 0.0075 = 0.3925
     albedo_vis_dir = 0.3925 ! coszen=0 value of above expression
   endwhere
   white_cap_coverage=0.000738*max(0.0,u10-4.23)**1.42
   albedo_vis_dir = albedo_vis_dir*(1.0-white_cap_coverage)+max(albedo_vis_dir,0.22)*white_cap_coverage
   albedo_vis_dif = 0.06*(1.0-white_cap_coverage)+0.22*white_cap_coverage
   albedo_nir_dir = albedo_vis_dir
   albedo_nir_dif = albedo_vis_dif
  else
   call error_mesg ('compute_ocean_albedo_new: ',&
                    'ocean_albedo_option=6 but flux_u,flux_v are not present in arguments.', FATAL)
  endif
endif

where (.not.ocean)
  albedo_vis_dir = 0.0
  albedo_vis_dif = 0.0
  albedo_nir_dir = 0.0
  albedo_nir_dif = 0.0
end where
   
!-----------------------------------------------------------------------

   end subroutine compute_ocean_albedo_new

!#######################################################################

   subroutine ocean_albedo_init(ocean,lat)
   logical, intent(in), optional :: ocean(:,:)
   real,    intent(in), optional :: lat(:,:)

   integer :: unit
   integer :: io ,ierr
   real,    allocatable, dimension(:,:) :: xx
   integer, allocatable, dimension(:,:) :: j1
   integer :: i,j

      rad2deg = 90./asin(1.0)

  read (input_nml_file, nml=ocean_albedo_nml, iostat=io)
  ierr = check_nml_error(io, 'ocean_albedo_nml')

!------- write version number and namelist ---------

      if ( mpp_pe() == mpp_root_pe() ) then
           call write_version_number(version, tagname)
           unit = stdlog()
           write (unit, nml=ocean_albedo_nml)
      endif

   if (ocean_albedo_option < 1 .or. ocean_albedo_option > 6)   &
       call error_mesg ('ocean_albedo',                        &
                        'ocean_albedo_option must = 1,2,3,4,5 or 6', FATAL)

   if(ocean_albedo_option == 2) then
     if ( present(ocean) .and. present(lat) ) then
       allocate (alb2(size(lat,1),size(lat,2)))
       allocate (xx(size(ocean,1),size(ocean,2)))
       allocate (j1(size(ocean,1),size(ocean,2)))
       xx = (rad2deg*lat + 90.0)/10.0
       j1 = int(xx)
       xx = xx - float(j1)
       do j = 1, size(ocean,2)
         do i = 1, size(ocean,1)
           if (ocean(i,j)) then
             alb2(i,j) = albedo_mcm(j1(i,j)+1) + xx(i,j)*(albedo_mcm(j1(i,j)+2) - albedo_mcm(j1(i,j)+1))
           endif
         enddo
       enddo
       deallocate (xx, j1)
     else
       call error_mesg ('ocean_albedo_init', &
         'ocean_albedo_option = 2 but ocean or lat or both are missing', FATAL)
     endif
   endif

   first   = .false.

   end subroutine ocean_albedo_init

   
! ##############################################################################

subroutine invert_tau_for_du(u,v)
! Arguments
real, dimension(:,:),intent(inout) :: u, v
! Local variables
integer :: i, j
real :: cd, cddvmod, tau2

  cd=0.0015

  do j=lbound(u,2), ubound(u,2)
    do i=lbound(u,1), ubound(u,1)
      tau2=u(i,j)*u(i,j)+v(i,j)*v(i,j)
      cddvmod=sqrt(cd*sqrt(tau2))
      if (cddvmod.ne.0.) then
        u(i,j)=u(i,j)/cddvmod
        v(i,j)=v(i,j)/cddvmod
      else
        u(i,j)=0.
        v(i,j)=0.
      endif
    enddo
  enddo

end subroutine invert_tau_for_du

!#######################################################################

end module ocean_albedo_mod

