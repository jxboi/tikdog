#!/usr/bin/env python3
"""Fail closed before archiving; external launch evidence is intentionally explicit."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import sys
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--online', action='store_true', help='Fetch the configured public policy/support pages')
parser.add_argument('--archive', action='store_true', help='Also require real launch evidence and Apple signing configuration')
parser.add_argument('--bundle', type=Path, help='Check values in a built app Info.plist')
args = parser.parse_args()
config_digest = hashlib.sha256((ROOT/'release/config.json').read_bytes()).hexdigest()
errors = []
def public_key(value):
    if value.startswith('sb_publishable_'): return len(value)>15
    try:
        parts=value.split('.')
        return len(parts)==3 and json.loads(base64.urlsafe_b64decode(parts[1]+'='*((4-len(parts[1])%4)%4)))['role']=='anon'
    except (ValueError,KeyError,TypeError): return False

config = json.loads((ROOT / 'release/config.json').read_text())
legal=json.loads((ROOT/'release/legal.json').read_text())
values={key: value or f'[Configure {key.replace("_", " ")} before release]' for key,value in config.items()}
expected={kind:{'title':doc['title'],'sections':[[title,text.format(**values)]for title,text in doc['sections']]}for kind,doc in legal.items()}
if json.loads((ROOT/'TikDog/Resources/Legal.json').read_text())!=expected: errors.append('Generated app policies are stale; run scripts/prepare_release.py')

required = ['operator_name','support_email','website_url','privacy_url','terms_url','support_url','moderation_owner']
for field in required:
    if not isinstance(config.get(field), str) or not config[field].strip(): errors.append(f'Set {field} in release/config.json')
if config.get('support_email') and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', config['support_email']): errors.append('Set a valid support email')
for field in ['website_url','privacy_url','terms_url','support_url']:
    value = config.get(field)
    if value and (not value.startswith('https://') or any(x in value.lower() for x in ['example.com','localhost','your-domain','placeholder'])): errors.append(f'{field} must be a real public HTTPS URL')
if config['terms_version'] != '2026-10-18' or config['minimum_age'] != 16 or config['moderation_response_hours'] != 24:
    errors.append('Terms version, minimum age or moderation commitment changed; update server/client policy and verify together')
# No server secret may enter iOS build settings or resources.
secrets=ROOT/'Config/Secrets.xcconfig'
if secrets.exists():
    match=re.search(r'^SUPABASE_PUBLISHABLE_KEY\s*=\s*(\S+)',secrets.read_text(),re.M)
    if match and not public_key(match[1]): errors.append('Client Supabase key must be a publishable or anon key; server credentials are forbidden')

secret_names = ['SUPABASE_SERVICE_ROLE_KEY', 'APPLE_PRIVATE_KEY', 'APPLE_CLIENT_SECRET', 'FACEBOOK_APP_SECRET', 'FACEBOOK_CLIENT_SECRET']
for file in [ROOT/'Config/App.xcconfig',ROOT/'Config/Release.xcconfig',ROOT/'Config/Secrets.xcconfig',ROOT/'TikDog/Resources/Info.plist']:
    if file.exists() and any(name in file.read_text() for name in secret_names): errors.append(f'Server secret setting in client file {file.relative_to(ROOT)}')
if args.bundle:
    with (args.bundle/'Info.plist').open('rb') as f: info = plistlib.load(f)
    mapping = {'operator_name':'TIKDOG_OPERATOR_NAME','support_email':'TIKDOG_SUPPORT_EMAIL','privacy_url':'TIKDOG_PRIVACY_URL','terms_url':'TIKDOG_TERMS_URL','support_url':'TIKDOG_SUPPORT_URL'}
    for field,key in mapping.items():
        if info.get(key) != config.get(field): errors.append(f'Built {key} does not match release configuration')
    if not str(info.get('SUPABASE_URL','')).startswith('https://') or not public_key(str(info.get('SUPABASE_PUBLISHABLE_KEY',''))): errors.append('Built app requires live Supabase URL and public key')
    if '[Configure ' in (args.bundle/'Legal.json').read_text(): errors.append('Built policies still contain unconfigured operator details')
if args.online:
    before_online = len(errors)
    for kind in ['privacy','terms','support']:
        url = config.get(kind+'_url')
        if not url: continue
        try:
            with urlopen(Request(url, headers={'User-Agent':'TikDog-Release-Check/1.0'}), timeout=20) as r:
                page = r.read().decode('utf-8')
                if r.status!=200 or config['support_email'] not in page or '[Configure ' in page: errors.append(f'{kind} page is incomplete')
        except Exception as e: errors.append(f'{kind} page unavailable: {type(e).__name__}')
    if len(errors)==before_online and not errors:
        (ROOT/'.build-artifacts').mkdir(exist_ok=True)
        (ROOT/'.build-artifacts/public-policy-check.json').write_text(json.dumps({'passed':True,'verified_at':datetime.now(timezone.utc).isoformat(),'config_sha256':config_digest,'urls':{key:config[key] for key in ['privacy_url','terms_url','support_url']}}))
if args.archive:
    for field,key in {'operator_name':'TIKDOG_OPERATOR_NAME','support_email':'TIKDOG_SUPPORT_EMAIL','privacy_url':'TIKDOG_PRIVACY_URL','terms_url':'TIKDOG_TERMS_URL','support_url':'TIKDOG_SUPPORT_URL'}.items():
        if os.environ.get(key)!=config.get(field): errors.append(f'Archive {key} must match the public release configuration')
    proof=ROOT/'.build-artifacts/public-policy-check.json'
    try:
        policy_proof=json.loads(proof.read_text())
        age=(datetime.now(timezone.utc)-datetime.fromisoformat(policy_proof['verified_at'])).total_seconds()
        if policy_proof.get('passed') is not True or policy_proof.get('config_sha256')!=config_digest or not 0<=age<=7*86400: raise ValueError()
    except (OSError,ValueError,KeyError,TypeError): errors.append('Verify current public policy pages with --online within 7 days of archiving')
    if not os.environ.get('DEVELOPMENT_TEAM'): errors.append('Set DEVELOPMENT_TEAM from your Apple Developer membership')
    if not os.environ.get('SUPABASE_URL','').startswith('https://') or not public_key(os.environ.get('SUPABASE_PUBLISHABLE_KEY','')): errors.append('Configure the production backend for the archive')
    evidence_path = ROOT/'release/live-evidence.json'
    if not evidence_path.exists(): errors.append('Run live smoke verification and record hardware, Facebook, Apple, and moderation launch checks in release/live-evidence.json')
    else:
        evidence=json.loads(evidence_path.read_text())
        for check in ['live_backend','apple_signin_and_revocation','facebook_signin_and_deletion','physical_device_camera_and_permissions','testflight_install','moderation_staffed','privacy_labels_and_age_rating','audit_retention_job']:
            if not isinstance(evidence.get(check),dict) or evidence[check].get('passed') is not True or not evidence[check].get('evidence'): errors.append(f'Missing verified launch check: {check}')
        if evidence.get('config_sha256')!=config_digest: errors.append('Launch evidence belongs to different release configuration')
        if evidence.get('backend_url')!=os.environ.get('SUPABASE_URL') or evidence.get('bundle_id')!=os.environ.get('PRODUCT_BUNDLE_IDENTIFIER'):
            errors.append('Launch evidence must match the actual archive backend URL and bundle identifier')
        live=ROOT/'.build-artifacts/live-smoke.json'
        try:
            smoke=json.loads(live.read_text())
            if smoke.get('passed') is not True or smoke.get('backend_url')!=os.environ.get('SUPABASE_URL') or len(smoke.get('checks',[]))<14: raise ValueError()
        except (OSError,ValueError,TypeError): errors.append('Missing successful live smoke artifact for the archive backend')
for error in errors: print('BLOCKED: '+error)
if errors:
    print(f'{len(errors)} release requirement(s) remain. Development builds are still supported.')
    sys.exit(1)
print('Release configuration checks passed. This is not an App Store approval guarantee.')
