#!/usr/bin/env python3
"""Write a copy of a Dory GGUF with the per-weight scale constants folded into F32 tensors.

The graph then reads each folded vector directly and does not recompute it for every token.
The copy carries dory.scales_folded = true. The input file is not changed.
"""
import argparse, math, sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'gguf-py'))
import gguf

def to_f32(t):
    if t.tensor_type == gguf.GGMLQuantizationType.F32:
        return np.asarray(t.data, dtype=np.float32).reshape(-1)
    if t.tensor_type == gguf.GGMLQuantizationType.BF16:
        u = np.frombuffer(np.asarray(t.data).tobytes(), dtype=np.uint16).astype(np.uint32) << 16
        return u.view(np.float32)
    raise SystemExit(f'{t.name}: unsupported type {t.tensor_type.name}')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('input'); ap.add_argument('output')
    ap.add_argument('--no-head-norm', action='store_true', help='with --fused-norm: leave the per-head q and k norms unfused')
    ap.add_argument('--fused-norm', action='store_true', help='also write the 1/sqrt(n) norm vectors and fold 1/sqrt(head_dim) into attn_qk_scale')
    a = ap.parse_args()
    r = gguf.GGUFReader(a.input)
    arch = r.fields['general.architecture'].contents()
    kv = lambda k: r.fields[f'{arch}.{k}'].contents()
    if f'{arch}.scales_folded' in r.fields:
        raise SystemExit('input is already folded')
    init_std, alpha_init, gate_init = (np.float32(kv(k)) for k in ('init_std', 'alpha_init', 'gate_init'))
    n_embd = kv('embedding_length')
    hd = kv('attention.key_length')
    n_ff = kv('feed_forward_length'); n_ff = n_ff[0] if hasattr(n_ff, '__len__') else n_ff
    n_head = kv('attention.head_count'); n_head = n_head[0] if hasattr(n_head, '__len__') else n_head
    inv = lambda n: np.float32(1.0) / np.sqrt(np.float32(n))
    f = np.float32
    fold = {
        'residual_alpha':  lambda x: np.abs(x * f(alpha_init / init_std)),
        'attn_qk_scale':   (lambda x: np.square(x * f(math.sqrt(hd) / init_std)) * inv(hd)) if a.fused_norm and not a.no_head_norm else (lambda x: np.square(x * f(math.sqrt(hd) / init_std))),
        'attn_gate_scale': lambda x: np.square(x * f(math.sqrt(gate_init) / init_std)),
        'ffn_gate_scale':  lambda x: x * f(math.sqrt(n_embd)),
        'ffn_up_scale':    lambda x: x * f(math.sqrt(n_embd)),
    }
    def folded(t):
        key = t.name.split('.')[-2] if t.name.startswith('blk.') else t.name.rsplit('.', 1)[0]
        if key == 'output_scale':
            return to_f32(t) * f(1.0 / init_std)
        return fold[key](to_f32(t)) if key in fold else None

    w = gguf.GGUFWriter(a.output, arch=arch, endianess=r.endianess)
    for field in r.fields.values():
        if field.name == gguf.Keys.General.ARCHITECTURE or field.name.startswith('GGUF.'):
            continue
        vt = field.types[0]
        st = field.types[-1] if vt == gguf.GGUFValueType.ARRAY else None
        w.add_key_value(field.name, field.contents(), vt, sub_type=st)
    w.add_key_value(f'{arch}.scales_folded', True, gguf.GGUFValueType.BOOL)
    if a.fused_norm and not a.no_head_norm:
        w.add_key_value(f'{arch}.qk_norm_folded', True, gguf.GGUFValueType.BOOL)
    out = []
    for t in r.tensors:
        d = folded(t)
        if d is not None:
            d = d.astype(np.float32).reshape(tuple(int(x) for x in reversed(t.shape)))
            w.add_tensor_info(t.name, d.shape, d.dtype, d.nbytes, gguf.GGMLQuantizationType.F32)
        else:
            w.add_tensor_info(t.name, t.data.shape, t.data.dtype, t.data.nbytes, t.tensor_type)
        out.append(d if d is not None else t.data)
    if a.fused_norm:
        for n in sorted({int(n_embd), int(n_ff), int(n_head) * int(hd)} | (set() if a.no_head_norm else {int(hd)})):
            d = np.full((n,), inv(n), dtype=np.float32)
            w.add_tensor_info(f'dory_norm_scale.{n}', d.shape, d.dtype, d.nbytes, gguf.GGMLQuantizationType.F32)
            out.append(d)
    w.write_header_to_file(); w.write_kv_data_to_file(); w.write_ti_data_to_file()
    for d in out:
        w.write_tensor_data(d, tensor_endianess=r.endianess)
    w.close()
    print(f'folded -> {a.output}')

if __name__ == '__main__':
    main()
