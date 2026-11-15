"""gate_flip.py <dir> <base> <other>...: per file pair, the max same-token logprob delta BEFORE the first argmax flip, and the base top-2 margin at the flip."""
import json, sys
d = sys.argv[1]
L = lambda n: json.load(open(f'{d}/{n}.json', encoding='utf-8'))
for base, other in zip(sys.argv[2::2], sys.argv[3::2]):
    a, b = L(base), L(other)
    m, flip = 0.0, None
    for i, (x, y) in enumerate(zip(a['completion_probabilities'], b['completion_probabilities'])):
        yb = {t['token']: t['logprob'] for t in y['top_logprobs']}
        for t in x['top_logprobs']:
            if t['token'] in yb: m = max(m, abs(t['logprob'] - yb[t['token']]))
        if x['top_logprobs'][0]['token'] != y['top_logprobs'][0]['token']:
            tl = x['top_logprobs']; flip = (i, round(tl[0]['logprob'] - tl[1]['logprob'], 4)); break
    print(f'{other:18s} vs {base:14s} max_delta_before_flip={m:.4f} flip(at, base_margin)={flip}')
