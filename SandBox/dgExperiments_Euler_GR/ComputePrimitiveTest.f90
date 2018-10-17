PROGRAM ComputePrimitiveTest

  USE KindModule, ONLY: &
    DP, Zero, SqrtTiny, Half, One
  USE GeometryFieldsModule, ONLY: &
    nGF, iGF_Gm_dd_11, iGF_Gm_dd_22, iGF_Gm_dd_33
  USE FluidFieldsModule, ONLY: &
    nCF, iCF_D, iCF_S1, iCF_S2, iCF_S3, iCF_E, iCF_Ne, &
    nPF, iPF_D, iPF_V1, iPF_V2, iPF_V3, iPF_E, iPF_Ne
  USE EquationOfStateModule, ONLY: &
    InitializeEquationOfState, &
    FinalizeEquationOfState, &
    ComputePressureFromSpecificInternalEnergy
  USE EulerEquationsUtilitiesModule_Beta_GR, ONLY: &
    ComputePrimitive_GR, &
    ComputeFunJacP    

  IMPLICIT NONE

  INTEGER,  PARAMETER :: N = 10000, nNodes = 1
  INTEGER             :: i
  REAL(DP)            :: Pressure(nNodes), q, SSq
  REAL(DP)            :: U(nNodes,nCF), P(nNodes,nPF), G(nNodes,nGF)
  REAL(DP)            :: Pmin, Pmax, DeltaP
  REAL(DP), PARAMETER :: Gamma_IDEAL = 4.0_DP / 3.0_DP

  CALL InitializeEquationOfState &
         ( EquationOfState_Option = 'IDEAL', &
           Gamma_IDEAL_Option = Gamma_IDEAL )

  i = 1

  ! --- MAKE SURE TO CHANGE 'E' TO 'd' ---
  U(i,iCF_D)        =  1.0774584450311608d-011
  U(i,iCF_S1)       =  4.5946496158721857d+000
  U(i,iCF_S2)       =  0.0000000000000000d+000
  U(i,iCF_S3)       =  0.0000000000000000d+000
  U(i,iCF_E)        =  4.5946501977159642d+000

  G(i,iGF_Gm_dd_11) =  1.0000000000000000d+000
  G(i,iGF_Gm_dd_22) =  2.1972656249999999d-005
  G(i,iGF_Gm_dd_33) =  2.1972656249999999d-005

  SSq =  U(i,iCF_S1)**2 / G(i,iGF_Gm_dd_11) &
       + U(i,iCF_S2)**2 / G(i,iGF_Gm_dd_22) &
       + U(i,iCF_S3)**2 / G(i,iGF_Gm_dd_33)

  q = U(i,iCF_D) + U(i,iCF_E) - SQRT( U(i,iCF_D)**2 + SSq )

  Pmin = MAX( -( U(i,iCF_D) + U(i,iCF_E) ) + SQRT( SSq ), SqrtTiny )
  Pmax = 2.0_DP * ( One - One / Gamma_IDEAL ) * U(i,iCF_E)
  
  WRITE(*,'(A,ES24.16E3,ES24.16E3)') 'Pmin, Pmax: ', Pmin, Pmax
  WRITE(*,'(A)') 'Creating FunP array...'
  CALL CreateFunParray( U(i,iCF_D), U(i,iCF_E), SSq, Pmin, Pmax )
  !STOP 'Created FunP array'

  CALL ComputePrimitive_GR &
         ( U(:,iCF_D), &
           U(:,iCF_S1), U(:,iCF_S2), U(:,iCF_S3), &
           U(:,iCF_E), U(:,iCF_Ne), &
           P(:,iPF_D), &
           P(:,iPF_V1), P(:,iPF_V2), P(:,iPF_V3), &
           P(:,iPF_E), P(:,iPF_Ne), &
           Pressure, &
           G(:,iGF_Gm_dd_11), G(:,iGF_Gm_dd_22), G(:,iGF_Gm_dd_33) )

  WRITE(*,'(A9,ES24.16E3)') "P(out) = ", Pressure(i)
  
  CALL FinalizeEquationOfState

CONTAINS
  

    SUBROUTINE CreateFunParray( CF_D, CF_E, SSq, Pmin, Pmax )

      REAL(DP), INTENT(in) :: CF_D, CF_E, SSq, Pmin, Pmax
      REAL(DP)             :: Parr(N), FunP(N), JacP(N), DeltaP
      INTEGER              :: j

      OPEN( 100, FILE = 'FunP.dat' )

      DeltaP = ( Pmax - Pmin ) / N
      DO j = 1, N
         Parr(j) = Pmin + (j-1) * DeltaP
         CALL ComputeFunJacP &
                ( CF_D, CF_E, SSq, Parr(j), FunP(j), JacP(j) )
         WRITE( 100, '(ES24.16E3,1x,ES24.16E3,1x,ES24.16E3)') &
           Parr(j), FunP(j), JacP(j)
      END DO

      CLOSE( 100 )

    END SUBROUTINE CreateFunParray


END PROGRAM ComputePrimitiveTest
