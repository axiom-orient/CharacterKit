#!/usr/bin/env python3
"""Encode frames captured by the real native showcase view; never redraw characters."""
import argparse
import html
import json
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('capture_directory', type=Path)
parser.add_argument('output_directory', type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
source = args.capture_directory.resolve()
output = args.output_directory.resolve()
output.mkdir(parents=True, exist_ok=True)
video = output / 'all-characters.mp4'
if video.exists():
    parser.error('Output video already exists; use a new output directory')
records = json.loads((source / 'observations.json').read_text())
characters = json.loads((source / 'characters.json').read_text())
if not records:
    parser.error('Capture manifest is empty')
lines = []
phases = []
start = records[0]['captureUptime']
last_phase = None
for i, record in enumerate(records):
    name = record['frame']
    if Path(name).name != name or not name.endswith('.png'):
        parser.error('Invalid frame path')
    path = source / name
    if not path.is_file():
        parser.error(f'Missing captured frame: {name}')
    if "'" in str(path) or '\n' in str(path):
        parser.error('Unsupported quote/newline in input path')
    duration = (records[i + 1]['captureUptime'] - record['captureUptime']) if i + 1 < len(records) else 0.15
    if duration <= 0:
        parser.error('Non-monotonic capture timestamps')
    lines += [f"file '{path}'", f'duration {duration:.6f}']
    if record['phase'] != last_phase:
        phases.append({'label': record['phase'], 'seconds': record['captureUptime'] - start,
                       'frame': name})
        last_phase = record['phase']
lines.append(f"file '{source / records[-1]['frame']}'")
concat = output / 'captured-frames.ffconcat'
concat.write_text('\n'.join(lines) + '\n')
subprocess.run(['ffmpeg', '-v', 'error', '-f', 'concat', '-safe', '0', '-i', str(concat),
                '-r', '12', '-fps_mode', 'cfr', '-c:v', 'libx264', '-preset', 'medium',
                '-crf', '19', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(video)], check=True)
concat.unlink()
shutil.copy2(source / 'overview.png', output / 'overview.png')
manifest = {'source': 'Native NSHostingView/CALayer capture of the real public SDK views',
            'sdk_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
            'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo, text=True).strip()),
            'characters': len(characters), 'inventory': characters, 'captured_frames': len(records),
            'capture_duration_seconds': records[-1]['captureUptime'] - start,
            'phases': phases,
            'limitations': ['Capture cadence is lower than the live app; this is functional visual evidence, not a frame-performance trace.']}
(output / 'evidence.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
# A local review page makes the long recording navigable without recreating its renderer.
buttons = ''.join(f'<button data-time="{p["seconds"]:.3f}">{html.escape(p["label"])}</button>' for p in phases)
html = '''<!doctype html><html lang="ko"><meta charset="utf-8"><title>CharacterKit 전체 시연</title>
<style>body{font:16px system-ui;margin:24px;background:#f0f2f6;color:#20242b;max-width:1200px}video{width:100%;max-height:78vh;background:white;border-radius:12px}nav{display:flex;flex-wrap:wrap;gap:6px;margin:16px 0}button{border:1px solid #bbc3d0;border-radius:7px;padding:8px;background:white;cursor:pointer}p{line-height:1.6}.note{background:#fff4db;padding:14px;border-radius:8px}</style>
<h1>CharacterKit · CHARACTER_COUNT종 실제 앱 시연</h1><p>실제 SDK 뷰에 동일한 호스트 이벤트를 입력한 화면입니다. 아래 버튼으로 검증 단계로 이동할 수 있습니다.</p>
<video controls preload="metadata" src="all-characters.mp4" poster="overview.png"></video><nav>BUTTONS</nav>
<p class="note">화면 저장 간격 때문에 이 영상으로 실제 프레임 성능을 판정할 수는 없습니다.</p>
<script>const v=document.querySelector('video');document.querySelectorAll('button').forEach(b=>b.onclick=()=>{v.currentTime=Number(b.dataset.time);v.play()});</script></html>'''
(output / 'index.html').write_text(html.replace('BUTTONS', buttons).replace('CHARACTER_COUNT', str(len(characters))))
print(json.dumps({'video': str(video), 'bytes': video.stat().st_size, 'phases': len(phases),
                  'frames': len(records), 'duration': manifest['capture_duration_seconds']}, ensure_ascii=False))
