from playwright.sync_api import sync_playwright
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from functools import partial
from pathlib import Path
import shutil
import threading
server=ThreadingHTTPServer(("127.0.0.1",0),partial(SimpleHTTPRequestHandler,directory=str(Path(__file__).resolve().parents[1] / "web")))
threading.Thread(target=server.serve_forever,daemon=True).start()
with sync_playwright() as p:
 b=p.chromium.launch(executable_path=shutil.which('chromium'),headless=True,args=['--no-sandbox'])
 page=b.new_page(viewport={'width':1920,'height':1080})
 errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.goto(f"http://127.0.0.1:{server.server_port}/index.html")
 page.evaluate('''() => {
 window.GetParentResourceName=()=> 'FiveEMS';window.requests=[];window.testOK=false;
 window.fetch=async(url,o)=>{requests.push(JSON.parse(o.body));return {json:async()=>({ok:testOK,message:'Falha simulada'})};};
 window.confirm=()=>{throw Error('Native confirm called');};
 state.open=true;state.context='creator';state.creatorView='edit';state.creatorTab='garages';state.creatorGarageSelectedId=8;
 state.bootstrap={isAdmin:true,departments:[]};state.department={id:2,name:'Hospital',points:[{id:8,department_id:2,type:'garage',label:'Garagem HSP',x:1,y:2,z:3,data:{spawns:[{x:10,y:20,z:30}],interaction:{kind:'marker'}}}]};
 root.classList.remove('hidden');render();
 }''')
 page.locator('[data-del-gspawn]').click();modal=page.locator('.garage-slot-modal');assert modal.is_visible()
 assert page.evaluate('document.querySelector("#deviceFrame").contains(document.querySelector(".garage-slot-modal"))')
 f=page.locator('#deviceFrame').bounding_box();m=modal.bounding_box();assert m['x']>=f['x'] and m['y']>=f['y'] and m['width']<=f['width']
 modal.locator('[data-cancel]').first.click();assert page.locator('.garage-slot-modal').count()==0
 assert page.evaluate('requests.length')==0
 page.locator('[data-del-gspawn]').click();modal.locator('[data-confirm]').click()
 page.get_by_role('alert').filter(has_text='Falha simulada').wait_for();assert modal.is_visible()
 assert page.evaluate('requests[0].expected.x')==10
 page.evaluate('testOK=true');modal.locator('[data-confirm]').click();page.wait_for_function('!document.querySelector(".garage-slot-modal")')
 assert page.evaluate('requests.length')==2
 assert not errors,errors
 print('PASS NUI: containment, cancel, failure, retry, server-confirmed success; no native confirm')
 b.close()
