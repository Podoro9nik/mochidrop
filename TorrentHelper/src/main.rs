use std::{env, fs, path::PathBuf, time::Duration};

use librqbit::{AddTorrent, AddTorrentOptions, Session};

const MAX_TORRENT_BYTES: usize = 8 * 1024 * 1024;

#[tokio::main]
async fn main() {
    if env::args().nth(1).as_deref() == Some("--version") {
        println!("mochidrop-torrent 1.0.0");
        return;
    }
    if let Err(error) = run().await {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

async fn run() -> Result<(), String> {
    let mut args = env::args().skip(1);
    let source = args.next().ok_or("Usage: mochidrop-torrent SOURCE DESTINATION")?;
    let destination = args.next().ok_or("Missing destination")?;
    if args.next().is_some() {
        return Err("Too many arguments".into());
    }
    let destination = PathBuf::from(destination);
    tokio::fs::create_dir_all(&destination)
        .await
        .map_err(|error| error.to_string())?;
    let input = if source.starts_with("magnet:?") {
        AddTorrent::from_url(source)
    } else {
        let bytes = if source.starts_with("https://") || source.starts_with("http://") {
            let response = reqwest::Client::new()
                .get(source)
                .timeout(Duration::from_secs(30))
                .send()
                .await
                .map_err(|error| error.to_string())?
                .error_for_status()
                .map_err(|error| error.to_string())?;
            if response.content_length().unwrap_or(0) > MAX_TORRENT_BYTES as u64 {
                return Err("Torrent metadata is too large".into());
            }
            response.bytes().await.map_err(|error| error.to_string())?.to_vec()
        } else {
            fs::read(source).map_err(|error| error.to_string())?
        };
        if bytes.len() > MAX_TORRENT_BYTES {
            return Err("Torrent metadata is too large".into());
        }
        AddTorrent::from_bytes(bytes)
    };
    let session = Session::new(destination)
        .await
        .map_err(|error| error.to_string())?;
    let options = AddTorrentOptions {
        overwrite: true,
        ..Default::default()
    };
    let handle = session
        .add_torrent(input, Some(options))
        .await
        .map_err(|error| error.to_string())?
        .into_handle()
        .ok_or("Could not open torrent")?;
    loop {
        let stats = handle.stats();
        if let Some(error) = stats.error {
            return Err(error);
        }
        println!("PROGRESS {} {}", stats.progress_bytes, stats.total_bytes);
        if stats.finished {
            break;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    session.stop().await;
    println!("COMPLETE");
    Ok(())
}
