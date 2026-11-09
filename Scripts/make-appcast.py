#!/usr/bin/env python3
"""Sign a release archive and feed. Private keys stay outside the repository."""
import argparse
import email.utils
import pathlib
import plistlib
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('archive', type=pathlib.Path)
parser.add_argument('--notes', default='改进与修复请参阅 GitHub Release。')
parser.add_argument('--key', type=pathlib.Path, default=pathlib.Path.home()/'.config/esai-wordbar/updates/ed25519.seed')
parser.add_argument('--output', type=pathlib.Path, default=ROOT/'updates/appcast-arm64.xml')
args = parser.parse_args()
info = plistlib.loads((ROOT/'Info.plist').read_bytes())
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
archive = args.archive.resolve()
if archive.name != f'esai-wordbar-{version}-apple-silicon.zip':
    parser.error('Archive filename must match the current app version')
with zipfile.ZipFile(archive) as package:
    root_plists = [entry for entry in package.infolist() if entry.filename.endswith('.app/Contents/Info.plist') and entry.filename.count('/') == 2]
    if len(root_plists) != 1:
        parser.error('Update archive must contain exactly one top-level app')
    packaged_info = plistlib.loads(package.read(root_plists[0]))
for field in ('CFBundleVersion','CFBundleShortVersionString','CFBundleIdentifier','SUPublicEDKey'):
    if packaged_info[field] != info[field]:
        parser.error(f'Packaged {field} does not match the release source')
if not args.key.is_file():
    parser.error('Update signing key is missing; restore the original key. Do not rotate it for an existing app.')
if args.key.stat().st_mode & 0o077:
    parser.error('Signing key must be private (chmod 600)')
sparkle = subprocess.check_output(['zsh',str(ROOT/'Scripts/fetch-sparkle.sh')],text=True).strip()
signer = str(pathlib.Path(sparkle)/'bin/sign_update')
signature = subprocess.check_output([signer,'--ed-key-file',str(args.key),'-p',str(archive)],text=True).strip()
subprocess.run(['swift',str(ROOT/'Scripts/verify-update.swift'),info['SUPublicEDKey'],str(archive),signature],check=True)
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle',ns)
root = ET.Element('rss',{'version':'2.0'})
channel = ET.SubElement(root,'channel')
ET.SubElement(channel,'title').text = 'esai单词 updates (Apple Silicon)'
ET.SubElement(channel,'link').text = 'https://github.com/fitzsmith2000/esai-wordbar'
ET.SubElement(channel,'description').text = 'Stable signed updates for esai单词.'
item = ET.SubElement(channel,'item')
ET.SubElement(item,'title').text = f'esai单词 {version}'
ET.SubElement(item,'pubDate').text = email.utils.formatdate(usegmt=True)
ET.SubElement(item,f'{{{ns}}}version').text = build
ET.SubElement(item,f'{{{ns}}}shortVersionString').text = version
ET.SubElement(item,f'{{{ns}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
ET.SubElement(item,'description').text = args.notes
ET.SubElement(item,'enclosure',{
    'url':f'https://github.com/fitzsmith2000/esai-wordbar/releases/download/v{version}/{archive.name}',
    'length':str(archive.stat().st_size), 'type':'application/octet-stream',
    f'{{{ns}}}edSignature':signature,
})
# Preserve recent releases so a later OS requirement bump has a supported fallback.
if args.output.exists():
    old = ET.parse(args.output).getroot()
    for previous in old.findall('./channel/item')[:9]:
        if previous.findtext(f'{{{ns}}}version') != build:
            channel.append(previous)
ET.indent(root)
args.output.parent.mkdir(parents=True,exist_ok=True)
ET.ElementTree(root).write(args.output,encoding='utf-8',xml_declaration=True)
subprocess.run([signer,'--ed-key-file',str(args.key),str(args.output)],check=True)
subprocess.run([signer,'--verify','--ed-key-file',str(args.key),str(args.output)],check=True)
print(args.output)
