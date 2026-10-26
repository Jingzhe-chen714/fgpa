"""Configure a freshly assembled advanced project for native OV5640 1080p.

This edits generated vendor files only. Call configure(project, 60), generate
the Efinity interface, refresh constraints, then check(project, 60, True).
It does not modify the advanced pipeline/Canny instance or run Efinity.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path
import xml.etree.ElementTree as ET

PT = 'http://www.efinixinc.com/peri_design_db'
ET.register_namespace('efxpt', PT)
ET.register_namespace('xsi', 'http://www.w3.org/2001/XMLSchema-instance')
SENSOR = Path('src/cmos_i2c/I2C_OV5640_1280720_Config.v')
I2C = Path('src/cmos_i2c/i2c_timing_ctrl_16bit.v')
WIDTH, HEIGHT, HTOTAL, VTOTAL = 1920, 1080, 2200, 1125
FRAME_BYTES = WIDTH * HEIGHT * 2
XCLK_HZ, DVP_HZ = 24_000_000, 84_000_000

# OV5640 native 1080 mode: no horizontal/vertical 2x binning. The window is
# the 1952x1088 sensor crop used by the upstream Linux OV5640 DVP mode.
# RGB565 byte order is unchanged: 0x4300=0x61, MSB first on the 8-bit bus.
REGISTERS = {
    0x3034: 0x18, 0x3035: 0x20, 0x3036: 0x54, 0x3037: 0x13,
    0x3108: 0x01, 0x3820: 0x40, 0x3821: 0x06,
    0x3c07: 0x07,
    0x3814: 0x11, 0x3815: 0x11,
    0x3800: 0x01, 0x3801: 0x50, 0x3802: 0x01, 0x3803: 0xb2,
    0x3804: 0x08, 0x3805: 0xef, 0x3806: 0x05, 0x3807: 0xf1,
    0x3808: 0x07, 0x3809: 0x80, 0x380a: 0x04, 0x380b: 0x38,
    0x380c: 0x09, 0x380d: 0xc4, 0x380e: 0x04, 0x380f: 0x60,
    0x3810: 0x00, 0x3811: 0x10, 0x3812: 0x00, 0x3813: 0x04,
    0x3618: 0x04, 0x3612: 0x2b, 0x3708: 0x64,
    0x3709: 0x12, 0x370c: 0x00,
    0x3a00: 0x78, 0x3a02: 0x04, 0x3a03: 0x60,
    0x3a14: 0x04, 0x3a15: 0x60,
    # SCLK=42MHz, HTS=2500: 50Hz step168, 60Hz step140 lines.
    0x3a08: 0x00, 0x3a09: 0xa8, 0x3a0a: 0x00, 0x3a0b: 0x8c,
    0x3a0d: 0x07, 0x3a0e: 0x06,
    0x4004: 0x06, 0x4005: 0x1a,
    0x4300: 0x61, 0x501f: 0x01,
    0x460b: 0x37, 0x460c: 0x20, 0x3824: 0x04,
    0x5001: 0x83, 0x3503: 0x00, 0x4740: 0x21,
}


def _replace_once(text, pattern, replacement, label):
    text, count = re.subn(pattern, replacement, text, flags=re.M)
    if count != 1:
        raise ValueError(f'{label}: expected one anchor, found {count}')
    return text


def _literal(expression):
    match = re.fullmatch(r"24'h([0-9a-fA-F_]+)", expression.strip())
    if match:
        value = int(match[1].replace('_', ''), 16)
        return value >> 8, value & 255
    # Only the vendor table's four parameterized dimensions/orientation.
    match = re.fullmatch(r"\{16'h([0-9a-fA-F]{4}),\s*IMAGE_(WIDTH|HEIGHT)\[\s*(15:8|7:0)\]\}", expression.strip())
    if match:
        value = WIDTH if match[2] == 'WIDTH' else HEIGHT
        return int(match[1], 16), (value >> 8 if match[3] == '15:8' else value & 255)
    if re.fullmatch(r"\{16'h3820,\s*IMAGE_FLIP\}", expression.strip()):
        return 0x3820, 0x40
    if re.fullmatch(r"\{20'h38210,\s*IMAGE_MIRROR\}", expression.strip()):
        return 0x3821, 0x06
    raise ValueError(f'Unexpected sensor LUT expression: {expression}')


def _sensor_entries(text):
    rows = re.findall(r'^\s*(\d+)\s*:\s*LUT_DATA\s*=\s*([^;]+);', text, flags=re.M)
    if not rows or [int(i) for i, _ in rows] != list(range(len(rows))):
        raise ValueError('Sensor ROM addresses are not contiguous')
    return [_literal(expression) for _, expression in rows]


def _configure_sensor(path):
    text = path.read_bytes().decode('latin1')
    original = _sensor_entries(text)
    # Retain the vendor analog/ISP calibration, AWB, gamma and lens tables.
    # All programming happens in standby; the sole wake-up is the final entry.
    # Repeated mode writes can be folded while in standby. The added exposure
    # registers require a9-bit LUT index/size, widened through the sequencer.
    entries, seen = [], set()
    for address, value in original:
        if address == 0x3008 and value == 0x02:
            continue
        if address not in (0x3008, 0x3103) and address in seen:
            continue
        value = REGISTERS.get(address, value)
        entries.append((address, value))
        seen.add(address)
    entries.extend((a, v) for a, v in REGISTERS.items() if a not in seen)
    # Program the complete clock plan in standby before selecting PLL as the
    # ISP source, instead of retaining reset-default clocks during ISP setup.
    clock_registers = (0x3034, 0x3035, 0x3036, 0x3037, 0x3108)
    entries = [(a, v) for a, v in entries if a not in clock_registers]
    select_pll = entries.index((0x3103, 0x03))
    entries[select_pll:select_pll] = [(a, REGISTERS[a]) for a in clock_registers]
    entries.append((0x3008, 0x02))
    if not len(entries) < 512:
        raise ValueError(f'9-bit sensor sequencer overflow: {len(entries)}')
    text = re.sub(r"IMAGE_WIDTH\s*=\s*16'd\d+", "IMAGE_WIDTH = 16'd1920", text)
    text = re.sub(r"IMAGE_HEIGHT\s*=\s*16'd\d+", "IMAGE_HEIGHT = 16'd1080", text)
    text = re.sub(r"IMAGE_MIRROR\s*=\s*4'h[0-9a-fA-F]", "IMAGE_MIRROR = 4'h6", text)
    text = text.replace('//1280*720@60 with AutO/Manual Exposure',
                        '// Native1920x1080 RGB565, nominal15fps; XCLK24MHz')
    text = _replace_once(text, r'assign\s+LUT_SIZE\s*=\s*[^;]+;',
                         f"assign LUT_SIZE = 9'd{len(entries)};", 'LUT size')
    for signal in ('LUT_INDEX', 'LUT_SIZE'):
        text = _replace_once(text, r'\[[78]:0\](\s*' + signal + r'\b)',
                             r'[8:0]\1', signal + ' width')
    start = text.index('case(LUT_INDEX)') + len('case(LUT_INDEX)')
    end = text.index('endcase', start)
    body = '\n// Clock plan: VCO672MHz / sys2 / root2 / bit2 = DVP84MHz.\n'
    body += '// SCLK42MHz / (2500*1120) = nominal15fps; no pixel upscaling.\n'
    body += '\n'.join(f"{i}: LUT_DATA = 24'h{a:04x}_{v:02x};" for i, (a, v) in enumerate(entries))
    body += "\ndefault: LUT_DATA = 24'h0000_00;\n\t"
    path.write_bytes((text[:start] + body + text[end:]).encode('latin1'))


def _clock_periods(refresh_hz):
    if refresh_hz not in (30, 60):
        raise ValueError('refresh_hz must be30 or60')
    pixel = 148_800_000 if refresh_hz == 60 else 74_400_000
    return {'clk_pixel': 1e9 / pixel, 'clk_pixel_2x': 1e9 / (pixel * 2),
            'clk_27m': 1e9 / XCLK_HZ, 'cmos_pclk': 1e9 / DVP_HZ}


def _patch_sdc(path, periods):
    lines = path.read_text(encoding='utf-8').splitlines()
    found = {name: 0 for name in periods}
    for index, line in enumerate(lines):
        if not line.startswith('create_clock '):
            continue
        if '<USER_PERIOD>' in line:
            lines[index] = '# ' + line
            continue
        for name, period in periods.items():
            if re.search(r'(?<![\w])' + name + r'(?![\w])', line):
                lines[index] = re.sub(r'-period\s+[\d.]+', f'-period {period:.9f}', line)
                found[name] += 1
                break
    if any(count != 1 for count in found.values()):
        raise ValueError(f'{path.name}: missing/duplicate bootstrap clock definitions: {found}')
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def configure(project: Path, refresh_hz=60):
    """Mutate the newly generated project; leave parent-owned Canny wiring alone."""
    project = Path(project).resolve()
    if not (project / 'case4_build_manifest.json').is_file():
        raise ValueError('Expected an assembled Case4 generated project')
    periods = _clock_periods(refresh_hz)
    _configure_sensor(project / SENSOR)
    i2c = (project / I2C).read_bytes().decode('latin1')
    for signal in ('i2c_config_index', 'i2c_config_size'):
        i2c = _replace_once(i2c, r'\[[78]:0\](\s*' + signal + r'\b)',
                            r'[8:0]\1', signal + ' width')
    (project / I2C).write_bytes(i2c.encode('latin1'))
    top_path = project / 'example_top.v'
    top = top_path.read_bytes().decode('latin1')
    for signal in ('ov5640_i2c_config_index', 'ov5640_i2c_config_size'):
        top = _replace_once(top, r'\[\s*[78]:0\](\s*' + signal + r'\b)',
                            r'[8:0]\1', signal + ' width')
    for parameter, value in [('IMAGE_HSIZE_SOURCE', '1920 * 2 / CSI_STRB_WIDTH'),
                             ('IMAGE_HSIZE_TARGET', '1920 * 2 / CSI_STRB_WIDTH'),
                             ('IMAGE_VSIZE_SOURCE', '1080'), ('IMAGE_YSIZE_TARGET', '1080'),
                             ('C_RD_END_ADDR', '1920 * 2 * 1080')]:
        top = _replace_once(top, r'(\.' + parameter + r'\s*\()[^)]*(\))',
                            lambda m, v=value: m[1] + v + m[2], parameter)
    # Internal video/frame-store VSYNC stays active low; CTA1080 sync is
    # positive only at the HDMI encoder input, after all processing.
    for port, signal in [('vid_pVSync', 'case4_vs'), ('vid_pHSync', 'case4_hs')]:
        top = _replace_once(top, r'(\.' + port + r'\s*\()\s*~?' + signal + r'\s*(\))',
                            lambda m, s=signal: m[1] + '~' + s + m[2], port)
    top = re.sub(r'(input\s+clk_27m,)[^\r\n]*',
                 r'\1 // Historical name; physical CMOS XCLK is24MHz.', top)
    top = re.sub(r'(input\s+clk_pixel,)[^\r\n]*',
                 lambda m: m[1] + f' // HDMI pixel clock {1e3/periods["clk_pixel"]:.3f}MHz.', top)
    top = re.sub(r'(input\s+clk_pixel_10x,)[^\r\n]*',
                 lambda m: m[1] + (' // HDMI744MHz, half-rate serializer (5x pixel).' if refresh_hz == 60 else
                                 ' // HDMI744MHz, full-rate serializer (10x pixel).'), top)
    top_path.write_bytes(top.encode('latin1'))
    values = {'H_FRONT': 88, 'H_SYNC': 44, 'H_BACK': 148, 'H_DISP': WIDTH,
              'H_DISP_REQ': WIDTH, 'H_TOTAL': HTOTAL, 'V_FRONT': 4, 'V_SYNC': 5,
              'V_BACK': 36, 'V_DISP': HEIGHT, 'V_DISP_REQ': HEIGHT, 'V_TOTAL': VTOTAL}
    header = '// Case4 native1920x1080 timings; clocks/actual FPS: native1080_clock_plan.json\n'
    lcd_path = project / 'src/lcd_para.v'
    lcd_original = lcd_path.read_bytes().decode('latin1')
    split_marker = '// Case4 native1920x1080 timings' if header.split(';')[0] in lcd_original else '//vga parameter define'
    if split_marker not in lcd_original:
        raise ValueError('Missing vendor LCD header; rebuild generated project before configuring')
    # Keep the vendor copyright, color constants and SYNC_POLARITY. Other
    # vendor modules in the source list use them even when their logic is idle.
    lcd_prefix = lcd_original.split(split_marker, 1)[0]
    # This header is included inside vendor modules; a timescale directive
    # there is illegal in standard Verilog. Each source defines its own scale.
    lcd_prefix = re.sub(r'^\s*`timescale[^\r\n]*', '', lcd_prefix, flags=re.M)
    if not all(re.search(r'`define\s+' + name + r'\b', lcd_prefix)
               for name in ('RED', 'GREEN', 'BLUE', 'WHITE', 'BLACK', 'YELLOW', 'CYAN', 'ROYAL', 'SYNC_POLARITY')):
        raise ValueError('Vendor LCD color/polarity macros are incomplete; rebuild generated project')
    lcd_path.write_bytes((lcd_prefix + header + '\n'.join(
        f"`define {name} 12'd{value}" for name, value in values.items()) + '\n').encode('latin1'))
    peri_path = project / 'Case4_Ti60.peri.xml'
    peri = ET.parse(peri_path)
    for name, divider in [('clk_pixel', 20 if refresh_hz == 60 else 40),
                          ('clk_pixel_2x', 10 if refresh_hz == 60 else 20), ('clk_27m', 56)]:
        nodes = peri.findall(f'.//{{{PT}}}comp_output_clock[@name="{name}"]')
        if len(nodes) != 1:
            raise ValueError(f'Expected one PLL output {name}')
        nodes[0].set('out_divider', str(divider))
    hdmi = [n for n in peri.findall(f'.//{{{PT}}}lvds') if n.get('name', '').startswith('hdmi_')]
    if len(hdmi) != 4:
        raise ValueError('Expected four HDMI serialized differential outputs')
    for node in hdmi:
        node.find(f'{{{PT}}}adv_ltx_info').set('is_half_rate', 'true' if refresh_hz == 60 else 'false')
    peri.write(peri_path, encoding='utf-8', xml_declaration=True)
    # refresh_constraints.py reads external clocks from vendor_original.pt.sdc.
    # Keep that bootstrap copy consistent as well as the initial active SDC.
    for file in ['vendor_original.pt.sdc', 'Case4_Ti60.sdc']:
        _patch_sdc(project / file, periods)
    report = check(project, refresh_hz)
    (project / 'native1080_clock_plan.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    manifest_path = project / 'case4_build_manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    manifest.update(resolution=[WIDTH, HEIGHT], h_total=HTOTAL, v_total=VTOTAL,
                    native1080=report, top_sha256=hashlib.sha256(top_path.read_bytes()).hexdigest())
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return report


def check(project: Path, refresh_hz=60, generated=False):
    """Independently decode the written sensor ROM, periphery and constraints."""
    project = Path(project)
    periods = _clock_periods(refresh_hz)
    text = (project / SENSOR).read_bytes().decode('latin1')
    entries = _sensor_entries(text)
    registers = dict(entries)
    for address, value in REGISTERS.items():
        if registers.get(address) != value:
            raise ValueError(f'Sensor register{address:04x}: expected{value:02x}')
    if entries[-1] != (0x3008, 0x02) or any(a == 0x3008 and v == 2 for a, v in entries[:-1]):
        raise ValueError('Sensor must remain in standby until all mode registers are programmed')
    clock_set = entries.index((0x3036, REGISTERS[0x3036]))
    if not entries.index((0x3008, 0x42)) < clock_set < entries.index((0x3103, 0x03)):
        raise ValueError('Configure sensor clocks in standby before selecting the PLL source')
    size = re.search(r"assign\s+LUT_SIZE\s*=\s*9'd(\d+)", text)
    if not size or int(size[1]) != len(entries) or len(entries) >= 512:
        raise ValueError('Sensor LUT size/9-bit sequencer mismatch')
    i2c = (project / I2C).read_bytes().decode('latin1')
    for signal in ('i2c_config_index', 'i2c_config_size'):
        if not re.search(r'\[8:0\]\s*' + signal + r'\b', i2c):
            raise ValueError(f'I2C sequencer{signal} is not9-bit')
    reg16 = lambda address: registers[address] * 256 + registers[address + 1]
    sensor_vco = XCLK_HZ / (registers[0x3037] & 15) * registers[0x3036]
    byteclock = sensor_vco / (registers[0x3035] >> 4) / (((registers[0x3037] >> 4) & 1) + 1) / 2
    sysclock = byteclock / (1 << (registers[0x3108] & 3))
    sensor_fps = sysclock / (reg16(0x380c) * reg16(0x380e))
    if byteclock != DVP_HZ or sensor_fps != 15 or (reg16(0x3808), reg16(0x380a)) != (WIDTH, HEIGHT):
        raise ValueError('Sensor clock or raster does not implement native1080p15')
    peri = ET.parse(project / 'Case4_Ti60.peri.xml')
    plls = {p.get('name'): p for p in peri.findall(f'.//{{{PT}}}pll')}
    syspll = plls['sys_pll']
    if (syspll.get('ref_clock_freq'), syspll.get('multiplier'), syspll.get('pre_divider')) != ('24.0000', '4', '1'):
        raise ValueError('Unexpected system PLL input/feedback plan')
    outputs = {o.get('name'): int(o.get('out_divider')) for o in syspll.findall(f'{{{PT}}}comp_output_clock')}
    sys_vco = 96_000_000 * outputs['clk_sys']
    pixel_hz = sys_vco / outputs['clk_pixel']
    serial_hz = sys_vco / outputs['clk_pixel_10x']
    if not math.isclose(pixel_hz, 1e9 / periods['clk_pixel']) or serial_hz != 744_000_000:
        raise ValueError('HDMI PLL outputs do not match selected refresh')
    camera_div = peri.find(f'.//{{{PT}}}comp_output_clock[@name="clk_27m"]')
    camera_pll = plls['lvds_pll']
    if (camera_pll.get('ref_clock_name'), camera_pll.get('ref_clock_freq'), camera_pll.get('multiplier'), camera_pll.get('pre_divider')) != ('clk_sys', '96.0000', '1', '2'):
        raise ValueError('Unexpected camera reference PLL plan')
    camera_feedback = camera_pll.find(f'{{{PT}}}comp_output_clock[@name="clk_lvds_1x"]')
    camera_hz = 96_000_000 / 2 * int(camera_feedback.get('out_divider')) / int(camera_div.get('out_divider'))
    if camera_hz != XCLK_HZ:
        raise ValueError('CMOS XCLK divider must generate24MHz, not original16MHz')
    camera_gpio = peri.find(f'.//{{{PT}}}comp_gpio[@name="cmos_xclk"]/{{{PT}}}output_config')
    if camera_gpio is None or camera_gpio.get('clock_name') != 'clk_27m':
        raise ValueError('Physical CMOS XCLK GPIO is not driven by expected PLL output')
    for node in peri.findall(f'.//{{{PT}}}lvds'):
        if node.get('name', '').startswith('hdmi_'):
            attrs = node.find(f'{{{PT}}}adv_ltx_info').attrib
            if attrs['is_half_rate'] != ('true' if refresh_hz == 60 else 'false') or attrs['serial_width'] != '10':
                raise ValueError('HDMI serializer/PLL frequency ratio mismatch')
    top = (project / 'example_top.v').read_bytes().decode('latin1')
    if not re.search(r'w_ddr3_ui_clk\s*=\s*clk_sys\s*;', top):
        raise ValueError('Expected DDR user AXI clock96MHz=clk_sys')
    for signal in ('ov5640_i2c_config_index', 'ov5640_i2c_config_size'):
        if not re.search(r'\[8:0\]\s*' + signal + r'\b', top):
            raise ValueError(f'Top sensor{signal} is not9-bit')
    for name, expected in [('IMAGE_HSIZE_SOURCE', '1920*2/CSI_STRB_WIDTH'),
                           ('IMAGE_HSIZE_TARGET', '1920*2/CSI_STRB_WIDTH'),
                           ('IMAGE_VSIZE_SOURCE', '1080'), ('IMAGE_YSIZE_TARGET', '1080'),
                           ('C_RD_END_ADDR', '1920*2*1080')]:
        match = re.search(r'\.' + name + r'\s*\(([^)]*)\)', top)
        if not match or re.sub(r'\s+', '', match[1]) != expected:
            raise ValueError(f'Camera crop/DDR frame size mismatch: {name}')
    if not re.search(r'CSI_DATA_WIDTH\s*=\s*8\s*;', top):
        raise ValueError('Expected8-bit camera byte stream')
    if FRAME_BYTES >= 2**22 or FRAME_BYTES % 2048:
        raise ValueError('Frame does not fit current4MiB bank/full AXI burst design')
    lcd = (project / 'src/lcd_para.v').read_bytes().decode('latin1')
    macros = {name: int(value) for name, value in re.findall(r"`define\s+(\w+)\s+12'd(\d+)", lcd)}
    if (macros.get('H_DISP'), macros.get('V_DISP'), macros.get('H_TOTAL'), macros.get('V_TOTAL')) != (WIDTH, HEIGHT, HTOTAL, VTOTAL):
        raise ValueError('HDMI raster must be native1920x1080 with2200x1125 totals')
    if sum(macros[n] for n in ('H_FRONT', 'H_SYNC', 'H_BACK', 'H_DISP')) != HTOTAL or sum(macros[n] for n in ('V_FRONT', 'V_SYNC', 'V_BACK', 'V_DISP')) != VTOTAL:
        raise ValueError('HDMI porch/sync totals inconsistent')
    active = (project / 'Case4_Ti60.sdc').read_text(encoding='utf-8')
    for name, target_period in periods.items():
        lines = [line for line in active.splitlines() if line.startswith('create_clock ') and re.search(r'(?<![\w])' + name + r'(?![\w])', line)]
        if len(lines) != 1:
            raise ValueError(f'SDC clock missing or duplicated: {name}')
        period = float(re.search(r'-period\s+([\d.]+)', lines[0])[1])
        if not math.isclose(period, target_period, abs_tol=0.001):
            raise ValueError(f'SDC clock{ name}={period}ns; expected{target_period}ns')
    if generated:
        generated_text = (project / 'outflow/Case4_Ti60.pt.sdc').read_text(encoding='utf-8')
        for name, target in periods.items():
            if name == 'cmos_pclk':
                continue  # External clock is deliberately added by refresh_constraints.
            lines = [line for line in generated_text.splitlines() if line.startswith('create_clock ') and re.search(r'(?<![\w])' + name + r'(?![\w])', line)]
            if len(lines) != 1 or not math.isclose(float(re.search(r'-period\s+([\d.]+)', lines[0])[1]), target, abs_tol=0.001):
                raise ValueError(f'Actual Interface Designer output clock mismatch: {name}')
    return {'sensor_resolution': [WIDTH, HEIGHT], 'sensor_format': 'RGB565 MSB first,8-bit DVP',
            'sensor_xclk_hz': XCLK_HZ, 'sensor_dvp_hz': int(byteclock), 'sensor_nominal_fps': sensor_fps,
            'sensor_hts': reg16(0x380c), 'sensor_vts': reg16(0x380e), 'sensor_rom_entries': len(entries),
            'display_pixel_hz': int(pixel_hz), 'display_serial_hz': int(serial_hz),
            'display_requested_refresh_hz': refresh_hz, 'display_actual_refresh_hz': pixel_hz / HTOTAL / VTOTAL,
            'display_positive_hsync_vsync': True, 'display_half_rate_serializer': refresh_hz == 60,
            'ddr_frame_bytes': FRAME_BYTES, 'ddr_bursts_per_frame': FRAME_BYTES // 2048,
            'ddr_axi_ui_hz': 96_000_000, 'ddr_internal_core_hz': 192_000_000,
            'ddr_bank_bytes': 2**22, 'ddr_bank_spare_bytes': 2**22 - FRAME_BYTES,
            'interface_generated_clocks_checked': generated,
            'validation_scope': 'Static register/PLL/raster/bank audit; physical sensor FPS and board operation require hardware measurement.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('--refresh-hz', type=int, choices=(30, 60), default=60)
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--generated', action='store_true', help='Also verify current Efinity generated PLL timing')
    args = parser.parse_args()
    result = check(args.project, args.refresh_hz, args.generated) if args.check_only else configure(args.project, args.refresh_hz)
    print(json.dumps(result, indent=2))
