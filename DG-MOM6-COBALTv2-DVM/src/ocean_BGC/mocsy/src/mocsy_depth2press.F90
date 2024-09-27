!> \file depth2press.F90
!! \BRIEF 
!> Module with depth2press subroutine - converts depth to pressure
!! with Saunders (1981) formula
MODULE mocsy_depth2press

USE mocsy_singledouble, only : rx, r8, wp
USE mocsy_p80, only : p80

IMPLICIT NONE ; PRIVATE

PUBLIC depth2press

CONTAINS
!>     Compute pressure [db] from depth [m] & latitude [degrees north].
!!     This subroutine is needed because p80 is a function (using scalars not arrays)
SUBROUTINE depth2press(depth, lat, pdbar, N)

  !     Purpose:
  !     Compute pressure [db] from depth [m] & latitude [degrees north].
  !     Needed because p80 is a function 


  !> number of records
!f2py intent(hide) n
  INTEGER, intent(in) :: N

! INPUT variables
  !> depth [m]
  REAL(kind=rx), INTENT(in), DIMENSION(N) :: depth
  !> latitude [degrees]
  REAL(kind=rx), INTENT(in), DIMENSION(N) :: lat

! OUTPUT variables:
  !> pressure [db]
  REAL(kind=rx), INTENT(out), DIMENSION(N) :: pdbar

  !     Local variables
  INTEGER :: i

! REAL(kind=rx) ::  p80
! EXTERNAL p80

  DO i = 1,N
     pdbar(i) = p80(depth(i), lat(i))
  END DO

  RETURN
END SUBROUTINE depth2press
END MODULE mocsy_depth2press
