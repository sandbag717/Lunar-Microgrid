%% MMC intertie: bus current and voltage graph
% Part 1: bus current = power / voltage (same as the PV and battery rows of the table).
% Part 2: start-up and load steps (23.5 -> 31.5 -> 39.5 -> 63.4 kW) with a phase-shift PI controller.
% Calculated values; 
% Npar, Kp and Ki are calculated below.
if ~exist('mmcFromData','var'), clear; clc; close all; mmcFromData = false; end

%% Given values
V_LV  = 120;   V_ref = 1500;              % V
n     = 1.25;  rv = 10;                   % transformer ratio (HV/LV), MMC voltage ratio
f     = 200e3; Lleak = 3.7e-6;            % Hz, H
phi_rated = 0.35;                         % rad, phase shift for 1.5 kW per converter
L_line = 1e-3;                            % H
R_line = 0;                               % ohm (lossless line)
P_load = [23500 31500 39466.7 63400];     % W, load cases 1-3
use_1mF = false;                      % false: calculated capacitance (2 mF); true: 1 mF
t_step = [0.2 0.4 0.6];                   % s, load steps
dt = 1e-5;  Tend = 0.8;  N = round(Tend/dt);

%% Calculated values
% Bus capacitance: the capacitor alone must hold the bus within 5% during the biggest load step
% for the time the converter needs to respond:  C = 2*dP*dt / (V^2 - Vmin^2)
dP    = max(P_load) - min(P_load);        % W, biggest step between the load cases (39.9 kW)
dip   = 0.05;  t_resp = 5e-3;             % allowed dip (5%), response time in s
C_HV  = 2*dP*t_resp/(V_ref^2 - (V_ref*(1-dip))^2);      % F, 1.5 kV bus (about 1.82 mF)
C_LV  = 2*dP*t_resp/(V_LV^2  - (V_LV*(1-dip))^2);       % F, 120 V bus (about 284 mF)
C_HV_calc = C_HV;                         % F, calculated value
C_HV  = ceil(C_HV*2000)/2000;             % F, rounded up to the next 0.5 mF (2 mF)
if use_1mF, C_HV = 1e-3; end          % F, 1 mF option
C_RX  = C_HV;                             % F, receiving end same as sending end
Kc    = @(V) n*V_LV*V/(2*pi*rv*f*Lleak);  % W/rad, power coefficient
P1    = Kc(V_ref)*phi_rated*(1-phi_rated/pi);   % W, one converter at 0.35 rad (about 1.5 kW)
Npar  = ceil(max(P_load)/P1);             % converters in parallel to carry the largest case at 0.35 rad
x0    = P_load(1)/Npar/Kc(V_ref);
phi0  = (pi/2)*(1 - sqrt(1 - 4*x0/pi));   % rad, steady phase shift at the first case
g     = Npar*Kc(V_ref)*(1-2*phi0/pi)/V_ref/C_HV;   % (V/s)/rad, plant gain: bus voltage vs phase shift
w_res = 1/sqrt(L_line*C_HV);              % rad/s, LC resonance of the line
wc    = 0.5*w_res;                        % rad/s, loop crossover (half the resonance)
Kp    = wc/g;                             % rad/V
Ki    = Kp*wc/10;                         % rad/(V s), integral corner one decade below crossover

%% Values used
fprintf('\n=== VALUES USED ===\n');
fprintf('GIVEN: 120 V, 1500 V, n = 1.25, rv = 10, 200 kHz, 3.7 uH, phase shift 0.35 rad,\n');
fprintf('  line R = 0 ohm, line L = 1 mH, load cases 23.5 / 31.5 / 63.4 kW and their average 39.5 kW\n');
fprintf('CALCULATED: HV bus capacitance %.2f mF -> using %.2f mF, Npar = %d, Kp = %.4f, Ki = %.3f\n', C_HV_calc*1e3, C_HV*1e3, Npar, Kp, Ki);

if ~mmcFromData   % skipped when the data script reads this file

%% Part 1: bus current for the table
fprintf('\n=== BUS CURRENT ===\n');
for c = 1:numel(P_load)
    fprintf('%.1f kW: %.0f A on the 120 V bus, %.1f A on the 1.5 kV line\n', P_load(c)/1e3, P_load(c)/V_LV, P_load(c)/V_ref);
end

%% Part 2: simulation (starts at 50% of the HV reference and charges up)
V = 0.5*V_ref;  Vrx = V - 10;  I = P_load(1)/Vrx;  z = 0;
t = (0:N-1)*dt;
Vlog = zeros(1,N); Vrxlog = zeros(1,N); Ilog = zeros(1,N); I_LV = zeros(1,N);
for k = 1:N
    Pload = P_load(1 + sum(t(k) >= t_step));
    e   = V_ref - V;
    u   = Kp*e + Ki*z;
    phi = min(max(u,-pi/2),pi/2);
    if ~((u >= pi/2 && e > 0) || (u <= -pi/2 && e < 0)), z = z + e*dt; end
    P   = Npar*Kc(V)*phi*(1 - abs(phi)/pi);
    dV  = (P/V - I)/C_HV;
    dI  = (V - Vrx - R_line*I)/L_line;
    dVr = (I - Pload/Vrx)/C_RX;
    V = V + dV*dt;  I = I + dI*dt;  Vrx = Vrx + dVr*dt;
    Vlog(k) = V; Vrxlog(k) = Vrx; Ilog(k) = I; I_LV(k) = P/V_LV;
end

%% Graph
bg = [0.07 0.07 0.07];
figure(1); clf; set(gcf,'Color','w','Position',[100 100 900 650]);

ax1 = subplot(2,1,1); hold on; set(ax1,'Color',bg,'XColor','k','YColor','k','GridColor',[0.6 0.6 0.6]); grid on;
plot(t,V_ref*ones(1,N),'Color',[0.95 0.5 0.15],'LineWidth',1.5);
plot(t,Vlog,'Color',[0.2 0.6 1],'LineWidth',1.5);
ylabel('Voltage (V)','Color','k'); title('MMC Converter: 1.5 kV Bus Voltage','Color','k');
ylim([0 1700]);
text(0.45,V_ref+90,'Reference (1.5 kV)','Color',[0.95 0.5 0.15]);
text(0.02,Vlog(round(0.02/dt))-120,'HV bus voltage','Color',[0.2 0.6 1]);

ax2 = subplot(2,1,2); hold on; set(ax2,'Color',bg,'XColor','k','YColor','k','GridColor',[0.6 0.6 0.6]); grid on;
plot(t,I_LV,'Color',[1 0.9 0.2],'LineWidth',1.5);
plot(t,Ilog,'Color',[0.2 0.6 1],'LineWidth',1.5);
xlabel('Time (s)','Color','k'); ylabel('Current (A)','Color','k'); title('Bus Current','Color','k');
ylim([0 650]);
text(0.45,I_LV(round(0.75/dt))+35,'120 V bus current','Color',[1 0.9 0.2]);
text(0.45,Ilog(round(0.75/dt))+35,'1.5 kV line current','Color',[0.2 0.6 1]);
tl = [0.1 t_step+0.01];                   % label positions for each power case
for c = 1:numel(P_load)
    text(tl(c),610,sprintf('%.1f kW',P_load(c)/1e3),'Color','w');
end

%% Results
fprintf('\n=== RESULTS ===\n');
fprintf('HV bus reaches 1500 V (within 1%%) at %.3f s, overshoot %.1f V\n', t(find(abs(Vlog-V_ref) < 0.01*V_ref,1)), max(Vlog)-V_ref);
tb = [t_step Tend];
for c = 1:numel(P_load)
    s = min(round(tb(c)/dt),N);
    fprintf('%.1f kW: 120 V bus current %.0f A, line current %.1f A, receiving end %.0f V\n', P_load(c)/1e3, I_LV(s), Ilog(s), Vrxlog(s));
end
end