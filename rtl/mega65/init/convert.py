#!/usr/bin/env python3
# MEGA65 port 2026-10-26: converts the Quartus RAM/ROM init files (.mif, Intel .hex) into
# plain text, one word per line in hex, which the RAM templates in ../x68k_rams.vhd read
# at elaboration (Vivado and ghdl). Run from this directory; the outputs are committed.
import os, re, sys

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')

def read_mif(path):
    text = open(path, encoding='latin-1').read()
    text = re.sub(r'--[^\n]*', '', text)
    depth = int(re.search(r'DEPTH\s*=\s*(\d+)', text).group(1))
    width = int(re.search(r'WIDTH\s*=\s*(\d+)', text).group(1))
    arad = re.search(r'ADDRESS_RADIX\s*=\s*(\w+)', text).group(1).upper()
    drad = re.search(r'DATA_RADIX\s*=\s*(\w+)', text).group(1).upper()
    base = {'HEX': 16, 'DEC': 10, 'UNS': 10, 'BIN': 2, 'OCT': 8}
    body = text[text.index('BEGIN') + 5:text.rindex('END')]
    mem = [0] * depth
    for entry in body.split(';'):
        entry = entry.strip()
        if not entry:
            continue
        a, d = [s.strip() for s in entry.split(':')]
        vals = [int(v, base[drad]) for v in d.split()]
        if a.startswith('['):
            lo, hi = [int(x, base[arad]) for x in a[1:-1].split('..')]
            addrs = range(lo, hi + 1)
        else:
            start = int(a, base[arad])
            addrs = range(start, start + len(vals))
        for i, ad in enumerate(addrs):
            mem[ad] = vals[i % len(vals)] if a.startswith('[') else vals[i]
    return mem, width

def read_ihex(path, depth, width):
    nbytes = (width + 7) // 8
    mem = [0] * depth
    upper = 0
    for line in open(path):
        line = line.strip()
        if not line.startswith(':'):
            continue
        b = bytes.fromhex(line[1:])
        n, addr, typ, data = b[0], (b[1] << 8) | b[2], b[3], b[4:4 + b[0]]
        assert sum(b) & 0xFF == 0, 'checksum ' + line
        if typ == 0:
            for i in range(0, n, nbytes):        # Quartus: one word per address, MSB first
                mem[upper + addr + i // nbytes] = int.from_bytes(data[i:i + nbytes], 'big')
        elif typ == 4:
            upper = int.from_bytes(data, 'big') << 16
        elif typ == 1:
            break
    return mem

def write(name, mem, width):
    digits = (width + 3) // 4
    with open(name, 'w') as f:
        for v in mem:
            f.write('%0*x\n' % (digits, v))

def main():
    for src, out in [('cycV/TPalH.mif', 'tpalh.hex'), ('cycV/TPalL.mif', 'tpall.hex'),
                     ('diskemu/sxsidrv.mif', 'sxsidrv.hex'),
                     ('MFP/KBIF/ktbln_m.mif', 'ktbln_m.hex'), ('MFP/KBIF/ktble0_m.mif', 'ktble0_m.hex')]:
        mem, width = read_mif(os.path.join(SRC, src))
        write(out, mem, width)
    sram = read_ihex(os.path.join(SRC, 'diskemu/sramdefault.hex'), 8192, 16)
    write('sram_hi.hex', [v >> 8 for v in sram], 8)    # data_a(15 downto 8)
    write('sram_lo.hex', [v & 0xFF for v in sram], 8)  # data_a(7 downto 0) = even byte of port B
    return 0

if __name__ == '__main__':
    sys.exit(main())
