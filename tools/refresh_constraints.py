"""Combine current Interface Designer timing with vendor user exceptions.

Run AFTER interface generation and BEFORE place/route. The 2022 example's
fixed peripheral delay numbers must not override the installed I3 database.
No timing exceptions are added to the image pipeline. Diagnostic camera CDC
control inputs are exempt only at their first synchronizer stage; its held
snapshot payload has an explicit bound below one destination clock period.
"""
import argparse
from pathlib import Path


def refresh(project):
    generated=project/'outflow'/'Case4_Ti60.pt.sdc'
    original=project/'vendor_original.pt.sdc'
    if not generated.is_file() or not original.is_file():
        raise FileNotFoundError('Generate the interface first; keep vendor_original.pt.sdc')
    text=original.read_text(encoding='utf-8')
    pre_gpio=text.split('# GPIO Constraints')[0]
    clocks=[]; exceptions=[]
    for line in pre_gpio.splitlines():
        if line.startswith('create_clock') and ('cmos_pclk' in line or 'csi_rxc_i' in line):
            clocks.append(line)
        elif line.startswith('set_'):
            exceptions.append(line)
    result=('# Case 4: external clocks + current peripheral timing + vendor CDC exceptions\n'
            '# Rebuild with boards/vf_ti60/refresh_constraints.py after interface changes.\n'
            +'\n'.join(clocks)+'\n'+generated.read_text(encoding='utf-8')
            +'\n# User exceptions inherited from the vendor example\n'+'\n'.join(exceptions)+'\n')
    result += '\n# Asynchronous mechanical keys use explicit two-stage synchronizers.\nset_false_path -from [get_ports {key_n[0] key_n[1]}]\n'
    result += '\n# UART RX is asynchronous; only first synchronizer D is exempt.\nset_false_path -from [get_ports {uart_rx_i}] -to [get_pins {u_case4_video/uart/rx_meta~FF|D}]\n'
    result += '''
# Read-only camera diagnostic handshake: unrelated camera/pixel clocks.
# Only first control synchronizer stages are asynchronous timing endpoints.
set_false_path -from [get_pins {u_capture_diag/cam_snapshot/request~FF|CLK}] -to [get_pins {u_capture_diag/cam_snapshot/request_sync[0]~FF|D}]
set_false_path -from [get_pins {u_capture_diag/cam_snapshot/ack~FF|CLK}] -to [get_pins {u_capture_diag/cam_snapshot/ack_sync[0]~FF|D}]
# held changes together with ack and stays fixed for the request/ack round trip.
# Data crosses two destination registers before consumption; ack crosses three.
# 3 ns bounds the payload crossing below one 6.720 ns pixel clock period.
# All subsequent synchronizer/data registers retain ordinary same-clock STA.
set_max_delay -from [get_pins {u_capture_diag/cam_snapshot/held[*]~FF|CLK}] -to [get_pins {u_capture_diag/cam_snapshot/data_meta[*]~FF|D}] 3.000
'''
    result='\n'.join('# '+line if line.startswith('create_clock') and '<USER_PERIOD>' in line else line for line in result.splitlines())+'\n'
    (project/'Case4_Ti60.sdc').write_text(result,encoding='utf-8')
    print(project/'Case4_Ti60.sdc')


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('project',type=Path,nargs='?',
                        default=Path(__file__).resolve().parents[2]/'build'/'vf_ti60_demo')
    refresh(parser.parse_args().project.resolve())

