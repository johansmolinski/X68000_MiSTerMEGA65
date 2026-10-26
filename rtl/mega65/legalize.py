#!/usr/bin/env python3
# MEGA65 port 2026-10-26: renames identifiers in upstream files that Vivado or ghdl
# reject. Quartus accepts identifiers that VHDL-2008 reserves; both other tools stop
# at them:
#   context (a VHDL-2008 keyword)  X68K_top.vhd: the contrast width constant
#   vmode   (a PSL keyword)        X68mmapCV.vhd: a port, and X68K_top.vhd's
#                                  component declaration and port map of it
#   VMODE                          X68K_top.vhd: port of the SystemVerilog module
#                                  x68k_native_crtc, which keeps its name: written
#                                  as the extended identifier \VMODE\
# and one that only ghdl's Verilog writer trips over (5.0.1 crashes with an internal
# error in netlists-disp_verilog.adb when several instances drive a port named after
# a Verilog keyword):
#   reg                            SPRITE/ramreg.vhd and its component declaration
#                                  in SPRITE/sprregs.vhd: output port -> regout
# The script is idempotent. After an upstream merge that touched these files, take
# upstream's version of them and run it again (from anywhere):
#   python3 rtl/mega65/legalize.py
import os, re, sys

RTL = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
TAG = b'-- MEGA65 port: identifier renames by rtl/mega65/legalize.py'
NOTE = (TAG + b' (context -> contbits, vmode -> vmode_m,'
        b' x68k_native_crtc port VMODE -> \\VMODE\\)')

def words(line):
    code = line.split(b'--', 1)[0]
    return code, line[len(code):]

def fix_top(lines):
    out, scope = [], None
    for line in lines:
        code, comment = words(line)
        # scope = the component being declared or instantiated ("label :name"
        # followed by nothing, generic or port; port declarations have a mode)
        m = re.search(rb'^\s*component\s+(\w+)', code, re.I) or \
            re.search(rb'^\s*\w+\s*:\s*(?:entity\s+work\.)?(\w+)\s*($|generic\b|port\b)', code, re.I)
        if m and m.group(1).lower() not in (b'in', b'out', b'inout', b'buffer'):
            scope = m.group(1).lower()
        if scope == b'x68k_native_crtc':
            code = re.sub(rb'(?<![\\\w])vmode\b(?!\\)', rb'\\VMODE\\', code, flags=re.I)
        else:
            code = re.sub(rb'(?<![\\\w])vmode\b', b'vmode_m', code, flags=re.I)
        code = re.sub(rb'(?<![\\\w])context\b', b'contbits', code, flags=re.I)
        out.append(code + comment)
    return out

def fix_mmap(lines):
    out = []
    for line in lines:
        code, comment = words(line)
        out.append(re.sub(rb'(?<![\\\w])vmode\b', b'vmode_m', code, flags=re.I) + comment)
    return out

def fix_reg(lines):
    out = []
    for line in lines:
        code, comment = words(line)
        out.append(re.sub(rb'(?<![\\\w])reg\b', b'regout', code) + comment)
    return out

def process(name, fixer, note=None):
    path = os.path.join(RTL, name)
    data = open(path, 'rb').read()
    lines = data.split(b'\n')
    new = fixer(lines)
    if not any(l.startswith(TAG) for l in new[:3]):
        cr = b'\r' if lines[0].endswith(b'\r') else b''
        new.insert(0, (note or NOTE) + cr)
    result = b'\n'.join(new)
    if result != data:
        open(path, 'wb').write(result)
        print('legalized', name)

def main():
    process('X68K_top.vhd', fix_top)
    process('X68mmapCV.vhd', fix_mmap)
    reg_note = TAG + b' (output port reg -> regout, for ghdl\'s Verilog writer)'
    process('SPRITE/ramreg.vhd', fix_reg, reg_note)
    process('SPRITE/sprregs.vhd', fix_reg, reg_note)
    return 0

if __name__ == '__main__':
    sys.exit(main())
