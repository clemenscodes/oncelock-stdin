use std::io::{self, BufRead, BufReader};
use std::sync::{Arc, Mutex, OnceLock};

pub struct InputOutput {
  stdin: Box<dyn BufRead + Send>,
}

impl InputOutput {
  pub fn new(stdin: Box<dyn BufRead + Send>) -> Self {
    Self { stdin }
  }
}

impl std::fmt::Debug for InputOutput {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    let _ = f.debug_struct("InputOutput");
    Ok(())
  }
}

static IO: OnceLock<Arc<Mutex<InputOutput>>> = OnceLock::new();

fn init_io(stdin: Box<dyn BufRead + Send>) {
  if let Some(existing) = IO.get() {
    let mut io = existing.lock().unwrap();
    *io = InputOutput::new(stdin);
  } else {
    IO.set(Arc::new(Mutex::new(InputOutput::new(stdin))))
      .unwrap();
  }
}

fn get_io() -> Arc<Mutex<InputOutput>> {
  IO.get().expect("Global input not initialized").clone()
}

fn main() {
  println!("Initializing with stdin...");

  let stdin = io::stdin();
  init_io(Box::new(BufReader::new(stdin)));

  println!("Type something and press Enter:");

  {
    let io = get_io();
    let mut io = io.lock().unwrap();
    let mut line = String::new();
    io.stdin.read_line(&mut line).unwrap();
    println!("Received from stdin: {}", line.trim());
  }

  println!("Switching to file input...");

  if let Ok(file) = std::fs::File::open("example.txt") {
    init_io(Box::new(BufReader::new(file)));
    let io = get_io();
    let mut io = io.lock().unwrap();
    let mut line = String::new();
    io.stdin.read_line(&mut line).unwrap();
    println!("Received from file: {}", line.trim());
  } else {
    println!("File 'example.txt' not found.");
  }

  println!("Switching to mock input...");

  use std::io::Cursor;
  init_io(Box::new(Cursor::new("This is mock input\nAnother line")));

  {
    let io = get_io();
    let mut io = io.lock().unwrap();
    let mut line = String::new();
    io.stdin.read_line(&mut line).unwrap();
    println!("Received from mock input: {}", line.trim());
  }
}
