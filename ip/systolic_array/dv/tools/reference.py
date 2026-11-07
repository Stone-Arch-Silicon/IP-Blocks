#!/usr/bin/env python3
"""Independent, integer/rational golden model. No numpy or RTL-derived float ops."""
from fractions import Fraction
import json
import random
import re
from pathlib import Path

CONFIG_KEYS = ('DATAFLOW', 'NUMERIC_MODE', 'ROWS', 'COLS', 'INT_W', 'MAX_K',
               'MAX_M', 'INT_ACC_OVERRIDE', 'FP_RESULT_W',
               'EXTRA_PRODUCT_REGS', 'OUT_FIFO_DEPTH')
SYMBOLS = {'OUTPUT_STATIONARY': 0, 'WEIGHT_STATIONARY': 1,
           'INTEGER_MODE': 0, 'FP16_MODE': 1}

def read_config(package):
    text = Path(package).read_text()
    result = {}
    for key in CONFIG_KEYS:
        expr = re.search(rf'localparam int {key}\s*=\s*([^;]+);', text).group(1).strip()
        result[key] = SYMBOLS[expr] if expr in SYMBOLS else int(expr, 0)
    return result

def widths(c):
    terms = c['MAX_K'] if c['DATAFLOW'] == 0 else c['ROWS']
    growth = (terms-1).bit_length()
    iw = c['INT_W']
    acc = c['INT_ACC_OVERRIDE'] or max(32, 2*iw+growth)
    return (16 if c['NUMERIC_MODE'] else iw,
            c['FP_RESULT_W'] if c['NUMERIC_MODE'] else acc)

def signed(value, width):
    return value-(1 << width) if value & (1 << (width-1)) else value

def half(value):
    """Return (kind, exact Fraction or sign, signaling)."""
    sign = -1 if value >> 15 else 1
    e, f = (value >> 10) & 31, value & 1023
    if e == 31:
        return ('nan', 0, not bool(f & 512)) if f else ('inf', sign, False)
    m = f + (1024 if e else 0)
    power = max(e, 1)-25
    v = Fraction(sign*m) * Fraction(2)**power
    return 'finite', v, False

def rounded_quotient(value):
    q, r = divmod(value.numerator, value.denominator)
    return q + (2*r > value.denominator or
                (2*r == value.denominator and (q & 1))), bool(r)

def quantize(value, bits):
    """Round an exact Fraction to binary16/32, nearest ties even, tiny after round."""
    f, e = (10, 5) if bits == 16 else (23, 8)
    bias = (1 << (e-1))-1
    sign = int(value < 0)
    value = abs(value)
    if not value:
        return 0, 0
    exponent = value.numerator.bit_length()-value.denominator.bit_length()
    if value < Fraction(2)**exponent:
        exponent -= 1
    emin = 1-bias
    quantum = Fraction(2)**(max(exponent, emin)-f)
    significand, inexact = rounded_quotient(value/quantum)
    if exponent < emin:
        normal = significand >= (1 << f)
        packed = (int(normal) << f) | (significand & ((1 << f)-1))
        flags = int(inexact) | (int(inexact and not normal) << 1)
    else:
        if significand == (1 << (f+1)):
            significand >>= 1
            exponent += 1
        if exponent > bias:
            packed = ((1 << e)-1) << f
            flags = 5
        else:
            packed = ((exponent+bias) << f) | (significand & ((1 << f)-1))
            flags = int(inexact)
    return (sign << (bits-1)) | packed, flags

def fp_dot(a, b, result_bits=32):
    total = Fraction(0)
    nan = invalid = posinf = neginf = False
    for av, bv in zip(a, b):
        ak, x, sa = half(av)
        bk, y, sb = half(bv)
        invalid |= sa or sb
        if ak == 'nan' or bk == 'nan':
            nan = True
        elif (ak == 'inf' and bk == 'finite' and y == 0) or \
             (bk == 'inf' and ak == 'finite' and x == 0):
            nan = invalid = True
        elif ak == 'inf' or bk == 'inf':
            negative = bool((av ^ bv) & 0x8000)
            neginf |= negative
            posinf |= not negative
        else:
            total += x*y
    conflict = posinf and neginf
    f, e = (10, 5) if result_bits == 16 else (23, 8)
    if nan or conflict:
        return (((1 << e)-1) << f) | (1 << (f-1)), int(invalid or conflict) << 4
    if posinf or neginf:
        return (int(neginf) << (result_bits-1)) | (((1 << e)-1) << f), 0
    return quantize(total, result_bits)

def pack(lanes, width):
    mask = (1 << width)-1
    return sum((v & mask) << (i*width) for i, v in enumerate(lanes))

def make_case(c, rng, length, ar, ac, kind='random', pair=None, b_override=None,
              mode=0, shadow=0, bad_last=0, stalls=1):
    iw, ow = widths(c)
    r, n = c['ROWS'], c['COLS']
    m, k = (ar, length) if c['DATAFLOW'] == 0 else (length, ar)
    def value(i):
        if pair is not None: return pair[i & 1]
        if kind == 'zero': return 0
        if kind == 'one': return 0x3c00 if c['NUMERIC_MODE'] else 1
        if kind == 'extreme': return 0x7bff if c['NUMERIC_MODE'] else (1 << (iw-1))
        if c['NUMERIC_MODE']:
            # Mix finite full-range bit patterns with exceptional directed values.
            v = rng.randrange(65536)
            return v if kind == 'allbits' else (v & 0x83ff) | (rng.randrange(31) << 10)
        return rng.randrange(1 << iw)
    # Retain random inactive lanes so masking is checked, not assumed from padding.
    aa = [[value(0) for _ in range(k if c['DATAFLOW'] == 0 else r)]
          for _ in range(r if c['DATAFLOW'] == 0 else m)]
    bb = b_override or [[value(1) for _ in range(n)]
                       for _ in range(k if c['DATAFLOW'] == 0 else r)]
    inputs = ([pack([aa[row][t] for row in range(r)] + bb[t], iw) for t in range(k)]
              if c['DATAFLOW'] == 0 else [pack(row, iw) for row in aa])
    outputs, flags = [], []
    for row in range(m):
        ys, fs = [], []
        for col in range(n):
            if col >= ac:
                y, status = 0, 0
            elif c['NUMERIC_MODE']:
                y, status = fp_dot(aa[row][:k], [bb[t][col] for t in range(k)], ow)
            else:
                y = sum(signed(aa[row][t], iw)*signed(bb[t][col], iw) for t in range(k))
                status = 0
            ys.append(y)
            fs.append(status)
        outputs.append(pack(ys, ow))
        flags.append(pack(fs, 5))
    return dict(length=length, ar=ar, ac=ac, m=m, weights=bb, inputs=inputs,
                outputs=outputs, flags=flags, mode=mode, shadow=shadow,
                bad_last=bad_last, stalls=stalls)

def generate(c, dest, seed=20261105, random_cases=60):
    rng = random.Random(seed)
    r, n = c['ROWS'], c['COLS']
    maximum = c['MAX_K'] if c['DATAFLOW'] == 0 else c['MAX_M']
    cases = []
    for kind in ('zero', 'one', 'extreme'):
        for length in sorted(set((1, min(3, maximum), maximum))):
            cases.append(make_case(c, rng, length, r, n, kind=kind, stalls=0))
    if c['NUMERIC_MODE']:
        directed = [0x0000,0x8000,0x0001,0x03ff,0x0400,0x3c00,0xbc00,
                    0x3555,0x3c01,0x7bff,0xfbff,0x7c00,0xfc00,0x7e00,0x7d00]
        pairs = [(x,y) for x in directed for y in directed]
    elif c['INT_W'] <= 4:
        pairs = [(x,y) for x in range(1 << c['INT_W']) for y in range(1 << c['INT_W'])]
    else:
        pairs = [(x,y) for x in (0,1,127,128,255) for y in (0,1,127,128,255)]
    for pair in pairs:
        cases.append(make_case(c, rng, 1, 1, 1, pair=pair))
    for i in range(random_cases):
        length = rng.randint(1, min(maximum, 31))
        cases.append(make_case(c, rng, length, rng.randint(1,r), rng.randint(1,n),
                               kind='allbits' if i%3 == 0 else 'random'))
    cases.append(make_case(c, rng, min(maximum,7), r,n,bad_last=1))
    if c['DATAFLOW'] == 1:
        first = make_case(c,rng,min(maximum,31),r,n,shadow=1)
        next_weights = make_case(c,rng,1,r,n)['weights']
        first['shadow_weights'] = next_weights
        cases.append(first)
        cases.append(make_case(c,rng,min(maximum,19),r,n,b_override=next_weights,mode=2))
        cases.append(make_case(c,rng,min(maximum,13),r,n,b_override=next_weights,mode=1))
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    iw, ow = widths(c)
    with (dest/'vectors.txt').open('w') as f:
        f.write(f'{len(cases)}\n')
        for t in cases:
            f.write(' '.join(str(t[x]) for x in ('length','ar','ac','m','mode','shadow','bad_last','stalls'))+'\n')
            if c['DATAFLOW']:
                for row in t['weights']: f.write(f'{pack(row,iw):x}\n')
                if t['shadow']:
                    for row in t['shadow_weights']: f.write(f'{pack(row,iw):x}\n')
            for word in t['inputs']: f.write(f'{word:x}\n')
            for word, flags in zip(t['outputs'],t['flags']): f.write(f'{word:x} {flags:x}\n')
    info = dict(config=c, seed=seed, matrix_cases=len(cases),
                checked_results=sum(t['m']*n for t in cases),
                directed_operand_pairs=len(pairs), model='exact rational dot product + RNE once')
    (dest/'vectors.json').write_text(json.dumps(info,indent=2)+'\n')
    return info

if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('--package',default='rtl/sa_pkg.sv')
    p.add_argument('--out',default='build/vectors')
    p.add_argument('--seed',type=int,default=20261105)
    args = p.parse_args()
    print(json.dumps(generate(read_config(args.package),args.out,args.seed),indent=2))
