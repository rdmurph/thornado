MODULE CharacteristicDecompositionModule

  USE KindModule, ONLY: &
    DP, Zero, Half, One, Two, Three
  USE RadiationFieldsModule, ONLY: &
    nPR, iPR_D, iPR_I1, iPR_I2, iPR_I3
  USE TwoMoment_ClosureModule, ONLY: &
    FluxFactor, &
    EddingtonFactor
  USE ClosureModule, ONLY: &
    PartialDerivativeEddingtonFactor    

  IMPLICIT NONE
  PRIVATE

  LOGICAL, PARAMETER :: Debug = .FALSE.

  PUBLIC :: ComputeCharacteristicDecomposition_RC

  EXTERNAL  DGEEV

CONTAINS

  SUBROUTINE ComputeCharacteristicDecomposition_RC &
    ( iDim, G, U, R, invR )

    INTEGER,  INTENT(in)  :: iDim
    REAL(DP), INTENT(in)  :: G(3)   ! Gm_dd_11,22,33
    REAL(DP), INTENT(in)  :: U(nPR)
    REAL(DP), INTENT(out) :: R(nPR,nPR)
    REAL(DP), INTENT(out) :: invR(nPR,nPR)

    INTEGER :: i
    REAL(DP) :: Gm_dd_11, Gm_dd_22, Gm_dd_33, Eigens(nPR)
    REAL(DP) :: Jacobian(nPR,nPR)

    Gm_dd_11 = G(1)
    Gm_dd_22 = G(2)
    Gm_dd_33 = G(3)

    CALL ComputeFluxJacobian &
    ( iDim, U(iPR_D), U(iPR_I1), U(iPR_I2), U(iPR_I3), &
      Gm_dd_11, Gm_dd_22, Gm_dd_33, Jacobian )

    CALL ComputeEigen( nPR, Jacobian, R, invR, Eigens )

!    IF ( Debug ) THEN
      WRITE(*,*)
      WRITE(*,'(A4,A)')'', 'ComputeCharacteristicDecomposition_RC:'
      WRITE(*,*)
      WRITE(*,'(A4,A6,I2)')'', 'iDim = ', iDim
      WRITE(*,*)
      WRITE(*,'(A6,4ES16.5)') '', Eigens
!    END IF

  END SUBROUTINE ComputeCharacteristicDecomposition_RC


  SUBROUTINE ComputeFluxJacobian &
    ( iDim, D, I_1, I_2, I_3, Gm_dd_11, Gm_dd_22, Gm_dd_33, Jacobian )

    INTEGER,  INTENT(in)     :: iDim
    REAL(DP), INTENT(in)     :: D, I_1, I_2, I_3
    REAL(DP), INTENT(in)     :: Gm_dd_11, Gm_dd_22, Gm_dd_33
    REAL(DP), INTENT(out)    :: Jacobian(nPR,nPR)

    REAL(DP)                 :: FF, EF

    INTEGER  :: i, j
    REAL(DP) :: A21, A22, A23, A24, A31, A32, A33, A34, &
                A41, A42, A43, A44, EF_FF, EF_D
    REAL(DP) :: hd1, hu1, hd2, hu2, hd3, hu3
    REAL(DP) :: Elem1, Elem2
        
    FF = FluxFactor( D, I_1, I_2, I_3, Gm_dd_11, Gm_dd_22, Gm_dd_33 )
    EF = EddingtonFactor( D, FF )

    hu1 = I_1 / (FF * D)
    hu2 = I_2 / (FF * D)
    hu3 = I_3 / (FF * D)
    hd1 = Gm_dd_11 * hu1
    hd2 = Gm_dd_22 * hu2
    hd3 = Gm_dd_33 * hu3
    
    CALL PartialDerivativeEddingtonFactor( D, FF, EF_D, EF_FF )
    
    Elem1 = -One + Three * EF + Three * EF_D * D
    Elem2 = Two + Three * EF_FF * FF - 6.d0 * EF

    
    SELECT CASE ( iDim ) 

      CASE ( 1 )

        A21 = Half * ( One + EF_FF * ( FF - Three * FF * hd1 * hu1 ) &
                       - EF_D * D - EF + hd1 * hu1 * Elem1 )

        A22 = Half * ( EF_FF * hu1 * ( -One + Three * hd1 * hu1 ) ) &
            + ( hd1 / Gm_dd_11 + hu1 - Two * hd1 * hu1 * hu1 ) &
              * ( -One + Three * EF ) / FF
     
        A23 = Half * EF_FF * ( -One + Three * hd1 * hu1 ) * hu2 &
            + hd1 * hu1 * hu2 * ( One - Three * EF ) / FF
  
        A24 = Half * EF_FF * ( -One + Three * hd1 * hu1 ) * hu3 &
            + hd1 * hu1 * hu3 * ( One - Three * EF ) / FF

        A31 = Half * hd2 * hu1 * ( Elem1 - Three * EF_FF )

        A32 = Half * hd2 * ( -One + Gm_dd_11 * hu1 * hu1 &
                           * Elem2  + Three * EF ) / ( Gm_dd_11 * FF )

        A33 = Half * hu1 * ( -One + hd2 * hu2 * Elem2 + Three * EF ) / FF

        A34 = Half * hd2 * hu1 * hu3 * Elem2 / FF

        A41 = Half * hd3 * hu1 * ( Elem1 - Three * EF_FF * FF  )

        A42 = Half * hd3 * &
              ( -One + Gm_dd_11 * hu1 * hu1 * Elem2 + Three * EF ) &
              / ( Gm_dd_11 * FF )

        A43 = Half * hd3 * hu1 * hu2 * Elem2 / FF

        A44 = Half * hu1 * ( -One + hd3 * hu3 * Elem2 + Three * EF ) / FF

! ---------------------------------------------------------------
! Fortran is column-major order. The Jacobian in writting format:    
!        Jacobian(1,:) = [ Zero, One/Gm_dd_11,  Zero, Zero ]
!        Jacobian(2,:) = [ A21,  A22,           A23,  A24  ]
!        Jacobian(3,:) = [ A31,  A32,           A33,  A34  ]
!        Jacobian(4,:) = [ A41,  A42,           A43,  A44  ]
! ---------------------------------------------------------------

        Jacobian(:,1) = [ Zero, A21, A31, A41 ]
        Jacobian(:,2) = [ One/Gm_dd_11, A22, A32, A42 ]
        Jacobian(:,3) = [ Zero, A23, A33, A43 ]
        Jacobian(:,4) = [ Zero, A24, A34, A44 ]

      CASE ( 2 )

        A21 = Half * hd1 * hu2 * ( Elem1 - Three * EF_FF * FF )

        A22 = Half * hu2 * ( -One + hd1 * hu1 * Elem2 + Three * EF ) / FF
       
        A23 = Half * hd1 * ( -One + Gm_dd_22 * hu2 * hu2 * Elem2 &
                             + Three * EF ) / ( Gm_dd_22 * FF )

        A24 = Half * hd1 * hu2 * hu3 * Elem2 / FF

        A31 = Half * ( One + EF_FF * ( FF - Three * FF * hd2 * hu2 ) &
                       - EF_D * D - EF + hd2 * hu2 * Elem1 )

        A32 = Half * EF_FF * hu1 * ( -One + Three * hd2 * hu2 ) &
              + hd2 * hu1 * hu2 * ( One - Three * EF ) / FF

        A33 = Half * ( EF_FF * hu2 * ( -One + Three * hd2 * hu2 ) &
                       + ( hd2 / Gm_dd_22 + hu2 - Two * hd2 * hu2 * hu2 ) &
                       * ( -One + Three * EF ) / FF ) 

        A34 = Half * EF_FF * ( -One + Three * hd2 * hu2 ) * hu3 &
              + hd2 * hu2 * hu3 * ( One - Three * EF ) / FF 
 
        A41 = Half * hd3 * hu2 * ( Elem2 - Three * EF_FF * FF )

        A42 = Half * hd3 * hu1 * hu2 * Elem2 / FF

        A43 = Half * hd3 * ( -One + Gm_dd_22 * hu2 * hu2 * Elem2 &
                             + Three * EF ) / ( Gm_dd_22 * FF ) 

        A44 = Half * hu2 * ( -One + hd3 * hu3 * Elem2 + Three * EF ) / FF
 
        Jacobian(:,1) = [ Zero, A21, A31, A41 ]
        Jacobian(:,2) = [ Zero, A22, A32, A42 ]
        Jacobian(:,3) = [ One/Gm_dd_22, A23, A33, A43 ]
        Jacobian(:,4) = [ Zero, A24, A34, A44 ]

      CASE (3)

        A21 = Half * hd1 * hu3 * ( Elem1 - Three * EF_FF * FF )
 
        A22 = Half * hu3 * ( -One + hd1 * hu1 * Elem2 + Three * EF ) / FF

        A23 = Half * hd1 * hu2 * hu3 * Elem2 / FF

        A24 = Half * hd1 * ( -One + Gm_dd_33 * hu3 * hu3 * Elem2 &
                             + Three * EF ) / ( Gm_dd_33 * FF ) 

        A31 = Half * hd2 * hu3 * ( Elem1 - Three * EF_FF * FF )

        A32 = Half * hd2 * hu1 * hu3 * Elem2 / FF

        A33 = Half * hu3 * ( -One + hd2 * hu2 * Elem2 + Three * EF ) / FF

        A34 = Half * hd2 * ( -One + Gm_dd_33 * hu3 * hu3 * Elem2 &
                             + Three * EF ) / ( Gm_dd_33 * FF )

        A41 = Half * ( One + EF_FF * ( FF - Three * FF * hd3 * hu3 ) &
                       - EF_D * D - EF + hd3 * hu3 * Elem1 )
 
        A42 = Half * EF_FF * hu1 * ( -One + Three * hd3 * hu3 ) &
              + hd3 * hu1 * hu3 * ( One - Three * EF ) / FF

        A43 = Half * EF_FF * hu2 * ( -One + Three * hd3 * hu3 ) &
              + hd3 * hu2 * hu3 * ( One - Three * EF ) / FF

        A44 = Half * ( EF_FF * hu3 * ( -One + Three * hd3 * hu3 ) &
                       + ( hd3 / Gm_dd_33 + hu3 - Two * hd3 * hu3 * hu3 ) &
                         * ( -One + Three * EF ) / FF )

        Jacobian(:,1) = [ Zero, A21, A31, A41 ]
        Jacobian(:,2) = [ Zero, A22, A32, A42 ]
        Jacobian(:,3) = [ Zero, A23, A33, A43 ]
        Jacobian(:,4) = [ One/Gm_dd_33, A24, A34, A44 ]

      CASE DEFAULT

        WRITE(*,*)
        WRITE(*,'(A4,A)') '', &
          'Not able to compute flux matrix in dimension : '
        WRITE(*,'(A4,A6,I3)') '', 'iDim = ', iDim

    END SELECT

    !   Debug Printing

    IF ( Debug ) THEN

      WRITE(*,*)
      WRITE(*,'(A4,A)') '', 'ComputeFluxJacobian with : '
      WRITE(*,'(A6,A14,2ES15.5)') '', '( J, h ) : ', D, FF

      WRITE(*,*)
      WRITE(*,'(A6,A15,ES12.3,A5,A5,ES12.3)') '', 'hu1 =', hu1, '', 'hd1 =', hd1
      WRITE(*,'(A6,A15,ES12.3,A5,A5,ES12.3)') '', 'hu2 =', hu2, '', 'hd2 =', hd2
      WRITE(*,'(A6,A15,ES12.3,A5,A5,ES12.3)') '', 'hu3 =', hu3, '', 'hd3 =', hd3

      WRITE(*,*)
      WRITE(*,'(A6,A15,I3,A)') '', 'dF_i/dU in ', iDim, 'D :'
  
      DO j = 1, iDim
          WRITE(*,'(A6,A10,I2)') '', 'i =', j
        DO i = 1, 4
          WRITE(*,'(A6,4ES16.5)') '', Jacobian(i,:)
        END DO ! i
      END DO ! j
 
    END IF ! Debug printing

  END SUBROUTINE ComputeFluxJacobian


  SUBROUTINE ComputeEigen( Rank, Matrix, R, invR, Eigens ) 

    INTEGER,  INTENT(in)  :: Rank
    REAL(DP), INTENT(in)  :: Matrix(Rank,Rank)
    REAL(DP), INTENT(out) :: R(Rank,Rank)
    REAL(DP), INTENT(out) :: invR(Rank,Rank)
    REAL(DP), INTENT(out) :: Eigens(Rank)

    INTEGER  :: i
    REAL(DP) :: MatrixProduct(Rank,Rank)
    REAL(DP) :: EigenValueMatrix(Rank,Rank)
  
    REAL(DP) :: TransposeVL(Rank,Rank)
    REAL(DP) :: NormalMatrix(Rank,Rank)

    INTEGER          N
    PARAMETER        ( N = 4 )
    INTEGER          LDA, LDVL, LDVR
    PARAMETER        ( LDA = N, LDVL = N, LDVR = N )
    INTEGER          LWMAX
    PARAMETER        ( LWMAX = 1000 )
    INTEGER          INFO, LWORK
    REAL(DP)         A( LDA, N ), VL( LDVL, N ), VR( LDVR, N ), &
                     WR( N ), WI( N ), WORK( LWMAX )

    INTRINSIC        INT, MIN

    EigenValueMatrix(:,:) = Zero

    !   Call lapack routine DGEEV

    A = Matrix
    LWORK = -1
    CALL DGEEV( 'Vectors', 'Vectors', N, A, LDA, WR, WI, VL, LDVL, &
                 VR, LDVR, WORK, LWORK, INFO )
    LWORK = MIN( LWMAX, INT( WORK( 1 ) ) )

    CALL DGEEV( 'Vectors', 'Vectors', N, A, LDA, WR, WI, VL, LDVL, &
                 VR, LDVR, WORK, LWORK, INFO )

    IF( INFO.GT.0 ) THEN
       WRITE(*,*)'The algorithm failed to compute eigenvalues.'
       STOP
    END IF
    
    !   Output

    TransposeVL = TRANSPOSE( VL ) 
    NormalMatrix = MATMUL( TransposeVL, VR ) 
    R = VR

    DO i = 1, 4
      invR(i,:) = TransposeVL(i,:) / NormalMatrix(i,i)
    END DO
 
    Eigens = WR

    !   Debug Printing

    IF ( Debug ) THEN

      WRITE(*,*)
      WRITE(*,'(A6,A)') '', 'Eigenvalues given by DGEEV : '
      WRITE(*,'(A6,A)') '', 'Input Matrix : '
      DO i = 1, 4
        WRITE(*,'(A6,4ES16.5)') '', Matrix(i,:)
      END DO ! i

      WRITE(*,'(A6,A)') '', 'EigenValues : '
      DO i = 1, 4
        EigenValueMatrix(i,i) = WR(i)
        WRITE(*,'(A6,4ES16.5)') '', EigenValueMatrix(i,:)
      END DO

      WRITE(*,'(A6,A)') '', 'R : '
      DO i = 1, 4
        WRITE(*,'(A6,4ES16.5)') '', R(i,:)
      END DO ! i

      WRITE(*,'(A6,A)') '', 'invR : '
      DO i = 1, 4
        WRITE(*,'(A6,4ES16.5)') '', invR(i,:)
      END DO ! i

      WRITE(*,'(A6,A)') '', 'invR * R : '
      MatrixProduct = MATMUL( invR, R )
      DO i = 1, 4
        WRITE(*,'(A6,4ES16.5)') '', MatrixProduct(i,:)
      END DO ! i

      WRITE(*,'(A6,A)') '', 'invR * Input * R : '
      MatrixProduct = MATMUL( invR, MATMUL( Matrix, R ) )
      DO i = 1, 4
        WRITE(*,'(A6,4ES16.5)') '', MatrixProduct(i,:)
      END DO ! i
  
      WRITE(*,'(A6,A)') '', '-----------------------------------------'
      WRITE(*,*)
  
    END IF ! Debug printing

  END SUBROUTINE ComputeEigen

END MODULE CharacteristicDecompositionModule
