#!/usr/bin/env python3
"""Render only independent fixture windows; never send desktop input or activate an app."""
import argparse
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path, help='A new directory for fixture screenshots and measurements')
    parser.add_argument('--color-picker', action='store_true', help='Verify native color Popover close/reopen lifecycle instead of the layout matrix')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    settings = json.loads(subprocess.check_output([
        'xcodebuild', '-project', str(repo / 'StatPeek.xcodeproj'), '-scheme', 'StatPeek',
        '-configuration', 'Release', '-showBuildSettings', '-json'], cwd=repo))
    build = next(item['buildSettings'] for item in settings if item['target'] == 'StatPeek')
    runner = Path(build['TARGET_BUILD_DIR']) / 'StatPeekLayoutVerification'
    runner.parent.mkdir(parents=True, exist_ok=True)
    sources = ['SettingsViewController', 'GlassSurfaceView', 'ModuleSymbolView', 'Metrics', 'MetricSelection',
               'StatusStripLayout', 'StatusStripView', 'SystemSampler', 'LoginItemController', 'DashboardPresentationController',
               'DiskHistory', 'DiskHistoryStore', 'DiskHistoryViewController']
    fixture = 'verify-color-lifecycle.swift' if args.color_picker else 'verify-layout.swift'
    command = ['swiftc', '-swift-version', '6', '-parse-as-library', str(repo / 'scripts' / fixture)]
    command += [str(repo / 'StatPeek' / (name + '.swift')) for name in sources]
    for framework in ['AppKit', 'Charts', 'SwiftUI', 'IOKit', 'ServiceManagement']:
        command += ['-framework', framework]
    command += ['-l', 'sqlite3', '-o', str(runner)]
    try:
        subprocess.run(command, check=True, cwd=repo)
        with (output / 'runner.log').open('w') as log:
            process = subprocess.Popen([str(runner), str(output)], stdout=log, stderr=subprocess.STDOUT)
            seen = set()
            try:
                while process.poll() is None:
                    state = output / 'state.json'
                    if state.exists():
                        record = json.loads(state.read_text())  # Swift writes this file atomically.
                        if record['sequence'] not in seen:
                            subprocess.run(['screencapture', '-x', '-l', str(record['window']),
                                            str(output / (record['name'] + '.png'))], check=True)
                            seen.add(record['sequence'])
                            (output / ('ack-' + str(record['sequence']))).touch()
                    time.sleep(.03)
                if process.returncode:
                    raise RuntimeError((output / 'runner.log').read_text())
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait()
        result = json.loads((output / 'result.json').read_text())
        if args.color_picker:
            assert len(result['states']) == 12 and len(seen) == 12
            assert not result['posted_input_events'] and result['native_color_model']
            for state in result['states']:
                assert state['parent_visible'] and state['picker_visible'] and state['picker_shown']
                assert state['parent_closed'] and state['picker_closed'] and state['well_deactivated']
                assert not state['app_in_foreground'] and not state['is_key'] and not state['is_main']
            print(f'12 native color Popover lifecycle checks passed without desktop input: {output}')
            return
        assert len(result['states']) == 20 and len(seen) == 20
        assert result['arrowless_panel'] and result['rapid_toggles'] == 200 and not result['delayed_reopen']
        for state in result['states']:
            assert not state['is_key'] and not state['is_main'] and state['ignores_mouse']
            assert not state['app_in_foreground']
            assert abs(state['viewport_height'] - (state['actual_height'] - 126)) < .5
            assert state['scrolling'] == (state['document_height'] > state['viewport_height'] + .5)
            assert state['actual_height'] <= state['limit']
            if state['name'].endswith('bottom'):
                assert abs(state['offset'] - (state['document_height'] - state['viewport_height'])) < .5
        print(f'20 independent window states captured without desktop input: {output}')
    finally:
        runner.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
