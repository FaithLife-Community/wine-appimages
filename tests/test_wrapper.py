import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TestRuntimeDispatch(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='wine runtime ')
        self.addCleanup(self.temp.cleanup)
        self.appdir = Path(self.temp.name) / 'AppDir'
        for directory in ('bin', 'usr/bin', 'usr/libexec'):
            (self.appdir / directory).mkdir(parents=True, exist_ok=True)
        self.env = dict(os.environ, APPDIR=str(self.appdir), WINEPREFIX=str(self.appdir / 'prefix'))
        self.env.pop('APPIMAGE', None)
        self.env.pop('ARGV0', None)
        self.probe('usr/bin/wine', 'wine')
        self.probe('usr/bin/wineserver', 'wineserver')
        self.probe('usr/libexec/winetricks', 'winetricks')

    def probe(self, relative, name):
        path = self.appdir / relative
        path.write_text('#!/usr/bin/env python3\nimport json,os,sys\n'
                        f'print(json.dumps(dict(program={name!r},args=sys.argv[1:],'
                        'wine=os.environ.get("WINE"),server=os.environ.get("WINESERVER"),'
                        'prefix=os.environ.get("WINEPREFIX"))))\n')
        path.chmod(0o755)

    def run_wrapper(self, *args, invocation=None):
        if invocation:
            self.env['ARGV0'] = invocation
        return subprocess.run(['bash', str(ROOT / 'appimage/wrapper'), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def result(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_od_appimage_symlink_dispatches_arial_to_winetricks(self):
        self.env['APPIMAGE'] = '/downloads/Wine.AppImage'
        result = self.result(self.run_wrapper('-q', 'arial', invocation='/install/bin/winetricks'))
        self.assertEqual(result['program'], 'winetricks')
        self.assertEqual(result['args'], ['-q', 'arial'])
        self.assertEqual(result['wine'], str(self.appdir / 'usr/bin/wine'))
        self.assertEqual(result['server'], str(self.appdir / 'usr/bin/wineserver'))

    def test_explicit_winetricks_command_uses_same_script(self):
        result = self.result(self.run_wrapper('winetricks', '--version'))
        self.assertEqual(result['program'], 'winetricks')
        self.assertEqual(result['args'], ['--version'])

    def test_missing_winetricks_is_not_sent_to_windows_loader(self):
        (self.appdir / 'usr/libexec/winetricks').unlink()
        result = self.run_wrapper('-q', 'arial', invocation='winetricks')
        self.assertEqual(result.returncode, 127)
        self.assertIn('Bundled Winetricks is missing', result.stderr)
        self.assertEqual(result.stdout, '')

    def test_wineserver_without_arguments_is_not_given_winecfg(self):
        result = self.result(self.run_wrapper(invocation='wineserver'))
        self.assertEqual(result['program'], 'wineserver')
        self.assertEqual(result['args'], [])

    def test_wine64_uses_wine_when_build_has_no_separate_loader(self):
        result = self.result(self.run_wrapper('--version', invocation='wine64'))
        self.assertEqual(result['program'], 'wine')
        self.assertEqual(result['args'], ['--version'])

    def test_default_without_arguments_still_opens_winecfg(self):
        result = self.result(self.run_wrapper())
        self.assertEqual(result['program'], 'wine')
        self.assertEqual(result['args'], ['winecfg'])

    def test_extracted_bundle_entry_points_work_through_external_symlinks(self):
        # Simulate generated AppRun; the public launchers must preserve the entry
        # name and locate the actual bundle even through OD's external symlinks.
        shutil.copy(ROOT / 'appimage/wrapper', self.appdir / 'wrapper')
        apprun = self.appdir / 'AppRun'
        apprun.write_text('#!/bin/sh\nexec bash "$APPDIR/wrapper" "$@"\n')
        apprun.chmod(0o755)
        for entry, program, args in [('winetricks', 'winetricks', ['-q', 'arial']),
                                     ('wine', 'wine', ['--version']),
                                     ('wine64', 'wine', ['--version']),
                                     ('wineserver', 'wineserver', ['-w'])]:
            with self.subTest(entry=entry):
                target = self.appdir / 'bin' / entry
                shutil.copy(ROOT / 'appimage/runtime-entry', target)
                target.chmod(0o755)
                link = Path(self.temp.name) / entry
                link.symlink_to(target)
                env = dict(self.env)
                env.pop('APPDIR', None)
                result = self.result(subprocess.run([str(link), *args], env=env,
                                                   capture_output=True, text=True, timeout=10))
                self.assertEqual(result['program'], program)
                self.assertEqual(result['args'], args)
                self.assertEqual(result['prefix'], self.env['WINEPREFIX'])

    def test_install_entries_after_builder_has_removed_bin(self):
        (self.appdir / 'bin').rmdir()
        subprocess.run(['bash', str(ROOT / 'appimage/add-entry-points.sh'), str(self.appdir)], check=True)
        for entry in ('wine', 'wine64', 'wineserver', 'winetricks'):
            self.assertTrue(os.access(self.appdir / 'bin' / entry, os.X_OK))

    def test_install_entries_preserves_loader_with_merged_usr_layout(self):
        (self.appdir / 'bin').rmdir()
        (self.appdir / 'bin').symlink_to('usr/bin')
        original = (self.appdir / 'usr/bin/wine').read_bytes()
        subprocess.run(['bash', str(ROOT / 'appimage/add-entry-points.sh'), str(self.appdir)], check=True)
        self.assertFalse((self.appdir / 'bin').is_symlink())
        self.assertEqual((self.appdir / 'usr/bin/wine').read_bytes(), original)
        self.assertTrue(os.access(self.appdir / 'bin/winetricks', os.X_OK))


if __name__ == '__main__':
    unittest.main()
