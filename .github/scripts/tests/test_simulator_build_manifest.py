import importlib.util
import tempfile
from pathlib import Path
import subprocess
import unittest

spec=importlib.util.spec_from_file_location('manifest',Path(__file__).parents[1]/'simulator_build_manifest.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


class BuildCompatibilityTests(unittest.TestCase):
    def test_only_shipped_inputs_change_application_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            def git(*args): return subprocess.check_output(['git','-C',directory,*args],stderr=subprocess.DEVNULL)
            git('init');git('config','user.name','CI test');git('config','user.email','ci@example.invalid')
            (root/'lib').mkdir();(root/'lib/main.dart').write_text('original')
            (root/'test').mkdir();(root/'test/qa.dart').write_text('first test')
            git('add','.');git('commit','-m','app')
            def tree():return git('ls-tree','-r','-z','HEAD','--',*module.APP_PATHS)
            original=tree()
            (root/'test/qa.dart').write_text('updated test');git('add','.');git('commit','-m','qa')
            self.assertEqual(tree(),original)
            (root/'lib/main.dart').write_text('changed app');git('add','.');git('commit','-m','app change')
            self.assertNotEqual(tree(),original)

    def expected(self):
        return {'schema':1,'application_hash':'tree','configuration':{'flutter':'3.38.1','sdk':'27.1','mode':'debug'},'fingerprint':'key'}

    def test_completed_matching_archive_is_compatible(self):
        expected=self.expected();saved=expected|{'build_completed':True,'archive_sha256':'bytes','source_commit':'older QA-only commit'}
        module.validate_manifest(saved,expected,'bytes')

    def test_different_toolchain_is_not_compatible(self):
        expected=self.expected();saved=expected|{'configuration':{'sdk':'26.2'},'build_completed':True,'archive_sha256':'bytes'}
        with self.assertRaisesRegex(ValueError,'configuration'):module.validate_manifest(saved,expected,'bytes')

    def test_incomplete_or_corrupt_archive_cannot_pass(self):
        expected=self.expected()
        for saved,checksum in [(expected|{'build_completed':False,'archive_sha256':'bytes'},'bytes'),(expected|{'build_completed':True,'archive_sha256':'bytes'},'corrupted')]:
            with self.assertRaises(ValueError):module.validate_manifest(saved,expected,checksum)

    def test_different_application_revision_is_not_compatible(self):
        expected=self.expected();saved=expected|{'application_hash':'other','build_completed':True,'archive_sha256':'bytes'}
        with self.assertRaisesRegex(ValueError,'application_hash'):module.validate_manifest(saved,expected,'bytes')
