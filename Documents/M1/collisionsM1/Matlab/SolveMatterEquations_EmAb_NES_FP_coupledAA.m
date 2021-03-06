function [J0, D, T, Y, E, iter] = SolveMatterEquations_EmAb_NES_FP_coupledAA( Jin, dt, Chi, D, T, Y, E)

% g_E_N       : nE_G x 1 (energy grid)
% J, J_0    : nE_G x 1 (size of energy grid)
% Chi       : nE_G x 1 (size of energy grid)
% W2_N, W3_N: nE_G x 1 (size of energy grid)

% constants
global AtomicMassUnit BoltzmannConstant Erg2MeV SpeedOfLight PlanckConstant;

% energy grid
global g_E_N g_W2_N g_W3_N;


hc = PlanckConstant * SpeedOfLight;
c = SpeedOfLight;

Rtol = 1e-8; Utol = 1e-10; maxIter = 100;

iY = 1;
iE = 2;
iJNe = iE + (1:length(Jin.Ne));
iJANe = iJNe(end) + (1:length(Jin.ANe));

U = zeros(2,1);
C = zeros(2,1);


% \rho / m_B
N_B = D / AtomicMassUnit;

Chi.Ne = Chi.Ne * c * dt;
Chi.ANe = Chi.ANe * c * dt;

% scales
s_Y = N_B;
s_E = D;

% weights (for NES)
W2_N = g_W2_N;


% (scaled) weights
Theta2_N = 4 * pi * g_W2_N;
Theta3_N = 4 * pi * g_W3_N;

Theta2_N = Theta2_N / (hc)^3;
Theta3_N = Theta3_N / (hc)^3;

% store initial values
Y0 = Y;
E0 = E * Erg2MeV; % change unit

% update scales
s_Y = s_Y * Y0;
s_E = s_E * E0;

% initial guess (both 1 for now)
U(iY) = Y / Y0;
U(iE) = E * Erg2MeV / E0; % change unit

U0 = U;

J = Jin;


% calculate known values
C(iY) = Theta2_N' * (Jin.Ne - Jin.ANe)/ s_Y;
C(iE) = Theta3_N' * (Jin.Ne + Jin.ANe) / s_E;


k = 0;
CONVERGED = false;

% Anderson acceleration truncation parameter
m = 3;
Fvec = zeros(length(U)+length(J.Ne)+length(J.ANe),m);
Jvec = zeros(length(U)+length(J.Ne)+length(J.ANe),m);
alpha = zeros(m,1);


% compute chemical potential and derivatives
[Mnu, ~, ~] = ComputeNeutrinoChemicalPotentials(D, T, Y);

% equilibrium distribution
[J0.Ne, J0.ANe] = FermiDirac( g_E_N, Mnu, BoltzmannConstant * T );
    
% FOR IMPLICIT R_NES, UPDATE (interpolate) R_NES here:
[R_in_NES.Ne, R_out_NES.Ne, R_in_NES.ANe, R_out_NES.ANe] = ComputeNesScatteringOpacityOnEGrid_TABLE(g_E_N, D, T, Y);

% scale R_NES by dt and c
R_in_NES.Ne = R_in_NES.Ne * c * dt;
R_out_NES.Ne = R_out_NES.Ne * c * dt;

R_in_NES.ANe = R_in_NES.ANe * c * dt;
R_out_NES.ANe = R_out_NES.ANe * c * dt;

eta_NES.Ne = (R_in_NES.Ne'*diag(W2_N)*J.Ne);
Chi_NES.Ne = (R_out_NES.Ne'*diag(W2_N)*(1 - J.Ne));

eta_NES.ANe = (R_in_NES.ANe'*diag(W2_N)*J.ANe);
Chi_NES.ANe = (R_out_NES.ANe'*diag(W2_N)*(1 - J.ANe));

% the following two lines will be coupled after including pairing 
J.Ne = (Jin.Ne + Chi.Ne.*J0.Ne + eta_NES.Ne)./(1 + Chi.Ne + eta_NES.Ne + Chi_NES.Ne);
J.ANe = (Jin.ANe + Chi.ANe.*J0.ANe + eta_NES.ANe)./(1 + Chi.ANe + eta_NES.ANe + Chi_NES.ANe);

    
while((~CONVERGED)&&(k<=maxIter))
    
    k = k + 1;
    mk = min(m,k);
 
    % Update (U,J)
    Jvec(iY,mk) = 1 + C(iY) - Theta2_N' * (J.Ne - J.ANe)/ s_Y;
    Jvec(iE,mk) = 1 + C(iE) - Theta3_N' * (J.Ne + J.ANe) / s_E;
    
    eta_NES.Ne = (R_in_NES.Ne'*diag(W2_N)*J.Ne);
    Chi_NES.Ne = (R_out_NES.Ne'*diag(W2_N)*(1 - J.Ne));

    eta_NES.ANe = (R_in_NES.ANe'*diag(W2_N)*J.ANe);
    Chi_NES.ANe = (R_out_NES.ANe'*diag(W2_N)*(1 - J.ANe));
  
    % the following two lines will be coupled after including pairing 
    Jvec(iJNe,mk) = (Jin.Ne + Chi.Ne.*J0.Ne + eta_NES.Ne)./(1 + Chi.Ne + eta_NES.Ne + Chi_NES.Ne);
    Jvec(iJANe,mk) = (Jin.ANe + Chi.ANe.*J0.ANe + eta_NES.ANe)./(1 + Chi.ANe + eta_NES.ANe + Chi_NES.ANe);
    
    Fvec(:,mk) = Jvec(:,mk) - [U; J.Ne; J.ANe];
    
    if (mk == 1)
        Unew = Jvec(1:2,1);
        Jnew.Ne = Jvec(iJNe,1);
        Jnew.ANe = Jvec(iJANe,1);
    else
        alpha(1:mk-1) = (Fvec(:,1:mk-1) - Fvec(:,mk)*ones(1,mk-1))\(-Fvec(:,mk));
        alpha(mk) = 1 - sum(alpha(1:mk-1));
        temp = Jvec(:,1:mk) * alpha(1:mk);
        Unew = temp(1:2);
        Jnew.Ne = temp(iJNe);
        Jnew.ANe = temp(iJANe);
    end
    
    % check convergence
    if (norm([Unew; Jnew.Ne; Jnew.ANe] - [U; J.Ne; J.ANe]) <= Rtol * norm([U0; Jin.Ne; Jin.ANe]))
        CONVERGED = true;
    end
    
    if (mk == m)
        Jvec = circshift(Jvec,-1,2);
        Fvec = circshift(Fvec,-1,2);
    end
    
    % update U, Y, E, T, J
    U = Unew;
    
    Y = U(iY) * Y0;
    E = U(iE) * E0 / Erg2MeV; % change unit    
    T = ComputeTemperatureFromSpecificInternalEnergy_TABLE(D, E, Y);
    
    J = Jnew;
    
    % compute chemical potential and derivatives
    [Mnu, ~, ~] = ComputeNeutrinoChemicalPotentials(D, T, Y);
    
    % equilibrium distribution
    [J0.Ne, J0.ANe]= FermiDirac( g_E_N, Mnu, BoltzmannConstant * T );
    
    if (~CONVERGED)
        % FOR IMPLICIT R_NES, UPDATE (interpolate) R_NES here:
        [R_in_NES.Ne, R_out_NES.Ne, R_in_NES.ANe, R_out_NES.ANe] = ComputeNesScatteringOpacityOnEGrid_TABLE(g_E_N, D, T, Y);

        % scale R_NES by dt and c
        R_in_NES.Ne = R_in_NES.Ne * c * dt;
        R_out_NES.Ne = R_out_NES.Ne * c * dt;
        
        R_in_NES.ANe = R_in_NES.ANe * c * dt;
        R_out_NES.ANe = R_out_NES.ANe * c * dt;
    end
end

if(k >= maxIter)
    disp("Failed to converge within maxIter.");
end


iter = k;



end












