use kuchiki::traits::TendrilSink;
use mdictlib::MdxFile;
use rusqlite::{Connection, params};
use serde::Deserialize;
use std::{env, error::Error, fs::File, io::{BufWriter, Write}};

#[derive(Deserialize)]
struct EcdictRow {
    word: String,
    definition: String,
    translation: String,
}

fn main() -> Result<(), Box<dyn Error>> {
    let mut arguments = env::args().skip(1);
    let source = arguments.next().ok_or("missing MDX path")?;
    let destination = arguments.next().ok_or("missing output path")?;
    if source == "--ecdict" {
        let csv_path = destination;
        let database_path = arguments.next().ok_or("missing database path")?;
        let mut reader = csv::Reader::from_path(csv_path)?;
        let mut database = Connection::open(database_path)?;
        database.execute_batch("PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; CREATE TABLE entries(word TEXT PRIMARY KEY COLLATE NOCASE, zh TEXT NOT NULL, en TEXT NOT NULL);")?;
        let transaction = database.transaction()?;
        let mut statement = transaction.prepare("INSERT OR IGNORE INTO entries VALUES (?1, ?2, ?3)")?;
        let mut count = 0;
        for row in reader.deserialize::<EcdictRow>() {
            let row = row?;
            let word = row.word.trim();
            if word.is_empty() || word.len() > 90 || (row.translation.is_empty() && row.definition.is_empty()) {
                continue;
            }
            count += statement.execute(params![word, row.translation.replace("\\n", "\n"), row.definition.replace("\\n", "\n")])?;
        }
        drop(statement);
        transaction.commit()?;
        println!("imported {count} ECDICT entries");
        return Ok(());
    }
    if source == "--collins" {
        let mdx_path = destination;
        let database_path = arguments.next().ok_or("missing database path")?;
        let dictionary = MdxFile::open(mdx_path)?;
        let mut database = Connection::open(database_path)?;
        database.execute_batch("PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; CREATE TABLE entries(word TEXT PRIMARY KEY COLLATE NOCASE, html TEXT NOT NULL);")?;
        let transaction = database.transaction()?;
        let mut statement = transaction.prepare("INSERT OR IGNORE INTO entries VALUES (?1, ?2)")?;
        let mut count = 0;
        for entry in dictionary.entries() {
            let entry = entry?;
            if entry.text().starts_with("@@@LINK=") { continue; }
            let document = kuchiki::parse_html().one(entry.text());
            if let Ok(content) = document.select_first(".collins_content") {
                if let Ok(extras) = content.as_node().select(".addon, .synonym, .tts_button, .icon-speak-form, .def_cn.cn_after") {
                    let extras = extras.map(|item| item.as_node().clone()).collect::<Vec<_>>();
                    for extra in extras { extra.detach(); }
                }
                count += statement.execute(params![entry.key().trim(), content.as_node().to_string()])?;
            }
        }
        drop(statement);
        transaction.commit()?;
        println!("imported {count} Collins entries");
        return Ok(());
    }
    let dictionary = MdxFile::open(source)?;
    let mut output = BufWriter::new(File::create(destination)?);
    for entry in dictionary.entries() {
        let entry = entry?;
        serde_json::to_writer(&mut output, &(entry.key(), entry.text()))?;
        output.write_all(b"\n")?;
    }
    Ok(())
}
