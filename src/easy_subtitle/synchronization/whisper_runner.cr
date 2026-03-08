require "digest/sha1"
require "file_utils"

module EasySubtitle
  class WhisperRunner < SyncBackend
    WHISPER_BINARY_NAMES = ["whisper-cli", "whisper", "main"]
    ALASS_BINARY_NAMES   = ["alass", "alass-cli"]
    MODEL_DIR            = Path.home / ".cache" / "easy-subtitle" / "models"
    REF_DIR              = Path.home / ".cache" / "easy-subtitle" / "whisper-refs"
    MODEL_BASE_URL       = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    MODELS = {
      "base.en"  => "ggml-base.en.bin",
      "small"    => "ggml-small.bin",
      "medium"   => "ggml-medium.bin",
      "large-v3" => "ggml-large-v3.bin",
    }

    @@ref_mutex = Mutex.new
    @@ref_cache = Hash(String, Path).new

    def initialize(@config : Config, @log : Log, timeout : Time::Span = DEFAULT_TIMEOUT)
      super(@log, timeout)
    end

    def name : String
      "whisper"
    end

    def binary_names : Array(String)
      WHISPER_BINARY_NAMES
    end

    def install_help : String
      "brew install whisper-cpp  OR  build from https://github.com/ggml-org/whisper.cpp"
    end

    def sync(video_path : Path, sub_in : Path, sub_out : Path) : ShellResult
      alass_cmd = find_alass!

      ref_srt = ensure_reference_srt(video_path)
      unless ref_srt
        return ShellResult.new(stdout: "", stderr: "Whisper did not produce reference SRT", exit_code: 1)
      end

      # Align downloaded subtitle against Whisper reference via alass
      @log.debug "Aligning #{sub_in.basename} against Whisper reference"
      Spinner.run("Aligning #{sub_in.basename} against Whisper reference") do
        Shell.run(alass_cmd, [
          ref_srt.to_s, sub_in.to_s, sub_out.to_s,
        ], raise_on_error: false, timeout: @timeout)
      end
    end

    # Generate the Whisper reference SRT once per video. Concurrent fibers
    # (from smart_sync) wait on the mutex and reuse the cached result.
    private def ensure_reference_srt(video_path : Path) : Path?
      video_key = video_path.to_s

      @@ref_mutex.synchronize do
        if cached = @@ref_cache[video_key]?
          return cached if File.exists?(cached.to_s)
        end

        ref_srt = generate_reference_srt(video_path)
        if ref_srt && File.exists?(ref_srt.to_s)
          @@ref_cache[video_key] = ref_srt
          ref_srt
        end
      end
    end

    private def generate_reference_srt(video_path : Path) : Path?
      whisper_cmd = find_whisper!
      model_path = ensure_model!

      Dir.mkdir_p(REF_DIR.to_s)
      video_hash = Digest::SHA1.hexdigest(video_path.to_s)
      ref_srt = REF_DIR / "#{video_hash}.srt"

      # Already generated (e.g. from a previous run)
      return ref_srt if File.exists?(ref_srt.to_s)

      audio_path = REF_DIR / "#{video_hash}.wav"
      ref_base = REF_DIR / video_hash

      begin
        # Step 1: Extract 16kHz mono WAV from video
        @log.debug "Extracting audio from #{video_path.basename}"
        Spinner.run("Extracting audio from #{video_path.basename}") do
          Shell.run("ffmpeg", [
            "-i", video_path.to_s,
            "-vn", "-acodec", "pcm_s16le",
            "-ar", "16000", "-ac", "1",
            "-y", audio_path.to_s,
          ], timeout: 5.minutes)
        end

        # Step 2: Generate reference SRT via Whisper ASR
        model_name = resolve_model_name
        lang = whisper_language
        @log.debug "Running Whisper (model: #{model_name}, language: #{lang})"
        Spinner.run("Generating speech timeline via Whisper (#{model_name})") do
          Shell.run(whisper_cmd, [
            "-m", model_path.to_s,
            "-f", audio_path.to_s,
            "-osrt",
            "-of", ref_base.to_s,
            "-l", lang,
          ], raise_on_error: false, timeout: 30.minutes)
        end

        File.exists?(ref_srt.to_s) ? ref_srt : nil
      ensure
        # Clean up the large WAV file, keep the reference SRT
        File.delete(audio_path.to_s) if File.exists?(audio_path.to_s)
      end
    end

    private def find_whisper! : String
      WHISPER_BINARY_NAMES.each do |name|
        return name if Shell.which(name)
      end
      raise ExternalToolError.new("whisper-cli", -1,
        "not found (tried: #{WHISPER_BINARY_NAMES.join(", ")}). Install: #{install_help}")
    end

    private def find_alass! : String
      ALASS_BINARY_NAMES.each do |name|
        return name if Shell.which(name)
      end
      raise ExternalToolError.new("alass", -1,
        "not found (tried: #{ALASS_BINARY_NAMES.join(", ")}). Install: cargo install alass-cli")
    end

    # Auto-select model based on audio languages:
    #   - English-only content → base.en (142 MB, fast)
    #   - Anime / multilingual → small (466 MB, good Japanese)
    private def resolve_model_name : String
      model = @config.whisper_model
      if model == "auto"
        all_english = @config.audio_track_languages.all? { |l|
          Language.normalize(l) == "en"
        }
        all_english ? "base.en" : "small"
      else
        model
      end
    end

    # Let whisper auto-detect the audio language. The audio_track_languages
    # config lists tracks to *keep* during remuxing, not what the video
    # actually contains — and ffmpeg may pick a different default stream.
    private def whisper_language : String
      "auto"
    end

    private def ensure_model! : Path
      model_name = resolve_model_name
      filename = MODELS[model_name]?
      raise ConfigError.new(
        "Unknown whisper_model: '#{model_name}'. Valid: #{MODELS.keys.join(", ")}"
      ) unless filename

      model_path = MODEL_DIR / filename

      unless File.exists?(model_path.to_s)
        download_model(model_name, filename, model_path)
      end

      model_path
    end

    private def download_model(model_name : String, filename : String, model_path : Path) : Nil
      Dir.mkdir_p(MODEL_DIR.to_s)
      url = "#{MODEL_BASE_URL}/#{filename}"
      @log.info "Downloading Whisper model '#{model_name}' (~#{model_size(model_name)})..."

      tmp_path = Path.new("#{model_path}.part")

      begin
        if Shell.which("curl")
          Spinner.run("Downloading #{filename}") do
            Shell.run("curl", [
              "-fSL", "--progress-bar",
              "-o", tmp_path.to_s,
              url,
            ], timeout: 30.minutes)
          end
        elsif Shell.which("wget")
          Spinner.run("Downloading #{filename}") do
            Shell.run("wget", ["-q", "-O", tmp_path.to_s, url], timeout: 30.minutes)
          end
        else
          raise Error.new("curl or wget required to download the Whisper model")
        end

        File.rename(tmp_path.to_s, model_path.to_s)
        @log.success "Model downloaded: #{model_path}"
      rescue ex
        File.delete(tmp_path.to_s) if File.exists?(tmp_path.to_s)
        raise ex
      end
    end

    private def model_size(model_name : String) : String
      case model_name
      when "base.en"  then "142 MB"
      when "small"    then "466 MB"
      when "medium"   then "1.5 GB"
      when "large-v3" then "3.1 GB"
      else                 "unknown"
      end
    end
  end
end
