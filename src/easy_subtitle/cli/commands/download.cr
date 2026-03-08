module EasySubtitle
  module CLI
    class DownloadCommand
      def initialize(@config : Config, @log : Log)
      end

      def run(args : Array(String)) : Nil
        languages = @config.languages.dup

        parser = OptionParser.new do |p|
          p.banner = "Usage: easy-subtitle download [OPTIONS] PATH"
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

        auth = Authenticator.new(@config)
        client = ApiClient.new(@config, auth)
        search = SubtitleSearch.new(client, @config, @log)
        downloader = SubtitleDownloader.new(client, @config, @log)
        series_mode = VideoScanner.detect_mode(path, @config) == :series

        total_downloaded = 0
        videos.each do |video|
          begin
            if @config.use_movie_hash
              video.compute_hash!
            end

            languages.each do |lang|
              if final_subtitle_present?(video, lang)
                @log.info "Skipping #{video.name} [#{lang}] - synchronized subtitle already exists"
                next
              end

              candidates = search.search(video, lang, series_mode)
              if candidates.empty?
                @log.warn "No subtitles found for #{video.name} [#{lang}]"
                next
              end

              existing_file_ids = existing_candidate_file_ids(video, lang)
              active_count = active_candidate_count(video, lang)
              remaining_slots = @config.top_downloads - active_count

              if remaining_slots <= 0
                @log.info "Skipping #{video.name} [#{lang}] - already have #{@config.top_downloads} active candidate(s)"
                next
              end

              count = 0
              candidates.each do |candidate|
                break if count >= remaining_slots
                if existing_file_ids.includes?(candidate.file_id)
                  @log.debug "Skipping duplicate candidate #{candidate.file_id} for #{video.name} [#{lang}]"
                  next
                end

                output_dir = video.directory
                output_name = "#{video.stem}.#{lang}.d#{candidate.download_count}.f#{candidate.file_id}.srt"
                output_path = output_dir / output_name

                if downloader.download(candidate, output_path)
                  @log.success "Downloaded: #{output_name}"
                  existing_file_ids << candidate.file_id
                  count += 1
                end
              end
              total_downloaded += count
            end
          rescue ex : Exception
            @log.error "Failed to process #{video.name}: #{ex.message}"
          end
        end

        @log.success "Downloaded #{total_downloaded} subtitle(s)"
      end

      private def final_subtitle_present?(video : VideoFile, lang : String) : Bool
        return false if @config.resync_mode

        File.exists?(SubtitleFiles.final_path(video, lang).to_s)
      end

      private def active_candidate_count(video : VideoFile, lang : String) : Int32
        count = 0
        Dir.each_child(video.directory.to_s) do |name|
          count += 1 if SubtitleFiles.active_candidate?(name, video, lang)
        end
        count
      rescue ex : File::Error
        @log.error "Failed to inspect #{video.directory}: #{ex.message}"
        0
      end

      private def existing_candidate_file_ids(video : VideoFile, lang : String) : Set(Int64)
        ids = Set(Int64).new

        Dir.each_child(video.directory.to_s) do |name|
          next unless name.starts_with?("#{video.stem}.#{lang}.")
          if file_id = SubtitleFiles.candidate_file_id(name)
            ids << file_id
          end
        end

        ids
      rescue ex : File::Error
        @log.error "Failed to inspect #{video.directory}: #{ex.message}"
        Set(Int64).new
      end
    end
  end
end
