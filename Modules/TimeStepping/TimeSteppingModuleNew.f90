MODULE TimeSteppingModule

  USE KindModule, ONLY: &
    DP
  USE UnitsModule, ONLY: &
    UnitsDisplay
  USE ProgramHeaderModule, ONLY: &
    nX, nDOFX, nNodes, &
    nE, nDOF
  USE MeshModule, ONLY: &
    MeshX
  USE GeometryModule, ONLY: &
    a, b, c
  USE FluidFieldsModule, ONLY: &
    uCF, rhsCF, nCF, nPF, nAF, iPF_V1, iPF_V2, iPF_V3, iAF_Cs
  USE RadiationFieldsModule, ONLY: &
    uCR, rhsCR, nCR, nSpecies
  USE EquationOfStateModule, ONLY: &
    Auxiliary_Fluid
  USE InputOutputModule, ONLY: &
    WriteFields1D
  USE EulerEquationsUtilitiesModule, ONLY: &
    Primitive, &
    Eigenvalues
  USE FluidEvolutionModule, ONLY: &
    ComputeRHS_Fluid, &
    ApplySlopeLimiter_Fluid, &
    ApplyPositivityLimiter_Fluid
  USE RadiationEvolutionModule, ONLY: &
    ComputeRHS_Radiation, &
    ApplySlopeLimiter_Radiation
  USE FluidRadiationCouplingModule, ONLY: &
    CoupleFluidRadiation
  USE BoundaryConditionsModule, ONLY: &
    ApplyBoundaryConditions_Fluid, &
    ApplyBoundaryConditions_Radiation

  IMPLICIT NONE
  PRIVATE

  REAL(DP) :: wtR, wtS, wtP

  LOGICAL :: EvolveFluid     = .FALSE.
  LOGICAL :: EvolveRadiation = .FALSE.
  INTEGER :: nStages_SSP_RK  = 1
  INTEGER :: nStages_SI_RK   = 1
  REAL(DP), DIMENSION(:,:,:,:,:),     ALLOCATABLE :: uCF_0
  REAL(DP), DIMENSION(:,:,:,:,:,:,:), ALLOCATABLE :: uCR_0

  PROCEDURE (TimeStepper), POINTER, PUBLIC :: &
    SSP_RK => NULL(), &
    SI_RK  => NULL()

  INTERFACE
    SUBROUTINE TimeStepper( t, dt )
      USE KindModule, ONLY: DP
      REAL(DP), INTENT(in) :: t, dt
    END SUBROUTINE TimeStepper
  END INTERFACE

  PUBLIC :: InitializeTimeStepping
  PUBLIC :: FinalizeTimeStepping
  PUBLIC :: EvolveFields
  PUBLIC :: BackwardEuler

CONTAINS


  SUBROUTINE InitializeTimeStepping &
               ( EvolveFluid_Option, EvolveRadiation_Option, &
                 nStages_SSP_RK_Option, nStages_SI_RK_Option )

    LOGICAL, INTENT(in), OPTIONAL :: EvolveFluid_Option
    LOGICAL, INTENT(in), OPTIONAL :: EvolveRadiation_Option
    INTEGER, INTENT(in), OPTIONAL :: nStages_SSP_RK_Option
    INTEGER, INTENT(in), OPTIONAL :: nStages_SI_RK_Option

    IF( PRESENT( EvolveFluid_Option ) )THEN
      EvolveFluid = EvolveFluid_Option
    END IF
    WRITE(*,*)
    WRITE(*,'(A5,A19,L1)') '', 'Evolve Fluid = ', EvolveFluid

    IF( PRESENT( EvolveRadiation_Option ) )THEN
      EvolveRadiation = EvolveRadiation_Option
    END IF
    WRITE(*,'(A5,A19,L1)') '', 'Evolve Radiation = ', EvolveRadiation
    WRITE(*,*)

    IF( PRESENT( nStages_SSP_RK_Option ) )THEN
      nStages_SSP_RK = nStages_SSP_RK_Option
    END IF

    SELECT CASE ( nStages_SSP_RK )
      CASE ( 1 )

        SSP_RK => SSP_RK1

      CASE ( 2 )

        SSP_RK => SSP_RK2

      CASE ( 3 )

        SSP_RK => SSP_RK3

      CASE DEFAULT

        WRITE(*,*)
        WRITE(*,'(A4,A43,I2.2)') &
          '', 'SSP_RK not implemented for nStatgesSSPRK = ', nStages_SSP_RK
        STOP

    END SELECT

    IF( PRESENT( nStages_SI_RK_Option ) )THEN
      nStages_SI_RK = nStages_SI_RK_Option
    END IF

    SELECT CASE ( nStages_SI_RK )
      CASE ( 1 )

        SI_RK => SI_RK1

      CASE ( 2 )

        SI_RK => SI_RK2

      CASE DEFAULT

        WRITE(*,*)
        WRITE(*,'(A4,A43,I2.2)') &
          '', 'SI_RK not implemented for nStatges_SI_RK = ', nStages_SI_RK
        STOP

    END SELECT

  END SUBROUTINE InitializeTimeStepping


  SUBROUTINE FinalizeTimeStepping

    NULLIFY( SSP_RK, SI_RK )

  END SUBROUTINE FinalizeTimeStepping


  SUBROUTINE EvolveFields &
               ( t_begin, t_end, dt_write, UpdateFields, dt_fixed_Option )

    REAL(DP), INTENT(in) :: t_begin, t_end, dt_write
    PROCEDURE (TimeStepper) :: UpdateFields
    REAL(DP), INTENT(in), OPTIONAL :: dt_fixed_Option

    LOGICAL  :: WriteOutput = .FALSE.
    LOGICAL  :: FixedTimeStep
    INTEGER  :: iCycle
    REAL(DP) :: t, t_write, dt, dt_fixed
    REAL(DP), DIMENSION(0:1) :: WallTime

    FixedTimeStep = .FALSE.
    IF( PRESENT( dt_fixed_Option ) )THEN
      FixedTimeStep = .TRUE.
      dt_fixed = dt_fixed_Option
    END IF

    ASSOCIATE( U => UnitsDisplay )

    WRITE(*,*)
    WRITE(*,'(A4,A21)') '', 'INFO: Evolving Fields'
    WRITE(*,*)
    WRITE(*,'(A6,A10,ES10.4E2,A1,2A2,A8,ES10.4E2,&
              &A1,2A2,A11,ES10.4E2,A1,A2)') &
      '', 't_begin = ',  t_begin  / U % TimeUnit, '', TRIM( U % TimeLabel ), &
      '', 't_end = ',    t_end    / U % TimeUnit, '', TRIM( U % TimeLabel ), &
      '', 'dt_write = ', dt_write / U % TimeUnit, '', TRIM( U % TimeLabel )
    WRITE(*,*)

    iCycle  = 0
    t       = t_begin
    t_write = dt_write

    CALL WriteFields1D( Time = t )

    CALL CPU_TIME( WallTime(0) )

    wtR = 0.0_DP; wtS = 0.0_DP; wtP = 0.0_DP

    DO WHILE( t < t_end )

      iCycle = iCycle + 1

      IF( FixedTimeStep )THEN
        dt = dt_fixed
      ELSE
        !PRINT *, 'Computing timestep.'
        CALL ComputeTimeStep( dt )
        !PRINT *, 'Timestep computed.'
      END IF

      IF( t + dt > t_end )THEN

        dt = t_end - t

      END IF

      !PRINT *, 'Current time is: ', t
      !PRINT *, 'Current timestep is: ', dt
      !PRINT *, 'Write time is: ', t_write

      IF( t + dt > t_write )THEN

        dt          = t_write - t
        t_write     = t_write + dt_write
        WriteOutput = .TRUE.

      END IF

      IF( MOD( iCycle, 100 ) == 0 )THEN

        WRITE(*,'(A8,A8,I8.8,A2,A4,ES10.4E2,A1,A2,A2,A5,ES10.4E2,A1,A2)') &
          '', 'Cycle = ', iCycle, &
          '', 't = ', t / U % TimeUnit, '', TRIM( U % TimeLabel ), &
          '', 'dt = ', dt / U % TimeUnit, '', TRIM( U % TimeLabel )

      END IF

      CALL UpdateFields( t, dt )

      !PRINT*, 'Fields updated.'

      t = t + dt

      IF( WriteOutput )THEN

        CALL WriteFields1D( Time = t )

        WriteOutput = .FALSE.

      END IF

    END DO

    CALL CPU_TIME( WallTime(1) )

    WRITE(*,*)
    WRITE(*,'(A6,A15,ES10.4E2,A1,A2,A6,I8.8,A7,A4,ES10.4E2,A2)') &
      '', 'Evolved to t = ', t / U % TimeUnit, '', TRIM( U % TimeLabel ), &
      ' with ', iCycle, ' cycles', &
      ' in ', WallTime(1)-WallTime(0), ' s'
    WRITE(*,*)
    WRITE(*,'(A6,A12,ES10.4E2,A2,A12,ES10.4E2,A2,A12,ES10.4E2)') &
      '', '  wt(RHS) = ', wtR / (WallTime(1)-WallTime(0)), &
      '', '  wt(SLM) = ', wtS / (WallTime(1)-WallTime(0)), &
      '', '  wt(PLM) = ', wtP / (WallTime(1)-WallTime(0))
    WRITE(*,*)

    CALL WriteFields1D( Time = t )

    END ASSOCIATE ! U

  END SUBROUTINE EvolveFields


  SUBROUTINE ComputeTimeStep( dt )

    REAL(DP), INTENT(out) :: dt

    REAL(DP) :: dt_Fluid, dt_Radiation

    dt_Fluid     = HUGE( 1.0_DP )
    dt_Radiation = HUGE( 1.0_DP )

    IF( EvolveFluid )THEN

      CALL ComputeTimeStep_Fluid( dt_Fluid )

    END IF

    IF( EvolveRadiation )THEN

      CALL ComputeTimeStep_Radiation( dt_Radiation )

    END IF

    dt = MIN( dt_Fluid, dt_Radiation )

  END SUBROUTINE ComputeTimeStep


  SUBROUTINE ComputeTimeStep_Fluid( dt )

    REAL(DP), INTENT(out) :: dt

    INTEGER                    :: iX1, iX2, iX3, iNodeX
    REAL(DP)                   :: CFL, dt_X1, dt_X2, dt_X3
    REAL(DP), DIMENSION(1:nPF) :: uPF_N
    REAL(DP), DIMENSION(1:nAF) :: uAF_N

    dt = HUGE( 1.0_DP )

    ASSOCIATE( dX1 => MeshX(1) % Width(1:nX(1)), &
               dX2 => MeshX(2) % Width(1:nX(2)), &
               dX3 => MeshX(3) % Width(1:nX(3)), &
               X1 => MeshX(1) % Center(1:nX(1)), &
               X2 => MeshX(2) % Center(1:nX(2)), &
               X3 => MeshX(3) % Center(1:nX(3))  )

    CFL = 0.2_DP / ( 2.0_DP * DBLE( nNodes - 1 ) + 1.0_DP ) ! For Debugging

    DO iX3 = 1, nX(3)
      DO iX2 = 1, nX(2)
        DO iX1 = 1, nX(1)
          DO iNodeX = 1, nDOFX

            uPF_N = Primitive( uCF(iNodeX,iX1,ix2,ix3,1:nCF) )

            uAF_N = Auxiliary_Fluid( uPF_N )

            dt_X1 &
              = CFL * dX1(iX1) &
                   / MAXVAL(ABS(Eigenvalues( uPF_N(iPF_V1), uAF_N(iAF_Cs) )))

            dt_X2 &
              = CFL * dX2(iX2) * a([X1(iX1), X2(iX2), X3(iX3)]) &
                    / MAXVAL(ABS(Eigenvalues( uPF_N(iPF_V2), uAF_N(iAF_Cs) )))

            dt_X3 &
              = CFL * dX3(iX3) * b([X1(iX1), X2(iX2), X3(iX3)]) &
                               * c([X1(iX1), X2(iX2), X3(iX3)]) &
                   / MAXVAL(ABS(Eigenvalues( uPF_N(iPF_V3), uAF_N(iAF_Cs) )))

            dt = MIN( dt, dt_x1, dt_X2, dt_X3 )

          END DO
        END DO
      END DO
    END DO

    END ASSOCIATE ! dX1, etc.

  END SUBROUTINE ComputeTimeStep_Fluid


  SUBROUTINE ComputeTimeStep_Radiation( dt )

    REAL(DP), INTENT(out) :: dt

    INTEGER  :: iX1, iX2, iX3, iNodeX
    REAL(DP) :: CFL, dt_X1, dt_X2, dt_X3

    dt = HUGE( 1.0_DP )

    ASSOCIATE( dX1 => MeshX(1) % Width (1:nX(1)), &
               dX2 => MeshX(2) % Width (1:nX(2)), &
               dX3 => MeshX(3) % Width (1:nX(3)), &
               X1  => MeshX(1) % Center(1:nX(1)), &
               X2  => MeshX(2) % Center(1:nX(2)), &
               X3  => MeshX(3) % Center(1:nX(3)) )

    CFL = 0.2_DP / ( 2.0_DP * DBLE( nNodes - 1 ) + 1.0_DP ) ! For Debugging

    DO iX3 = 1, nX(3)
      DO iX2 = 1, nX(2)
        DO iX1 = 1, nX(1)

          dt_X1 = CFL * dX1(iX1)
          dt_X2 = CFL * a( [ X1(iX1), X2(iX2), X3(iX3) ] ) &
                      * dX2(iX2)
          dt_X3 = CFL * b( [ X1(iX1), X2(iX2), X3(iX3) ] ) &
                      * c( [ X1(iX1), X2(iX2), X3(iX3) ] ) &
                      * dX3(iX3)

          dt = MIN( dt, dt_x1, dt_X2, dt_X3 )

        END DO
      END DO
    END DO

    END ASSOCIATE ! dX1, etc.

  END SUBROUTINE ComputeTimeStep_Radiation


  SUBROUTINE SSP_RK1( t, dt )

    REAL(DP), INTENT(in) :: t, dt

    CALL Initialize_SSP_RK

    IF( EvolveFluid )THEN

      CALL ApplyBoundaryConditions_Fluid

      !PRINT *, 'Computing RHS of fluid.'

      CALL ComputeRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

      !PRINT *, 'RHS Computed.'

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyBoundaryConditions_Radiation( Time = t )

      CALL ComputeRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveFluid )THEN

      CALL ApplyRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.0_DP, beta = 1.0_DP )

      !PRINT *, 'RHS Applied'

      CALL ApplyBoundaryConditions_Fluid

      CALL ApplySlopeLimiter_Fluid

      CALL ApplyPositivityLimiter_Fluid

      !PRINT *, 'Slope and Pos. Limits Applied.'

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.0_DP, beta = 1.0_DP )

      CALL ApplySlopeLimiter_Radiation

    END IF

    CALL Finalize_SSP_RK

  END SUBROUTINE SSP_RK1


  SUBROUTINE SSP_RK2( t, dt )

    REAL(DP), INTENT(in) :: t, dt

    REAL(DP), DIMENSION(0:1) :: WT

    CALL Initialize_SSP_RK

    ! -- RK Stage 1 --

    IF( EvolveFluid )THEN

      CALL ApplyBoundaryConditions_Fluid

      CALL CPU_TIME( WT(0) )

      CALL ComputeRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

      CALL CPU_TIME( WT(1) )
      wtR = wtR + ( WT(1) - WT(0) )

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyBoundaryConditions_Radiation( Time = t )

      CALL ComputeRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveFluid )THEN

      CALL ApplyRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.0_DP, beta = 1.0_DP )

      CALL ApplyBoundaryConditions_Fluid

      CALL CPU_TIME( WT(0) )

      CALL ApplySlopeLimiter_Fluid

      CALL CPU_TIME( WT(1) )
      wtS = wtS + ( WT(1) - WT(0) )

      CALL CPU_TIME( WT(0) )

      CALL ApplyPositivityLimiter_Fluid

      CALL CPU_TIME( WT(1) )
      wtP = wtP + ( WT(1) - WT(0) )

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.0_DP, beta = 1.0_DP )

      CALL ApplySlopeLimiter_Radiation

    END IF

    ! -- RK Stage 2 --

    IF( EvolveFluid )THEN

      CALL ApplyBoundaryConditions_Fluid

      CALL CPU_TIME( WT(0) )

      CALL ComputeRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

      CALL CPU_TIME( WT(1) )
      wtR = wtR + ( WT(1) - WT(0) )

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyBoundaryConditions_Radiation( Time = t + dt )

      CALL ComputeRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveFluid )THEN

      CALL ApplyRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.5_DP, beta = 0.5_DP )

      CALL ApplyBoundaryConditions_Fluid

      CALL CPU_TIME( WT(0) )

      CALL ApplySlopeLimiter_Fluid

      CALL CPU_TIME( WT(1) )
      wtS = wtS + ( WT(1) - WT(0) )

      CALL CPU_TIME( WT(0) )

      CALL ApplyPositivityLimiter_Fluid

      CALL CPU_TIME( WT(1) )
      wtP = wtP + ( WT(1) - WT(0) )

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.5_DP, beta = 0.5_DP )

      CALL ApplySlopeLimiter_Radiation

    END IF

    CALL Finalize_SSP_RK

  END SUBROUTINE SSP_RK2


  SUBROUTINE SSP_RK3( t, dt )

    REAL(DP), INTENT(in) :: t, dt

    CALL Initialize_SSP_RK

    ! -- RK Stage 1 -- 

    IF( EvolveFluid )THEN

      CALL ApplyBoundaryConditions_Fluid

      CALL ComputeRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyBoundaryConditions_Radiation( Time = t )

      CALL ComputeRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveFluid )THEN

      CALL ApplyRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.0_DP, beta = 1.0_DP )

      CALL ApplyBoundaryConditions_Fluid

      CALL ApplySlopeLimiter_Fluid

      CALL ApplyPositivityLimiter_Fluid

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.0_DP, beta = 1.0_DP )

      CALL ApplySlopeLimiter_Radiation

    END IF

    ! -- RK Stage 2 --

    IF( EvolveFluid )THEN

      CALL ApplyBoundaryConditions_Fluid

      CALL ComputeRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyBoundaryConditions_Radiation( Time = t + dt )

      CALL ComputeRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveFluid )THEN

      CALL ApplyRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.75_DP, beta = 0.25_DP )

      CALL ApplyBoundaryConditions_Fluid

      CALL ApplySlopeLimiter_Fluid

      CALL ApplyPositivityLimiter_Fluid

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.75_DP, beta = 0.25_DP )

      CALL ApplySlopeLimiter_Radiation

    END IF

    ! -- RK Stage 3 --

    IF( EvolveFluid )THEN

      CALL ApplyBoundaryConditions_Fluid

      CALL ComputeRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyBoundaryConditions_Radiation( Time = t + 0.5_DP * dt )

      CALL ComputeRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveFluid )THEN

      CALL ApplyRHS_Fluid &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 1.0_DP / 3.0_DP, beta = 2.0_DP / 3.0_DP )

      CALL ApplyBoundaryConditions_Fluid

      CALL ApplySlopeLimiter_Fluid

      CALL ApplyPositivityLimiter_Fluid

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 1.0_DP / 3.0_DP , beta = 2.0_DP / 3.0_DP )

      CALL ApplySlopeLimiter_Radiation

    END IF

    CALL Finalize_SSP_RK

  END SUBROUTINE SSP_RK3


  SUBROUTINE Initialize_SSP_RK

    IF( EvolveFluid )THEN

      ALLOCATE( uCF_0(1:nDOFX,1:nX(1),1:nX(2),1:nX(3),1:nCF) )

      uCF_0(1:nDOFX,1:nX(1),1:nX(2),1:nX(3),1:nCF) &
        = uCF(1:nDOFX,1:nX(1),1:nX(2),1:nX(3),1:nCF)

    END IF

    IF( EvolveRadiation )THEN

      ALLOCATE( uCR_0(1:nDOF,1:nE,1:nX(1),1:nX(2),1:nX(3),1:nCR,1:nSpecies) )

      uCR_0(1:nDOF,1:nE,1:nX(1),1:nX(2),1:nX(3),1:nCR,1:nSpecies) &
        = uCR(1:nDOF,1:nE,1:nX(1),1:nX(2),1:nX(3),1:nCR,1:nSpecies)

    END IF

  END SUBROUTINE Initialize_SSP_RK


  SUBROUTINE Finalize_SSP_RK

    IF( EvolveFluid )THEN

      DEALLOCATE( uCF_0 )

    END IF

    IF( EvolveRadiation )THEN

      DEALLOCATE( uCR_0 )

    END IF

  END SUBROUTINE Finalize_SSP_RK


  SUBROUTINE SI_RK1( t, dt )

    REAL(DP), INTENT(in) :: t, dt

    CALL Initialize_SI_RK

    IF( EvolveRadiation )THEN

      CALL ApplyBoundaryConditions_Radiation( Time = t )

      CALL ComputeRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.0_DP, beta = 1.0_DP )

      CALL ApplySlopeLimiter_Radiation

    END IF

    CALL CoupleFluidRadiation &
           ( dt, iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    CALL Finalize_SI_RK

  END SUBROUTINE SI_RK1


  SUBROUTINE SI_RK2( t, dt )

    REAL(DP), INTENT(in) :: t, dt

    INTEGER :: iE, iX1, iX2, iX3, iCR, iS

    CALL Initialize_SI_RK

    ! -- SI-RK Stage 1 --

    IF( EvolveRadiation )THEN

      CALL ApplyBoundaryConditions_Radiation( Time = t )

      CALL ComputeRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.0_DP, beta = 1.0_DP )

      CALL ApplySlopeLimiter_Radiation

    END IF

    CALL CoupleFluidRadiation &
           ( dt, iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    ! -- SI-RK Stage 2 --

    IF( EvolveRadiation )THEN

      CALL ApplyBoundaryConditions_Radiation( Time = t + dt )

      CALL ComputeRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    END IF

    IF( EvolveRadiation )THEN

      CALL ApplyRHS_Radiation &
             ( iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ], &
               dt = dt, alpha = 0.0_DP, beta = 1.0_DP )

      CALL ApplySlopeLimiter_Radiation

    END IF

    CALL CoupleFluidRadiation &
           ( dt, iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

    ! -- Combine Steps --

    DO iS = 1, nSpecies
      DO iCR = 1, nCR
        DO iX3 = 1, nX(3)
          DO iX2 = 1, nX(2)
            DO iX1 = 1, nX(1)
              DO iE = 1, nE

                uCR(:,iE,iX1,iX2,iX3,iCR,iS) &
                  = 0.5_DP * ( uCR_0(:,iE,iX1,iX2,iX3,iCR,iS) &
                               + uCR(:,iE,iX1,iX2,iX3,iCR,iS) )

              END DO
            END DO
          END DO
        END DO
      END DO
    END DO

    CALL Finalize_SI_RK

  END SUBROUTINE SI_RK2


  SUBROUTINE Initialize_SI_RK

    IF( EvolveRadiation )THEN

      ALLOCATE( uCR_0(1:nDOF,1:nE,1:nX(1),1:nX(2),1:nX(3),1:nCR,1:nSpecies) )

      uCR_0(1:nDOF,1:nE,1:nX(1),1:nX(2),1:nX(3),1:nCR,1:nSpecies) &
        = uCR(1:nDOF,1:nE,1:nX(1),1:nX(2),1:nX(3),1:nCR,1:nSpecies)

    END IF

  END SUBROUTINE Initialize_SI_RK


  SUBROUTINE Finalize_SI_RK

    IF( EvolveRadiation )THEN

      DEALLOCATE( uCR_0 )

    END IF

  END SUBROUTINE Finalize_SI_RK


  SUBROUTINE ApplyRHS_Fluid( iX_Begin, iX_End, dt, alpha, beta )

    INTEGER, DIMENSION(3), INTENT(in) :: iX_Begin, iX_End
    REAL(DP),              INTENT(in) :: dt, alpha, beta

    INTEGER :: iX1, iX2, iX3, iCF

    DO iCF = 1, nCF
      DO iX3 = iX_Begin(3), iX_End(3)
        DO iX2 = iX_Begin(2), iX_End(2)
          DO iX1 = iX_Begin(1), iX_End(1)

            uCF(:,iX1,iX2,iX3,iCF) &
              = alpha * uCF_0(:,iX1,iX2,iX3,iCF) &
                  + beta * ( uCF(:,iX1,iX2,iX3,iCF) &
                             + dt * rhsCF(:,iX1,iX2,iX3,iCF) )

          END DO
        END DO
      END DO
    END DO

  END SUBROUTINE ApplyRHS_Fluid


  SUBROUTINE ApplyRHS_Radiation( iX_Begin, iX_End, dt, alpha, beta )

    INTEGER, DIMENSION(3), INTENT(in) :: iX_Begin, iX_End
    REAL(DP),              INTENT(in) :: dt, alpha, beta

    INTEGER :: iE, iX1, iX2, iX3, iCR, iS

    DO iS = 1, nSpecies
      DO iCR = 1, nCR
        DO iX3 = iX_Begin(3), iX_End(3)
          DO iX2 = iX_Begin(2), iX_End(2)
            DO iX1 = iX_Begin(1), iX_End(1)
              DO iE = 1, nE

                uCR(:,iE,iX1,iX2,iX3,iCR,iS) &
                  = alpha * uCR_0(:,iE,iX1,iX2,iX3,iCR,iS) &
                      + beta * ( uCR(:,iE,iX1,iX2,iX3,iCR,iS) &
                                 + dt * rhsCR(:,iE,iX1,iX2,iX3,iCR,iS) )

              END DO
            END DO
          END DO
        END DO
      END DO
    END DO

  END SUBROUTINE ApplyRHS_Radiation


  SUBROUTINE BackwardEuler( t, dt )

    REAL(DP), INTENT(in) :: t, dt

    CALL CoupleFluidRadiation &
           ( dt, iX_Begin = [ 1, 1, 1 ], iX_End = [ nX(1), nX(2), nX(3) ] )

  END SUBROUTINE BackwardEuler


END MODULE TimeSteppingModule