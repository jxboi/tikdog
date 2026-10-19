#!/usr/bin/env python3
"""Behavior checks for the archive gate using an isolated fixture, never the real release settings."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parent.parent
class ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='tikdog-gate-')
        self.root=Path(self.temp.name)
        for folder in ['scripts','release','Config','TikDog/Resources']:(self.root/folder).mkdir(parents=True)
        for file in ['scripts/check_release.py','scripts/prepare_release.py','release/config.json','release/legal.json','TikDog/Resources/Info.plist','Config/App.xcconfig']:
            shutil.copyfile(SOURCE/file,self.root/file)
    def tearDown(self):self.temp.cleanup()
    def run_gate(self,*args,env=None):
        return subprocess.run(['python3',str(self.root/'scripts/check_release.py'),*args],capture_output=True,text=True,env=env)
    def configure(self):
        config=json.loads((self.root/'release/config.json').read_text())
        config.update(operator_name='Fixture Operator',support_email='support@fixture.invalid',website_url='https://fixture.invalid',privacy_url='https://fixture.invalid/privacy.html',terms_url='https://fixture.invalid/terms.html',support_url='https://fixture.invalid/support.html',moderation_owner='Fixture moderator')
        (self.root/'release/config.json').write_text(json.dumps(config))
        (self.root/'website').mkdir(exist_ok=True)
        subprocess.run(['python3',str(self.root/'scripts/prepare_release.py')],check=True,capture_output=True)
    def test_missing_operator_identity_blocks(self):
        self.configure()
        config=json.loads((self.root/'release/config.json').read_text());config['operator_name']=None
        (self.root/'release/config.json').write_text(json.dumps(config))
        result=self.run_gate();self.assertNotEqual(result.returncode,0);self.assertIn('operator_name',result.stdout)
    def test_configured_development_check_passes_but_archive_requires_real_evidence(self):
        self.configure();self.assertEqual(self.run_gate().returncode,0)
        result=self.run_gate('--archive',env={**os.environ,'DEVELOPMENT_TEAM':'','SUPABASE_URL':'','SUPABASE_PUBLISHABLE_KEY':''})
        self.assertNotEqual(result.returncode,0);self.assertIn('DEVELOPMENT_TEAM',result.stdout);self.assertIn('live smoke',result.stdout)
    def test_evidence_for_another_backend_and_truthy_strings_cannot_pass(self):
        self.configure()
        import hashlib
        checks=['live_backend','apple_signin_and_revocation','facebook_signin_and_deletion','physical_device_camera_and_permissions','testflight_install','moderation_staffed','privacy_labels_and_age_rating','audit_retention_job']
        evidence={key:{'passed':'false','evidence':'fixture'} for key in checks}
        evidence.update(config_sha256=hashlib.sha256((self.root/'release/config.json').read_bytes()).hexdigest(),backend_url='https://old.supabase.co',bundle_id='com.tikdog.app')
        (self.root/'release/live-evidence.json').write_text(json.dumps(evidence))
        result=self.run_gate('--archive',env={**os.environ,'DEVELOPMENT_TEAM':'ABCDEFGHIJ','SUPABASE_URL':'https://new.supabase.co','SUPABASE_PUBLISHABLE_KEY':'sb_publishable_fixture','PRODUCT_BUNDLE_IDENTIFIER':'com.tikdog.app'})
        self.assertNotEqual(result.returncode,0);self.assertIn('actual archive backend',result.stdout);self.assertIn('Missing verified launch check',result.stdout);self.assertIn('public policy pages',result.stdout)
    def test_complete_matching_fixture_can_pass_archive_gate(self):
        self.configure()
        import hashlib
        from datetime import datetime,timezone
        config=json.loads((self.root/'release/config.json').read_text())
        digest=hashlib.sha256((self.root/'release/config.json').read_bytes()).hexdigest()
        checks=['live_backend','apple_signin_and_revocation','facebook_signin_and_deletion','physical_device_camera_and_permissions','testflight_install','moderation_staffed','privacy_labels_and_age_rating','audit_retention_job']
        evidence={key:{'passed':True,'evidence':'test fixture only'} for key in checks}
        evidence.update(config_sha256=digest,backend_url='https://fixture.supabase.co',bundle_id='com.tikdog.app')
        (self.root/'release/live-evidence.json').write_text(json.dumps(evidence))
        artifacts=self.root/'.build-artifacts';artifacts.mkdir()
        (artifacts/'public-policy-check.json').write_text(json.dumps({'passed':True,'verified_at':datetime.now(timezone.utc).isoformat(),'config_sha256':digest}))
        (artifacts/'live-smoke.json').write_text(json.dumps({'passed':True,'backend_url':'https://fixture.supabase.co','checks':['fixture']*14}))
        env={**os.environ,'DEVELOPMENT_TEAM':'ABCDEFGHIJ','SUPABASE_URL':'https://fixture.supabase.co','SUPABASE_PUBLISHABLE_KEY':'sb_publishable_fixture','PRODUCT_BUNDLE_IDENTIFIER':'com.tikdog.app',**{key:config[field] for field,key in {'operator_name':'TIKDOG_OPERATOR_NAME','support_email':'TIKDOG_SUPPORT_EMAIL','privacy_url':'TIKDOG_PRIVACY_URL','terms_url':'TIKDOG_TERMS_URL','support_url':'TIKDOG_SUPPORT_URL'}.items()}}
        result=self.run_gate('--archive',env=env);self.assertEqual(result.returncode,0,result.stdout+result.stderr)
    def test_client_server_key_is_rejected_without_printing_the_secret(self):
        self.configure();secret='sb_secret_do_not_print_this'
        (self.root/'Config/Secrets.xcconfig').write_text('SUPABASE_PUBLISHABLE_KEY = '+secret)
        result=self.run_gate();self.assertNotEqual(result.returncode,0);self.assertNotIn(secret,result.stdout);self.assertIn('server credentials are forbidden',result.stdout)
    def test_stale_generated_policy_blocks(self):
        self.configure();legal=json.loads((self.root/'release/legal.json').read_text());legal['privacy']['title']='Changed policy'
        (self.root/'release/legal.json').write_text(json.dumps(legal));result=self.run_gate()
        self.assertNotEqual(result.returncode,0);self.assertIn('stale',result.stdout)
if __name__=='__main__':unittest.main()
