% builds LunarMicrogrid_Full from the DAB + supercap model, the P170 PV converter and the MMC intertie
% takes out the boost converter, old PV Control and the PV array circuit
% adds the P170 PV converter (averaged, from P170_PV_MPPT_Integration) as a current into the 120 V bus
% adds the MMC intertie (averaged, from mmc_and_bus_current.m) as a current out of the 120 V bus
% originals dont get changed, running again overwrites LunarMicrogrid_Full
% needs in the folder: battery_integrated.slx, P170_PV_MPPT_Integration.slx, LunarMicrogridA_Data.mlx,
% LunarDAB_Params.m, mmc_and_bus_current.m and the Azur Space csv
% all parameters (PV converter, droop, MMC) come from LunarMicrogridA_Data

srcB  = 'battery_integrated';          % model with the DAB, droop and supercap (or LunarMicrogrid_Combined)
srcPV = 'P170_PV_MPPT_Integration';    % model with the working PV converter
mdl   = 'LunarMicrogrid_Full';

if bdIsLoaded(mdl), close_system(mdl, 0); end
run('LunarMicrogridA_Data');
load_system(srcB);  save_system(srcB, mdl);  close_system(srcB, 0);
load_system(srcPV);
open_system(mdl);

% removes unused 'data' output in Mode Control if it is still there
ch = find(sfroot, '-isa','Stateflow.Chart', 'Path', [mdl '/Mode Control']);
dOut = find(ch, '-isa','Stateflow.Data', 'Name','data');
if ~isempty(dOut)
    lh = get_param([mdl '/Mode Control'], 'LineHandles');
    if lh.Outport(dOut.Port) > 0, delete_line(lh.Outport(dOut.Port)); end
    delete(dOut);
end

% removes old PV Control and the From blocks feeding it
pvc = [mdl '/PV Control'];
pc = get_param(pvc, 'PortConnectivity');
srcs = [pc.SrcBlock];
srcs = srcs(srcs > 0);
for h = srcs
    if strcmp(get_param(h, 'BlockType'), 'From'), delBlk(h); end
end
delBlk(pvc);
delBlk([mdl '/Gpv']);
delBlk([mdl '/Gpv1']);

% removes the boost converter but keeps its bus side wires (they also connect the BMS and load)
bc = [mdl '/Boost Converter'];
pvPos = get_param(bc, 'Position');
lh = get_param(bc, 'LineHandles');
hs = [lh.Inport lh.LConn];
for h = hs(hs > 0)
    try
        delete_line(h);
    catch
    end
end
delete_block(bc);

% removes the PV array circuit (the P170 converter has the array curve inside it)
for b = {'Solar Plant','Capacitor','DC Current Sensor','DC Voltage Sensor','Simulink-PS Converter'}
    delBlk([mdl '/' b{1}]);
end

% solver config and ground go on the bus - side now
% connects solver config and ground to bus -, skips any that are already connected
for p = {'Solver Configuration/RConn1', 'Electrical Reference/LConn1'}
    try
        add_line(mdl, p{1}, 'Load/RConn1', 'autorouting','on');
    catch
    end
end

% bus capacitor (was inside the boost converter)
CAP  = 'fl_lib/Electrical/Electrical Elements/Capacitor';
S2PS = ['nesl_utility/Simulink-PS' newline 'Converter'];
CCS  = 'fl_lib/Electrical/Electrical Sources/Controlled Current Source';
add_block(CAP, [mdl '/Bus Capacitor'], 'Position', [450 220 490 260], 'c','boost.outputCapacitor', ...
    'vc_specify','on', 'vc_priority','High', 'vc','dcVoltage.reqDCBusVoltage');
add_line(mdl, 'Bus Capacitor/LConn1', 'Load/LConn1', 'autorouting','on');
add_line(mdl, 'Bus Capacitor/RConn1', 'Load/RConn1', 'autorouting','on');

%% P170 PV converter
x = pvPos(1) - 300;  y = pvPos(2) - 250;
for b = {'PV_MPPT_6module','T_C','Vmp_EOL_vs_T','Imp_EOL_vs_T'}
    add_block([srcPV '/' b{1}], [mdl '/' b{1}]);
end
set_param([mdl '/PV_MPPT_6module'], 'Position', [x+250 y x+400 y+200]);
set_param([mdl '/T_C'],          'Position', [x y+60 x+30 y+80]);
set_param([mdl '/Vmp_EOL_vs_T'], 'Position', [x+80 y+140 x+140 y+170]);
set_param([mdl '/Imp_EOL_vs_T'], 'Position', [x+80 y+185 x+140 y+215]);
close_system(srcPV, 0);

% runs the PV converter at its own step (its code assumes dt = 1e-4)
fb = find(sfroot, '-isa','Stateflow.EMChart', 'Path', [mdl '/PV_MPPT_6module']);
fb.ChartUpdate = 'DISCRETE';
fb.SampleTime = 'P170_dt';

% inputs: G, T, Vbus, en, VmpT, ImpT
add_block('simulink/Signal Routing/From', [mdl '/PV_Vo'], 'GotoTag','Vo', 'Position',[x-150 y+100 x-100 y+120]);
add_block('simulink/Discrete/Unit Delay', [mdl '/PV_VbusDelay'], 'SampleTime','P170_dt', ...
    'InitialCondition','dcVoltage.reqDCBusVoltage', 'Position',[x-70 y+95 x-40 y+125]);
add_block('simulink/Sources/Constant', [mdl '/PV_Vend'], 'Value','pvDroop.Vend', 'Position',[x-70 y+230 x-20 y+250]);
add_block('simulink/Math Operations/Sum', [mdl '/PV_droopErr'], 'Inputs','+-', 'Position',[x y+235 x+20 y+265]);
add_block('simulink/Math Operations/Gain', [mdl '/PV_droopK'], 'Gain','1/(pvDroop.Vend-pvDroop.Vstart)', 'Position',[x+40 y+235 x+80 y+265]);
add_block('simulink/Discontinuities/Saturation', [mdl '/PV_droopSat'], 'UpperLimit','1', 'LowerLimit','0', 'Position',[x+100 y+235 x+130 y+265]);
add_block('simulink/Signal Routing/From', [mdl '/PV_off'], 'GotoTag','PVoff', 'Position',[x-70 y+290 x-20 y+310]);
add_block('simulink/Signal Attributes/Data Type Conversion', [mdl '/PV_offDbl'], 'OutDataTypeStr','double', 'Position',[x y+290 x+40 y+310]);
add_block('simulink/Sources/Constant', [mdl '/PV_one'], 'Value','1', 'Position',[x y+325 x+20 y+345]);
add_block('simulink/Math Operations/Sum', [mdl '/PV_on'], 'Inputs','+-', 'Position',[x+60 y+300 x+80 y+330]);
add_block('simulink/Math Operations/Product', [mdl '/PV_enable'], 'Inputs','2', 'Position',[x+160 y+250 x+190 y+300]);

add_line(mdl, 'Irradiance/1',      'PV_MPPT_6module/1', 'autorouting','on');
add_line(mdl, 'T_C/1',             'PV_MPPT_6module/2', 'autorouting','on');
add_line(mdl, 'T_C/1',             'Vmp_EOL_vs_T/1',    'autorouting','on');
add_line(mdl, 'T_C/1',             'Imp_EOL_vs_T/1',    'autorouting','on');
add_line(mdl, 'PV_Vo/1',           'PV_VbusDelay/1',    'autorouting','on');
add_line(mdl, 'PV_VbusDelay/1',    'PV_MPPT_6module/3', 'autorouting','on');
add_line(mdl, 'PV_Vend/1',         'PV_droopErr/1',     'autorouting','on');
add_line(mdl, 'PV_VbusDelay/1',    'PV_droopErr/2',     'autorouting','on');
add_line(mdl, 'PV_droopErr/1',     'PV_droopK/1',       'autorouting','on');
add_line(mdl, 'PV_droopK/1',       'PV_droopSat/1',     'autorouting','on');
add_line(mdl, 'PV_off/1',          'PV_offDbl/1',       'autorouting','on');
add_line(mdl, 'PV_one/1',          'PV_on/1',           'autorouting','on');
add_line(mdl, 'PV_offDbl/1',       'PV_on/2',           'autorouting','on');
add_line(mdl, 'PV_droopSat/1',     'PV_enable/1',       'autorouting','on');
add_line(mdl, 'PV_on/1',           'PV_enable/2',       'autorouting','on');
add_line(mdl, 'PV_enable/1',       'PV_MPPT_6module/4', 'autorouting','on');
add_line(mdl, 'Vmp_EOL_vs_T/1',    'PV_MPPT_6module/5', 'autorouting','on');
add_line(mdl, 'Imp_EOL_vs_T/1',    'PV_MPPT_6module/6', 'autorouting','on');

% outputs: Ibus into the bus, Vpv and Ipv for the dashboard and scopes
add_block(S2PS, [mdl '/PV_S2PS'], 'Position',[x+450 y+20 x+470 y+40]);
add_block(CCS,  [mdl '/PV_Isrc'], 'Position',[x+500 y x+540 y+60]);
add_block('simulink/Signal Routing/Goto', [mdl '/Vpv_goto'], 'GotoTag','Vpv', 'TagVisibility','global', 'Position',[x+450 y+110 x+500 y+130]);
add_block('simulink/Signal Routing/Goto', [mdl '/Ipv_goto'], 'GotoTag','Ipv', 'TagVisibility','global', 'Position',[x+450 y+140 x+500 y+160]);
add_line(mdl, 'PV_MPPT_6module/1', 'PV_S2PS/1',  'autorouting','on');
add_line(mdl, 'PV_MPPT_6module/4', 'Vpv_goto/1', 'autorouting','on');
add_line(mdl, 'PV_MPPT_6module/5', 'Ipv_goto/1', 'autorouting','on');
% same port use as the DAB bus-side source: RConn1 = signal, LConn1 = bus +, RConn2 = bus -
add_line(mdl, 'PV_S2PS/RConn1', 'PV_Isrc/RConn1', 'autorouting','on');
add_line(mdl, 'PV_Isrc/LConn1', 'Load/LConn1',    'autorouting','on');
add_line(mdl, 'PV_Isrc/RConn2', 'Load/RConn1',    'autorouting','on');

%% MMC intertie
xm = 900;  ym = 250;
mb = [mdl '/MMC Intertie'];
add_block('simulink/User-Defined Functions/MATLAB Function', mb, 'Position',[xm+150 ym xm+300 ym+150]);
mf = find(sfroot, '-isa','Stateflow.EMChart', 'Path', mb);
mf.Script = strjoin({
'function [I_LV, P, V_HV, I_line, V_rx, phi] = fcn(Vbus, P_rx, mmc)'
'% averaged MMC intertie, same equations as mmc_and_bus_current.m'
'% uses the real 120 V bus voltage instead of a fixed 120 V'
'persistent V I Vrx z'
'if isempty(V)'
'    V = mmc.V0; I = mmc.I0; Vrx = mmc.Vrx0; z = mmc.z0;'
'end'
'dt = mmc.dt;'
'vb = max(Vbus, 1);'
'e = mmc.V_ref - V;'
'u = mmc.Kp*e + mmc.Ki*z;'
'phi = min(max(u, -pi/2), pi/2);'
'if ~((u >= pi/2 && e > 0) || (u <= -pi/2 && e < 0)), z = z + e*dt; end'
'Kc = mmc.n*vb*V/(2*pi*mmc.rv*mmc.f*mmc.Lleak);'
'P = mmc.Npar*Kc*phi*(1 - abs(phi)/pi);'
'dV  = (P/V - I)/mmc.C_HV;'
'dI  = (V - Vrx - mmc.R_line*I)/mmc.L_line;'
'dVr = (I - P_rx/max(Vrx, 1))/mmc.C_RX;'
'V_HV = V; I_line = I; V_rx = Vrx;'
'V = V + dV*dt; I = I + dI*dt; Vrx = Vrx + dVr*dt;'
'I_LV = P/vb;'
'end'}', newline);
mp = find(mf, '-isa','Stateflow.Data', 'Name','mmc');
mp.Scope = 'Parameter';
mf.ChartUpdate = 'DISCRETE';
mf.SampleTime = 'mmc.dt';

add_block('simulink/Signal Routing/From', [mdl '/MMC_Vo'], 'GotoTag','Vo', 'Position',[xm ym+20 xm+50 ym+40]);
add_block('simulink/Discrete/Unit Delay', [mdl '/MMC_VbusDelay'], 'SampleTime','mmc.dt', ...
    'InitialCondition','dcVoltage.reqDCBusVoltage', 'Position',[xm+70 ym+15 xm+100 ym+45]);
add_block('simulink/Sources/Constant', [mdl '/MMC_Prx'], 'Value','mmc.P_rx_W', 'Position',[xm+40 ym+90 xm+100 ym+110]);
add_block('simulink/Math Operations/Gain', [mdl '/MMC_sink'], 'Gain','-1', 'Position',[xm+340 ym+10 xm+370 ym+40]);
add_block(S2PS, [mdl '/MMC_S2PS'], 'Position',[xm+400 ym+15 xm+420 ym+35]);
add_block(CCS,  [mdl '/MMC_Isrc'], 'Position',[xm+450 ym-5 xm+490 ym+55]);
add_line(mdl, 'MMC_Vo/1',        'MMC_VbusDelay/1',  'autorouting','on');
add_line(mdl, 'MMC_VbusDelay/1', 'MMC Intertie/1',   'autorouting','on');
add_line(mdl, 'MMC_Prx/1',       'MMC Intertie/2',   'autorouting','on');
add_line(mdl, 'MMC Intertie/1',  'MMC_sink/1',       'autorouting','on');
add_line(mdl, 'MMC_sink/1',      'MMC_S2PS/1',       'autorouting','on');
% same port use as the PV source, the -1 makes it draw current out of the bus
add_line(mdl, 'MMC_S2PS/RConn1', 'MMC_Isrc/RConn1',  'autorouting','on');
add_line(mdl, 'MMC_Isrc/LConn1', 'Load/LConn1',      'autorouting','on');
add_line(mdl, 'MMC_Isrc/RConn2', 'Load/RConn1',      'autorouting','on');

% local 120 V load follows localLoad_kW (0 when the load is at the far end of the line)
set_param([mdl '/Load/Load/Load Power (kW)'], 'Gain', 'localLoad_kW');

%% signals that show up in data inspector
logPort([mdl '/PV_MPPT_6module'], 1, 'PV bus current (A)');
logPort([mdl '/PV_MPPT_6module'], 2, 'PV bus power (W)');
logPort([mdl '/PV_MPPT_6module'], 4, 'PV voltage (V)');
logPort([mdl '/PV_enable'],       1, 'PV curtail factor');
logPort(mb, 1, 'MMC 120 V bus current (A)');
logPort(mb, 2, 'MMC power (W)');
logPort(mb, 3, 'MMC HV bus voltage (V)');
logPort(mb, 4, 'MMC line current (A)');
logPort(mb, 5, 'MMC receiving end voltage (V)');
logPort(mb, 6, 'MMC phase shift (rad)');

% compile check
try
    set_param(mdl, 'SimulationCommand', 'update');
    disp('Model compiles.');
catch err
    fprintf(2, 'Compile error: %s\n', err.message);
end
save_system(mdl);
disp('Saved LunarMicrogrid_Full.slx');

% helper func, deletes a block and its wires, skips if it doesnt exist
function delBlk(b)
if ischar(b) && getSimulinkBlockHandle(b) == -1
    return
end
lh = get_param(b, 'LineHandles');
f  = fieldnames(lh);
for i = 1:numel(f)
    hh = lh.(f{i});
    hh = hh(hh > 0);
    for j = 1:numel(hh)
        try
            delete_line(hh(j));
        catch
        end
    end
end
delete_block(b);
end

% helper func, turns on logging for one output port with a name
function logPort(blk, k, name)
ph = get_param(blk, 'PortHandles');
set_param(ph.Outport(k), 'DataLogging','on', 'DataLoggingNameMode','Custom', 'DataLoggingName', name);
end
