# easy-subtitle

A fast, single-binary CLI tool for automated subtitle extraction, downloading, and synchronization. Written in [Crystal](https://crystal-lang.org/), ported from the Python project [Subservient](https://github.com/N3xigen/Subservient).

## Why a Crystal port?

Subservient is a capable ~10,000-line Python tool with an interactive menu UI, ffsubsync dependency, and INI config. **easy-subtitle** modernizes it into:

- **Single static binary** — no Python runtime, no pip, no virtualenv
- **Subcommand CLI** — scriptable, composable, no interactive menus
- **alass sync engine** — Rust-based, replaces ffsubsync (no Python dependency)
- **YAML config** — simpler than INI, with sensible defaults
- **Parallel sync** — Crystal fibers for concurrent subtitle synchronization
- **Zero runtime dependencies** — just the binary + `mkvtoolnix` and `alass` on your PATH

## Installation

### Homebrew (macOS / Linux)

```bash
brew install akitaonrails/tap/easy-subtitle
```

### Quick install (Linux x86_64)

```bash
curl -fsSL https://raw.githubusercontent.com/akitaonrails/easy-subtitle/master/install.sh | bash
```

### From GitHub Releases

Download the latest binary for your platform from [Releases](https://github.com/akitaonrails/easy-subtitle/releases), then:

```bash
chmod +x easy-subtitle
sudo mv easy-subtitle /usr/local/bin/
```

### Build from source

Requires [Crystal](https://crystal-lang.org/install/) >= 1.15.0:

```bash
git clone https://github.com/akitaonrails/easy-subtitle.git
cd easy-subtitle
shards install
make release
sudo make install
```

## Prerequisites

These external tools must be on your PATH:

| Tool | Purpose | Install |
|---|---|---|
| [mkvtoolnix](https://mkvtoolnix.download/) | MKV track extraction/remuxing | `pacman -S mkvtoolnix-cli` / `brew install mkvtoolnix` / `apt install mkvtoolnix` |
| [alass](https://github.com/kaegi/alass) | Subtitle synchronization | `cargo install alass-cli` or download from releases |

An [OpenSubtitles](https://www.opensubtitles.com/) account and API key are required for the `download` command.

## Usage

```
easy-subtitle [OPTIONS] COMMAND [COMMAND_OPTIONS] PATH

Global Options:
  -c, --config PATH    Config file (default: ~/.config/easy-subtitle/config.yml)
  -v, --verbose        Verbose output
  -q, --quiet          Suppress non-error output
  --no-color           Disable colors
  --version            Show version
  -h, --help           Show help
```

### Commands

#### `init` — Generate default config

```bash
easy-subtitle init
easy-subtitle init -o ./my-config.yml
```

Creates a YAML config file with all defaults. Edit it to add your OpenSubtitles credentials.

#### `extract` — Extract subtitles from MKV

```bash
easy-subtitle extract /path/to/movies
easy-subtitle extract --remux /path/to/movies   # also strip unwanted tracks
```

Extracts embedded subtitle tracks (SRT, ASS) from MKV files using `mkvextract`.

#### `download` — Download subtitles from OpenSubtitles

```bash
easy-subtitle download /path/to/movies
easy-subtitle download -l en,pt /path/to/movies
```

Searches OpenSubtitles using movie hash (most accurate) and text search (fallback), then downloads the top candidates.

#### `sync` — Synchronize subtitles with video

```bash
easy-subtitle sync /path/to/movies
```

Uses `alass` to synchronize downloaded subtitle files with the video. Supports two strategies:

- **Smart sync** (default): runs all candidates in parallel, picks the one with the lowest timing offset
- **First match**: stops at the first subtitle that syncs within the acceptance threshold

#### `run` — Full pipeline

```bash
easy-subtitle run /path/to/movies
easy-subtitle run --skip-extract /path/to/movies
```

Runs the complete pipeline: **extract → download → sync**. Individual phases can be skipped.

#### `clean` — Remove ads/watermarks

```bash
easy-subtitle clean /path/to/subtitles
easy-subtitle clean --no-backup /path/to/file.srt
```

Removes advertising blocks from SRT files (OpenSubtitles watermarks, "subtitles by" credits, URLs, social media handles, etc.). Creates `.bak` backups by default.

#### `scan` — Report subtitle coverage

```bash
easy-subtitle scan /path/to/movies
easy-subtitle scan --json /path/to/movies
easy-subtitle scan -l en,pt,ja /path/to/movies
```

Reports which videos have subtitles for your configured languages. Supports table and JSON output.

#### `hash` — Compute movie hash

```bash
easy-subtitle hash /path/to/movie.mkv
easy-subtitle hash -v /path/to/movie.mkv   # verbose with file size
```

Computes the OpenSubtitles 64-bit movie hash. Useful for debugging search results.

#### `doctor` — Check setup

```bash
easy-subtitle doctor
```

Validates your setup: checks config file, API credentials, tests API login, and verifies external tool dependencies (`mkvmerge`, `mkvextract`, `alass`) are installed. Shows platform-specific install instructions for any missing tools.

## Configuration

Generate the default config with `easy-subtitle init`, then edit `~/.config/easy-subtitle/config.yml`:

```yaml
# OpenSubtitles API credentials
api_key: ""
username: ""
password: ""
api_url: "https://api.opensubtitles.com/api/v1"

# Languages to download (ISO 639-1 codes)
languages:
  - en

# Audio track languages to keep when remuxing
audio_track_languages:
  - en
  - ja

# Sync thresholds (in seconds)
accept_offset_threshold: 0.101   # below this = accepted
reject_offset_threshold: 2.5     # above this = rejected

# Behavior
series_mode: false                # true = treat folder as TV series
smart_sync: true                  # true = parallel all candidates, pick best
use_movie_hash: true              # true = hash search first (most accurate)
last_resort_search: false         # true = unfiltered search when all else fails

# Track handling
preserve_forced_subtitles: false
preserve_unwanted_subtitles: false
resync_mode: false                # true = re-sync even if subtitles exist

# Download limits
max_search_results: 10
top_downloads: 3
download_retry_503: 6
```

## Architecture

```
easy-subtitle/
  src/easy_subtitle/
    cli/           # Subcommand router and command implementations
    core/          # Language maps, SRT parser/writer/cleaner, video scanner
    acquisition/   # OpenSubtitles API client, auth, search, download, movie hash
    extraction/    # MKV track parsing, extraction, remuxing
    synchronization/  # alass runner, offset calculator, smart/first-match strategies
    models/        # VideoFile, SubtitleCandidate, CoverageEntry
```

Key design choices:

- **Crystal fibers** for parallel smart-sync (spawn N alass processes, collect via Channel)
- **Rate-limited API client** (500ms throttle via Mutex, required by OpenSubtitles)
- **YAML::Serializable** config with validation and sensible defaults
- **Zero external shards** for production (only `webmock` for tests)

## Porting from Subservient

| Feature | Subservient (Python) | easy-subtitle (Crystal) |
|---|---|---|
| Runtime | Python 3 + pip packages | Single binary |
| UI | Interactive menu | Subcommand CLI |
| Sync engine | ffsubsync (Python) | alass (Rust) |
| Config | INI (.config) | YAML |
| Concurrency | ThreadPoolExecutor | Crystal fibers + channels |
| Hash algorithm | Same (OpenSubtitles 64-bit) | Same |
| API | OpenSubtitles REST v1 | Same |

## Development

```bash
shards install          # install dev dependencies
make spec               # run tests
make format             # format code
make check              # check formatting
make build              # debug build
make release            # optimized build
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE) for details.

The original [Subservient](https://github.com/N3xigen/Subservient) is also GPL-3.0 licensed.
