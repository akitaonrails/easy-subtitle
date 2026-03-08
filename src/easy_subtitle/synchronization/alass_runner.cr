module EasySubtitle
  class AlassRunner
    DEFAULT_TIMEOUT = 10.minutes
    BINARY_NAMES    = ["alass", "alass-cli"]

    def initialize(@log : Log, @timeout : Time::Span = DEFAULT_TIMEOUT)
    end

    def sync(video_path : Path, sub_in : Path, sub_out : Path) : ShellResult
      cmd = find_binary!
      @log.debug "Running #{cmd}: #{video_path.basename} + #{sub_in.basename}"
      Spinner.run("Syncing #{sub_in.basename}") do
        Shell.run(
          cmd,
          [video_path.to_s, sub_in.to_s, sub_out.to_s],
          raise_on_error: false,
          timeout: @timeout
        )
      end
    end

    def available? : Bool
      !find_binary.nil?
    end

    private def find_binary : String?
      BINARY_NAMES.each do |name|
        return name if Shell.which(name)
      end
      nil
    end

    private def find_binary! : String
      find_binary || raise ExternalToolError.new("alass", -1, "not found (tried: #{BINARY_NAMES.join(", ")})")
    end
  end
end
