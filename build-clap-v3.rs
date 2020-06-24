use clap::crate_name;
use clap::derive::IntoApp;
use clap_generate::{generate, generators};
use std::env;
use std::fs::{self, File};
use std::path::Path;

// This file must export a struct named `Args` with `#[derive(Clap)]`.
include!("src/cli.rs");

fn main() {
    let mut app = Args::into_app();
    let name = crate_name!();

    // https://doc.rust-lang.org/cargo/reference/build-scripts.html#outputs-of-the-build-script
    let outdir = env::var_os("OUT_DIR").expect("failed to find OUT_DIR");
    fs::create_dir_all(&outdir).expect("failed to create dirs for OUT_DIR");

    // Create a stamp file. (This is used by CI to help find the OUT_DIR.)
    fs::write(Path::new(&outdir).join("repgrep-stamp"), "").unwrap();

    let f = |name: &str| File::create(Path::new(&outdir).join(name)).unwrap();

    generate::<generators::Zsh, _>(&mut app, name, &mut f(&format!("_{}", name)));
    generate::<generators::Bash, _>(&mut app, name, &mut f(&format!("{}.bash", name)));
    generate::<generators::Fish, _>(&mut app, name, &mut f(&format!("{}.fish", name)));
    generate::<generators::Elvish, _>(&mut app, name, &mut f(&format!("{}.elvish", name)));
    generate::<generators::PowerShell, _>(&mut app, name, &mut f(&format!("{}.ps1", name)));
}
