use std::fmt;
use std::io::{self, BufRead, BufReader};
use std::sync::{Arc, Mutex, OnceLock};

struct DebuggableReader(Box<dyn BufRead + Send>);

impl fmt::Debug for DebuggableReader {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    write!(f, "DebuggableReader(Box<dyn BufRead>)")
  }
}

static INPUT: OnceLock<Arc<Mutex<DebuggableReader>>> = OnceLock::new();

fn init_reader<R>(reader: R)
where
  R: BufRead + Send + 'static,
{
  if let Some(existing) = INPUT.get() {
    let mut locked_reader = existing.lock().unwrap();
    *locked_reader = DebuggableReader(Box::new(reader));
  } else {
    INPUT
      .set(Arc::new(Mutex::new(DebuggableReader(Box::new(reader)))))
      .unwrap();
  }
}

fn get_reader() -> Arc<Mutex<DebuggableReader>> {
  INPUT.get().expect("Global input not initialized").clone()
}

fn main() {
  println!("Initializing with stdin...");
  let stdin = io::stdin();
  init_reader(BufReader::new(stdin));

  println!("Type something and press Enter:");
  {
    let reader = get_reader();
    let mut reader = reader.lock().unwrap();
    let mut line = String::new();
    reader.0.read_line(&mut line).unwrap();
    println!("Received from stdin: {}", line.trim());
  }

  println!("Switching to file input...");
  if let Ok(file) = std::fs::File::open("example.txt") {
    init_reader(BufReader::new(file));

    let reader = get_reader();
    let mut reader = reader.lock().unwrap();
    let mut line = String::new();
    reader.0.read_line(&mut line).unwrap();
    println!("Received from file: {}", line.trim());
  } else {
    println!("File 'example.txt' not found.");
  }

  println!("Switching to mock input...");
  use std::io::Cursor;
  init_reader(Cursor::new("This is mock input\nAnother line"));

  {
    let reader = get_reader();
    let mut reader = reader.lock().unwrap();
    let mut line = String::new();
    reader.0.read_line(&mut line).unwrap();
    println!("Received from mock input: {}", line.trim());
  }
}
