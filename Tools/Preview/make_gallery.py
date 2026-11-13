#!/usr/bin/env python3
"""Build a local review UI for the real SDK frames exported by CharacterPreview.

No network, model, rendering approximation or alternate motion implementation.
The motion player only replays captured frames at their recorded sample times.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('frames', type=Path, help='Directory containing exported index.json and frames')
    args = parser.parse_args()
    root = args.frames.resolve()
    data = json.loads((root/'index.json').read_text())
    for group in data:
        for frame in group['frames']:
            target = (root/frame['path']).resolve()
            if root not in target.parents or not target.is_file():
                raise ValueError(f"Missing or unsafe frame: {frame['path']}")
    payload = json.dumps(data, ensure_ascii=False).replace('<', '\\u003c')
    document = TEMPLATE.replace('__FRAME_DATA__', payload)
    (root/'index.html').write_text(document, encoding='utf-8')
    print(f"Created {root/'index.html'} ({sum(len(g['frames']) for g in data)} real SDK frames)")


TEMPLATE = r'''<!doctype html><html lang="ko"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>CharacterKit · 실제 렌더링 검토</title>
<style>
:root{font:16px/1.6 system-ui,sans-serif;color:#202a28;background:#f4f5f1}*{box-sizing:border-box}
body{max-width:1200px;margin:0 auto;padding:48px 24px 80px}h1{font-size:42px;letter-spacing:-1.8px;line-height:1.15;margin:12px 0 18px}h2{font-size:23px;margin:36px 0 12px}p{max-width:860px;color:#56645f}small{color:#60736c}.eyebrow{font-weight:700;letter-spacing:2px;color:#39796b}button,select,input{font:inherit}button,select{padding:9px 16px;border:1px solid #ced9d0;border-radius:12px;background:white;color:#202a28}button{cursor:pointer}button:focus-visible,select:focus-visible,input:focus-visible{outline:3px solid #28765e;outline-offset:4px}.row{display:flex;gap:12px;align-items:center;flex-wrap:wrap}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px}.card{padding:12px;border:1px solid #dce2d8;border-radius:20px;background:#fafbf8}.card img{display:block;width:100%;aspect-ratio:1;object-fit:contain}.card figcaption{font-size:14px;text-align:center}.card{margin:0}.stage{display:grid;grid-template-columns:minmax(260px,420px) 1fr;align-items:center;gap:30px;background:#e6eee5;border-radius:26px;padding:24px}.stage img{width:100%;aspect-ratio:1;object-fit:contain}input[type=range]{width:100%;accent-color:#39796b}output{display:block;overflow-wrap:anywhere;max-width:560px;font-size:14px;min-height:90px}.note{padding:16px 20px;background:#fffaf0;border-left:3px solid #ad915b;border-radius:6px}body.dark{background:#17211e;color:#e0e8e0}.dark p,.dark small{color:#b3c5b8}.dark .card{background:#293830;border-color:#49574c}.dark .stage{background:#2b3d32}.dark .note{background:#3b372b}button[aria-pressed=true]{background:#dcece1}footer{margin-top:44px;font-size:14px;color:#667467}@media(max-width:640px){body{padding:28px 14px}h1{font-size:34px}.stage{grid-template-columns:1fr;padding:16px;gap:12px}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.card{padding:6px}output{min-height:60px}}
</style>
<div class="eyebrow">CHARACTERKIT / RENDER REVIEW</div>
<h1>하나의 상태. 같은 감정.<br>새로운 SEMI.</h1>
<p>캐릭터 이미지를 새로 생성한 목업이 아닙니다. 실제 <code>ReactiveCharacter.pose → CharacterSceneBuilder → renderer</code> 출력과 <code>CharacterPresentationSession</code>의 전환 샘플입니다.</p>
<p class="note" id="backend"></p>
<div class="row"><button id="backdrop" aria-pressed="false">배경 밝기 전환</button><small>배경 전환은 대비 검토용이며 SDK의 테마 설정을 바꾸지 않습니다.</small></div>
<h2>감정과 외형</h2>
<div class="row"><label for="theme">외형</label><select id="theme"></select><small>기본 · 쓰기 · 12개 감정</small></div>
<div class="grid" id="emotions" style="margin-top:20px"></div>
<h2>모션과 중단·복귀</h2>
<div class="stage"><img id="motionImage" alt="선택한 실제 모션 프레임"><div>
<label for="motion">검토할 시퀀스</label><select id="motion" style="width:100%;margin:10px 0"></select>
<div class="row"><button id="play" aria-pressed="false">재생</button><span id="time"></span></div>
<label for="frame">프레임</label><input id="frame" type="range" min="0" value="0" aria-label="모션 프레임">
<output id="caption"></output><small>자동 재생하지 않습니다. 슬라이더·방향키로 정확한 프레임을 검토할 수 있습니다.</small>
</div></div><footer>캡처된 시퀀스의 재생입니다. 브라우저 재생 속도는 iPhone·Mac 네이티브 성능 측정치가 아닙니다. 입력 이벤트 이름과 실제 enum 값은 원문 그대로 표시합니다.</footer>
<script>
const groups=__FRAME_DATA__;
const $=id=>document.getElementById(id), themes=groups.filter(x=>x.kind==='emotions'), motions=groups.filter(x=>x.kind==='motion');
const first=groups[0].frames[0].path;
$('backend').textContent=first.endsWith('.svg')?'검증 경로: SDK의 실제 SVG를 브라우저에서 표시합니다. SwiftUI Canvas·ImageRenderer·실기기 접근성 검증은 이 화면으로 대체되지 않습니다.':'검증 경로: SDK의 네이티브 PNG 출력입니다. 화면 조작·VoiceOver·에너지 검증까지 완료했다는 뜻은 아닙니다.';
const names={semi:'SEMI 문서 고양이',black:'Black',white:'White',arcade:'Arcade',cat:'Animated Cat','cat-simple':'Simple Cat',norwegian:'Norwegian Forest',portrait:'Portrait',girl:'Bob Girl','flower-girl':'Flower Girl',boy:'Short Hair Boy','capped-boy':'Capped Boy','boy-three-quarter':'Three-quarter Boy'};
for(const g of themes){const o=new Option(names[g.id]||g.label,g.id);$('theme').add(o)}
for(const g of motions)$('motion').add(new Option(g.label,g.id));
function showTheme(){const g=themes.find(x=>x.id===$('theme').value);$('emotions').replaceChildren(...g.frames.map(f=>{const card=document.createElement('figure');card.className='card';const im=document.createElement('img');im.src=f.path;im.alt=f.label;im.loading='lazy';const caption=document.createElement('figcaption');caption.textContent=f.label;card.append(im,caption);return card}))}
let playing=false,start=0,position=0;function group(){return motions.find(x=>x.id===$('motion').value)}
function showFrame(index){const f=group().frames[index];$('frame').value=index;$('motionImage').src=f.path;$('motionImage').alt=f.label;$('time').textContent=f.time.toFixed(3)+' s';$('caption').textContent=f.label;position=f.time}
function stop(){playing=false;$('play').textContent='재생';$('play').setAttribute('aria-pressed','false')}
function selectMotion(){stop();$('frame').max=group().frames.length-1;showFrame(0)}
function animate(now){if(!playing)return;const fs=group().frames,duration=fs.at(-1).time+0.25,t=((now-start)/1000)%duration;let i=0;while(i+1<fs.length&&fs[i+1].time<=t)i++;showFrame(i);requestAnimationFrame(animate)}
$('play').onclick=()=>{if(playing){stop();return}playing=true;start=performance.now()-position*1000;$('play').textContent='일시정지';$('play').setAttribute('aria-pressed','true');requestAnimationFrame(animate)};
$('theme').onchange=showTheme;$('motion').onchange=selectMotion;$('frame').oninput=()=>{stop();showFrame(Number($('frame').value))};
$('backdrop').onclick=()=>{$('backdrop').setAttribute('aria-pressed',String(document.body.classList.toggle('dark')))};
document.addEventListener('visibilitychange',()=>{if(document.hidden)stop()});
showTheme();selectMotion();
</script></html>'''

if __name__ == '__main__':
    main()
