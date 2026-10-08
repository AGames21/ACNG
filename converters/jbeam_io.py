"""Tolerant JBeam reader: JSON plus comments, optional commas and trailing commas.

Original code. Output is plain JSON, which BeamNG also reads.
"""
import json
import re

_TOKEN = re.compile(r'''
    (?P<ws>\s+|//[^\n]*|/\*.*?\*/)
  | (?P<str>"(?:[^"\\]|\\.)*")
  | (?P<num>[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)
  | (?P<lit>true|false|null)
  | (?P<punct>[{}\[\]:,])
''', re.S | re.X)


def _tokens(text):
    pos = 0
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            raise ValueError(f'Unexpected JBeam text at {pos}: {text[pos:pos + 30]!r}')
        pos = m.end()
        kind = m.lastgroup
        if kind != 'ws':
            yield kind, m.group(kind)


def loads(text):
    toks = list(_tokens(text))
    i = 0

    def value():
        nonlocal i
        kind, tok = toks[i]
        i += 1
        if kind == 'str':
            return json.loads(tok)
        if kind == 'num':
            f = float(tok)
            return int(f) if re.fullmatch(r'[-+]?\d+', tok) else f
        if kind == 'lit':
            return {'true': True, 'false': False, 'null': None}[tok]
        if tok == '[':
            out = []
            while True:
                while toks[i][1] == ',':
                    i += 1
                if toks[i][1] == ']':
                    i += 1
                    return out
                out.append(value())
        if tok == '{':
            out = {}
            while True:
                while toks[i][1] == ',':
                    i += 1
                if toks[i][1] == '}':
                    i += 1
                    return out
                key = value()
                if toks[i][1] != ':':
                    raise ValueError(f'Expected ":" after key {key!r}')
                i += 1
                out[str(key)] = value()
        raise ValueError(f'Unexpected token {tok!r}')

    result = value()
    return result


def dumps(data):
    return json.dumps(data, indent=1, ensure_ascii=True)
