//! A minimal loopback HTTP server for video.
//!
//! WebKitGTK's media pipeline can't stream from custom URI schemes (it reads
//! the first range and gives up), so videos are served over plain HTTP on
//! 127.0.0.1 instead. Every URL carries a random per-launch token, so other
//! local processes can't use the server to read files.

use crate::media::{mime_for, parse_range};
use std::collections::hash_map::RandomState;
use std::fs::File;
use std::hash::{BuildHasher, Hasher};
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::sync::Arc;

/// Maps `(session gen, item index)` to a video file, if it is one.
pub type Resolver = Arc<dyn Fn(u64, usize) -> Option<(PathBuf, String)> + Send + Sync>;

pub struct VideoServer {
    pub port: u16,
    pub token: String,
}

fn random_token() -> String {
    // RandomState is seeded from the OS's random source.
    let word = || {
        let mut h = RandomState::new().build_hasher();
        h.write_u64(std::process::id() as u64);
        h.finish()
    };
    format!("{:016x}{:016x}", word(), word())
}

pub fn start(resolve: Resolver) -> std::io::Result<VideoServer> {
    let listener = TcpListener::bind(("127.0.0.1", 0))?;
    let port = listener.local_addr()?.port();
    let token = random_token();
    let expected = format!("/{token}/");
    std::thread::spawn(move || {
        for stream in listener.incoming().filter_map(Result::ok) {
            let resolve = resolve.clone();
            let expected = expected.clone();
            std::thread::spawn(move || {
                if let Err(e) = handle(stream, &expected, &resolve) {
                    // Broken pipes are normal when the player seeks or closes.
                    if e.kind() != std::io::ErrorKind::BrokenPipe && e.kind() != std::io::ErrorKind::ConnectionReset {
                        eprintln!("bestshot: video server: {e}");
                    }
                }
            });
        }
    });
    Ok(VideoServer { port, token })
}

fn handle(stream: TcpStream, expected_prefix: &str, resolve: &Resolver) -> std::io::Result<()> {
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut out = stream;
    // Keep-alive: GStreamer reuses the connection for seeks.
    loop {
        let mut request_line = String::new();
        if reader.read_line(&mut request_line)? == 0 {
            return Ok(());
        }
        let mut range = None;
        loop {
            let mut line = String::new();
            if reader.read_line(&mut line)? == 0 {
                return Ok(());
            }
            let line = line.trim_end();
            if line.is_empty() {
                break;
            }
            if let Some((name, value)) = line.split_once(':') {
                if name.eq_ignore_ascii_case("range") {
                    range = Some(value.trim().to_string());
                }
            }
        }

        let mut parts = request_line.split_whitespace();
        let method = parts.next().unwrap_or("");
        let target = parts.next().unwrap_or("");
        let head_only = method == "HEAD";
        let file = (method == "GET" || head_only)
            .then(|| target.strip_prefix(expected_prefix))
            .flatten()
            .and_then(|rest| {
                let (gen, index) = rest.split_once('/')?;
                resolve(gen.parse().ok()?, index.parse().ok()?)
            });
        let Some((path, ext)) = file else {
            write_status(&mut out, "404 Not Found")?;
            continue;
        };
        serve(&mut out, &path, mime_for(&ext), range.as_deref(), head_only)?;
    }
}

fn write_status(out: &mut TcpStream, status: &str) -> std::io::Result<()> {
    write!(out, "HTTP/1.1 {status}\r\nContent-Length: 0\r\n\r\n")
}

fn serve(out: &mut TcpStream, path: &PathBuf, mime: &str, range: Option<&str>, head_only: bool) -> std::io::Result<()> {
    let mut file = File::open(path)?;
    let len = file.metadata()?.len();
    let (status, start, end) = match range {
        None => ("200 OK", 0, len.saturating_sub(1)),
        Some(r) => match parse_range(r, len) {
            Some((s, e)) => ("206 Partial Content", s, e),
            None => {
                return write!(
                    out,
                    "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */{len}\r\nContent-Length: 0\r\n\r\n"
                )
            }
        },
    };
    let count = if len == 0 { 0 } else { end - start + 1 };
    let mut head = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {mime}\r\nAccept-Ranges: bytes\r\nContent-Length: {count}\r\nCache-Control: no-store\r\n"
    );
    if range.is_some() {
        head.push_str(&format!("Content-Range: bytes {start}-{end}/{len}\r\n"));
    }
    head.push_str("\r\n");
    out.write_all(head.as_bytes())?;
    if !head_only && count > 0 {
        file.seek(SeekFrom::Start(start))?;
        std::io::copy(&mut file.take(count), out)?;
    }
    out.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn get(port: u16, path: &str, range: Option<&str>) -> String {
        let mut s = TcpStream::connect(("127.0.0.1", port)).unwrap();
        let range = range.map(|r| format!("Range: {r}\r\n")).unwrap_or_default();
        write!(s, "GET {path} HTTP/1.1\r\nHost: x\r\n{range}Connection: close\r\n\r\n").unwrap();
        s.shutdown(std::net::Shutdown::Write).unwrap();
        let mut buf = String::new();
        let _ = s.read_to_string(&mut buf);
        buf
    }

    #[test]
    fn serves_ranges_and_requires_token() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("clip.mp4");
        std::fs::write(&file, b"0123456789").unwrap();
        let server = start(Arc::new(move |gen, index| {
            (gen == 1 && index == 0).then(|| (file.clone(), "mp4".to_string()))
        }))
        .unwrap();
        let url = format!("/{}/1/0", server.token);

        let whole = get(server.port, &url, None);
        assert!(whole.starts_with("HTTP/1.1 200 OK"));
        assert!(whole.ends_with("0123456789"));

        let part = get(server.port, &url, Some("bytes=2-4"));
        assert!(part.starts_with("HTTP/1.1 206"));
        assert!(part.contains("Content-Range: bytes 2-4/10"));
        assert!(part.ends_with("234"));

        assert!(get(server.port, "/wrong-token/1/0", None).starts_with("HTTP/1.1 404"));
        assert!(get(server.port, &format!("/{}/1/7", server.token), None).starts_with("HTTP/1.1 404"));
    }
}
