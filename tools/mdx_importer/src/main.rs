use mdictlib::MdxFile;
use std::{env, error::Error, fs::File, io::{BufWriter, Write}};

fn main() -> Result<(), Box<dyn Error>> {
    let mut arguments = env::args().skip(1);
    let source = arguments.next().ok_or("missing MDX path")?;
    let destination = arguments.next().ok_or("missing output path")?;
    let dictionary = MdxFile::open(source)?;
    let mut output = BufWriter::new(File::create(destination)?);
    for entry in dictionary.entries() {
        let entry = entry?;
        serde_json::to_writer(&mut output, &(entry.key(), entry.text()))?;
        output.write_all(b"\n")?;
    }
    Ok(())
}
