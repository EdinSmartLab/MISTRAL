! The main right-hand side wrapper
subroutine cal_nlk(time,u,nlk,work,mask,mask_color,us,Insect,beams)
  use p3dfft_wrapper
  use basic_operators
  use insect_module
  use solid_model
  use vars
  implicit none

  type(timetype), intent(inout) :: time
  real(kind=pr),intent(inout)::u(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  real(kind=pr),intent(inout)::nlk(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  real(kind=pr),intent(inout)::work(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:nrw)
  real(kind=pr),intent(inout)::mask(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  real(kind=pr),intent(inout)::us(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  integer(kind=2),intent(inout)::mask_color(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  type(solid), dimension(1:nBeams),intent(inout) :: beams
  type(diptera), intent(inout) :: Insect
  real(kind=pr)::t1


  !-----------------------------------------------------------------------------
  ! Update mask function to ensure it is at the right time
  !-----------------------------------------------------------------------------
  if ((iMoving==1).and.(iPenalization==1)) then
    call create_mask( time%time,mask,mask_color,us, Insect, beams, 0 )
  endif

  !-----------------------------------------------------------------------------
  ! compute RHS vector
  !-----------------------------------------------------------------------------
  t1 = MPI_wtime()
  select case(method)
  case("centered_2nd")
    if (nx==1) then
      call rhs_acm_2nd_2D(time,u,nlk,work,mask,mask_color,us,Insect,beams,0)
    else
      call rhs_acm_2nd(time,u,nlk,work,mask,mask_color,us,Insect,beams,0)
    endif
  case("centered_4th")
    if (nx==1) then
      call rhs_acm_4th_2D(time,u,nlk,work,mask,mask_color,us,Insect,beams,0)
    else
      call rhs_acm_4th(time,u,nlk,work,mask,mask_color,us,Insect,beams,0)
    endif
  end select
  time_rhs = time_rhs + MPI_wtime() - t1
end subroutine cal_nlk


!-------------------------------------------------------------------------------
! RHS of the penalized ACM equations
!
! du/dt = vor \cross u + nu*laplacian(u) -chi/eta*(u-us) -grad(p) +f
! dp/dt = -c_o^2 * div(u) - gamma*p
!
! computed using second order finite differences. The constant c_o is the
! pseudo speed of sound, gamma is a damping term for the pressure that helps
! reducing spurious oscillations. The forcing term f can be used to gently
! force the mean flow in one direction to unity.
!
! The first step is to synchronize the ghost points on the solution vector
! u=(/ux,uy,uz,p/), and then in one big loop to compute the entire RHS at once.
! Note the loop is more cache-efficient than individual loops or subroutines.
!
! INPUT:
!       time: struct containing the current time, time step and so on
!       u:  solution vector at time n, unchanged
!       mask: mask function containg geometry
!       us: velocity inside solid
!       work: work array, unused
!       mask_color: unused
!       Insect: unused
!       beam: unused
!       impmode: implicit solver mode. 0:explicit; 1:viscous term implicit
! OUTPUT:
!       nlk: the right hand side vector
!-------------------------------------------------------------------------------
subroutine rhs_acm_2nd(time,u,nlk,work,mask,mask_color,us,Insect,beams,impmode)
  use vars
  use insect_module
  use solid_model
  use basic_operators
  use ghosts

  implicit none
  type(timetype), intent(in) :: time
  real(kind=pr),intent(inout)::u(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  real(kind=pr),intent(inout)::nlk(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  real(kind=pr),intent(inout)::work(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:nrw)
  real(kind=pr),intent(inout)::mask(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  real(kind=pr),intent(inout)::us(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  integer(kind=2),intent(inout)::mask_color(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  type(solid), dimension(1:nBeams),intent(inout) :: beams
  type(diptera), intent(inout) :: Insect
  integer, intent(in) :: impmode

  integer::ix,iy,iz
  real(kind=pr)::ux,uy,uz,vorx,vory,vorz,uxdx,uxdy,uxdz,uydx,uydy,uydz,&
  uzdx,uzdy,uzdz,uxdxdx,uxdydy,uxdzdz,uydxdx,uydydy,uydzdz,uzdxdx,uzdydy,uzdzdz,&
  dxinv,dyinv,dzinv,dx2inv,dy2inv,dz2inv,pdx,pdy,pdz,penalx,penaly,penalz,p,fx
  real(kind=pr)::forcing(1:3)

  call synchronize_ghosts(u,neq)

  ! fetch forcing term used to accelerate the mean flow
  call forcing_term(time,u,forcing)

  dxinv = 1.d0/(2.d0*dx)
  dyinv = 1.d0/(2.d0*dy)
  dzinv = 1.d0/(2.d0*dz)

  dx2inv = 1.d0/(dx**2)
  dy2inv = 1.d0/(dy**2)
  dz2inv = 1.d0/(dz**2)

  do iz=ra(3),rb(3)
    do iy=ra(2),rb(2)
      do ix=ra(1),rb(1)
        ux = u(ix,iy,iz,1)
        uy = u(ix,iy,iz,2)
        uz = u(ix,iy,iz,3)
        p  = u(ix,iy,iz,4)

        uxdx = (u(ix+1,iy,iz,1) - u(ix-1,iy,iz,1))*dxinv
        uxdy = (u(ix,iy+1,iz,1) - u(ix,iy-1,iz,1))*dyinv
        uxdz = (u(ix,iy,iz+1,1) - u(ix,iy,iz-1,1))*dzinv

        uydx = (u(ix+1,iy,iz,2) - u(ix-1,iy,iz,2))*dxinv
        uydy = (u(ix,iy+1,iz,2) - u(ix,iy-1,iz,2))*dyinv
        uydz = (u(ix,iy,iz+1,2) - u(ix,iy,iz-1,2))*dzinv

        uzdx = (u(ix+1,iy,iz,3) - u(ix-1,iy,iz,3))*dxinv
        uzdy = (u(ix,iy+1,iz,3) - u(ix,iy-1,iz,3))*dyinv
        uzdz = (u(ix,iy,iz+1,3) - u(ix,iy,iz-1,3))*dzinv

        pdx = (u(ix+1,iy,iz,4) - u(ix-1,iy,iz,4))*dxinv
        pdy = (u(ix,iy+1,iz,4) - u(ix,iy-1,iz,4))*dyinv
        pdz = (u(ix,iy,iz+1,4) - u(ix,iy,iz-1,4))*dzinv

        vorx = uzdy - uydz
        vory = uxdz - uzdx
        vorz = uydx - uxdy

        penalx = -mask(ix,iy,iz)*(ux-us(ix,iy,iz,1))
        penaly = -mask(ix,iy,iz)*(uy-us(ix,iy,iz,2))
        penalz = -mask(ix,iy,iz)*(uz-us(ix,iy,iz,3))

        uxdxdx = (u(ix-1,iy,iz,1)-2.d0*u(ix,iy,iz,1)+u(ix+1,iy,iz,1))*dx2inv
        uxdydy = (u(ix,iy-1,iz,1)-2.d0*u(ix,iy,iz,1)+u(ix,iy+1,iz,1))*dy2inv
        uxdzdz = (u(ix,iy,iz-1,1)-2.d0*u(ix,iy,iz,1)+u(ix,iy,iz+1,1))*dz2inv

        uydxdx = (u(ix-1,iy,iz,2)-2.d0*u(ix,iy,iz,2)+u(ix+1,iy,iz,2))*dx2inv
        uydydy = (u(ix,iy-1,iz,2)-2.d0*u(ix,iy,iz,2)+u(ix,iy+1,iz,2))*dy2inv
        uydzdz = (u(ix,iy,iz-1,2)-2.d0*u(ix,iy,iz,2)+u(ix,iy,iz+1,2))*dz2inv

        uzdxdx = (u(ix-1,iy,iz,3)-2.d0*u(ix,iy,iz,3)+u(ix+1,iy,iz,3))*dx2inv
        uzdydy = (u(ix,iy-1,iz,3)-2.d0*u(ix,iy,iz,3)+u(ix,iy+1,iz,3))*dy2inv
        uzdzdz = (u(ix,iy,iz-1,3)-2.d0*u(ix,iy,iz,3)+u(ix,iy,iz+1,3))*dz2inv

        nlk(ix,iy,iz,1) = uy*vorz -uz*vory - pdx + nu*(uxdxdx+uxdydy+uxdzdz) + penalx + forcing(1)
        nlk(ix,iy,iz,2) = uz*vorx -ux*vorz - pdy + nu*(uydxdx+uydydy+uydzdz) + penaly + forcing(2)
        nlk(ix,iy,iz,3) = ux*vory -uy*vorx - pdz + nu*(uzdxdx+uzdydy+uzdzdz) + penalz + forcing(3)
        nlk(ix,iy,iz,4) = -(c_0**2)*(uxdx+uydy+uzdz) - gamma_p*p
      enddo
    enddo
  enddo
end subroutine



!-------------------------------------------------------------------------------
! RHS of the penalized ACM equations
!
! du/dt = vor \cross u + nu*laplacian(u) -chi/eta*(u-us) -grad(p) +f
! dp/dt = -c_o^2 * div(u) - gamma*p
!
! computed using FOURTH order finite differences. The constant c_o is the
! pseudo speed of sound, gamma is a damping term for the pressure that helps
! reducing spurious oscillations. The forcing term f can be used to gently
! force the mean flow in one direction to unity.
!
! The first step is to synchronize the ghost points on the solution vector
! u=(/ux,uy,uz,p/), and then in one big loop to compute the entire RHS at once.
! Note the loop is more cache-efficient than individual loops or subroutines.
!
! INPUT:
!       time: struct containing the current time, time step and so on
!       u:  solution vector at time n, unchanged
!       mask: mask function containg geometry
!       us: velocity inside solid
!       work: work array, unused
!       mask_color: unused
!       Insect: unused
!       beam: unused
!       impmode: implicit solver mode. 0:explicit; 1: viscous term implicit
! OUTPUT:
!       nlk: the right hand side vector
!-------------------------------------------------------------------------------
subroutine rhs_acm_4th(time,u,nlk,work,mask,mask_color,us,Insect,beams,impmode)
  use vars
  use insect_module
  use solid_model
  use ghosts

  implicit none
  type(timetype), intent(in) :: time
  real(kind=pr),intent(inout)::u(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  real(kind=pr),intent(inout)::nlk(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  real(kind=pr),intent(inout)::work(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:nrw)
  real(kind=pr),intent(inout)::mask(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  real(kind=pr),intent(inout)::us(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  integer(kind=2),intent(inout)::mask_color(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  type(solid), dimension(1:nBeams),intent(inout) :: beams
  type(diptera), intent(inout) :: Insect
  integer, intent(in) :: impmode

  integer::ix,iy,iz
  real(kind=pr)::ux,uy,uz,vorx,vory,vorz,uxdx,uxdy,uxdz,uydx,uydy,uydz,&
  uzdx,uzdy,uzdz,uxdxdx,uxdydy,uxdzdz,uydxdx,uydydy,uydzdz,uzdxdx,uzdydy,uzdzdz,&
  dxinv,dyinv,dzinv,dx2inv,dy2inv,dz2inv,pdx,pdy,pdz,a1,a2,a4,a5,&
  b1,b2,b3,b4,b5,penalx,penaly,penalz,p
  real(kind=pr)::forcing(1:3)
  real(kind=pr)::a(-3:+3)

  call synchronize_ghosts(u,neq)

  ! fetch forcing term used to accelerate the mean flow
  call forcing_term(time,u,forcing)

  a1 = 1.d0/12.d0
  a2 =-2.d0/3.d0
  a4 = 2.d0/3.d0
  a5 = -1.d0/12.d0


  ! Tam & Webb, 4th order optimized
  a=(/-0.02651995d0, +0.18941314d0, -0.79926643d0, 0.0d0, &
       0.79926643d0, -0.18941314d0, 0.02651995d0/)

  b1=-1.d0/12.d0
  b2=4.d0/3.d0
  b3=-5.d0/2.d0
  b4=4.d0/3.d0
  b5=-1.d0/12.d0

  dxinv = 1.d0/dx
  dyinv = 1.d0/dy
  dzinv = 1.d0/dz

  dx2inv = 1.d0/(dx**2)
  dy2inv = 1.d0/(dy**2)
  dz2inv = 1.d0/(dz**2)

  do iz=ra(3),rb(3)
    do iy=ra(2),rb(2)
      do ix=ra(1),rb(1)
        ux = u(ix,iy,iz,1)
        uy = u(ix,iy,iz,2)
        uz = u(ix,iy,iz,3)
        p  = u(ix,iy,iz,4)

        uxdx = (a(-3)*u(ix-3,iy,iz,1)+a(-2)*u(ix-2,iy,iz,1)+a(-1)*u(ix-1,iy,iz,1)+a(0)*u(ix,iy,iz,1)&
               +a(+3)*u(ix+3,iy,iz,1)+a(+2)*u(ix+2,iy,iz,1)+a(+1)*u(ix+1,iy,iz,1))*dxinv
        uxdy = (a(-3)*u(ix,iy-3,iz,1)+a(-2)*u(ix,iy-2,iz,1)+a(-1)*u(ix,iy-1,iz,1)+a(0)*u(ix,iy,iz,1)&
               +a(+3)*u(ix,iy+3,iz,1)+a(+2)*u(ix,iy+2,iz,1)+a(+1)*u(ix,iy+1,iz,1))*dyinv
        uxdz = (a(-3)*u(ix,iy,iz-3,1)+a(-2)*u(ix,iy,iz-2,1)+a(-1)*u(ix,iy,iz-1,1)+a(0)*u(ix,iy,iz,1)&
               +a(+3)*u(ix,iy,iz+3,1)+a(+2)*u(ix,iy,iz+2,1)+a(+1)*u(ix,iy,iz+1,1))*dzinv

        uydx = (a(-3)*u(ix-3,iy,iz,2)+a(-2)*u(ix-2,iy,iz,2)+a(-1)*u(ix-1,iy,iz,2)+a(0)*u(ix,iy,iz,1)&
               +a(+3)*u(ix+3,iy,iz,2)+a(+2)*u(ix+2,iy,iz,2)+a(+1)*u(ix+1,iy,iz,2))*dxinv
        uydy = (a(-3)*u(ix,iy-3,iz,2)+a(-2)*u(ix,iy-2,iz,2)+a(-1)*u(ix,iy-1,iz,2)+a(0)*u(ix,iy,iz,1)&
               +a(+3)*u(ix,iy+3,iz,2)+a(+2)*u(ix,iy+2,iz,2)+a(+1)*u(ix,iy+1,iz,2))*dyinv
        uydz = (a(-3)*u(ix,iy,iz-3,2)+a(-2)*u(ix,iy,iz-2,2)+a(-1)*u(ix,iy,iz-1,2)+a(0)*u(ix,iy,iz,1)&
               +a(+3)*u(ix,iy,iz+3,2)+a(+2)*u(ix,iy,iz+2,2)+a(+1)*u(ix,iy,iz+1,2))*dzinv

        uzdx = (a(-3)*u(ix-3,iy,iz,3)+a(-2)*u(ix-2,iy,iz,3)+a(-1)*u(ix-1,iy,iz,3)+a(0)*u(ix,iy,iz,1)&
               +a(+3)*u(ix+3,iy,iz,3)+a(+2)*u(ix+2,iy,iz,3)+a(+1)*u(ix+1,iy,iz,3))*dxinv
        uzdy = (a(-3)*u(ix,iy-3,iz,3)+a(-2)*u(ix,iy-2,iz,3)+a(-1)*u(ix,iy-1,iz,3)+a(0)*u(ix,iy,iz,1)&
               +a(+3)*u(ix,iy+3,iz,3)+a(+2)*u(ix,iy+2,iz,3)+a(+1)*u(ix,iy+1,iz,3))*dyinv
        uzdz = (a(-3)*u(ix,iy,iz-3,3)+a(-2)*u(ix,iy,iz-2,3)+a(-1)*u(ix,iy,iz-1,3)+a(0)*u(ix,iy,iz,1)&
               +a(+3)*u(ix,iy,iz+3,3)+a(+2)*u(ix,iy,iz+2,3)+a(+1)*u(ix,iy,iz+1,3))*dzinv

        pdx = (a(-3)*u(ix-3,iy,iz,4)+a(-2)*u(ix-2,iy,iz,4)+a(-1)*u(ix-1,iy,iz,4)+a(0)*u(ix,iy,iz,1)&
              +a(+3)*u(ix+3,iy,iz,4)+a(+2)*u(ix+2,iy,iz,4)+a(+1)*u(ix+1,iy,iz,4))*dxinv
        pdy = (a(-3)*u(ix,iy-3,iz,4)+a(-2)*u(ix,iy-2,iz,4)+a(-1)*u(ix,iy-1,iz,4)+a(0)*u(ix,iy,iz,1)&
              +a(+3)*u(ix,iy+3,iz,4)+a(+2)*u(ix,iy+2,iz,4)+a(+1)*u(ix,iy+1,iz,4))*dyinv
        pdz = (a(-3)*u(ix,iy,iz-3,4)+a(-2)*u(ix,iy,iz-2,4)+a(-1)*u(ix,iy,iz-1,4)+a(0)*u(ix,iy,iz,1)&
              +a(+3)*u(ix,iy,iz+3,4)+a(+2)*u(ix,iy,iz+2,4)+a(+1)*u(ix,iy,iz+1,4))*dzinv

        ! penalization term
        penalx = -mask(ix,iy,iz)*(ux-us(ix,iy,iz,1))
        penaly = -mask(ix,iy,iz)*(uy-us(ix,iy,iz,2))
        penalz = -mask(ix,iy,iz)*(uz-us(ix,iy,iz,3))

        ! second derivatives
        uxdxdx = (b1*u(ix-2,iy,iz,1)+b2*u(ix-1,iy,iz,1)+b3*u(ix,iy,iz,1)&
                  +b4*u(ix+1,iy,iz,1)+b5*u(ix+2,iy,iz,1))*dx2inv
        uxdydy = (b1*u(ix,iy-2,iz,1)+b2*u(ix,iy-1,iz,1)+b3*u(ix,iy,iz,1)&
                  +b4*u(ix,iy+1,iz,1)+b5*u(ix,iy+2,iz,1))*dy2inv
        uxdzdz = (b1*u(ix,iy,iz-2,1)+b2*u(ix,iy,iz-1,1)+b3*u(ix,iy,iz,1)&
                  +b4*u(ix,iy,iz+1,1)+b5*u(ix,iy,iz+2,1))*dz2inv

        uydxdx = (b1*u(ix-2,iy,iz,2)+b2*u(ix-1,iy,iz,2)+b3*u(ix,iy,iz,2)&
                  +b4*u(ix+1,iy,iz,2)+b5*u(ix+2,iy,iz,2))*dx2inv
        uydydy = (b1*u(ix,iy-2,iz,2)+b2*u(ix,iy-1,iz,2)+b3*u(ix,iy,iz,2)&
                  +b4*u(ix,iy+1,iz,2)+b5*u(ix,iy+2,iz,2))*dy2inv
        uydzdz = (b1*u(ix,iy,iz-2,2)+b2*u(ix,iy,iz-1,2)+b3*u(ix,iy,iz,2)&
                  +b4*u(ix,iy,iz+1,2)+b5*u(ix,iy,iz+2,2))*dz2inv

        uzdxdx = (b1*u(ix-2,iy,iz,3)+b2*u(ix-1,iy,iz,3)+b3*u(ix,iy,iz,3)&
                  +b4*u(ix+1,iy,iz,3)+b5*u(ix+2,iy,iz,3))*dx2inv
        uzdydy = (b1*u(ix,iy-2,iz,3)+b2*u(ix,iy-1,iz,3)+b3*u(ix,iy,iz,3)&
                  +b4*u(ix,iy+1,iz,3)+b5*u(ix,iy+2,iz,3))*dy2inv
        uzdzdz = (b1*u(ix,iy,iz-2,3)+b2*u(ix,iy,iz-1,3)+b3*u(ix,iy,iz,3)&
                  +b4*u(ix,iy,iz+1,3)+b5*u(ix,iy,iz+2,3))*dz2inv

        ! nlk(ix,iy,iz,1) = uy*vorz -uz*vory - pdx + nu*(uxdxdx+uxdydy+uxdzdz) + penalx + forcing(1)
        ! nlk(ix,iy,iz,2) = uz*vorx -ux*vorz - pdy + nu*(uydxdx+uydydy+uydzdz) + penaly + forcing(2)
        ! nlk(ix,iy,iz,3) = ux*vory -uy*vorx - pdz + nu*(uzdxdx+uzdydy+uzdzdz) + penalz + forcing(3)
        ! nlk(ix,iy,iz,4) = -(c_0**2)*(uxdx+uydy+uzdz) - gamma_p*p

        nlk(ix,iy,iz,1) = -ux*uxdx - uy*uxdy - uz*uxdz - pdx + nu*(uxdxdx + uxdydy + uxdzdz) + penalx + forcing(1)
        nlk(ix,iy,iz,2) = -ux*uydx - uy*uydy - uz*uydz - pdy + nu*(uydxdx + uydydy + uydzdz) + penaly + forcing(2)
        nlk(ix,iy,iz,3) = -ux*uzdx - uy*uzdy - uz*uzdz - pdz + nu*(uzdxdx + uzdydy + uzdzdz) + penalz + forcing(3)
        nlk(ix,iy,iz,4) = -(c_0**2)*(uxdx+uydy+uzdz) - gamma_p*p

      enddo
    enddo
  enddo
end subroutine


!-------------------------------------------------------------------------------
! RHS of the penalized ACM equations
!
! du/dt = vor \cross u + nu*laplacian(u) -chi/eta*(u-us) -grad(p) +f
! dp/dt = -c_o^2 * div(u) - gamma*p
!
! computed using second order finite differences. The constant c_o is the
! pseudo speed of sound, gamma is a damping term for the pressure that helps
! reducing spurious oscillations. The forcing term f can be used to gently
! force the mean flow in one direction to unity.
!
! The first step is to synchronize the ghost points on the solution vector
! u=(/ux,uy,uz,p/), and then in one big loop to compute the entire RHS at once.
! Note the loop is more cache-efficient than individual loops or subroutines.
!
! INPUT:
!       time: struct containing the current time, time step and so on
!       u:  solution vector at time n, unchanged
!       mask: mask function containg geometry
!       us: velocity inside solid
!       work: work array, unused
!       mask_color: unused
!       Insect: unused
!       beam: unused
!       impmode: implicit solver mode. 0:explicit; 1: viscous term implicit
! OUTPUT:
!       nlk: the right hand side vector
!-------------------------------------------------------------------------------
subroutine rhs_acm_2nd_2D(time,u,nlk,work,mask,mask_color,us,Insect,beams,impmode)
  use vars
  use insect_module
  use solid_model
  use basic_operators
  use ghosts

  implicit none
  type(timetype), intent(in) :: time
  real(kind=pr),intent(inout)::u(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  real(kind=pr),intent(inout)::nlk(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  real(kind=pr),intent(inout)::work(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:nrw)
  real(kind=pr),intent(inout)::mask(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  real(kind=pr),intent(inout)::us(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  integer(kind=2),intent(inout)::mask_color(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  type(solid), dimension(1:nBeams),intent(inout) :: beams
  type(diptera), intent(inout) :: Insect
  integer,intent(in) :: impmode

  integer::ix,iy,iz
  real(kind=pr)::uy,uz,vorx,uydy,uydz,&
  uzdy,uzdz,uydydy,uydzdz,uzdydy,uzdzdz,&
  dyinv,dzinv,dy2inv,dz2inv,pdy,pdz,penaly,penalz,p,fx
  real(kind=pr)::forcing(1:3)

  call synchronize_ghosts(u,neq)

  ! fetch forcing term used to accelerate the mean flow
  call forcing_term(time,u,forcing)

  dyinv = 1.d0/(2.d0*dy)
  dzinv = 1.d0/(2.d0*dz)

  dy2inv = 1.d0/(dy**2)
  dz2inv = 1.d0/(dz**2)

  ix=0

  do iz=ra(3),rb(3)
    do iy=ra(2),rb(2)
      uy = u(ix,iy,iz,2)
      uz = u(ix,iy,iz,3)
      p  = u(ix,iy,iz,4)

      uydy = (u(ix,iy+1,iz,2) - u(ix,iy-1,iz,2))*dyinv
      uydz = (u(ix,iy,iz+1,2) - u(ix,iy,iz-1,2))*dzinv

      uzdy = (u(ix,iy+1,iz,3) - u(ix,iy-1,iz,3))*dyinv
      uzdz = (u(ix,iy,iz+1,3) - u(ix,iy,iz-1,3))*dzinv

      pdy  = (u(ix,iy+1,iz,4) - u(ix,iy-1,iz,4))*dyinv
      pdz  = (u(ix,iy,iz+1,4) - u(ix,iy,iz-1,4))*dzinv

      vorx = uzdy - uydz

      penaly = -mask(ix,iy,iz)*(uy-us(ix,iy,iz,2))
      penalz = -mask(ix,iy,iz)*(uz-us(ix,iy,iz,3))

      uydydy = (u(ix,iy-1,iz,2)-2.d0*u(ix,iy,iz,2)+u(ix,iy+1,iz,2))*dy2inv
      uydzdz = (u(ix,iy,iz-1,2)-2.d0*u(ix,iy,iz,2)+u(ix,iy,iz+1,2))*dz2inv

      uzdydy = (u(ix,iy-1,iz,3)-2.d0*u(ix,iy,iz,3)+u(ix,iy+1,iz,3))*dy2inv
      uzdzdz = (u(ix,iy,iz-1,3)-2.d0*u(ix,iy,iz,3)+u(ix,iy,iz+1,3))*dz2inv

      nlk(ix,iy,iz,1) = 0.d0
      nlk(ix,iy,iz,2) = -uy*uydy - uz*uydz -pdy + nu*(uydydy+uydzdz) + penaly + forcing(2)
      nlk(ix,iy,iz,3) = -uy*uzdy - uz*uzdz -pdz + nu*(uzdydy+uzdzdz) + penalz + forcing(3)
      nlk(ix,iy,iz,4) = -(c_0**2)*(uydy+uzdz) - gamma_p*p
    enddo
  enddo
end subroutine



!-------------------------------------------------------------------------------
! RHS of the penalized ACM equations
!
! du/dt = vor \cross u + nu*laplacian(u) -chi/eta*(u-us) -grad(p) +f
! dp/dt = -c_o^2 * div(u) - gamma*p
!
! computed using FOURTH order finite differences. The constant c_o is the
! pseudo speed of sound, gamma is a damping term for the pressure that helps
! reducing spurious oscillations. The forcing term f can be used to gently
! force the mean flow in one direction to unity.
!
! The first step is to synchronize the ghost points on the solution vector
! u=(/ux,uy,uz,p/), and then in one big loop to compute the entire RHS at once.
! Note the loop is more cache-efficient than individual loops or subroutines.
!
! INPUT:
!       time: struct containing the current time, time step and so on
!       u:  solution vector at time n, unchanged
!       mask: mask function containg geometry
!       us: velocity inside solid
!       work: work array, unused
!       mask_color: unused
!       Insect: unused
!       beam: unused
!       impmode: implicit solver mode. 0:explicit; 1: viscous term implicit
! OUTPUT:
!       nlk: the right hand side vector
!-------------------------------------------------------------------------------
subroutine rhs_acm_4th_2d(time,u,nlk,work,mask,mask_color,us,Insect,beams,impmode)
  use vars
  use insect_module
  use solid_model
  use ghosts

  implicit none
  type(timetype), intent(in) :: time
  real(kind=pr),intent(inout)::u(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  real(kind=pr),intent(inout)::nlk(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  real(kind=pr),intent(inout)::work(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:nrw)
  real(kind=pr),intent(inout)::mask(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  real(kind=pr),intent(inout)::us(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  integer(kind=2),intent(inout)::mask_color(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  type(solid), dimension(1:nBeams),intent(inout) :: beams
  type(diptera), intent(inout) :: Insect
  integer, intent(in) :: impmode

  integer::ix,iy,iz
  real(kind=pr)::uy,uz,vorx,uydy,uydz,&
  uzdy,uzdz,uydydy,uydzdz,uzdydy,uzdzdz,&
  dyinv,dzinv,dy2inv,dz2inv,pdy,pdz,a1,a2,a4,a5,&
  b1,b2,b3,b4,b5,penaly,penalz,p
  real(kind=pr)::forcing(1:3)
  real(kind=pr)::a(-3:+3)

  call synchronize_ghosts(u,neq)

  ! fetch forcing term used to accelerate the mean flow
  call forcing_term(time,u,forcing)

  a1 = 1.d0/12.d0
  a2 =-2.d0/3.d0
  a4 = 2.d0/3.d0
  a5 = -1.d0/12.d0


  ! Tam & Webb, 4th order optimized
  a=(/-0.02651995d0, +0.18941314d0, -0.79926643d0, 0.0d0, &
       0.79926643d0, -0.18941314d0, 0.02651995d0/)

  b1=-1.d0/12.d0
  b2=4.d0/3.d0
  b3=-5.d0/2.d0
  b4=4.d0/3.d0
  b5=-1.d0/12.d0

  dyinv = 1.d0/dy
  dzinv = 1.d0/dz

  dy2inv = 1.d0/(dy**2)
  dz2inv = 1.d0/(dz**2)

  ix=0

  do iz=ra(3),rb(3)
    do iy=ra(2),rb(2)
      uy = u(ix,iy,iz,2)
      uz = u(ix,iy,iz,3)
      p  = u(ix,iy,iz,4)

      uydy = (a(-3)*u(ix,iy-3,iz,2)+a(-2)*u(ix,iy-2,iz,2)+a(-1)*u(ix,iy-1,iz,2)+a(0)*u(ix,iy,iz,1)&
             +a(+3)*u(ix,iy+3,iz,2)+a(+2)*u(ix,iy+2,iz,2)+a(+1)*u(ix,iy+1,iz,2))*dyinv
      uydz = (a(-3)*u(ix,iy,iz-3,2)+a(-2)*u(ix,iy,iz-2,2)+a(-1)*u(ix,iy,iz-1,2)+a(0)*u(ix,iy,iz,1)&
             +a(+3)*u(ix,iy,iz+3,2)+a(+2)*u(ix,iy,iz+2,2)+a(+1)*u(ix,iy,iz+1,2))*dzinv

      uzdy = (a(-3)*u(ix,iy-3,iz,3)+a(-2)*u(ix,iy-2,iz,3)+a(-1)*u(ix,iy-1,iz,3)+a(0)*u(ix,iy,iz,1)&
             +a(+3)*u(ix,iy+3,iz,3)+a(+2)*u(ix,iy+2,iz,3)+a(+1)*u(ix,iy+1,iz,3))*dyinv
      uzdz = (a(-3)*u(ix,iy,iz-3,3)+a(-2)*u(ix,iy,iz-2,3)+a(-1)*u(ix,iy,iz-1,3)+a(0)*u(ix,iy,iz,1)&
             +a(+3)*u(ix,iy,iz+3,3)+a(+2)*u(ix,iy,iz+2,3)+a(+1)*u(ix,iy,iz+1,3))*dzinv

      pdy = (a(-3)*u(ix,iy-3,iz,4)+a(-2)*u(ix,iy-2,iz,4)+a(-1)*u(ix,iy-1,iz,4)+a(0)*u(ix,iy,iz,1)&
            +a(+3)*u(ix,iy+3,iz,4)+a(+2)*u(ix,iy+2,iz,4)+a(+1)*u(ix,iy+1,iz,4))*dyinv
      pdz = (a(-3)*u(ix,iy,iz-3,4)+a(-2)*u(ix,iy,iz-2,4)+a(-1)*u(ix,iy,iz-1,4)+a(0)*u(ix,iy,iz,1)&
            +a(+3)*u(ix,iy,iz+3,4)+a(+2)*u(ix,iy,iz+2,4)+a(+1)*u(ix,iy,iz+1,4))*dzinv

      ! vorticity
      vorx = uzdy - uydz

      ! penalization term
      penaly = -mask(ix,iy,iz)*(uy-us(ix,iy,iz,2))
      penalz = -mask(ix,iy,iz)*(uz-us(ix,iy,iz,3))

      ! second derivatives
      uydydy = (b1*u(ix,iy-2,iz,2)+b2*u(ix,iy-1,iz,2)+b3*u(ix,iy,iz,2)&
                +b4*u(ix,iy+1,iz,2)+b5*u(ix,iy+2,iz,2))*dy2inv
      uydzdz = (b1*u(ix,iy,iz-2,2)+b2*u(ix,iy,iz-1,2)+b3*u(ix,iy,iz,2)&
                +b4*u(ix,iy,iz+1,2)+b5*u(ix,iy,iz+2,2))*dz2inv

      uzdydy = (b1*u(ix,iy-2,iz,3)+b2*u(ix,iy-1,iz,3)+b3*u(ix,iy,iz,3)&
                +b4*u(ix,iy+1,iz,3)+b5*u(ix,iy+2,iz,3))*dy2inv
      uzdzdz = (b1*u(ix,iy,iz-2,3)+b2*u(ix,iy,iz-1,3)+b3*u(ix,iy,iz,3)&
                +b4*u(ix,iy,iz+1,3)+b5*u(ix,iy,iz+2,3))*dz2inv

      nlk(ix,iy,iz,1) = 0.d0
      nlk(ix,iy,iz,2) = -uy*uydy - uz*uydz -pdy + nu*(uydydy+uydzdz) + penaly + forcing(2)
      nlk(ix,iy,iz,3) = -uy*uzdy - uz*uzdz -pdz + nu*(uzdydy+uzdzdz) + penalz + forcing(3)
      nlk(ix,iy,iz,4) = -(c_0**2)*(uydy+uzdz) - gamma_p*p
    enddo
  enddo
end subroutine


!-------------------------------------------------------------------------------
! Forcing term for mean flow acceleration
! We add a spatially constant force, that may be time and u-dependend, to the
! ACM equations in order to accelerate the mean flow
! TODO:
!       the old "dynamic" mean flow forcing with given fluid mass requires the
!       penalization term here
!-------------------------------------------------------------------------------
subroutine forcing_term(time,u,forcing)
  use vars
  use basic_operators

  implicit none
  type(timetype),intent(in):: time
  real(kind=pr),intent(inout) :: u(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3),1:neq)
  real(kind=pr),intent(inout):: forcing(1:3)

  real(kind=pr) :: ux_mean,uy_mean,uz_mean

  forcing = 0.d0

  if (iMeanFlow_x=="accelerate_to_unity") then
    ! compute mean velocity in this direction
    ux_mean = volume_integral(u(:,:,:,1))/(xl*yl*zl)
    ! the force stabilizes around unity
    forcing(1) = max(0.d0,1.d0-ux_mean)*startup_conditioner(time%time,0.d0,0.50d0)
  endif

  if (iMeanFlow_y=="accelerate_to_unity") then
    uy_mean = volume_integral(u(:,:,:,2))/(xl*yl*zl)
    forcing(2) = max(0.d0,1.d0-uy_mean)*startup_conditioner(time%time,0.d0,0.50d0)
  endif

  if (iMeanFlow_z=="accelerate_to_unity") then
    uz_mean = volume_integral(u(:,:,:,3))/(xl*yl*zl)
    forcing(3) = max(0.d0,1.d0-uz_mean)*startup_conditioner(time%time,0.d0,0.50d0)
  endif

end subroutine forcing_term
