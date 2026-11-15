"""gate_cmp.py <dir> <base> <tag>: print the max same-token logprob delta and text equality per mode and prompt."""
import json, sys
d, base, tag = sys.argv[1:4]
L = lambda n: json.load(open(f'{d}/{n}.json', encoding='utf-8'))
for mode in ('nf', 'f'):
    for p in ('short', 'long'):
        a, b = L(f'{base}-{mode}-{p}'), L(f'{tag}-{mode}-{p}')
        m = 0.0
        for x, y in zip(a['completion_probabilities'], b['completion_probabilities']):
            yb = {t['token']: t['logprob'] for t in y['top_logprobs']}
            for t in x['top_logprobs']:
                if t['token'] in yb: m = max(m, abs(t['logprob'] - yb[t['token']]))
        print(f'{mode:2s} {p:5s} text_equal={a["content"]==b["content"]} max_dlogprob={m:.5f} prompt_n={b["timings"]["prompt_n"]}')
