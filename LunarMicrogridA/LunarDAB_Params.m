
%% Simulation Settings
Ts = 10e-9;             % Fixed solver time step [s]
Tsim = 10e-3;           % Simulation stop time [s]

%% DC Buses
V1 = 118;              % Nominal battery voltage [V]
V2 = 120;         % DC bus reference [V]

% Test Vdc = 99, 118, and 137 V

%% Magnetics
% E65/32/27 N95 transformer, 6:6 turns
Np = 6;
Ns = 6;
n = Np/Ns;              % 1:1 transformer

% Nominal self-inductance from core AL
AL = 11000e-9;          % [H/turn^2]
l1Xfmr = AL*Np^2;       % 275 uH
l2Xfmr = l1Xfmr/n^2;

% Preliminary leakage assumption
Llk_target = 0.5e-6;    % 0.5 uH, assumed
kCpl = sqrt(1 - Llk_target/l1Xfmr);

% Primary-referred short-circuit leakage
Llk = l1Xfmr*(1-kCpl^2);

% Estimated winding DC resistances at 20 C
rXfmr = [1.318e-3, 1.318e-3];

% Negligible parallel conductance initially
gXfmr = [1e-9, 1e-9];

%% Series Passives
lTotal_max = 3.59e-6;      % Maximum allowable [H]
lTotal_target = 3.5e-6; % Preliminary operating choice
Cdc = 7.30e-05;
lSeries = lTotal_target - Llk;
lTotal = lSeries + Llk;

% Idealized inductor initially
rLseries = 0;           % Replace with estimated ESR later

assert(lSeries >= 0, 'Negative series inductance');
assert(lTotal <= lTotal_max, ...
    'Total inductance exceeds maximum');

%% Input/Output Stage
Pout = 3100;
R_full = V1^2/Pout;
Co = 45e-6;             % secondary side bus capacitor [F]
Ci = 30e-6;            % primary side bus capacitor [F]
Lo = 0;                 % No PSFB output filter inductor

%% Switching
fsw = 100e3;
Tsw = 1/fsw;
PW = 49;
tDead = Tsw*(50-PW)/100; % 100 ns
omega = 2*pi*fsw;

%% EPC7020GSH GaN Switches
rdsOn = 0.014;          % Rds(on)
Goff = 1e-8;
Vth = 4.0;              % Approximation; check block behavior
Vgate = 6;              % Rated gate-drive operating point
Coss = 640e-12;         % Provisional constant approximation


%% Controller Parameters
kpCurrent = 0.005;
kiCurrent = 2;
kpVoltage = 0.4;
kiVoltage = 8;
thetaIC = 0;
thetaMaxDab = pi/4;

%% Legacy diode parameters
vfBody = 0.9;
ronBody = 0.01;
goffBody = 1e-8;

% Legacy PSFB rectifier diode parameters
vfSchottky = 0.39;
ronSchottky = 0.025;
goffSchottky = 1e-8;

% supercapacitor data

% test setting
Tsim     = 20e-3; % setting replaces top one
t_step   = 5e-3;    
I_step   = 0.5*Pout/V2;   
SC_enable = 1; % 1 = supercap on, 0 = battery only

% battery V-I droop
dV_droop = 0.05*V2; % 5 % tolerance
Ibat_max = Pout/V2; % max current
Rd_bat   = dV_droop/Ibat_max; % droop resistance
f_split  = 50; % response time for supercap to turn on 3.2mS, see if this is good
a_lpf    = exp(-2*pi*f_split*Tsw);

% supercapacitor bank
Csc_cell = 3000;  Ns_sc = 45;  Np_sc = 3;
Csc      = Csc_cell/Ns_sc*Np_sc;         
ESR_sc   = 0.23e-3*Ns_sc/Np_sc;           
Vsc_max  = 119;  Vsc_min = 66;            
Vsc0     = sqrt((Vsc_max^2 + Vsc_min^2)/2);  
Esc_usable = 0.5*Csc*(Vsc_max^2 - Vsc_min^2); 

% supercap converter and control 
eta_sc    = 0.95;
Isc_max   = 2*Pout/V2;
k_restore = 1; % voltage correction for supercap