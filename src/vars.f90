! Variables for pseudospectral simnulations
module vars
  use mpi
  implicit none


  integer,parameter :: nlines=2048 ! maximum number of lines in PARAMS-file
  integer,parameter :: strlen=80   ! standard string length
  ! Precision of doubles
  integer,parameter :: pr = 8

  !-----------------------------------------------------------------------------
  ! Type declarations
  !-----------------------------------------------------------------------------
  ! The derived integral quantities for fluid-structure interactions.
  type Integrals
     real(kind=pr) :: time
     real(kind=pr) :: EKin
     real(kind=pr) :: Dissip
     real(kind=pr) :: Divergence
     real(kind=pr) :: Volume
     real(kind=pr) :: APow
     real(kind=pr) :: IPow
     real(kind=pr) :: penalization_power
     real(kind=pr) :: penalization_power_x
     real(kind=pr) :: penalization_power_y
     real(kind=pr) :: penalization_power_z
     real(kind=pr),dimension(1:3) :: Force
     real(kind=pr),dimension(1:3) :: Force_unst
     real(kind=pr),dimension(1:3) :: Torque
     real(kind=pr),dimension(1:3) :: Torque_unst
  end type Integrals
  !-----------------------------------------------------------------------------
  ! derived datatype for rigid solid dynamics solver
  type SolidDynType
    ! solid dynamics solver flag (0=off, 1=on)
    integer :: idynamics
    ! vector of unknowns at new time step
    real(kind=pr), dimension(1:4) :: var_new
    ! vector of unknowns at current time step
    real(kind=pr), dimension(1:4) :: var_this
    ! rhs at current time step
    real(kind=pr), dimension(1:4) :: rhs_this
    ! rhs at previous time step
    real(kind=pr), dimension(1:4) :: rhs_old
  end type SolidDynType
  !-----------------------------------------------------------------------------
  ! derived datatype for time
  type timetype
    real(kind=pr) :: time
    real(kind=pr) :: dt_new
    real(kind=pr) :: dt_old
    integer :: it, it_start
    integer :: n0
    integer :: n1
  end type timetype



  !-----------------------------------------------------------------------------
  ! Global parameters and variables
  !-----------------------------------------------------------------------------

  ! Method variables set in the program file:
  character(len=strlen),save :: method
  character(len=strlen),save :: dry_run_without_fluid ! just save mask function
  character(len=strlen),save :: iMethodOrder = "4th-opt"
  character(len=strlen),save :: p_mean_zero = "no"

  integer,save :: neq ! number of equations
  integer,save :: nrw ! number of real work arrays in work
  integer,save :: ng  ! number of ghostpoints (if used)
  integer,save :: nrhs ! number of registers for right hand side vectors

  ! MPI and p3dfft variables and parameters
  integer,save :: mpisize, mpirank
  ! Local array bounds
  integer,dimension (1:3),save :: ra,rb,rs,ca,cb,cs
  ! Local array bounds with ghost points
  integer,dimension (1:3),save :: ga,gb
  ! Local array bounds for real arrays for all MPI processes
  integer, dimension (:,:), allocatable, save :: ra_table, rb_table
  ! for simplicity, store what decomposition we use
  character(len=strlen), save :: decomposition

  ! p3dfft domain decomposition parameters and communicators
  integer,save :: mpicommcart,mpicommy,mpicommz,mpitaskid,mpitasks
  integer,dimension(2),save :: mpidims,mpicoords,mpicommslab
  ! only root rank has this true:
  logical, save :: root=.false.

  real(kind=pr),save :: pi ! 3.14....

  ! Vabiables timing statistics.  Global to simplify syntax.
  real(kind=pr),save :: time_mask,tstart=0.d0
  real(kind=pr),save :: time_vor, time_p
  real(kind=pr),save :: time_bckp, time_save, time_total, time_fluid
  real(kind=pr),save :: time_insect_body
  real(kind=pr),save :: time_insect_wings, time_insect_vel
  real(kind=pr),save :: time_solid, time_drag, time_surf, time_LAPACK, time_sync
  real(kind=pr),save :: time_hdf5, time_integrals, time_rhs

  ! Variables set via the parameters file
  real(kind=pr),save :: length

  ! Domain size variables:
  integer,save :: nx,ny,nz
  real(kind=pr),save :: xl,yl,zl,dx,dy,dz,scalex,scaley,scalez

  ! Parameters to set which files are saved and how often:
  integer,save :: iSaveVelocity,iSaveVorticity,iSavePress,iSaveMask
  integer,save :: iSaveSolidVelocity,iSaveDivergence
  integer,save :: idobackup, striding=1
  integer,save :: iSaveXMF !directly write *.XMF files (1) or not (0)
  real(kind=pr),save :: tintegral ! Time between output of integral quantities
  real(kind=pr),save :: tsave ! Time between outpout of entire fields.
  real(kind=pr),save :: tsave_first ! don't save before this time
  ! compute drag force every itdrag time steps and compute unst corrections if
  ! you've told to do so.
  integer,save :: itdrag, unst_corrections
  ! save beam every itbeam time steps
  integer,save :: itbeam
  real(kind=pr),save :: truntime, truntimenext ! Number of hours bet
  real(kind=pr),save :: wtimemax ! Stop after a certain number of hours of wall.
  ! for periodically repeating flows, it may be better to always have only
  ! one set of files on the disk
  character(len=strlen),save :: save_only_one_period, field_precision="single"
  real(kind=pr),save :: tsave_period ! then this is period time

  ! Time-stepping parameters
  real(kind=pr),save :: tmax
  real(kind=pr),save :: dt_fixed
  real(kind=pr),save :: dt_max=0.d0
  real(kind=pr),save :: cfl
  integer,save :: nt
  character(len=strlen),save :: iTimeMethodFluid, intelligent_dt="no"

  ! viscosity (inverse of Reynolds number:)
  real(kind=pr),save :: nu, eps_sponge

  ! pseudo speed of sound for the artificial compressibility method
  real(kind=pr), save :: c_0, gamma_p

  ! Initial conditions:
  character(len=strlen),save :: inicond,file_ux,file_uy,file_uz,file_p


  ! Boundary conditions:
  character(len=strlen),save :: iMask
  integer,save :: iMoving,iPenalization
  real(kind=pr),save :: eps
  real(kind=pr),save :: x0,y0,z0 ! Parameters for logical centre of obstacle
  ! cavity mask:
  character(len=strlen), save :: iCavity, iChannel
  integer, save :: cavity_size
  ! wall thickness
  real(kind=pr),save :: thick_wall
  ! wall position (solid from pos_wall to pos_wall+thick_wall)
  real(kind=pr),save :: pos_wall
  ! periodization of coordinates
  logical, save :: periodic = .false.

  ! save forces and use unsteady corrections?
  integer, save :: compute_forces

  ! mean flow control
  real(kind=pr),save :: Uxmean,Uymean,Uzmean, m_fluid
  character(len=strlen),save :: iMeanFlow_x,iMeanFlow_y,iMeanFlow_z
  ! mean flow startup conditioner (if "dynamic" and mean flow at t=0 is not zero
  ! the forces are singular at the beginning. use the startup conditioner to
  ! avoid large accelerations in mean flow at the beginning)
  character(len=strlen),save :: iMeanFlowStartupConditioner
  real(kind=pr) :: tau_meanflow, T_release_meanflow



  ! solid model main switch
  character(len=strlen),save :: use_solid_model

  !-----------------------------------------------------------------------------

  type(Integrals),save :: GlobalIntegrals
  type(SolidDynType), save :: SolidDyn

  !*****************************************************************************
  !*****************************************************************************
  !*****************************************************************************
  ! Helper routines for general purpose use throughout the code
  !*****************************************************************************
  !*****************************************************************************
  !*****************************************************************************
    interface abort
      module procedure abort2, abort4, abort3
    end interface

    interface in_domain
      module procedure in_domain1, in_domain2
    end interface

    interface on_proc
      module procedure on_proc1, on_proc2
    end interface


  !!!!!!!!!!
    contains
  !!!!!!!!!!


    !-----------------------------------------------------------------------------
    ! convert degree to radiant
    !-----------------------------------------------------------------------------
    real(kind=pr) function deg2rad(deg)
      implicit none
      real(kind=pr), intent(in) :: deg
      deg2rad=deg*pi/180.d0
      return
    end function

    !-----------------------------------------------------------------------------
    ! radiant to degree
    !-----------------------------------------------------------------------------
    real(kind=pr) function rad2deg(deg)
      implicit none
      real(kind=pr), intent(in) :: deg
      rad2deg=deg*180.d0/pi
      return
    end function

    !-----------------------------------------------------------------------------
    ! cross product of two vectors
    !-----------------------------------------------------------------------------
    function cross(a,b)
      implicit none
      real(kind=pr),dimension(1:3),intent(in) :: a,b
      real(kind=pr),dimension(1:3) :: cross
      cross(1) = a(2)*b(3)-a(3)*b(2)
      cross(2) = a(3)*b(1)-a(1)*b(3)
      cross(3) = a(1)*b(2)-a(2)*b(1)
    end function

    !-----------------------------------------------------------------------------
    ! 2-norm length of vectors
    !-----------------------------------------------------------------------------
    function norm2(a)
      implicit none
      real(kind=pr),dimension(1:3),intent(in) :: a
      real(kind=pr) :: norm2
      norm2 = dsqrt( a(1)*a(1) + a(2)*a(2) + a(3)*a(3) )
    end function

    !---------------------------------------------------------------------------
    ! return periodic index, i.e. if we give ix greater than nx, return
    ! smallest image convention. used, e.g., when computing finite difference
    ! operators or interpolations
    !---------------------------------------------------------------------------
    integer function GetIndex(ix,nx)
      implicit none
      integer, intent (in) ::ix,nx
      integer :: tmp
      tmp=ix
      if (tmp<0) tmp = tmp+nx
      if (tmp>nx-1) tmp = tmp-nx
      GetIndex=tmp
      return
    end function GetIndex
    !---------------------------------------------------------------------------
    integer function per(ix,nx)
      implicit none
      integer, intent (in) ::ix,nx
      integer :: tmp
      tmp=ix
      if (tmp<0) tmp = tmp+nx
      if (tmp<0) tmp = tmp+nx
      if (tmp>nx-1) tmp = tmp-nx
      if (tmp>nx-1) tmp = tmp-nx
      if (nx==1) tmp=0
      per=tmp
      return
    end function per

    !---------------------------------------------------------------------------
    ! abort run, with or without bye-bye message
    !---------------------------------------------------------------------------
    subroutine abort2(msg)
      use mpi
      implicit none
      integer :: mpicode
      character(len=*), intent(in) :: msg
      ! it produces a  lot of output for all procs to write the message, but if
      ! root does not call this routine, you don't see anything...
      write(*,*) msg
      call MPI_abort(MPI_COMM_WORLD,666,mpicode)
    end subroutine abort2
    !---------------------------------------------------------------------------
    subroutine abort3(code)
      use mpi
      implicit none
      integer, intent(in) :: code
      integer :: mpicode
      ! at least with the error code you can find where the code aborted...
      call MPI_abort(MPI_COMM_WORLD,code,mpicode)
    end subroutine abort3
    !---------------------------------------------------------------------------
    subroutine abort4(code,msg)
      use mpi
      implicit none
      integer :: mpicode
      integer, intent(in) :: code
      character(len=*), intent(in) :: msg
      ! it produces a  lot of output for all procs to write the message, but if
      ! root does not call this routine, you don't see anything...
      write(*,*) msg
      call MPI_abort(MPI_COMM_WORLD,code,mpicode)
    end subroutine abort4

    !---------------------------------------------------------------------------
    ! wrapper for NaN checking (this may be compiler dependent)
    !---------------------------------------------------------------------------
    logical function is_nan( x )
      implicit none
      real(kind=pr)::x
      is_nan = .false.
      if (.not.(x.eq.x)) is_nan=.true.
    end function

    !---------------------------------------------------------------------------
    ! check wether real coordinates x are in the domain
    !---------------------------------------------------------------------------
    logical function in_domain1( x )
      implicit none
      real(kind=pr),intent(in)::x(1:3)
      in_domain1 = .false.
      if ( ((x(1)>=0.d0).and.(x(1)<xl)).and.&
           ((x(2)>=0.d0).and.(x(2)<yl)).and.&
           ((x(3)>=0.d0).and.(x(3)<zl)) ) in_domain1=.true.
    end function

    !---------------------------------------------------------------------------
    ! check wether integer coordinates x are in the domain
    !---------------------------------------------------------------------------
    logical function in_domain2( x )
      implicit none
      integer,intent(in)::x(1:3)
      in_domain2 = .false.
      if (  ((x(1)>=0).and.(x(1)<nx-1)).and.&
            ((x(2)>=0).and.(x(2)<ny-1)).and.&
            ((x(3)>=0).and.(x(3)<nz-1)) ) in_domain2=.true.
    end function

    !---------------------------------------------------------------------------
    ! check wether real coordinates x are on this mpi-process
    !---------------------------------------------------------------------------
    logical function on_proc1( x )
      implicit none
      real(kind=pr),intent(in)::x(1:3)
      on_proc1 = .false.
      if (  ((x(1)>=ra(1)*dx).and.(x(1)<=rb(1)*dx)).and.&
            ((x(2)>=ra(2)*dy).and.(x(2)<=rb(2)*dy)).and.&
            ((x(3)>=ra(3)*dz).and.(x(3)<=rb(3)*dz)) ) on_proc1=.true.
    end function

    !---------------------------------------------------------------------------
    ! check wether integer coordinates x are on this mpi-process
    !---------------------------------------------------------------------------
    logical function on_proc2( x )
      implicit none
      integer,intent(in)::x(1:3)
      on_proc2 = .false.
      if ( ((x(1)>=ra(1)).and.(x(1)<=rb(1))).and.&
           ((x(2)>=ra(2)).and.(x(2)<=rb(2))).and.&
           ((x(3)>=ra(3)).and.(x(3)<=rb(3))) ) on_proc2=.true.
    end function

    !---------------------------------------------------------------------------
    ! wrapper for random number generator (this may be compiler dependent)
    !---------------------------------------------------------------------------
    real(kind=pr) function rand_nbr()
      implicit none
      call random_number( rand_nbr )
    end function

    !---------------------------------------------------------------------------
    ! soft startup funtion, is zero until time=time_release, then gently goes to
    ! one during the time period time_tau
    !---------------------------------------------------------------------------
    real(kind=pr) function startup_conditioner(time,time_release,time_tau)
      implicit none
      real(kind=pr), intent(in) :: time,time_release,time_tau
      real(kind=pr) :: t

      t = time-time_release

      if (time <= time_release) then
        startup_conditioner = 0.d0
      elseif ( ( time >time_release ).and.(time<(time_release + time_tau)) ) then
        startup_conditioner =  (t**3)/(-0.5d0*time_tau**3) + 3.d0*(t**2)/time_tau**2
      else
        startup_conditioner = 1.d0
      endif
    end function

    !-----------------------------------------------------------------------------
    ! Condition for output conditions.
    ! return true after tfrequ time units or itfrequ time steps or if we're at the
    ! and of the simulation
    !-----------------------------------------------------------------------------
    logical function time_for_output( time, dt, it, tfrequ, ifrequ, tmax, tfirst )
      implicit none
      real(kind=pr), intent(in) :: time, dt, tfrequ, tfirst
      real(kind=pr), intent(in) :: tmax ! final time (if we save at the end of run)
      integer, intent(in) :: it ! time step counter
      integer, intent(in) :: ifrequ ! save every ifrequ time steps

      real(kind=pr) :: tnext1, tnext2

      time_for_output = .false.

      ! we never save before tfirst
      if (time<tfirst) return

      if (intelligent_dt=="yes") then
        ! with intelligent time stepping activated, the time step is adjusted not
        ! to pass by tsave,tintegral,tmax,tslice
        ! this is the next instant we want to save
        tnext1 = dble(ceiling(time/tfrequ))*tfrequ
        tnext2 = dble(floor  (time/tfrequ))*tfrequ
        ! please note that the time actually is very close to the next instant we
        ! want to save. however, it may be slightly less or larger. therefore, we
        ! cannot just check (time-tnext), since tnext may be wrong
        if ((abs(time-tnext1)<=1.0d-6).or.(abs(time-tnext2)<=1.0d-6).or.&
            (modulo(it,ifrequ)==0).or.(abs(time-tmax)<=1.0d-6)) then
          time_for_output = .true.
        endif
      else
        ! without intelligent time stepping, we save output when we're close enough
        if ( (modulo(time,tfrequ)<dt).or.(modulo(it,ifrequ)==0).or.(time==tmax) ) then
          time_for_output = .true.
        endif
      endif
    end function

    !-----------------------------------------------------------------------------
    ! given a point x, check if it lies in the computational domain centered at zero
    ! (note: we assume [-xl/2...+xl/2] size this is useful for insects )
    !-----------------------------------------------------------------------------
    function periodize_coordinate(x_glob)
      real(kind=pr),intent(in) :: x_glob(1:3)
      real(kind=pr),dimension(1:3) :: periodize_coordinate

      periodize_coordinate = x_glob

      if (periodic) then
        if (x_glob(1)<-xl/2.0) periodize_coordinate(1)=x_glob(1)+xl
        if (x_glob(2)<-yl/2.0) periodize_coordinate(2)=x_glob(2)+yl
        if (x_glob(3)<-zl/2.0) periodize_coordinate(3)=x_glob(3)+zl

        if (x_glob(1)>xl/2.0) periodize_coordinate(1)=x_glob(1)-xl
        if (x_glob(2)>yl/2.0) periodize_coordinate(2)=x_glob(2)-yl
        if (x_glob(3)>zl/2.0) periodize_coordinate(3)=x_glob(3)-zl
      endif

    end function


end module vars
