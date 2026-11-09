#!/usr/bin/env python3
"""Real Sparkle tests in disposable app bundles. Never touches esai单词 settings/apps."""
import base64
import functools
import http.server
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
runtime = pathlib.Path(subprocess.check_output(['zsh',str(ROOT/'Scripts/fetch-sparkle.sh')],text=True).strip())
key = pathlib.Path.home()/'.config/esai-wordbar/updates/ed25519.seed'
if not key.is_file():
    raise SystemExit('Integration tests require the local release signing key (not committed).')
info = plistlib.loads((ROOT/'Info.plist').read_bytes())
public_key = info['SUPublicEDKey']
signer = str(runtime/'bin/sign_update')
probe = ROOT/'build/update-probe'
subprocess.run(['swiftc','-swift-version','5','-target','arm64-apple-macos13.0','-F',str(runtime),'-framework','Sparkle','-framework','AppKit','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',str(ROOT/'Tests/UpdateProbe.swift'),'-o',str(probe)],check=True)

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*args): pass

with tempfile.TemporaryDirectory(prefix='esai-update-tests-') as directory:
    stage = pathlib.Path(directory)
    server = http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Handler,directory=directory))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    base = f'http://127.0.0.1:{server.server_port}'
    def bundle(path,identifier,build,mode,result,feed):
        contents = path/'Contents'
        (contents/'MacOS').mkdir(parents=True)
        (contents/'Frameworks').mkdir()
        shutil.copy2(probe,contents/'MacOS/UpdateProbe')
        subprocess.run(['ditto',str(runtime/'Sparkle.framework'),str(contents/'Frameworks/Sparkle.framework')],check=True)
        config = dict(CFBundleIdentifier=identifier,CFBundleName='esai单词 Update Test',CFBundleExecutable='UpdateProbe',CFBundlePackageType='APPL',CFBundleVersion=str(build),CFBundleShortVersionString=f'0.8.{build-14}',LSMinimumSystemVersion='13.0',LSUIElement=True,SUFeedURL=feed,SUPublicEDKey=public_key,SURequireSignedFeed=True,SUVerifyUpdateBeforeExtraction=True,SUEnableAutomaticChecks=False,SUAutomaticallyUpdate=True,SUAllowsAutomaticUpdates=True,SUSendProfileInfo=False,ProbeMode=mode,ProbeResult=str(result),NSAppTransportSecurity={'NSAllowsLocalNetworking':True})
        (contents/'Info.plist').write_bytes(plistlib.dumps(config))
        subprocess.run(['codesign','--force','--sign','-',str(path)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    def sign(path):
        return subprocess.check_output([signer,'--ed-key-file',str(key),'-p',str(path)],text=True).strip()
    def feed(path,archive):
        signature = sign(archive)
        ns='http://www.andymatuschak.org/xml-namespaces/sparkle'
        ET.register_namespace('sparkle',ns)
        root=ET.Element('rss',{'version':'2.0'})
        channel=ET.SubElement(root,'channel')
        ET.SubElement(channel,'title').text='Isolated esai updater test'
        item=ET.SubElement(channel,'item')
        ET.SubElement(item,'title').text='Fixture release'
        ET.SubElement(item,f'{{{ns}}}version').text='15'
        ET.SubElement(item,f'{{{ns}}}shortVersionString').text='0.8.1'
        ET.SubElement(item,f'{{{ns}}}minimumSystemVersion').text='13.0'
        ET.SubElement(item,'enclosure',{'url':f'{base}/{archive.name}','type':'application/octet-stream','length':str(archive.stat().st_size),f'{{{ns}}}edSignature':signature})
        ET.ElementTree(root).write(path,encoding='utf-8',xml_declaration=True)
        sign(path)
        return signature
    def run(case,mode,build=14,tampered=False,missing=False):
        identifier='com.esai.updater-test-'+uuid.uuid4().hex
        root=stage/case
        root.mkdir()
        result=root/'result.txt'
        feed_path=stage/f'{case}.xml'
        feed_url=f'{base}/{feed_path.name}'
        baseline=root/'esai 更新测试.app'
        candidate=root/'candidate/esai 更新测试.app'
        bundle(candidate,identifier,15,'installed',result,feed_url)
        archive=stage/f'{case}.zip'
        subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(candidate),str(archive)],check=True)
        signature=feed(feed_path,archive)
        if tampered:
            feed_path.write_bytes(feed_path.read_bytes().replace(b'Fixture release',b'Tampered update'))
        if missing: feed_path.unlink()
        bundle(baseline,identifier,build,mode,result,feed_url)
        output=open(root/'process.log','wb')
        process=subprocess.Popen([str(baseline/'Contents/MacOS/UpdateProbe')],stdout=output,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+60
            while time.monotonic()<deadline and not result.exists(): time.sleep(0.2)
            if not result.exists():
                raise AssertionError(f'{case}: timeout; '+(root/'process.log').read_text(errors='replace'))
            message=result.read_text()
            print(case+': '+message,flush=True)
            assert message.startswith('PASS'), (root/'process.log').read_text(errors='replace')
            if mode=='install':
                installed=plistlib.loads((baseline/'Contents/Info.plist').read_bytes())
                assert installed['CFBundleVersion']=='15','Bundle was not replaced'
                subprocess.run(['codesign','--verify','--deep','--strict',str(baseline)],check=True)
                assert process.wait(timeout=5)==0,'Old process did not quit cleanly'
            return archive,signature
        finally:
            if process.poll() is None: process.terminate(); process.wait(timeout=5)
            output.close()
            subprocess.run(['defaults','delete',identifier],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            cache=pathlib.Path.home()/'Library/Caches'/identifier
            if cache.is_dir(): shutil.rmtree(cache)
    if '--published-only' in sys.argv:
        identifier='com.esai.updater-test-'+uuid.uuid4().hex
        result=stage/'published-result.txt'
        baseline=stage/'Published Feed Probe.app'
        bundle(baseline,identifier,int(info['CFBundleVersion']),'current',result,info['SUFeedURL'])
        process=subprocess.Popen([str(baseline/'Contents/MacOS/UpdateProbe')],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        try:
            output=process.communicate(timeout=60)[0].decode(errors='replace')
            print(output,flush=True)
            assert process.returncode==0 and result.read_text().startswith('PASS'),output
        finally:
            if process.poll() is None: process.kill(); process.wait()
            subprocess.run(['defaults','delete',identifier],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            cache=pathlib.Path.home()/'Library/Caches'/identifier
            if cache.is_dir(): shutil.rmtree(cache)
    else:
        run('new-version','found')
        run('already-current','current',build=15)
        run('newer-than-feed','current',build=16)
        run('tampered-feed','error',tampered=True)
        run('unavailable-feed','error',missing=True)
        archive,signature=run('automatic-install','install')
        subprocess.run(['swift',str(ROOT/'Scripts/verify-update.swift'),public_key,str(archive),signature],check=True)
        archive.write_bytes(archive.read_bytes()+b'tampered')
        rejected=subprocess.run(['swift',str(ROOT/'Scripts/verify-update.swift'),public_key,str(archive),signature],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        assert rejected.returncode!=0,'Tampered archive accepted'
        print('tampered-archive: PASS signature rejected',flush=True)
    server.shutdown()
print('PASS all updater integration checks',flush=True)
