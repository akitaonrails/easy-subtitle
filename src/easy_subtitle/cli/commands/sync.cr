module EasySubtitle
  module CLI
    class SyncCommand
      def initialize(@config : Config, @log : Log)
      end

      def run(args : Array(String)) : Nil
        languages = @config.languages.dup

        parser = OptionParser.new do |p|
          p.banner = "Usage: easy-subtitle sync [OPTIONS] PATH"
          p.on("-l LANGS", "--languages LANGS", "Languages (comma-separated)") do |l|
            languages = l.split(",").map(&.strip)
          end
        end
        parser.parse(args)

        path = args.last?
        unless path
          STDERR.puts parser
          return
        end

        videos = VideoScanner.scan(path, @config)
        if videos.empty?
          @log.warn "No video files found in: #{path}"
          return
        end

        syncer = Syncer.new(@config, @log)
        accepted = 0
        drift = 0
        failed = 0
        total = 0

        videos.each do |video|
          languages.each do |lang|
            begin
              if final_subtitle_present?(video, lang)
                @log.info "Skipping #{video.name} [#{lang}] - synchronized subtitle already exists"
                next
              end

              candidates = find_candidates(video, lang)
              next if candidates.empty?
              total += 1

              result = syncer.sync(video, candidates, lang)
              if result
                case result.status
                when .accepted?
                  accepted += 1
                when .drift?
                  drift += 1
                else
                  failed += 1
                end
              end
            rescue ex : Exception
              @log.error "Failed to sync #{video.name} [#{lang}]: #{ex.message}"
              failed += 1
            end
          end
        end

        @log.success "Sync complete: #{accepted} accepted, #{drift} drift, #{failed} failed (#{total} total)"
      end

      private def find_candidates(video : VideoFile, lang : String) : Array(Path)
        dir = video.directory
        candidates = [] of Path

        Dir.each_child(dir.to_s) do |name|
          if SubtitleFiles.active_candidate?(name, video, lang)
            candidates << dir / name
          end
        end

        candidates.sort_by do |path|
          {
            -SubtitleFiles.candidate_download_count(path.basename),
            path.basename,
          }
        end
      rescue ex : File::Error
        @log.error "Failed to read #{dir}: #{ex.message}"
        [] of Path
      end

      private def final_subtitle_present?(video : VideoFile, lang : String) : Bool
        return false if @config.resync_mode

        File.exists?(SubtitleFiles.final_path(video, lang).to_s)
      end
    end
  end
end
