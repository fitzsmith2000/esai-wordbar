from bs4 import BeautifulSoup
from readmdict import MDX
from pathlib import Path
import argparse
import sqlite3
parser = argparse.ArgumentParser(description='Convert a locally owned Collins COBUILD MDX for esai单词')
parser.add_argument('source', type=Path, help='Path to local .mdx file')
parser.add_argument('--output', type=Path, default=Path.home() / 'Library/Application Support/esai-wordbar/dictionaries/collins.sqlite')
args = parser.parse_args()
source = args.source
target = args.output
target.parent.mkdir(parents=True, exist_ok=True)
connection = sqlite3.connect(target)
connection.execute('CREATE TABLE IF NOT EXISTS entries(word TEXT PRIMARY KEY COLLATE NOCASE, html TEXT NOT NULL)')
count = 0
batch = []
for raw_word, raw_html in MDX(str(source)).items():
    word = raw_word.decode('utf-8', 'replace').strip()
    html = raw_html.decode('utf-8', 'replace').strip()
    if not word or html.startswith('@@@LINK='):
        continue
    soup = BeautifulSoup(html, 'html.parser')
    content = soup.select_one('.collins_content')
    if content is None:
        continue
    for extra in content.select('.addon, .synonym, .tts_button, .icon-speak-form'):
        extra.decompose()
    for duplicate in content.select('.def_cn.cn_after'):
        duplicate.decompose()
    batch.append((word, str(content)))
    if len(batch) >= 1000:
        connection.executemany('INSERT OR REPLACE INTO entries VALUES (?, ?)', batch)
        connection.commit()
        count += len(batch)
        batch.clear()
connection.executemany('INSERT OR REPLACE INTO entries VALUES (?, ?)', batch)
connection.commit()
print('entries:', count + len(batch), 'bytes:', target.stat().st_size)
print('hut:', connection.execute('SELECT length(html) FROM entries WHERE word=?', ('hut',)).fetchone())
