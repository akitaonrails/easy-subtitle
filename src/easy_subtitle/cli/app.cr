require "option_parser"

module EasySubtitle
  module CLI
    class App
      @config_path : String = Config.default_path.to_s
      @verbose : Bool = false
      @quiet : Bool = false
      @no_color : Bool = false

      def run(args : Array(String)) : Nil
        command = parse_global_options(args)

        log = Log.new(
          level: @verbose ? Log::Level::Debug : (@quiet ? Log::Level::Error : Log::Level::Info),
          colorize: !@no_color,
        )

        config = load_config(command)

        case command
        when "init"
          InitCommand.new(log).run(args)
        when "extract"
          ExtractCommand.new(config, log).run(args)
        when "download"
          DownloadCommand.new(config, log).run(args)
        when "sync"
          SyncCommand.new(config, log).run(args)
        when "run"
          RunCommand.new(config, log).run(args)
        when "clean"
          CleanCommand.new(config, log).run(args)
        when "scan"
          ScanCommand.new(config, log).run(args)
        when "hash"
          HashCommand.new(log).run(args)
        when "doctor"
          DoctorCommand.new(config, log).run(args)
        else
          print_help
        end
      rescue ex : ConfigError
        STDERR.puts "Config error: #{ex.message}"
        exit 1
      rescue ex : Error
        STDERR.puts "Error: #{ex.message}"
        exit 1
      end

      private def parse_global_options(args : Array(String)) : String?
        command : String? = nil

        parser = OptionParser.new do |p|
          p.banner = "Usage: easy-subtitle [OPTIONS] COMMAND [COMMAND_OPTIONS] PATH"

          p.on("-c PATH", "--config PATH", "Config file path") { |path| @config_path = path }
          p.on("-v", "--verbose", "Verbose output") { @verbose = true }
          p.on("-q", "--quiet", "Suppress non-error output") { @quiet = true }
          p.on("--no-color", "Disable colors") { @no_color = true }
          p.on("--version", "Show version") do
            puts "easy-subtitle #{VERSION}"
            exit 0
          end
          p.on("-h", "--help", "Show help") do
            print_help
            exit 0
          end

          p.unknown_args do |remaining, _|
            command = remaining.shift? if remaining.any?
            # Put the rest back for command-level parsing
            remaining.each { |a| args.push(a) } if remaining.any?
          end
        end

        # Remove global args before the command
        global_args = [] of String
        idx = 0
        while idx < args.size
          arg = args[idx]
          if arg.starts_with?("-")
            global_args << arg
            # Check if this option takes a value
            if arg == "-c" || arg == "--config"
              idx += 1
              global_args << args[idx] if idx < args.size
            end
          else
            break
          end
          idx += 1
        end

        remaining = args[idx..]
        parser.parse(global_args)

        command = remaining.shift? if remaining.any?
        args.clear
        remaining.each { |a| args << a }

        command
      end

      private def load_config(command : String?) : Config
        return Config.default if command == "init" || command == "hash" || command == "doctor"

        if File.exists?(@config_path)
          Config.load(@config_path)
        else
          Config.default
        end
      end

      private def print_help : Nil
        puts "easy-subtitle #{VERSION} - Automated subtitle extraction, downloading, and synchronization"
        puts
        puts "Usage: easy-subtitle [OPTIONS] COMMAND [COMMAND_OPTIONS] PATH"
        puts
        puts "Global Options:"
        puts "  -c, --config PATH    Config file (default: #{Config.default_path})"
        puts "  -v, --verbose        Verbose output"
        puts "  -q, --quiet          Suppress non-error output"
        puts "  --no-color           Disable colors"
        puts "  --version            Show version"
        puts "  -h, --help           Show this help"
        puts
        puts "Commands:"
        puts "  init        Generate default config file"
        puts "  extract     Extract subtitle tracks from MKV containers"
        puts "  download    Search & download subtitles from OpenSubtitles"
        puts "  sync        Synchronize subtitles with video using alass"
        puts "  run         Full pipeline: extract -> download -> sync"
        puts "  clean       Remove ads/watermarks from SRT files"
        puts "  scan        Report subtitle coverage for videos"
        puts "  hash        Compute OpenSubtitles movie hash"
        puts "  doctor      Check config, credentials, and dependencies"
      end
    end
  end
end
