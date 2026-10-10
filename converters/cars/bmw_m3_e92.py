"""BMW M3 E92 (DCT) profile: AC `bmw_m3_e92` onto the ETK K-Series with the native ETK 4.4 V8.

Numeric targets are public figures (BMW US press kit, 2008 M3 Coupe / M DCT): 309 kW at 8300 rpm,
400 Nm at 3900 rpm, 8400 rpm limit, 250 km/h governed, M DCT ratios 4.78 / 2.933 / 2.153 /
1.678 / 1.39 / 1.203 / 1.000 (reverse 4.454), final drive 3.15, 63 L tank, 245/40 R18 front and
265/40 R18 rear tyres. Mesh, sound and skin data are read from the user's own AC install at build
time and written only to the build output.
"""
import copy

PREFIX = 'acng_m3_'

# AC torque curve (power.lut, crank Nm) sampled at the table rpm; 8300 rpm is the rated 309 kW.
TARGET = ((500, 177), (1000, 267), (1500, 283), (2000, 329), (2500, 347), (3000, 371), (3500, 389),
          (4000, 400), (4500, 392), (5000, 386), (5500, 393), (6000, 389), (6500, 381), (7000, 394),
          (7500, 373), (8000, 361), (8300, 355.5), (8500, 339), (9000, 300))
# The engine curve BeamNG reports is base * torqueModMult + exhaust mod - friction - dynamic
# friction * rad/s (combustionEngine.lua). The cloned long block keeps ttSport friction (19 Nm and
# 0.035 Nm s/rad, both * 0.9) and drops the high-rpm torqueModMult, so mult is 1.
FRICTION, DYN_FRICTION = 19 * 0.9, 0.035 * 0.9
EXHAUST_MOD = ((0, 0), (1000, -4), (2000, -7), (3000, -12), (4000, -16), (5000, -20), (6000, -22),
               (7000, -23), (8000, -30), (9000, -35), (10000, -45))  # etk_exhaust_v8_4.4_petrol_ttSport
IDLE_RPM = 1000
GEAR_RATIOS = [-4.454, 0, 4.78, 2.933, 2.153, 1.678, 1.39, 1.203, 1.0]


def _lerp(table, x):
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x0 <= x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return table[-1][1]


def base_torque():
    """Engine table rows so the reported curve lands on TARGET."""
    rows = [[0, 0]]
    for rpm, nm in TARGET:
        rows.append([rpm, round(nm + FRICTION + DYN_FRICTION * rpm * 3.141592653589793 / 30
                                - _lerp(EXHAUST_MOD, rpm), 2)])
    return rows


def _info(name):
    return {'name': name, 'authors': 'ACNG local build'}


def spec_parts(stock):
    """Clone native ETK V8 / DCT / tank / shifter parts with original numeric targets."""
    engine = copy.deepcopy(stock['etk_engine_v8_4.4_petrol'])
    engine['information'] = _info('BMW M3 E92 target 4.0L V8 (experimental)')
    engine.setdefault('vehicleController', {})['topSpeedLimit'] = 250 / 3.6
    header = [r for r in engine['mainEngine']['torque'] if not isinstance(r[0], (int, float))]
    engine['mainEngine']['torque'] = header + base_torque()
    engine['mainEngine']['maxRPM'] = 8600
    # The AC idle loops are recorded at ~1170 rpm (78 Hz V8 firing frequency); at the donor's 750
    # rpm idle they played 36 % flat. 1000 rpm keeps them within 15 % of their own pitch.
    engine['mainEngine']['idleRPM'] = IDLE_RPM
    internals = copy.deepcopy(stock['etk_engine_v8_4.4_petrol_internals_ttsport'])
    internals['information'] = _info('BMW M3 E92 long block (S65 target)')
    for key in ('torqueModMult', '$+maxRPM'):
        internals['mainEngine'].pop(key, None)
    ecu = copy.deepcopy(stock['etk_engine_v8_4.4_petrol_ecu_ttSport_470'])
    ecu['information'] = _info('BMW M3 E92 ECU (8400 rpm limit)')
    ecu['mainEngine']['revLimiterRPM'] = 8400
    transmission = copy.deepcopy(stock['etk_transmission_7DCT'])
    transmission['information'] = _info('BMW M3 E92 7-speed M DCT')
    transmission['gearbox']['gearRatios'] = GEAR_RATIOS[:]
    tank = copy.deepcopy(stock['etkc_fueltank'])
    tank['information'] = _info('BMW M3 E92 63 L fuel tank')
    tank['mainTank']['fuelCapacity'] = 63
    for row in tank['variables'][1:]:
        if isinstance(row, list) and row[0] == '$fuel':
            row[4], row[6] = 56.7, 63
    # The ETK automatic shifter plus ACNG's shift-sound controller: dctGearbox has no shift-sound
    # hook, and the native lever controllers only play FMOD events, never a WAV.
    shifter = copy.deepcopy(stock['etkc_shifter_A'])
    shifter['information'] = _info('BMW M3 E92 M DCT selector (local sounds)')
    shifter.setdefault('controller', [['fileName']]).append(['acng_shiftSound', {'name': 'acng_shiftSound'}])
    # f7 is the automatic selector's own slide node.
    shifter['acng_shiftSound'] = {'soundNode:': ['f7'], 'volume': 0.5}
    return {PREFIX + 'engine': engine, PREFIX + 'internals': internals, PREFIX + 'ecu': ecu,
            PREFIX + 'transmission': transmission, PREFIX + 'fueltank': tank, PREFIX + 'shifter': shifter}


def spec_config(pc):
    pc = copy.deepcopy(pc)
    parts = pc['parts']
    for key in ('etk_engine_i6_3.0_petrol_ecu', 'etk_engine_i6_3.0_petrol_internals', 'etk_exhaust_i6_3.0_petrol',
                'etk_intake_i6_3.0_petrol', 'etk_oilpan_i6', 'tire_F_19x9', 'tire_R_19x10'):
        parts.pop(key, None)
    parts.update({
        'etk_engine': PREFIX + 'engine',
        'etk_engine_v8_4.4_petrol_ecu': PREFIX + 'ecu',
        'etk_engine_v8_4.4_petrol_internals': PREFIX + 'internals',
        'etk_enginelogo_v8.4.4': 'etk_enginelogo_v8.4.4_etk',
        'etk_enginemounts': 'etk_enginemounts_heavy',
        'etk_exhaust_v8_4.4_petrol': 'etk_exhaust_v8_4.4_petrol_ttSport',
        'etk_intake_v8_4.4_petrol': 'etk_intake_v8_4.4_petrol_ttSport',
        'etk_oilpan_v8': 'etk_oilpan_v8_ttSport',
        'etk_transmission': PREFIX + 'transmission',
        'etk_finaldrive_R': 'etk_finaldrive_R_315',
        'etkc_differential_R': 'etkc_differential_R_LSD',
        'etkc_fueltank': PREFIX + 'fueltank',
        'etk_engine_ecu_speedlimit': 'etk_engine_ecu_speedlimit_250',
        'etkc_shifter': PREFIX + 'shifter',
        'tire_F_18x9': 'tire_F_245_40_18_sport',
        'tire_R_18x10': 'tire_R_255_40_18_sport',
    })
    pc.setdefault('vars', {}).update({'$fuel': 56.7})
    return pc


BUILD_AC_CAR = {
    'VEHICLE': 'acng_bmw_m3e92',
    'CONFIG': 'acng_bmw_m3e92_M',
    'PREFIX': PREFIX,
    'NAME': 'BMW M3 E92 (local)',
    'INFO': {'Brand': 'BMW', 'Body Style': 'Coupe', 'Country': 'Germany', 'Years': {'min': 2007, 'max': 2013}},
    'CONFIG_LABEL': 'M3 E92 DCT specifications target (experimental)',
    'TRANSMISSION': 'Dual Clutch',
    'PAINT_MATERIAL': 'CAR_chassis',
    'LOCAL_DONORS': ('etkc_fueltank', 'etkc_brake_F_tt', 'etkc_brake_R_tt', 'etkc_shifter_A',
                     'etk_exhaust_v8_4.4_petrol_ttSport', 'etkc_differential_R_LSD'),
    'UNMAPPED_EVENTS': {'limiter': 'No standalone native engine sample slot in BeamNG 0.39.4'},
    'SHIFT_SEMANTICS': 'ACNG acng_shiftSound controller: AC gearup on each DCT upshift, geardn on each downshift',
    'DEFAULT_SKIN': '0_monte_carlo_blue',
    # Solid (non-metallic) factory colours among the AC skins.
    'SOLID_SKINS': {'Brilliant_White', 'Dakar_Yellow', 'Hellrot', 'Red', 'Orange', 'Laguna_Seca_Blue', 'Power_Green'},
    'EXTRA_COMMON_FILES': ('wheels_R_5.jbeam',),
    # Node transform from the AC wheel-centre fit (wheelbase 2.761 m, roof ~1.42 m, short nose).
    'SY': 1.06659, 'TY': -0.11877, 'Z_KNEE': 0.9, 'Z_SCALE': 1.10,
    'Y_KNEE_F': -1.774, 'Y_SCALE_F': 0.75, 'MESH_LIFT': 0.018,
    'LAB_TARGETS': {
        'test': 'C014 M3 E92 specification lab',
        'mass_kg': 1605, 'power_kw': 309, 'torque_nm': 400, 'fuel_l': 63,
        'gears': 7, 'ratio_first': 4.78, 'ratio_last': 1.0, 'final_drive': 3.154, 'top_speed_kmh': 250,
        'limiter_rpm': 8400,
        'curve': {str(rpm): nm for rpm, nm in TARGET if 1000 <= rpm <= 8000},
        'controls': ['steer', 'pedal_throttle', 'pedal_brake'],
        'gauges': ['gauge_rpm', 'gauge_speed', 'gauge_fuel', 'gauge_oil'],
        # AC kn5 WHEEL_* pivot |x| (front, rear); CarLab checks the tire centres against them.
        'wheel_x': [0.758, 0.746],
    },
}

EXPORT_KN5 = {
    'LIGHT_PARENTS': {'FRONT_LIGHT': 'lights_F', 'REAR_LIGHT': 'lights_R'},
    # REAR_LIGHT_REAR is the clear inner tail-lamp section (reversing lamp on the E92).
    'LIGHT_FUNCTIONS': (('FRONT_LIGHT_LOW', 'headlight'), ('FRONT_LIGHT_HIGH', 'highbeam'),
                        ('FRONT_LIGHT_POSITION', 'position'), ('REAR_LIGHT_LIGHT', 'taillight'),
                        ('REAR_LIGHT_STOP', 'brakelight'), ('REAR_LIGHT_REAR', 'reverselight')),
    # All lamps share one CAR_lights atlas, so no lens-only material can be shaded red.
    'HEADLIGHT_MATERIALS': set(), 'TAILLIGHT_MATERIALS': set(), 'PATTERNED_GLOW': set(),
    'CHMSL_MESHES': set(),
    'GLASS_MATERIALS': set(),  # the M3 glass texture is neutral dark, not olive
    'MIRROR_MATERIAL': 'CAR_mirror',
    'METALLIC': {'CAR_mirror', 'CAR_chassis_chrome', 'INT_chrome', 'INT_aluminum', 'CAR_LOGHI_BMW', 'CAR_rim'},
    'DEBRAND': {},
}

CAR_UPGRADES = {
    'GEAR_RATIOS': GEAR_RATIOS,
    # AC final 3.15; the native etk_finaldrive_R_315 part is 3.154 (0.1 %), measured in lab 030.
    'FINAL_DRIVE': 3.154,
    'SEAT_BOX': ((0.06, 0.68), (-0.45, 0.40), (0.28, 1.26)),
    'BELT_MATERIALS': {'INT_belt'},
    'PEDAL_X': (('pedal_throttle', 0.33), ('pedal_brake', 0.44)),
    'PEDAL_MATERIALS': set(),
    'PEDAL_BOX': (0.2, 0.7, -0.66, 0.56),
    'SHIFTER_NODE': None, 'SHIFT_BOOT_NODE': None,
    'FENDER_ZONE': {'y_max': -0.70, 'abs_x_min': 0.6, 'z_max': 0.97},
    'NOSE_Y_MAX': -1.774,
    # The third brake lamp is modelled inside the tail-lamp mesh at the roof line.
    'LAMP_MOVES': (('REAR_LIGHT_STOP', 1.0, 'body'),),
    'spec_parts': spec_parts,
    'spec_config': spec_config,
}

CAR_DETAILS = {
    'GAUGES': {
        'ARROW_RPM': ('gauge_rpm', 'rpm', 0, 9000, 0, 262 / 9000),
        'ARROW_SPEED': ('gauge_speed', 'wheelspeed', 0, 330 / 3.6, 0, 262 / (330 / 3.6)),
        'ARROW_FUEL': ('gauge_fuel', 'fuel', 0, 1, 0, -98),
        'ARROW_TEMP': ('gauge_oil', 'oiltemp', 50, 150, -50, -0.98),
    },
    'PREFIX': PREFIX,
    'LABEL': 'BMW M3 E92',
    'MIRROR_MATERIAL': 'CAR_mirror',
    'TRACK': {'F': 0.248, 'R': 0.246},
    'WHEEL_DONORS': {'F': 'etk_wheel_06a_18x9_F', 'R': 'wheel_02a_18x10_R'},
    'RIM_LABEL': '18-inch rims',
    # The AC plate's centre (with mesh lift) and 11.7 degree lean; 0.86 scales the 520 mm native
    # plate to the 447 mm AC plate.
    'PLATE': {'pos': {'x': 0.0, 'y': 2.19, 'z': 0.805}, 'rot': {'x': 12, 'y': 0, 'z': 180},
              'scale': {'x': 0.86, 'y': 0.86, 'z': 0.86}},
    'BRAKE_CALIPER': 'brake_caliper_standard_plain',  # the E92 M3's floating calipers are unpainted grey
}

CAR_SOUNDS = {
    'PREFIX': PREFIX, 'LABEL': 'M3',
    'SETS': {'engine': {'idle': 'm3e92_idle', 'prefix_on': 'm3e92_on_', 'prefix_off': 'm3e92_off_'},
             'exhaust': {'idle': 'ext_m3e92_idle', 'prefix_on': 'ext_m3e92_on_', 'prefix_off': 'ext_m3e92_off_'}},
    'CHAINS': {'engine': (['m3e92_idle', 'm3e92_off_2800', 'm3e92_off_6000', 'm3e92_off_8500'],
                          ['m3e92_idle', 'm3e92_on_3000', 'm3e92_on_4198', 'm3e92_on_4000', 'm3e92_on_6000',
                           'm3e92_on_8500'])},
    'IDLE_TAGS': {'engine': 1176, 'exhaust': 1152},
    # Read from the M3 bank's event metadata: (fade-in window, AC volume dB) per loop.
    'AC_LAYOUT': {
        'engine': ({1176: (None, -3), 2800: ((1400, 1800), -1.5), 6000: ((2800, 3800), 0), 8500: ((6000, 6400), 0)},
                   {1176: (None, 0), 3000: ((1200, 1600), -1), 4198: ((1800, 2600), -3), 4000: ((2800, 3800), -1.5),
                    6000: ((4400, 5200), -3), 8500: ((6000, 6800), -2)}),
        'exhaust': ({1152: (None, 0), 4000: ((1200, 2000), 1.5), 6000: ((4000, 4400), 0), 8500: ((6000, 6400), 0)},
                    {1152: (None, 3), 2800: ((1200, 1600), 2.5), 4000: ((3000, 3400), 0), 5800: ((4200, 4600), 0),
                     8500: ((5000, 5800), 0)}),
    },
    'EVENT_SAMPLES': ('limiter', 'gearup', 'geardn'),
    'SEAMLESS_EVENTS': set(),
    'EVENT_HOOKS': (('shifter', 'acng_shiftSound', 'upSample', 'gearup'),
                    ('shifter', 'acng_shiftSound', 'downSample', 'geardn')),
}
