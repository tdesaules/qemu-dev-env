#!/usr/bin/env python3
"""Offline regression: large provisioning files must not break Task subprocesses."""
import json
import base64
import gzip
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import unquote_to_bytes

ROOT = Path(__file__).resolve().parents[1]
for tool in ('kcl', 'task', 'jq', 'butane'):
    if not shutil.which(tool):
        raise SystemExit(f'Required test tool: {tool}')

with tempfile.TemporaryDirectory(prefix='qemu-task-metadata-') as directory:
    project = Path(directory)
    runtime = project / 'runtime'
    runtime.mkdir()
    for name in ('schema.k', 'templates.k', 'butane-render.k', 'task-config.k', 'taskfile.qemu.yaml'):
        shutil.copyfile(ROOT / name, runtime / name)
    shutil.copytree(ROOT / 'scripts', runtime / 'scripts')
    home = project / 'home'
    home.mkdir()
    bin_dir = project / 'bin'
    bin_dir.mkdir()
    # Exercise the real jq subprocess in the Beszel fallback without reading
    # workstation credentials or contacting a hub.
    for name, body in {'mise': "printf '{}\\n'", 'gopass': 'exit 1', 'curl': "printf '{}\\n'"}.items():
        executable = bin_dir / name
        executable.write_text('#!/bin/sh\n' + body + '\n')
        executable.chmod(0o755)
    env = {'PATH': str(bin_dir) + os.pathsep + os.environ['PATH'],
           'HOME': str(home), 'PWD': str(runtime), 'KCL_FILE_SCOPE': 'off'}
    identity = '00000000-0000-4000-8000-000000000001'
    (runtime / '.uuid').write_text(identity + '\n')
    # A copied template is deliberately much larger than Linux's 128-KiB limit.
    payload = ('{{ requiredEnv "FIXTURE_ONLY" }}\n' * 12000).encode()
    (runtime / 'payload.txt').write_bytes(payload)
    config = '''import .schema as schema
config = schema.Qemu {
    hardware.cpu = 6
    butane.custom_copies = [{source = "payload.txt", path = "/etc/fixture-payload"}]
    butane.units += [{name = "fixture.service", enabled = False, contents = "[Service]\\nExecStart=/usr/bin/true\\n"}]
}
'''
    (runtime / 'config.k').write_text(config)
    (project / 'taskfile.qemu.yaml').write_text('''version: "3"
includes:
  devenv:
    taskfile: ./runtime/taskfile.qemu.yaml
    dir: ./runtime
''')

    def run(args, cwd=runtime):
        return subprocess.check_output(args, cwd=cwd, env=env, text=True, timeout=60)

    arguments = ['--argument', f'taskfile_dir={runtime}', '--argument', 'qemu_butane_user_name=fixture',
                 '--argument', 'qemu_butane_user_id=1000', '--argument', 'qemu_host_arch=x86_64',
                 '--argument', 'qemu_host_os=linux', '--argument', 'github_token=']
    full = run(['kcl', 'config.k', '--format', 'json', *arguments])
    assert len(full.encode()) > 128 * 1024
    metadata = run(['kcl', 'task-config.k', '--format', 'json', *arguments])
    assert len(metadata.encode()) < 16 * 1024
    actual = json.loads(metadata)['config']
    expected = json.loads(full)['config']
    for key in ('uuid', 'workspace', 'os', 'checksum', 'hardware', 'command'):
        assert actual[key] == expected[key], key
    assert actual['butane'] == {'github': {'token': ''}}
    for cwd, name in ((runtime, 'status'), (project, 'devenv:status')):
        status = json.loads(run(['task', '-t', 'taskfile.qemu.yaml', name], cwd=cwd))
        assert status['status'] == 'stopped' and status['id'] == identity
        assert status['config']['cpu'] == '6'
    rendered = run(['kcl', 'butane-render.k', '--path_selector', 'butane', *arguments])
    butane = runtime / 'fixture.bu'
    butane.write_text(rendered)
    ignition = json.loads(run(['butane', '--strict', str(butane)]))
    copied = next(f for f in ignition['storage']['files'] if f['path'] == '/etc/fixture-payload')
    source = copied['contents']['source']
    header, encoded = source.split(',', 1)
    assert header.startswith('data:')
    content = base64.b64decode(encoded) if header.endswith(';base64') else unquote_to_bytes(encoded)
    if copied['contents'].get('compression') == 'gzip':
        content = gzip.decompress(content)
    assert content == payload
    assert any(u['name'] == 'fixture.service' for u in ignition['systemd']['units'])
    # Optional hub settings and GitHub token retain their Task-facing shape.
    (runtime / 'config.k').write_text(config.replace('hardware.cpu = 6', '''hardware.cpu = 6
    butane.github.token = "fixture-github-token"
    butane.beszel = {url = "http://127.0.0.1:8090", token = "not-task-metadata"}'''))
    with_hub = json.loads(run(['kcl', 'task-config.k', '--format', 'json', *arguments]))['config']['butane']
    assert with_hub == {'github': {'token': 'fixture-github-token'}, 'beszel': {'url': 'http://127.0.0.1:8090'}}
    (runtime / 'config.k').write_text(config.replace('hardware.cpu = 6', 'hardware.cpu = 6\n    butane.beszel = {}'))
    default_hub = json.loads(run(['kcl', 'task-config.k', '--format', 'json', *arguments]))['config']['butane']
    assert default_hub['beszel'] == {'url': ''}
    # KCL errors must propagate rather than become a successful empty projection.
    (runtime / 'config.k').write_text('config = invalid syntax\n')
    invalid = subprocess.run(['task', '-t', 'taskfile.qemu.yaml', 'status'], cwd=runtime,
                             env=env, capture_output=True, text=True, timeout=60)
    assert invalid.returncode != 0
    # The existing config-not-created-yet fallback must still work.
    (runtime / 'config.k').unlink()
    run(['task', '-t', 'taskfile.qemu.yaml', '--list'])
    print(f'PASS: {len(full.encode())} bytes of full config -> {len(metadata.encode())} bytes of Task metadata; '
          'standalone/included status, full Ignition payload, optional settings and failure propagation verified.')
