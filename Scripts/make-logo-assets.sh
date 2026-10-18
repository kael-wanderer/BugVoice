#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 -I - <<'PY'
from pathlib import Path
import concurrent.futures, os, re, subprocess, tempfile
source = Path('docs/design/logo-options.html').read_text()
ids = ['wave-bug','antenna-mic','caret-bubble','wave-b','option-wave','firefly','ladybug-level','bee-bars','sound-rings','hud-pill','quote-wave','non-la','keycap-mic','code-bug','voice-v']
defs = re.search(r'<defs>(.*?)</defs>', source, re.S).group(1)
chrome = os.environ.get('CHROME', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
Path('App/Icons').mkdir(exist_ok=True)
Path('App/MenuBarIcons').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='bugvoice-logos-') as work:
    work = Path(work)
    jobs = []
    for number, name in enumerate(ids, 1):
        for kind, size, suffix in [('app',1024,''), ('menu',18,''), ('menu',36,'@2x')]:
            symbol = re.search(r'<symbol id="'+kind+str(number)+r'" viewBox="([^"]+)">(.*?)</symbol>', source, re.S)
            svg = work / f'{kind}{number}-{size}.svg'
            svg.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{symbol[1]}" width="{size}" height="{size}" style="color:black"><defs>{defs}</defs>{symbol[2]}</svg>')
            html = svg.with_suffix('.html')
            html.write_text(f'<html><body style="margin:0;background:transparent"><img src="{svg.as_uri()}" width="{size}" height="{size}" style="display:block"></body></html>')
            output = Path('App/Icons' if kind=='app' else 'App/MenuBarIcons') / (name+suffix+'.png')
            jobs.append((html, output.resolve(), size))
    def render(job):
        html, output, size = job
        with tempfile.TemporaryDirectory(dir=work) as profile:
            subprocess.run([chrome,'--headless=new','--disable-gpu','--hide-scrollbars','--force-device-scale-factor=1','--default-background-color=00000000',f'--user-data-dir={profile}',f'--window-size={size},{size}',f'--screenshot={output}',html.as_uri()], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(render, jobs))
print('Wrote 15 app icons and 30 menu glyphs.')
PY
