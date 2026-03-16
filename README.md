# easy-subtitle

A fast, single-binary CLI tool for automated subtitle extraction, downloading, and synchronization. Written in [Crystal](https://crystal-lang.org/), ported from the Python project [Subservient](https://github.com/N3xigen/Subservient).

## Why a Crystal port?

Subservient is a capable ~10,000-line Python tool with an interactive menu UI, ffsubsync dependency, and INI config. **easy-subtitle** modernizes it into:

- **Single static binary** — no Python runtime, no pip, no virtualenv
- **Subcommand CLI** — scriptable, composable, no interactive menus
- **Pluggable sync backend** — `alass` by default, optional `ffsubsync` backend support
- **YAML config** — simpler than INI, with sensible defaults
- **Parallel sync** — Crystal fibers for concurrent subtitle synchronization
- **Low runtime dependencies** — just the binary + `mkvtoolnix` and your configured sync backend on your PATH

## Installation

### Homebrew (macOS / Linux)

```bash
brew install akitaonrails/tap/easy-subtitle
```

### Quick install (Linux x86_64 / arm64, macOS arm64)

```bash
curl -fsSL https://raw.githubusercontent.com/akitaonrails/easy-subtitle/master/install.sh | bash
```

The installer auto-detects `x86_64` and `arm64` Linux hosts plus Apple Silicon macOS and downloads the matching release artifact.

Linux release binaries are built as static musl binaries so they can run on both Ubuntu and Arch without extra runtime libraries.

### From GitHub Releases

Download the latest binary for your platform from [Releases](https://github.com/akitaonrails/easy-subtitle/releases), then:

```bash
chmod +x easy-subtitle
sudo mv easy-subtitle /usr/local/bin/
```

### Build from source

Requires [Crystal](https://crystal-lang.org/install/) >= 1.15.0:

On Linux, install the native development packages first.

Ubuntu / Debian:

```bash
sudo apt-get update
sudo apt-get install -y zlib1g-dev libyaml-dev libssl-dev libpcre2-dev
```

Arch Linux:

```bash
sudo pacman -S --needed zlib libyaml openssl pcre2
```

That is enough for a normal Linux build on Arch.

If you want a fully static Linux binary from source, build it in a musl environment instead of trying to statically link against your host glibc stack. The release workflow does this with the official Alpine-based Crystal image.

Example:

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/work" \
  --workdir /work \
  crystallang/crystal:latest-alpine \
  sh -lc 'shards install --production && crystal build src/easy_subtitle.cr -o easy-subtitle --release --no-debug --static'
```

That static musl binary is the one intended to be portable across Ubuntu and Arch, including arm64 hosts when built from the matching release workflow target.

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
| [alass](https://github.com/kaegi/alass) | Default subtitle synchronization backend | `cargo install alass-cli` or download from releases |
| [ffsubsync](https://github.com/smacke/ffsubsync) | Optional subtitle synchronization backend | `pipx install ffsubsync` or `pip install ffsubsync` |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | AI-powered sync backend (uses ASR + alass) | `yay -S whisper.cpp` / `brew install whisper-cpp` |
| [ffmpeg](https://ffmpeg.org/) | Audio extraction (required by whisper backend) | `pacman -S ffmpeg` / `brew install ffmpeg` / `apt install ffmpeg` |

An [OpenSubtitles](https://www.opensubtitles.com/) account and API key are required for the `download` command.

### OpenSubtitles Quotas

OpenSubtitles enforces account and API download limits. When you hit that limit, the `download` phase will fail with HTTP `406` and a message like:

```text
You have downloaded your allowed 20 subtitles for 24h.
```

That limit is not controlled by `easy-subtitle`. It depends on your OpenSubtitles account tier and API plan.

- Free accounts can have a small daily subtitle quota.
- Higher tiers such as VIP and paid API plans raise that quota.
- `easy-subtitle` now stops further candidate downloads for that language as soon as OpenSubtitles reports a quota/account restriction, instead of wasting more requests.

To make your quota last longer:

- Keep `top_downloads` low. `2` or `3` is usually enough.
- Keep `max_search_results` reasonable instead of pulling large candidate lists.
- Leave `resync_mode` off unless you really want to replace existing final subtitles.
- Remember that `smart_sync` tests more downloaded candidates, which improves selection quality but consumes more quota.

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

If OpenSubtitles returns HTTP `406`, the most common cause is an exhausted daily quota or account restriction. The command now shows the API message so you can tell the difference between a quota problem and a bad candidate.

#### `sync` — Synchronize subtitles with video

```bash
easy-subtitle sync /path/to/movies
```

Uses the configured sync backend to synchronize downloaded subtitle files with the video. Supports two strategies:

- **Smart sync** (default): runs all candidates in parallel, keeps the most-downloaded subtitle that the backend synchronizes successfully
- **First match**: stops at the first subtitle that the backend synchronizes successfully

Successful syncs are classified as either:

- **Accepted**: the backend completed without warning signals
- **Drift**: the backend completed but emitted warnings that suggest the subtitle should be reviewed

When a final `video.lang.srt` already exists, `download`, `sync`, and `run` skip that language unless `resync_mode` is enabled.

##### Sync backends

| Backend | How it works | Best for |
|---|---|---|
| `alass` (default) | VAD-based dynamic programming alignment | Small offsets, fast |
| `ffsubsync` | VAD cross-correlation | Small offsets, alternative |
| `whisper` | Whisper ASR generates a reference SRT, then alass aligns against it | Large offsets (30-120s), anime, different release cuts |

The `whisper` backend uses [whisper.cpp](https://github.com/ggml-org/whisper.cpp) to transcribe the audio into a reference subtitle file, then uses `alass` to align the downloaded subtitle against it. This handles large timing shifts that pure VAD approaches miss.

Model selection (`whisper_model` in config):
- `auto` (default): uses `base.en` for English-only audio, `small` for multilingual/anime
- `base.en`: English-only, 142 MB, fast (~6 min per episode on CPU)
- `small`: Multilingual with good Japanese support, 466 MB (~12 min per episode on CPU)
- `medium` / `large-v3`: Higher accuracy, larger models

Models are downloaded automatically on first use to `~/.cache/easy-subtitle/models/`.

#### `run` — Full pipeline

```bash
easy-subtitle run /path/to/movies
easy-subtitle run --skip-extract /path/to/movies
```

Runs the complete pipeline: **extract → download → sync**. Individual phases can be skipped.

The `run` pipeline is idempotent: it skips download and sync for any language that already has a valid final subtitle (e.g. `video.en.srt`). This avoids wasting OpenSubtitles quota re-downloading candidates when a good subtitle already exists. To force re-processing, use the standalone `download` and `sync` commands with `resync_mode: true`.

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

Validates your setup: checks config file, API credentials, tests API login, and verifies external tool dependencies (`mkvmerge`, `mkvextract`, and the configured sync backend) are installed. Shows platform-specific install instructions for any missing tools.

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

# Legacy sync thresholds from Subservient (kept for config compatibility)
# The current sync flow no longer rejects successful backend runs on this basis.
accept_offset_threshold: 0.101
reject_offset_threshold: 2.5

# Behavior
series_mode: false                # true = treat folder as TV series
smart_sync: true                  # true = parallel all candidates, pick best
sync_backend: "alass"             # "alass", "ffsubsync", or "whisper"
whisper_model: "auto"             # "auto", "base.en", "small", "medium", "large-v3"
use_movie_hash: true              # true = hash search first (most accurate)
last_resort_search: false         # true = unfiltered search when all else fails

# Track handling
preserve_forced_subtitles: false
preserve_unwanted_subtitles: false
resync_mode: false                # true = re-sync even if subtitles exist

# Download limits
max_search_results: 10
top_downloads: 3                 # keep low if you want to conserve OpenSubtitles quota
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
    synchronization/  # sync backends, offset calculator, smart/first-match strategies
    models/        # VideoFile, SubtitleCandidate, CoverageEntry
```

Key design choices:

- **Crystal fibers** for parallel smart-sync (spawn N backend processes, collect via Channel)
- **Rate-limited API client** (500ms throttle via Mutex, required by OpenSubtitles)
- **YAML::Serializable** config with validation and sensible defaults
- **Zero external shards** for production (only `webmock` for tests)

## Porting from Subservient

| Feature | Subservient (Python) | easy-subtitle (Crystal) |
|---|---|---|
| Runtime | Python 3 + pip packages | Single binary |
| UI | Interactive menu | Subcommand CLI |
| Sync engine | ffsubsync (Python) | alass by default, optional ffsubsync backend |
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
