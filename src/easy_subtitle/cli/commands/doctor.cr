module EasySubtitle
  module CLI
    class DoctorCommand
      def initialize(@config : Config, @log : Log)
        @config_path = Config.default_path.to_s
        @passed = 0
        @total = 0
      end

      def run(args : Array(String)) : Nil
        OptionParser.parse(args) do |p|
          p.banner = "Usage: easy-subtitle doctor"
          p.on("-c PATH", "--config PATH", "Config file path") { |path| @config_path = path }
        end

        puts "Checking easy-subtitle setup...\n"

        check_config_file
        check_api_key
        check_credentials
        check_api_login
        check_tool("mkvmerge", mkvtoolnix_install_help)
        check_tool("mkvextract", mkvtoolnix_install_help)
        check_tool("alass", alass_install_help)

        puts "\n#{@passed}/#{@total} checks passed"
      end

      private def check_config_file
        if File.exists?(@config_path)
          pass("Config file exists: #{@config_path}")
        else
          fail("Config file not found: #{@config_path}")
          @log.info "  Run: easy-subtitle init"
        end
      end

      private def check_api_key
        if !@config.api_key.empty?
          pass("API key is set")
        else
          fail("API key is empty")
        end
      end

      private def check_credentials
        missing = [] of String
        missing << "username" if @config.username.empty?
        missing << "password" if @config.password.empty?

        if missing.empty?
          pass("Username and password are set")
        else
          fail("Missing credentials: #{missing.join(", ")}")
        end
      end

      private def check_api_login
        if @config.api_key.empty? || @config.username.empty? || @config.password.empty?
          skip("API login (skipped — credentials incomplete)")
          return
        end

        begin
          Authenticator.new(@config).login!
          pass("API login successful")
        rescue ex : ApiError
          fail("API login failed (HTTP #{ex.status_code}): #{ex.body}")
        rescue ex : Exception
          fail("API login failed: #{ex.message}")
        end
      end

      private def check_tool(name : String, install_help : String)
        if path = Shell.which(name)
          pass("#{name} found: #{path}")
        else
          fail("#{name} not found")
          @log.info "  Install: #{install_help}"
        end
      end

      private def detect_platform : String
        result = Shell.run("uname", ["-s"], raise_on_error: false)
        result.exit_code == 0 ? result.stdout.strip : "Unknown"
      end

      private def mkvtoolnix_install_help : String
        case detect_platform
        when "Linux"
          "sudo apt install mkvtoolnix  OR  sudo pacman -S mkvtoolnix-cli"
        when "Darwin"
          "brew install mkvtoolnix"
        else
          "https://mkvtoolnix.download/downloads.html"
        end
      end

      private def alass_install_help : String
        "cargo install alass-cli  OR  https://github.com/kaegi/alass/releases"
      end

      private def pass(msg : String)
        @total += 1
        @passed += 1
        puts "\e[32m✓\e[0m #{msg}"
      end

      private def fail(msg : String)
        @total += 1
        puts "\e[31m✗\e[0m #{msg}"
      end

      private def skip(msg : String)
        @total += 1
        puts "\e[33m–\e[0m #{msg}"
      end
    end
  end
end
