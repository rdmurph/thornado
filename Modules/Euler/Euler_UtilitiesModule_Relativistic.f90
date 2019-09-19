!> Perform computations related to the 3+1, CFA Euler equations.
!> Find the equations in Rezzolla & Zanotti, Relativistic Hydrodynamics, 2013,
!> Equation 7.234.
!> @param TolP Threshold for step-size in Newton-Raphson algorithm in
!>             Euler_ComputePrimitive_Relativistic to accept solution.
!> @param TolFunP Threshold for function in Newton-Raphson algorithm in
!>                Euler_ComputePrimitive_Relativistic to accept solution.
!> @todo Find optimal values for parameters TolP and TolFunP.
MODULE Euler_UtilitiesModule_Relativistic

  USE KindModule, ONLY: &
    DP, Zero, SqrtTiny, Half, One, Two, Three, Four
  USE ProgramHeaderModule, ONLY: &
    nDOFX, nDimsX, nX
  USE MeshModule, ONLY: &
    MeshX
  USE ReferenceElementModuleX, ONLY:          &
    nDOFX_X1, nDOFX_X2, nDOFX_X3, WeightsX_q, &
    WeightsX_X1, WeightsX_X2, WeightsX_X3
  USE ReferenceElementModuleX_Lagrange, ONLY: &
    dLXdX1_q, dLXdX2_q, dLXdX3_q,             &
    LX_X1_Dn, LX_X1_Up,                       &
    LX_X2_Dn, LX_X2_Up,                       &
    LX_X3_Dn, LX_X3_Up
  USE FluidFieldsModule, ONLY:                         &
    nCF, iCF_D, iCF_S1, iCF_S2, iCF_S3, iCF_E, iCF_Ne, &
    nPF, iPF_D, iPF_V1, iPF_V2, iPF_V3, iPF_E, iPF_Ne, &
    nAF, iAF_P, iAF_Cs
  USE GeometryFieldsModule, ONLY:             &
    iGF_h_1, iGF_h_2, iGF_h_3,                &
    iGF_Gm_dd_11, iGF_Gm_dd_22, iGF_Gm_dd_33, &
    iGF_Alpha, &
    iGF_Beta_1, iGF_Beta_2, iGF_Beta_3, nGF
  USE EquationOfStateModule, ONLY:             &
    ComputePressureFromSpecificInternalEnergy, &
    ComputeSoundSpeedFromPrimitive, &
    ComputePressureFromPrimitive
  USE EquationOfStateModule_IDEAL, ONLY: &
    Gamma_IDEAL

  IMPLICIT NONE
  PRIVATE

  PUBLIC :: Euler_ComputePrimitive_Relativistic
  PUBLIC :: Euler_ComputeConserved_Relativistic
  PUBLIC :: Euler_ComputeFromConserved_Relativistic
  PUBLIC :: Euler_ComputeTimeStep_Relativistic
  PUBLIC :: Euler_Eigenvalues_Relativistic
  PUBLIC :: Euler_AlphaMiddle_Relativistic
  PUBLIC :: Euler_Flux_X1_Relativistic
  PUBLIC :: Euler_Flux_X2_Relativistic
  PUBLIC :: Euler_Flux_X3_Relativistic
  PUBLIC :: Euler_StressTensor_Diagonal_Relativistic
  PUBLIC :: Euler_NumericalFlux_LLF_Relativistic
  PUBLIC :: Euler_NumericalFlux_HLL_Relativistic
  PUBLIC :: Euler_NumericalFlux_X1_HLLC_Relativistic
  PUBLIC :: Euler_NumericalFlux_X2_HLLC_Relativistic
  PUBLIC :: Euler_NumericalFlux_X3_HLLC_Relativistic

  ! --- These will all be private once
  !     Euler_ComputePrimitive_Relativistic is satisfactory ---
  PUBLIC :: ComputeFunJacP
  PUBLIC :: ComputePressureWithBisectionMethod
  PUBLIC :: ComputePressureWithBrentsMethod
  PRIVATE :: ComputeFunP

  REAL(DP), PARAMETER :: TolP = 1.0d-8, TolFunP = 1.0d-6, MachineEPS = 1.0d-16
  LOGICAL             :: DEBUG = .FALSE.


CONTAINS

  !> Compute the primitive variables from the conserved variables,
  !> a la Rezzolla & Zanotti, Relativistic Hydrodynamics, 2013, Appendix D.
  !> Use bisection algorithm to obtain an initial guess for the pressure,
  !> then use Newton-Raphson method hone-in on the actual pressure
  !> @todo Decide whether or not to send in previous pressure as initial guess.
  SUBROUTINE Euler_ComputePrimitive_Relativistic &
              ( CF_D, CF_S1, CF_S2, CF_S3, CF_E, CF_Ne, &
                PF_D, PF_V1, PF_V2, PF_V3, PF_E, PF_Ne, &
                GF_Gm_dd_11, GF_Gm_dd_22, GF_Gm_dd_33 )

    REAL(DP), INTENT(in)  :: CF_D(:), CF_S1(:), CF_S2(:), CF_S3(:), &
                             CF_E(:), CF_Ne(:)
    REAL(DP), INTENT(out) :: PF_D(:), PF_V1(:), PF_V2(:), PF_V3(:), &
                             PF_E(:), PF_Ne(:)
    REAL(DP), INTENT(in)  :: GF_Gm_dd_11(:), GF_Gm_dd_22(:), GF_Gm_dd_33(:)

    LOGICAL            :: CONVERGED
    INTEGER, PARAMETER :: MAX_IT = 100
    INTEGER            :: i, ITERATION, nNodes
    REAL(DP)           :: SSq, Pold, vSq, W, h, Pnew, q, Pbisec
    REAL(DP)           :: FunP, JacP, AF_P(SIZE(PF_D))

    ! --- Loop through all the nodes ---
    nNodes = SIZE( CF_D )
    DO i = 1, nNodes

      q = CF_E(i) + CF_D(i) - SQRT( CF_D(i)**2 &
                                  + CF_S1(i)**2 / GF_Gm_dd_11(i)  &
                                  + CF_S2(i)**2 / GF_Gm_dd_22(i)  &
                                  + CF_S3(i)**2 / GF_Gm_dd_33(i) )

      IF( q .LT. Zero )THEN
        WRITE(*,*)
        WRITE(*,'(A)')            'Euler_ComputePrimitive_Relativistic'
        WRITE(*,'(A)')            '-----------------------------------'
        WRITE(*,'(A6,I1)')        'Node:    ', i
        WRITE(*,'(A9,ES18.10E3)') 'q:       ', q
        WRITE(*,'(A9,ES18.10E3)') 'Gm11(i): ', GF_Gm_dd_11(i)
        WRITE(*,'(A9,ES18.10E3)') 'Gm22(i): ', GF_Gm_dd_22(i)
        WRITE(*,'(A9,ES18.10E3)') 'Gm33(i): ', GF_Gm_dd_33(i)
        WRITE(*,'(A9,ES18.10E3)') 'D(i):    ', CF_D(i)
        WRITE(*,'(A9,ES18.10E3)') 'tau(i):  ', CF_E(i)
        WRITE(*,'(A9,ES18.10E3)') 'S1(i):   ', CF_S1(i)
        WRITE(*,'(A9,ES18.10E3)') 'S2(i):   ', CF_S2(i)
        WRITE(*,'(A9,ES18.10E3)') 'S3(i):   ', CF_S3(i)
        STOP 'q < 0'
      END IF

      SSq =   CF_S1(i)**2 / GF_Gm_dd_11(i) &
            + CF_S2(i)**2 / GF_Gm_dd_22(i) &
            + CF_S3(i)**2 / GF_Gm_dd_33(i)

      ! --- Find Pressure with Newton's Method ---

      ! --- Get initial guess for pressure with bisection method ---
      CALL ComputePressureWithBisectionMethod( CF_D(i), CF_E(i), SSq, Pbisec )

      Pold = Pbisec
      IF( Pbisec .LT. SqrtTiny )THEN
        WRITE(*,'(A)') '    EE: Pbisec < SqrTiny. Stopping...'
        STOP
      END IF

      ! --- Get initial value for FunP ---
      CALL ComputeFunJacP( CF_D(i), CF_E(i), SSq, Pold, FunP, JacP )

      CONVERGED = .FALSE.

      IF( ABS( FunP ) .LT. TolFunP * ABS( TolFunP ) )THEN
        Pnew = Pold
        CONVERGED = .TRUE.
      END IF

      ITERATION = 0

      DO WHILE ( .NOT. CONVERGED )

        ITERATION = ITERATION + 1

        CALL ComputeFunJacP( CF_D(i), CF_E(i), SSq, Pold, FunP, JacP )

        IF( ABS( FunP / JacP ) .LT. MachineEPS ) THEN
          Pnew = Pold
          CONVERGED = .TRUE.
          EXIT
        END IF

        Pnew = MAX( Pold - FunP / JacP, SqrtTiny )

        ! --- Check if Newton's method has converged ---
        IF( ( ABS( ( Pnew - Pold ) / Pold ) ) .LT. TolP )THEN

          CALL ComputeFunJacP( CF_D(i), CF_E(i), SSq, Pnew, FunP, JacP )

          IF( .NOT. ( ABS( FunP ) .LT. TolFunP * ABS( Pnew ) ) ) THEN
            WRITE(*,*)
            WRITE(*,'(A)') 'WARNING:'
            WRITE(*,'(A)') '--------'
            WRITE(*,'(A)') 'ABS( FunP / Pnew ) > TolFunP'
            WRITE(*,'(A,ES24.16E3)') 'TolFunP              = ', TolFunP
            WRITE(*,'(A,ES24.16E3)') 'Pold                 = ', Pold
            WRITE(*,'(A,ES24.16E3)') 'Pnew                 = ', Pnew
            WRITE(*,'(A,ES24.16E3)') &
              '|(Pnew - Pold)/Pold| = ', ABS( ( Pnew - Pold ) / Pold )
            WRITE(*,'(A,ES24.16E3)') &
              '|FunP(Pnew) / Pnew|  = ', ABS( FunP / Pnew )
          END IF

          CONVERGED = .TRUE.
          EXIT

        END IF

        ! --- STOP after MAX_IT iterations ---
        IF( ITERATION .GE. MAX_IT - 4 .OR. DEBUG )THEN
          WRITE(*,*)
          WRITE(*,'(A)')           '    CP: Max iterations IF statement'
          WRITE(*,'(A)')           '    -------------------------------'
          WRITE(*,'(A,I1)')        '    CP: Node: ', i
          WRITE(*,'(A,ES7.1E2)')   '    CP: TolP    = ', TolP
          WRITE(*,'(A,ES7.1E2)')   '    CP: TolFunP = ', TolFunP
          WRITE(*,*)
          WRITE(*,'(A,ES24.16E3)') '    U(i,iCF_D)  = ', CF_D(i)
          WRITE(*,'(A,ES24.16E3)') '    U(i,iCF_S1) = ', CF_S1(i)
          WRITE(*,'(A,ES24.16E3)') '    U(i,iCF_S2) = ', CF_S2(i)
          WRITE(*,'(A,ES24.16E3)') '    U(i,iCF_S3) = ', CF_S3(i)
          WRITE(*,'(A,ES24.16E3)') '    U(i,iCF_E)  = ', CF_E(i)
          WRITE(*,*)
          WRITE(*,'(A,ES24.16E3)') '    G(i,iGF_Gm_dd_11) = ', GF_Gm_dd_11(i)
          WRITE(*,'(A,ES24.16E3)') '    G(i,iGF_Gm_dd_22) = ', GF_Gm_dd_22(i)
          WRITE(*,'(A,ES24.16E3)') '    G(i,iGF_Gm_dd_33) = ', GF_Gm_dd_33(i)
          WRITE(*,*)
          WRITE(*,'(A,ES24.16E3)') '    CP: |v|   = ', &
            ABS( CF_S1(i) / ( CF_E(i) + CF_D(i) + Pnew ) )
          WRITE(*,'(A,ES24.16E3)') '    CP: W     = ', &
            1.0d0 / SQRT( 1.0d0 - SSq / ( CF_E(i) + CF_D(i) + Pnew )**2 )
          WRITE(*,'(A,ES24.16E3)') '    CP: P/rho = ', &
            Pnew / ( CF_D(i) / ( 1.0d0 / SQRT( 1.0d0 &
              - SSq / ( CF_E(i) + CF_D(i) + Pnew )**2 ) ) )
          WRITE(*,*)
          WRITE(*,'(A,ES24.16E3)') '    CP: Pold   = ', Pold
          WRITE(*,*)
        END IF

        Pold = Pnew

      END DO

      AF_P(i) = Pnew

      vSq = SSq / ( CF_E(i) + Pnew + CF_D(i) )**2

      W = 1.0_DP / SQRT( 1.0_DP - vSq )

      h = ( CF_E(i) + Pnew + CF_D(i) ) / ( W * CF_D(i) )

      ! --- Recover Primitive Variables ---

      PF_D(i)  = CF_D(i) / W

      PF_V1(i) = CF_S1(i) / ( CF_D(i) * h * W * GF_Gm_dd_11(i) )

      PF_V2(i) = CF_S2(i) / ( CF_D(i) * h * W * GF_Gm_dd_22(i) )

      PF_V3(i) = CF_S3(i) / ( CF_D(i) * h * W * GF_Gm_dd_33(i) )

      PF_E(i)  = CF_D(i) * ( h - 1.0_DP ) / W - Pnew

      PF_Ne(i) = CF_Ne(i) / W

   END DO ! --- End of loop over nodes ---


  END SUBROUTINE Euler_ComputePrimitive_Relativistic


  !> Compute conserved variables from primitive variables.
  SUBROUTINE Euler_ComputeConserved_Relativistic &
    ( PF_D, PF_V1, PF_V2, PF_V3, PF_E, PF_Ne, &
      CF_D, CF_S1, CF_S2, CF_S3, CF_E, CF_Ne, &
      Gm11, Gm22, Gm33, &
      AF_P )

    REAL(DP), INTENT(in)  :: PF_D(:), PF_V1(:), PF_V2(:), PF_V3(:), &
                             PF_E(:), PF_Ne(:), AF_P(:), &
                             Gm11(:), Gm22(:), Gm33(:)
    REAL(DP), INTENT(out) :: CF_D(:), CF_S1(:), CF_S2(:), CF_S3(:), &
                             CF_E(:), CF_Ne(:)

    REAL(DP) :: VSq(SIZE(PF_D)), W(SIZE(PF_D)), h(SIZE(PF_D))

    VSq = Gm11 * PF_V1**2 + Gm22 * PF_V2**2 + Gm33 * PF_V3**2

    W = 1.0_DP / SQRT( 1.0_DP - VSq )
    h = 1.0_DP + ( PF_E + AF_P ) / PF_D

    CF_D  = W * PF_D
    CF_S1 = h * W**2 * PF_D * Gm11 * PF_V1
    CF_S2 = h * W**2 * PF_D * Gm22 * PF_V2
    CF_S3 = h * W**2 * PF_D * Gm33 * PF_V3
    CF_E  = h * W**2 * PF_D - AF_P - W * PF_D
    CF_Ne = W * PF_Ne

  END SUBROUTINE Euler_ComputeConserved_Relativistic


  !> Compute primitive variables, pressure, and sound-speed from conserved
  !> variables. Only used for IO.
  SUBROUTINE Euler_ComputeFromConserved_Relativistic( iX_B0, iX_E0, G, U, P, A )

    INTEGER, INTENT(in)  :: &
      iX_B0(3), iX_E0(3)
    REAL(DP), INTENT(in) :: &
      G(1:,iX_B0(1):,iX_B0(2):,iX_B0(3):,1:), &
      U(1:,iX_B0(1):,iX_B0(2):,iX_B0(3):,1:)
    REAL(DP), INTENT(inout)  :: &
      P(1:,iX_B0(1):,iX_B0(2):,iX_B0(3):,1:), &
      A(1:,iX_B0(1):,iX_B0(2):,iX_B0(3):,1:)

    INTEGER :: iX1, iX2, iX3

    ! --- Update primitive variables, pressure, and sound speed ---
    DO iX3 = iX_B0(3), iX_E0(3)
    DO iX2 = iX_B0(2), iX_E0(2)
    DO iX1 = iX_B0(1), iX_E0(1)

      CALL Euler_ComputePrimitive_Relativistic &
             ( U(1:nDOFX,iX1,iX2,iX3,iCF_D),         &
               U(1:nDOFX,iX1,iX2,iX3,iCF_S1),        &
               U(1:nDOFX,iX1,iX2,iX3,iCF_S2),        &
               U(1:nDOFX,iX1,iX2,iX3,iCF_S3),        &
               U(1:nDOFX,iX1,iX2,iX3,iCF_E),         &
               U(1:nDOFX,iX1,iX2,iX3,iCF_Ne),        &
               P(1:nDOFX,iX1,iX2,iX3,iPF_D),         &
               P(1:nDOFX,iX1,iX2,iX3,iPF_V1),        &
               P(1:nDOFX,iX1,iX2,iX3,iPF_V2),        &
               P(1:nDOFX,iX1,iX2,iX3,iPF_V3),        &
               P(1:nDOFX,iX1,iX2,iX3,iPF_E),         &
               P(1:nDOFX,iX1,iX2,iX3,iPF_Ne),        &
               G(1:nDOFX,iX1,iX2,iX3,iGF_Gm_dd_11),  &
               G(1:nDOFX,iX1,iX2,iX3,iGF_Gm_dd_22),  &
               G(1:nDOFX,iX1,iX2,iX3,iGF_Gm_dd_33) )

      CALL ComputePressureFromPrimitive &
             ( P(1:nDOFX,iX1,iX2,iX3,iPF_D ), P(1:nDOFX,iX1,iX2,iX3,iPF_E ), &
               P(1:nDOFX,iX1,iX2,iX3,iPF_Ne), A(1:nDOFX,iX1,iX2,iX3,iAF_P) )

      CALL ComputeSoundSpeedFromPrimitive &
             ( P(1:nDOFX,iX1,iX2,iX3,iPF_D ), P(1:nDOFX,iX1,iX2,iX3,iPF_E ), &
               P(1:nDOFX,iX1,iX2,iX3,iPF_Ne), A(1:nDOFX,iX1,iX2,iX3,iAF_Cs) )

    END DO
    END DO
    END DO

  END SUBROUTINE Euler_ComputeFromConserved_Relativistic


  !> Loop over all the elements in the spatial domain and compute the minimum
  !> required time-step for numerical stability.
  SUBROUTINE Euler_ComputeTimeStep_Relativistic &
    ( iX_B0, iX_E0, G, U, CFL, TimeStep )

    INTEGER,  INTENT(in)  :: &
      iX_B0(3), iX_E0(3)
    REAL(DP), INTENT(in)  :: &
      G(1:,iX_B0(1):,iX_B0(2):,iX_B0(3):,1:), &
      U(1:,iX_B0(1):,iX_B0(2):,iX_B0(3):,1:)
    REAL(DP), INTENT(in)  :: &
      CFL
    REAL(DP), INTENT(out) :: &
      TimeStep

    INTEGER  :: iX1, iX2, iX3, iNodeX
    REAL(DP) :: dX(3), dt(3)
    REAL(DP) :: P(nDOFX,nPF)
    REAL(DP) :: Cs(nDOFX)
    REAL(DP) :: EigVals_X1(nCF,nDOFX), alpha_X1, &
                EigVals_X2(nCF,nDOFX), alpha_X2, &
                EigVals_X3(nCF,nDOFX), alpha_X3

    TimeStep = HUGE( One )
    dt       = HUGE( One )

    ! --- Maximum wave-speeds ---
    alpha_X1 = -HUGE( One )
    alpha_X2 = -HUGE( One )
    alpha_X3 = -HUGE( One )

    DO iX3 = iX_B0(3), iX_E0(3)
    DO iX2 = iX_B0(2), iX_E0(2)
    DO iX1 = iX_B0(1), iX_E0(1)

      dX(1) = MeshX(1) % Width(iX1)
      dX(2) = MeshX(2) % Width(iX2)
      dX(3) = MeshX(3) % Width(iX3)

      CALL Euler_ComputePrimitive_Relativistic &
             ( U(1:nDOFX,iX1,iX2,iX3,iCF_D ), &
               U(1:nDOFX,iX1,iX2,iX3,iCF_S1), &
               U(1:nDOFX,iX1,iX2,iX3,iCF_S2), &
               U(1:nDOFX,iX1,iX2,iX3,iCF_S3), &
               U(1:nDOFX,iX1,iX2,iX3,iCF_E ), &
               U(1:nDOFX,iX1,iX2,iX3,iCF_Ne), &
               P(1:nDOFX,iPF_D ), &
               P(1:nDOFX,iPF_V1), &
               P(1:nDOFX,iPF_V2), &
               P(1:nDOFX,iPF_V3), &
               P(1:nDOFX,iPF_E ), &
               P(1:nDOFX,iPF_Ne), &
               G(1:nDOFX,iX1,iX2,iX3,iGF_Gm_dd_11), &
               G(1:nDOFX,iX1,iX2,iX3,iGF_Gm_dd_22), &
               G(1:nDOFX,iX1,iX2,iX3,iGF_Gm_dd_33) )

      CALL ComputeSoundSpeedFromPrimitive &
             ( P(1:nDOFX,iPF_D), P(1:nDOFX,iPF_E), P(1:nDOFX,iPF_Ne), &
               Cs(1:nDOFX) )

      IF     ( nDimsX .EQ. 1 )THEN

        DO iNodeX = 1, nDOFX

          EigVals_X1(1:nCF,iNodeX) &
            = Euler_Eigenvalues_Relativistic &
                ( P (iNodeX,iPF_V1), &
                  Cs(iNodeX),        &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_11), &
                  P (iNodeX,iPF_V1), &
                  P (iNodeX,iPF_V2), &
                  P (iNodeX,iPF_V3), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_11), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_22), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_33), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Alpha),    &
                  G (iNodeX,iX1,iX2,iX3,iGF_Beta_1) )

        END DO

        alpha_X1 = MAX( alpha_X1, MAXVAL( ABS( EigVals_X1(1:nCF,1:nDOFX) ) ) )

        dt(1) = dX(1) / alpha_X1

      ELSE IF( nDimsX .EQ. 2 )THEN

        DO iNodeX = 1, nDOFX

          EigVals_X1(1:nCF,iNodeX) &
            = Euler_Eigenvalues_Relativistic &
                ( P (iNodeX,iPF_V1), &
                  Cs(iNodeX),        &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_11), &
                  P (iNodeX,iPF_V1), &
                  P (iNodeX,iPF_V2), &
                  P (iNodeX,iPF_V3), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_11), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_22), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_33), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Alpha),    &
                  G (iNodeX,iX1,iX2,iX3,iGF_Beta_1) )

          EigVals_X2(1:nCF,iNodeX) &
            = Euler_Eigenvalues_Relativistic &
                ( P (iNodeX,iPF_V2), &
                  Cs(iNodeX),        &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_22), &
                  P (iNodeX,iPF_V1), &
                  P (iNodeX,iPF_V2), &
                  P (iNodeX,iPF_V3), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_11), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_22), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_33), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Alpha),    &
                  G (iNodeX,iX1,iX2,iX3,iGF_Beta_2) )
        END DO

        alpha_X1 = MAX( alpha_X1, MAXVAL( ABS( EigVals_X1(1:nCF,1:nDOFX) ) ) )
        alpha_X2 = MAX( alpha_X2, MAXVAL( ABS( EigVals_X2(1:nCF,1:nDOFX) ) ) )

        dt(1) = dX(1) / alpha_X1
        dt(2) = dX(2) / alpha_X2

      ELSE

        DO iNodeX = 1, nDOFX

          EigVals_X1(1:nCF,iNodeX) &
            = Euler_Eigenvalues_Relativistic &
                ( P (iNodeX,iPF_V1), &
                  Cs(iNodeX),        &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_11), &
                  P (iNodeX,iPF_V1), &
                  P (iNodeX,iPF_V2), &
                  P (iNodeX,iPF_V3), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_11), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_22), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_33), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Alpha),    &
                  G (iNodeX,iX1,iX2,iX3,iGF_Beta_1) )

          EigVals_X2(1:nCF,iNodeX) &
            = Euler_Eigenvalues_Relativistic &
                ( P (iNodeX,iPF_V2), &
                  Cs(iNodeX),        &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_22), &
                  P (iNodeX,iPF_V1), &
                  P (iNodeX,iPF_V2), &
                  P (iNodeX,iPF_V3), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_11), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_22), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_33), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Alpha),    &
                  G (iNodeX,iX1,iX2,iX3,iGF_Beta_2) )

          EigVals_X3(1:nCF,iNodeX) &
            = Euler_Eigenvalues_Relativistic &
                ( P (iNodeX,iPF_V3),   &
                  Cs(iNodeX),          &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_33), &
                  P (iNodeX,iPF_V1),   &
                  P (iNodeX,iPF_V2),   &
                  P (iNodeX,iPF_V3),   &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_11), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_22), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Gm_dd_33), &
                  G (iNodeX,iX1,iX2,iX3,iGF_Alpha),    &
                  G (iNodeX,iX1,iX2,iX3,iGF_Beta_3) )

        END DO

        alpha_X1 = MAX( alpha_X1, MAXVAL( ABS( EigVals_X1(1:nCF,1:nDOFX) ) ) )
        alpha_X2 = MAX( alpha_X2, MAXVAL( ABS( EigVals_X2(1:nCF,1:nDOFX) ) ) )
        alpha_X3 = MAX( alpha_X3, MAXVAL( ABS( EigVals_X3(1:nCF,1:nDOFX) ) ) )

        dt(1) = dX(1) / alpha_X1
        dt(2) = dX(2) / alpha_X2
        dt(3) = dX(3) / alpha_X3

      END IF

      TimeStep = MIN( TimeStep, MINVAL( dt(1:3) ) )

    END DO
    END DO
    END DO

    TimeStep = MAX( CFL * TimeStep, SqrtTiny )

  END SUBROUTINE Euler_ComputeTimeStep_Relativistic


  !> Compute the eigenvalues of the flux-Jacobian.
  !> Find the expressions in Font et al., (1998), Eqs. (14) and (18).
  !> @param Vi The ith contravariant component of the three-velocity.
  !> @param Gmii The ith covariant component of the spatial three-metric.
  !> @param Shift The ith contravariant component of the shift-vector.
  PURE FUNCTION Euler_Eigenvalues_Relativistic &
    ( Vi, Cs, Gmii, V1, V2, V3, Gm11, Gm22, Gm33, Lapse, Shift )

    REAL(DP), INTENT(in) :: Vi, Cs, Gmii, V1, V2, V3, &
                            Gm11, Gm22, Gm33, Lapse, Shift

    REAL(DP) :: VSq, Euler_Eigenvalues_Relativistic(nCF)

    VSq = Gm11 * V1**2 + Gm22 * V2**2 + Gm33 * V3**2

    Euler_Eigenvalues_Relativistic(1) &
      = Lapse / ( One - VSq * Cs**2 ) * ( Vi * ( One - Cs**2 ) &
        - Cs * SQRT( ( One - VSq ) * ( ( One - VSq * Cs**2 ) / Gmii &
           - Vi**2 * ( One - Cs**2 ) ) ) ) - Shift

    Euler_Eigenvalues_Relativistic(2) &
      = Lapse * Vi - Shift

    Euler_Eigenvalues_Relativistic(3) &
      = Lapse / ( One - VSq * Cs**2 ) * ( Vi * ( One - Cs**2 ) &
        + Cs * SQRT( ( One - VSq ) * ( ( One - VSq * Cs**2 ) / Gmii &
           - Vi**2 * ( One - Cs**2 ) ) ) ) - Shift

    Euler_Eigenvalues_Relativistic(4) &
      = Lapse * Vi - Shift

    Euler_Eigenvalues_Relativistic(5) &
      = Lapse * Vi - Shift

    Euler_Eigenvalues_Relativistic(6) &
      = Lapse * Vi - Shift

    RETURN
  END FUNCTION Euler_Eigenvalues_Relativistic


  !> Estimate the contact wave-speed as suggested by
  !> Mignone & Bodo, (2005), MNRAS, 364, 126.
  !> @param Shift The ith contravariant component of the shift-vector.
  !> @param Gmii The ith covariant component of the spatial three-metric.
  REAL(DP) FUNCTION Euler_AlphaMiddle_Relativistic &
    ( DL, SL, tauL, F_DL, F_SL, F_tauL, DR, SR, tauR, F_DR, F_SR, F_tauR, &
      Gmii, aP, aM, Lapse, Shift )

    REAL(DP), INTENT(in) :: DL, SL, tauL, F_DL, F_SL, F_tauL, &
                            DR, SR, tauR, F_DR, F_SR, F_tauR, &
                            Gmii, aP, aM, Lapse, Shift

    REAL(DP) :: EL, F_EL, ER, F_ER, a2, a1, a0
    REAL(DP) :: E_HLL, S_HLL, FE_HLL, FS_HLL

    EL   = tauL + DL
    F_EL = F_tauL + F_DL
    ER   = tauR + DR
    F_ER = F_tauR + F_DR

    E_HLL  = aP * ER + aM * EL + Lapse * ( F_EL - F_ER )
    S_HLL  = aP * SR + aM * SL + Lapse * ( F_SL - F_SR )
    FE_HLL = Lapse * ( aP * F_EL + aM * F_ER ) - aM * aP * ( ER - EL )
    FS_HLL = Lapse * ( aP * F_SL + aM * F_SR ) - aM * aP * ( SR - SL )

    ! --- Coefficients in quadratic equation ---
    a2 = Gmii**2 * ( FE_HLL + Shift * E_HLL )
    a1 = -Gmii * ( Lapse * E_HLL + FS_HLL + Shift * S_HLL )
    a0 = Lapse * S_HLL

    ! --- Accounting for special cases of the solution to a
    !     quadratic equation when a2 = 0 ---

    IF     ( ( ABS( a2 ) .LT. SqrtTiny ) .AND. ( ABS( a1 ) .LT. SqrtTiny ) &
            .AND. ( ABS( a0 ) .LT. SqrtTiny ) )THEN
      STOP 'AlphaMiddle is undefined'
    ELSE IF( ( ABS( a2 ) .LT. SqrtTiny ) .AND. ( ABS( a1 ) .LT. SqrtTiny ) )THEN
      STOP 'AlphaMiddle is undefined'
    ELSE IF( ( ABS( a2 ) .LT. SqrtTiny ) .AND. ( ABS( a0 ) .LT. SqrtTiny ) )THEN
      Euler_AlphaMiddle_Relativistic = Zero
    ELSE IF( ABS( a2 ) .LT. SqrtTiny )THEN
      Euler_AlphaMiddle_Relativistic = -a0 / a1
    ELSE IF( ABS( a0 ) .LT. SqrtTiny )THEN
       Euler_AlphaMiddle_Relativistic = Zero
    ELSE
      Euler_AlphaMiddle_Relativistic &
        = ( -a1 - SQRT( MAX( a1**2 - Four * a2 * a0, SqrtTiny ) ) ) &
            / ( Two * a2 )
    END IF

    RETURN
  END FUNCTION Euler_AlphaMiddle_Relativistic


  !> Compute the physical flux in the X1-direction.
  !> @param Vi The ith contravariant components of the three-velocity.
  !> @param Gmii The ith covariant components of the spatial three-metric.
  !> @param Shift The first contravariant component of the shift-vector.
  PURE FUNCTION Euler_Flux_X1_Relativistic &
    ( D, V1, V2, V3, E, Ne, P, Gm11, Gm22, Gm33, Lapse, Shift )

    REAL(DP), INTENT(in) :: D, V1, V2, V3, E, Ne, P, &
                            Gm11, Gm22, Gm33, Lapse, Shift

    REAL(DP) :: VSq, W, h, Euler_Flux_X1_Relativistic(nCF)

    VSq = Gm11 * V1**2 + Gm22 * V2**2 + Gm33 * V3**2
    W   = 1.0d0 / SQRT( 1.0d0 - VSq )
    h   = 1.0d0 + ( E + P ) / D

    Euler_Flux_X1_Relativistic(iCF_D)  &
      = D * W * ( V1 - Shift / Lapse )

    Euler_Flux_X1_Relativistic(iCF_S1) &
      = D * h * W**2 * Gm11 * V1  * ( V1 - Shift / Lapse ) + P

    Euler_Flux_X1_Relativistic(iCF_S2) &
      = D * h * W**2 * Gm22 * V2  * ( V1 - Shift / Lapse )

    Euler_Flux_X1_Relativistic(iCF_S3) &
      = D * h * W**2 * Gm33 * V3  * ( V1 - Shift / Lapse )

    Euler_Flux_X1_Relativistic(iCF_E)  &
      = D * W * ( h * W - 1.0d0 ) * ( V1 - Shift / Lapse ) + Shift / Lapse * P

    Euler_Flux_X1_Relativistic(iCF_Ne) &
      = Ne * W * ( V1 - Shift / Lapse )

    RETURN
  END FUNCTION Euler_Flux_X1_Relativistic


  !> Compute the physical flux in the X2-direction.
  !> @param Vi The ith contravariant components of the three-velocity.
  !> @param Gmii The ith covariant components of the spatial three-metric.
  !> @param Shift The first contravariant component of the shift-vector.
  PURE FUNCTION Euler_Flux_X2_Relativistic &
    ( D, V1, V2, V3, E, Ne, P, Gm11, Gm22, Gm33, Lapse, Shift )

    REAL(DP), INTENT(in) :: D, V1, V2, V3, E, Ne, P, &
                            Gm11, Gm22, Gm33, Lapse, Shift

    REAL(DP) :: VSq, W, h, Euler_Flux_X2_Relativistic(nCF)

    VSq = Gm11 * V1**2 + Gm22 * V2**2 + Gm33 * V3**2
    W   = 1.0d0 / SQRT( 1.0d0 - VSq )
    h   = 1.0d0 + ( E + P ) / D

    Euler_Flux_X2_Relativistic(iCF_D)  &
      = D * W * ( V2 - Shift / Lapse )

    Euler_Flux_X2_Relativistic(iCF_S1) &
      = D * h * W**2 * Gm11 * V1  * ( V2 - Shift / Lapse )

    Euler_Flux_X2_Relativistic(iCF_S2) &
      = D * h * W**2 * Gm22 * V2  * ( V2 - Shift / Lapse ) + P

    Euler_Flux_X2_Relativistic(iCF_S3) &
      = D * h * W**2 * Gm33 * V3  * ( V2 - Shift / Lapse )

    Euler_Flux_X2_Relativistic(iCF_E)  &
      = D * W * ( h * W - 1.0d0 ) * ( V2 - Shift / Lapse ) + Shift / Lapse * P

    Euler_Flux_X2_Relativistic(iCF_Ne) &
      = Ne * W * ( V2 - Shift / Lapse )

    RETURN
  END FUNCTION Euler_Flux_X2_Relativistic


  !> Compute the physical flux in the X3-direction.
  !> @param Vi The ith contravariant components of the three-velocity.
  !> @param Gmii The ith covariant components of the spatial three-metric.
  !> @param Shift The first contravariant component of the shift-vector.
  PURE FUNCTION Euler_Flux_X3_Relativistic &
    ( D, V1, V2, V3, E, Ne, P, Gm11, Gm22, Gm33, Lapse, Shift )

    REAL(DP), INTENT(in) :: D, V1, V2, V3, E, Ne, P, &
                            Gm11, Gm22, Gm33, Lapse, Shift

    REAL(DP) :: VSq, W, h, Euler_Flux_X3_Relativistic(nCF)

    VSq = Gm11 * V1**2 + Gm22 * V2**2 + Gm33 * V3**2
    W   = 1.0d0 / SQRT( 1.0d0 - VSq )
    h   = 1.0d0 + ( E + P ) / D

    Euler_Flux_X3_Relativistic(iCF_D)  &
      = D * W * ( V3 - Shift / Lapse )

    Euler_Flux_X3_Relativistic(iCF_S1) &
      = D * h * W**2 * Gm11 * V1  * ( V3 - Shift / Lapse )

    Euler_Flux_X3_Relativistic(iCF_S2) &
      = D * h * W**2 * Gm22 * V2  * ( V3 - Shift / Lapse )

    Euler_Flux_X3_Relativistic(iCF_S3) &
      = D * h * W**2 * Gm33 * V3  * ( V3 - Shift / Lapse ) + P

    Euler_Flux_X3_Relativistic(iCF_E)  &
      = D * W * ( h * W - 1.0d0 ) * ( V3 - Shift / Lapse ) + Shift / Lapse * P

    Euler_Flux_X3_Relativistic(iCF_Ne) &
      = Ne * W * ( V3 - Shift / Lapse )

    RETURN
  END FUNCTION Euler_Flux_X3_Relativistic


  !> Compute the diagonal elements of the stress-tensor, needed for the
  !> source-terms in the hydro equations.
  !> @param Si The ith covariant components of the conserved momentum-density.
  !> @param Vi The ith contravavriant components of the three-velocity.
  PURE FUNCTION Euler_StressTensor_Diagonal_Relativistic &
    ( S1, S2, S3, V1, V2, V3, P )

    REAL(DP), INTENT(in) :: S1, S2, S3, V1, V2, V3, P

    REAL(DP) :: Euler_StressTensor_Diagonal_Relativistic(3)

    Euler_StressTensor_Diagonal_Relativistic(1) = S1 * V1 + P
    Euler_StressTensor_Diagonal_Relativistic(2) = S2 * V2 + P
    Euler_StressTensor_Diagonal_Relativistic(3) = S3 * V3 + P

    RETURN
  END FUNCTION Euler_StressTensor_Diagonal_Relativistic


  !> Compute the Local-Lax-Friedrichs numerical flux at a given element
  !> interface, in a given dimension.
  PURE FUNCTION Euler_NumericalFlux_LLF_Relativistic &
    ( uL, uR, fL, fR, aP, aM )

    ! --- Local Lax-Friedrichs Flux ---

    REAL(DP), INTENT(in) :: uL(nCF), uR(nCF), fL(nCF), fR(nCF), aP, aM

    REAL(DP) :: Euler_NumericalFlux_LLF_Relativistic(nCF)

    REAL(DP) :: alpha

    alpha = MAX( aM, aP )

    Euler_NumericalFlux_LLF_Relativistic &
      = Half * ( fL + fR - alpha * ( uR - uL ) )

    RETURN
  END FUNCTION Euler_NumericalFlux_LLF_Relativistic


  !> Compute the Harten-Lax-van-Leer numerical flux at a given element
  !> interface, in a given dimension.
  PURE FUNCTION Euler_NumericalFlux_HLL_Relativistic &
    ( uL, uR, fL, fR, aP, aM )

    REAL(DP), INTENT(in) :: uL(nCF), uR(nCF), fL(nCF), fR(nCF), aP, aM

    REAL(DP) :: Euler_NumericalFlux_HLL_Relativistic(nCF)

    Euler_NumericalFlux_HLL_Relativistic &
      = ( aP * fL + aM * fR - aP * aM * ( uR - uL ) ) / ( aP + aM )

    RETURN
  END FUNCTION Euler_NumericalFlux_HLL_Relativistic


  !> Compute the Harten-Lax-van-Leer-Contact numerical flux at a given element
  !> in the X1-direction.
  !> @param Shift The first contravariant component of the shift-vector.
  !> @param Gm11 The first covariant component of the spatial three-metric.
  PURE FUNCTION Euler_NumericalFlux_X1_HLLC_Relativistic &
    ( uL, uR, fL, fR, aP, aM, aC, Gm11, vL, vR, pL, pR, Lapse, Shift )

    REAL(DP), INTENT(in) :: uL(nCF), uR(nCF), fL(nCF), fR(nCF), &
                            aP, aM, aC, Gm11, vL, vR, pL, pR, Lapse, Shift

    REAL(DP) :: p, D, S1, S2, S3, E, Ne, UE, FE, FS, VelocityRatio, &
                Euler_NumericalFlux_X1_HLLC_Relativistic(nCF)

    IF( aM .EQ. Zero )THEN

      Euler_NumericalFlux_X1_HLLC_Relativistic = fL

    ELSEIF( aP .EQ. Zero )THEN

      Euler_NumericalFlux_X1_HLLC_Relativistic = fR

    ELSE

      ! --- From Mignone & Bodo (2005)
      !     Note the sign change on aM which is due to it being
      !     read in as positive but the formulae assuming it is negative ---

      IF( aC .GE. Zero )THEN

        VelocityRatio = ( -aM - Lapse * vL + Shift ) &
                      / ( -aM - Lapse * aC + Shift )

        ! --- uL_star ---
        UE = uL(iCF_E) + uL(iCF_D)
        FE = uL(iCF_S1) / Gm11 - Shift / Lapse * UE
        FS = uL(iCF_S1) * ( vL - Shift / Lapse ) + pL

        p  = ( Gm11 * aC * ( -aM * UE - Lapse * FE ) &
               - ( -aM * uL(iCF_S1) - Lapse * FS ) ) &
             / ( Lapse - Gm11 * aC * ( -aM + Shift ) )

        D  = uL(iCF_D)  * VelocityRatio

        S1 = uL(iCF_S1) * VelocityRatio &
               + Lapse * ( p - pL ) / ( -aM - Lapse * aC + Shift )

        S2 = uL(iCF_S2) * VelocityRatio

        S3 = uL(iCF_S3) * VelocityRatio

        E  = UE         * VelocityRatio + Lapse * ( p * aC - pL * vL ) &
               / ( -aM - Lapse * aC + Shift )

        Ne = uL(iCF_Ne) * VelocityRatio

      ELSE

        VelocityRatio = ( aP - Lapse * vR + Shift ) &
                      / ( aP - Lapse * aC + Shift )

        ! --- uR_star ---
        UE = uR(iCF_E) + uR(iCF_D)
        FE = uR(iCF_S1) / Gm11 - Shift / Lapse * UE
        FS = uR(iCF_S1) * ( vR - Shift / Lapse ) + pR

        p  = ( Gm11 * aC * ( aP * UE - Lapse * FE ) &
               - ( aP * uR(iCF_S1) - Lapse * FS ) ) &
               / ( Lapse - Gm11 * aC * ( aP + Shift ) )

        D  = uR(iCF_D)  * VelocityRatio

        S1 = uR(iCF_S1) * VelocityRatio &
               + Lapse * ( p - pR ) / ( aP - Lapse * aC + Shift )

        S2 = uR(iCF_S2) * VelocityRatio

        S3 = uR(iCF_S3) * VelocityRatio

        E  = UE         * VelocityRatio + Lapse * ( p * aC - pR * vR ) &
               / ( aP - Lapse * aC + Shift )

        Ne = uR(iCF_Ne) * VelocityRatio

      END IF

      Euler_NumericalFlux_X1_HLLC_Relativistic(iCF_D)  &
        = D  * ( aC - Shift / Lapse )
      Euler_NumericalFlux_X1_HLLC_Relativistic(iCF_S1) &
        = S1 * ( aC - Shift / Lapse ) + p
      Euler_NumericalFlux_X1_HLLC_Relativistic(iCF_S2) &
        = S2 * ( aC - Shift / Lapse )
      Euler_NumericalFlux_X1_HLLC_Relativistic(iCF_S3) &
        = S3 * ( aC - Shift / Lapse )
      Euler_NumericalFlux_X1_HLLC_Relativistic(iCF_E)  &
        = S1 / Gm11 - D * aC - Shift / Lapse * ( E - D )
      Euler_NumericalFlux_X1_HLLC_Relativistic(iCF_Ne) &
        = Ne * ( aC - Shift / Lapse )

    END IF

    RETURN
  END FUNCTION Euler_NumericalFlux_X1_HLLC_Relativistic


  !> Compute the Harten-Lax-van-Leer-Contact numerical flux at a given element
  !> in the X2-direction.
  !> @param Shift The second contravariant component of the shift-vector.
  !> @param Gm22 The second covariant component of the spatial three-metric.
  PURE FUNCTION Euler_NumericalFlux_X2_HLLC_Relativistic &
    ( uL, uR, fL, fR, aP, aM, aC, Gm22, vL, vR, pL, pR, Lapse, Shift )

    REAL(DP), INTENT(in) :: uL(nCF), uR(nCF), fL(nCF), fR(nCF), &
                            aP, aM, aC, Gm22, vL, vR, pL, pR, Lapse, Shift

    REAL(DP) :: p, D, S1, S2, S3, E, Ne, UE, FE, FS, VelocityRatio
    REAL(DP) :: Euler_NumericalFlux_X2_HLLC_Relativistic(nCF)

    IF( aM .EQ. Zero )THEN

      Euler_NumericalFlux_X2_HLLC_Relativistic = fL

    ELSEIF( aP .EQ. Zero )THEN

      Euler_NumericalFlux_X2_HLLC_Relativistic = fR

    ELSE

      ! --- From Mignone & Bodo (2005)
      !     Note the sign change on aM which is due to it being
      !     read in as positive but the formulae assuming it is negative ---

      IF( aC .GE. Zero )THEN

        VelocityRatio = ( -aM - Lapse * vL + Shift ) &
                      / ( -aM - Lapse * aC + Shift )

        ! --- uL_star ---
        UE = uL(iCF_E) + uL(iCF_D)
        FE = uL(iCF_S2) / Gm22 - Shift / Lapse * UE
        FS = uL(iCF_S2) * ( vL - Shift / Lapse ) + pL

        p  = ( Gm22 * aC * ( -aM * UE - Lapse * FE ) &
               - ( -aM * uL(iCF_S2) - Lapse * FS ) ) &
             / ( Lapse - Gm22 * aC * ( -aM + Shift ) )

        D  = uL(iCF_D)  * VelocityRatio

        S1 = uL(iCF_S1) * VelocityRatio

        S2 = uL(iCF_S2) * VelocityRatio &
               + Lapse * ( p - pL ) / ( -aM - Lapse * aC + Shift )

        S3 = uL(iCF_S3) * VelocityRatio

        E  = UE         * VelocityRatio + Lapse * ( p * aC - pL * vL ) &
               / ( -aM - Lapse * aC + Shift )

        Ne = uL(iCF_Ne) * VelocityRatio

      ELSE

        VelocityRatio = ( aP - Lapse * vR + Shift ) &
                      / ( aP - Lapse * aC + Shift )

        ! --- uR_star ---
        UE = uR(iCF_E) + uR(iCF_D)
        FE = uR(iCF_S2) / Gm22 - Shift / Lapse * UE
        FS = uR(iCF_S2) * ( vR - Shift / Lapse ) + pR

        p  = ( Gm22 * aC * ( aP * UE - Lapse * FE ) &
               - ( aP * uR(iCF_S2) - Lapse * FS ) ) &
               / ( Lapse - Gm22 * aC * ( aP + Shift ) )

        D  = uR(iCF_D)  * VelocityRatio

        S1 = uR(iCF_S1) * VelocityRatio

        S2 = uR(iCF_S2) * VelocityRatio &
               + Lapse * ( p - pR ) / ( aP - Lapse * aC + Shift )

        S3 = uR(iCF_S3) * VelocityRatio

        E  = UE         * VelocityRatio + Lapse * ( p * aC - pR * vR ) &
               / ( aP - Lapse * aC + Shift )

        Ne = uR(iCF_Ne) * VelocityRatio

      END IF

      Euler_NumericalFlux_X2_HLLC_Relativistic(iCF_D)  &
        = D  * ( aC - Shift / Lapse )
      Euler_NumericalFlux_X2_HLLC_Relativistic(iCF_S1) &
        = S1 * ( aC - Shift / Lapse )
      Euler_NumericalFlux_X2_HLLC_Relativistic(iCF_S2) &
        = S2 * ( aC - Shift / Lapse ) + p
      Euler_NumericalFlux_X2_HLLC_Relativistic(iCF_S3) &
        = S3 * ( aC - Shift / Lapse )
      Euler_NumericalFlux_X2_HLLC_Relativistic(iCF_E)  &
        = S2 / Gm22 - D * aC - Shift / Lapse * ( E - D )
      Euler_NumericalFlux_X2_HLLC_Relativistic(iCF_Ne) &
        = Ne * ( aC - Shift / Lapse )

    END IF

    RETURN
  END FUNCTION Euler_NumericalFlux_X2_HLLC_Relativistic


  !> Compute the Harten-Lax-van-Leer-Contact numerical flux at a given element
  !> in the X3-direction.
  !> @param Shift The third contravariant component of the shift-vector.
  !> @param Gm33 The third covariant component of the spatial three-metric.
  PURE FUNCTION Euler_NumericalFlux_X3_HLLC_Relativistic &
      ( uL, uR, fL, fR, aP, aM, aC, Gm33, vL, vR, pL, pR, Lapse, Shift )

    ! --- Shift is the third contravariant component of the shift-vector
    !     Gm is the third covariant component of the spatial three-metric ---

    REAL(DP), INTENT(in) :: uL(nCF), uR(nCF), fL(nCF), fR(nCF), &
                            aP, aM, aC, Gm33, vL, vR, pL, pR, Lapse, Shift

    REAL(DP) :: p, D, S1, S2, S3, E, Ne, UE, FE, FS, VelocityRatio
    REAL(DP) :: Euler_NumericalFlux_X3_HLLC_Relativistic(nCF)

    IF( aM .EQ. Zero )THEN

      Euler_NumericalFlux_X3_HLLC_Relativistic = fL

    ELSEIF( aP .EQ. Zero )THEN

      Euler_NumericalFlux_X3_HLLC_Relativistic = fR

    ELSE

      ! --- From Mignone & Bodo (2005)
      !     Note the sign change on aM which is due to it being
      !     read in as positive but the formulae assuming it is negative ---

      IF( aC .GE. Zero )THEN

        VelocityRatio = ( -aM - Lapse * vL + Shift ) &
                      / ( -aM - Lapse * aC + Shift )

        ! --- uL_star ---
        UE = uL(iCF_E) + uL(iCF_D)
        FE = uL(iCF_S3) / Gm33 - Shift / Lapse * UE
        FS = uL(iCF_S3) * ( vL - Shift / Lapse ) + pL

        p  = ( Gm33 * aC * ( -aM * UE - Lapse * FE ) &
               - ( -aM * uL(iCF_S3) - Lapse * FS ) ) &
             / ( Lapse - Gm33 * aC * ( -aM + Shift ) )

        D  = uL(iCF_D)  * VelocityRatio

        S1 = uL(iCF_S1) * VelocityRatio

        S2 = uL(iCF_S2) * VelocityRatio

        S3 = uL(iCF_S3) * VelocityRatio &
               + Lapse * ( p - pL ) / ( -aM - Lapse * aC + Shift )

        E  = UE         * VelocityRatio + Lapse * ( p * aC - pL * vL ) &
               / ( -aM - Lapse * aC + Shift )

        Ne = uL(iCF_Ne) * VelocityRatio

      ELSE

        VelocityRatio = ( aP - Lapse * vR + Shift ) &
                      / ( aP - Lapse * aC + Shift )

        ! --- uR_star ---
        UE = uR(iCF_E) + uR(iCF_D)
        FE = uR(iCF_S3) / Gm33 - Shift / Lapse * UE
        FS = uR(iCF_S3) * ( vR - Shift / Lapse ) + pR

        p  = ( Gm33 * aC * ( aP * UE - Lapse * FE ) &
               - ( aP * uR(iCF_S3) - Lapse * FS ) ) &
               / ( Lapse - Gm33 * aC * ( aP + Shift ) )

        D  = uR(iCF_D)  * VelocityRatio

        S1 = uR(iCF_S1) * VelocityRatio

        S2 = uR(iCF_S2) * VelocityRatio

        S3 = uR(iCF_S3) * VelocityRatio &
               + Lapse * ( p - pR ) / ( aP - Lapse * aC + Shift )

        E  = UE         * VelocityRatio + Lapse * ( p * aC - pR * vR ) &
               / ( aP - Lapse * aC + Shift )

        Ne = uR(iCF_Ne) * VelocityRatio

      END IF

      Euler_NumericalFlux_X3_HLLC_Relativistic(iCF_D)  &
        = D  * ( aC - Shift / Lapse )
      Euler_NumericalFlux_X3_HLLC_Relativistic(iCF_S1) &
        = S1 * ( aC - Shift / Lapse )
      Euler_NumericalFlux_X3_HLLC_Relativistic(iCF_S2) &
        = S2 * ( aC - Shift / Lapse )
      Euler_NumericalFlux_X3_HLLC_Relativistic(iCF_S3) &
        = S3 * ( aC - Shift / Lapse ) + p
      Euler_NumericalFlux_X3_HLLC_Relativistic(iCF_E)  &
        = S3 / Gm33 - D * aC - Shift / Lapse * ( E - D )
      Euler_NumericalFlux_X3_HLLC_Relativistic(iCF_Ne) &
        = Ne * ( aC - Shift / Lapse )

    END IF

    RETURN
  END FUNCTION Euler_NumericalFlux_X3_HLLC_Relativistic


  ! --- PRIVATE FUNCTIONS/SUBROUTINES ---


  SUBROUTINE ComputeFunJacP( CF_D, CF_E, SSq, P, FunP, JacP, Pnorm_Option )

    REAL(DP), INTENT(in)           :: CF_D, CF_E, SSq, P
    REAL(DP), INTENT(in), OPTIONAL :: Pnorm_Option
    REAL(DP), INTENT(out)          :: FunP, JacP

    REAL(DP) :: HSq, RHO, EPS, dRHO, dEPS, Pnorm
    REAL(DP) :: Pbar(1)

    Pnorm = One
    IF( PRESENT( Pnorm_Option ) ) Pnorm = Pnorm_Option

    HSq = ( CF_E + P + CF_D )**2

    RHO = CF_D * SQRT( HSq - SSq ) / SQRT( HSq )

    EPS = ( SQRT( HSq - SSq ) &
            - P * SQRT( HSq ) / SQRT( HSq - SSq ) - CF_D ) / CF_D

    CALL ComputePressureFromSpecificInternalEnergy &
         ( [ RHO ], [ EPS ], [ 0.0_DP ], Pbar )

    FunP = ( P - Pbar(1) ) / Pnorm

    dRHO = CF_D * SSq / ( SQRT( HSq - SSq ) * HSq )

    dEPS = P * SSq / ( ( HSq - SSq ) * SQRT( HSq ) * RHO )

    JacP = ( 1.0_DP - Pbar(1) * ( dRHO / RHO + dEPS / EPS ) ) / Pnorm

  END SUBROUTINE ComputeFunJacP


  SUBROUTINE ComputePressureWithBisectionMethod( CF_D, CF_E, SSq, P )

    REAL(DP), INTENT(in)  :: CF_D, CF_E, SSq
    REAL(DP), INTENT(out) :: P

    LOGICAL            :: CONVERGED
    INTEGER, PARAMETER :: MAX_IT = 1 - INT( LOG(TolP) / LOG(2.0d0) )
    INTEGER            :: ITERATION
    REAL(DP)           :: PA, PB, PC, DeltaP
    REAL(DP)           :: FunPA, FunPB, FunPC

    ! --- Get upper and lower bounds on pressure, PA, PB ---
    PA = SqrtTiny
    PB = Three * CF_E

    ! --- Compute FunP for upper and lower bounds ---
    CALL ComputeFunP( CF_D, CF_E, SSq, PA, FunPA )
    CALL ComputeFunP( CF_D, CF_E, SSq, PB, FunPB )

    ! --- Check that sign of FunP changes across bounds ---
    IF( .NOT. FunPA * FunPB .LT. 0 )THEN

      WRITE(*,'(6x,A)') &
        'ComputePressureWithBisectionMethod:'
      WRITE(*,'(8x,A)') &
        'Error: No Root in Interval'
      WRITE(*,'(8x,A,ES24.16E3)') 'CF_D: ', CF_D
      WRITE(*,'(8x,A,ES24.16E3)') 'CF_E: ', CF_E
      WRITE(*,'(8x,A,ES24.16E3)') 'SSq:  ', SSq
      WRITE(*,'(8x,A,2ES15.6E3)') &
        'PA, PB = ', PA, PB
      WRITE(*,'(8x,A,2ES15.6E3)') &
        'FunPA, FunPB = ', FunPA, FunPB
      STOP

    END IF

    DeltaP = PB - PA

    ITERATION = 0
    CONVERGED = .FALSE.
    DO WHILE ( ITERATION .LT. MAX_IT )

      ITERATION = ITERATION + 1

      ! --- Compute midpoint, PC ---
      DeltaP = Half * DeltaP
      PC     = PA + DeltaP

      ! --- Compute FunP for midpoint pressure ---
      CALL ComputeFunP( CF_D, CF_E, SSq, PC, FunPC )

      ! --- Change PC to PA or PB, depending on sign of FunP(PC) ---
      IF( FunPA * FunPC .LT. Zero )THEN

        PB = PC
        FunPB = FunPC

      ELSE

        PA = PC
        FunPA = FunPC

      END IF

    END DO

    P = PA

  END SUBROUTINE ComputePressureWithBisectionMethod


  SUBROUTINE ComputePressureWithBrentsMethod( CF_D, CF_E, SSq, Pbrent )

    REAL(DP), INTENT(in)  :: CF_D, CF_E, SSq
    REAL(DP), INTENT(out) :: Pbrent

    REAL(DP) :: PA, PB, PC, PD, PS, PSwap, Pbisec
    REAL(DP) :: FunPA, FunPB, FunPC, FunPS
    REAL(DP) :: JacPA, JacPB, JacPC, JacPS

    LOGICAL            :: mflag, COND1, COND2, COND3, COND4, COND5
    INTEGER, PARAMETER :: MAX_IT = 100
    INTEGER            :: ITERATION

    ! --- Implementation of Brent's method from:
    !     https://en.wikipedia.org/wiki/Brent%27s_method#Algorithm ---

    ! --- Get Pbisec to normalize FunP ---
    CALL ComputePressureWithBisectionMethod( CF_D, CF_E, SSq, Pbisec )

    ! --- Define values that bracket the root ---
    PA = Zero
    PB = Three * CF_E
    CALL ComputeFunJacP( CF_D, CF_E, SSq, PA, FunPA, JacPA )
    CALL ComputeFunJacP( CF_D, CF_E, SSq, PB, FunPB, JacPB )

    ! --- Exit if solution is not bracketed ---
    IF( .NOT. FunPA * FunPB .LT. 0.0_DP )THEN
      WRITE(*,'(A)') 'No root in interval. Exiting...'
      STOP
    END IF

    ! --- Conditionally swap PA and PB ---
    IF( ABS( FunPA ) .LT. ABS( FunPB ) )THEN
      PSwap = PB
      PB    = PA
      PA    = PSwap
      CALL ComputeFunJacP( CF_D, CF_E, SSq, PA, FunPA, JacPA )
      CALL ComputeFunJacP( CF_D, CF_E, SSq, PB, FunPB, JacPB )
    END IF

    ! --- Set PC = PA and compute FunPC ---
    PC = PA
    CALL ComputeFunJacP( CF_D, CF_E, SSq, PC, FunPC, JacPC )

    ! --- Set mflag ---
    mflag = .TRUE.

    ITERATION = 0
    DO WHILE( ( ABS( PB - PA ) / ABS( Pbisec ) .GE. TolP    ) &
        .AND. ( ABS( FunPB )                   .GE. TolFunP ) &
        .AND. ( ITERATION                      .LE. MAX_IT  ) )

      ITERATION = ITERATION + 1

      IF( ( FunPA .NE. FunPC ) .AND. ( FunPB .NE. FunPC ) )THEN
        ! --- Inverse quadratic interpolation ---
        PS =   PA * FunPB * FunPC / ( ( FunPA - FunPB ) * ( FunPA - FunPC ) ) &
             + PB * FunPA * FunPC / ( ( FunPB - FunPA ) * ( FunPB - FunPC ) ) &
             + PC * FunPA * FunPB / ( ( FunPC - FunPA ) * ( FunPC - FunPB ) )
      ELSE
        ! --- Secant method (replace with Newton's method?) ---
        PS = PB - FunPB * ( PB - PA ) / ( FunPB - FunPA )
      END IF

      ! --- Condition 1 ---
      IF( PB .GT. ( 3.0_DP * PA + PB ) / 4.0_DP )THEN
        IF( .NOT. ( ( PS .GT. ( 3.0_DP * PA + PB ) / 4.0_DP ) &
                    .AND. ( PS .LT. PB ) ) )THEN
          COND1 = .TRUE.
        ELSE
          COND1 = .FALSE.
        END IF
      ELSE
        IF( .NOT. ( ( PS .LT. ( 3.0_DP * PA + PB ) / 4.0_DP ) &
              .AND. ( PS .GT. PB ) ) )THEN
          COND1 = .TRUE.
        ELSE
          COND1 = .FALSE.
        END IF
      END IF

      ! --- Condition 2 ---
      IF( mflag .AND. ( ABS( PS - PB ) .GE. ( ABS( PB - PC ) / 2.0_DP ) ) )THEN
        COND2 = .TRUE.
      ELSE
        COND2 = .FALSE.
      END IF

      ! --- Condition 3 ---
      IF( .NOT. mflag .AND. ( ABS( PS - PB ) &
          .GE. ( ABS( PC - PD ) / 2.0_DP ) ) )THEN
        COND3 = .TRUE.
      ELSE
        COND3 = .FALSE.
      END IF

      ! --- Condition 4 ---
      IF( mflag .AND. ( ABS( PB - PC ) .LT. TolP ) )THEN
        COND4 = .TRUE.
      ELSE
        COND4 = .FALSE.
      END IF

      ! --- Condition 5 ---
      IF( .NOT. mflag .AND. ( ABS( PC - PD ) .LT. TolP ) )THEN
        COND5 = .TRUE.
      ELSE
        COND5 = .FALSE.
      END IF

      IF( COND1 .OR. COND2 .OR. COND3 .OR. COND4 .OR. COND5 )THEN
        PS = ( PA + PB ) / 2.0_DP
        mflag = .TRUE.
      ELSE
        mflag = .FALSE.
      END IF

      CALL ComputeFunJacP( CF_D, CF_E, SSq, PS, FunPS, JacPS )
      PD = PC
      PC = PB

      IF( FunPA * FunPS .LT. 0.0_DP )THEN
        PB = PS
        CALL ComputeFunJacP( CF_D, CF_E, SSq, PB, FunPB, JacPB )
      ELSE
        PA = PS
        CALL ComputeFunJacP( CF_D, CF_E, SSq, PA, FunPA, JacPA )
      END IF

      ! --- Conditionally swap PA and PB ---
      IF( ABS( FunPA ) .LT. ABS( FunPB ) )THEN
        PSwap = PB
        PB    = PA
        PA    = PSwap
        CALL ComputeFunJacP( CF_D, CF_E, SSq, PA, FunPA, JacPA )
        CALL ComputeFunJacP( CF_D, CF_E, SSq, PB, FunPB, JacPB )
      END IF

      Pbrent = PB

      IF( ITERATION .EQ. MAX_IT )THEN
        WRITE(*,*)
        WRITE(*,'(A)') 'Maximum number of iterations reached.'
        WRITE(*,'(A,ES24.16E3)') 'Pbrent =        ', Pbrent
        WRITE(*,'(A,ES24.16E3)') '|dP|/|Pbisec| = ', &
          ABS( PB - PA ) / ABS( Pbisec )
        WRITE(*,'(A,ES24.16E3)') '|Pbrent-Pbisec|/|Pbisec| = ', &
          ABS( Pbrent - Pbisec ) / ABS( Pbisec )
        STOP
      END IF

    END DO

  END SUBROUTINE ComputePressureWithBrentsMethod


  SUBROUTINE ComputeFunP( CF_D, CF_E, SSq, P, FunP )

    REAL(DP), INTENT(in)  :: CF_D, CF_E, SSq, P
    REAL(DP), INTENT(out) :: FunP

    REAL(DP) :: HSq, RHO, EPS
    REAL(DP) :: Pbar(1)

    HSq = ( CF_E + P + CF_D )**2

    RHO = CF_D * SQRT( HSq - SSq ) / SQRT( HSq )

    EPS = ( SQRT( HSq - SSq ) &
            - P * SQRT( HSq ) / SQRT( HSq - SSq ) - CF_D ) / CF_D

    CALL ComputePressureFromSpecificInternalEnergy &
         ( [ RHO ], [ EPS ], [ 0.0_DP ], Pbar )

    FunP = P - Pbar(1)

  END SUBROUTINE ComputeFunP


END MODULE Euler_UtilitiesModule_Relativistic
