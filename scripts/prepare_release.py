#!/usr/bin/env python3
"""Generate the website and app legal resource from one reviewed policy source."""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
config = json.loads((ROOT / 'release/config.json').read_text())
legal = json.loads((ROOT / 'release/legal.json').read_text())
# Empty values remain visibly unconfigured in development. The release gate rejects them.
values = {key: value or f'[Configure {key.replace("_", " ")} before release]' for key, value in config.items()}
rendered = {kind: {'title': doc['title'], 'sections': [[title, text.format(**values)] for title, text in doc['sections']]} for kind, doc in legal.items()}
(ROOT / 'TikDog/Resources/Legal.json').write_text(json.dumps(rendered, indent=2) + '\n')
for kind, doc in rendered.items():
    sections = ''.join(f'<section><h2>{html.escape(title)}</h2><p>{html.escape(text)}</p></section>' for title, text in doc['sections'])
    page = f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{html.escape(doc['title'])} · TikDog</title><style>body{{margin:0;background:#faf8f4;color:#21201d;font:17px/1.65 system-ui}}main{{max-width:760px;margin:60px auto;padding:24px}}a{{color:#8a3e10}}h1{{font-size:40px;line-height:1.15}}h2{{font-size:22px;margin-top:36px}}nav{{display:flex;gap:20px}}small{{color:#625f58}}</style><main><small>TIKDOG · DOGS FIRST. ALWAYS.</small><h1>{html.escape(doc['title'])}</h1><nav><a href="privacy.html">Privacy</a><a href="terms.html">Terms</a><a href="support.html">Support</a></nav>{sections}</main></html>'''
    (ROOT / f'website/{kind}.html').write_text(page + '\n')
keys = {'operator_name':'TIKDOG_OPERATOR_NAME','support_email':'TIKDOG_SUPPORT_EMAIL','privacy_url':'TIKDOG_PRIVACY_URL','terms_url':'TIKDOG_TERMS_URL','support_url':'TIKDOG_SUPPORT_URL'}
lines = ['// Generated from release/config.json by scripts/prepare_release.py.']
for key, setting in keys.items():
    value = config[key] or ''
    if any(ch in value for ch in '\n\r"$'):
        raise SystemExit(f'Invalid characters in {key}')
    lines.append(f'{setting} = {value.replace("https://", "https:/$()/")}')
(ROOT / 'Config/Release.xcconfig').write_text('\n'.join(lines) + '\n')
print('Generated app policies, website pages, and public release configuration.')
