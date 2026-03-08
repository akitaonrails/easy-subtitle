module EasySubtitle
  class Syncer
    def initialize(@config : Config, @log : Log, runner : AlassRunner? = nil)
      @runner = runner || AlassRunner.new(@log)
    end

    def sync(video : VideoFile, candidates : Array(Path), language : String) : SyncResult?
      if candidates.empty?
        @log.warn "No subtitle candidates to sync for #{video.name}"
        return nil
      end

      @log.info "Syncing #{candidates.size} candidate(s) for #{video.name} [#{language}]"

      result = if @config.smart_sync
                 SmartSync.new(@runner, @config, @log).execute(candidates, video)
               else
                 FirstMatch.new(@runner, @config, @log).execute(candidates, video)
               end

      if result && result.output_path
        saved = finalize_result(result, video, language)
        if saved
          delete_candidate_files(candidates)
          cleanup_marked_candidates(video, language)
        elsif result.failed?
          mark_candidates(candidates, SyncStatus::Failed)
        end
      else
        if result.nil? || result.status.failed?
          mark_candidates(candidates, SyncStatus::Failed)
        end
        cleanup_temp_files(video.directory)
      end

      result
    end

    private def finalize_result(result : SyncResult, video : VideoFile, language : String) : Bool
      output = result.output_path
      return false unless output

      final_name = "#{video.stem}.#{language}.srt"
      final_path = video.directory / final_name

      if result.accepted? || result.status.drift?
        begin
          File.delete(final_path.to_s) if File.exists?(final_path.to_s)
          File.rename(output.to_s, final_path.to_s)
          if result.accepted?
            @log.success "Saved: #{final_name} (timing shift: #{result.offset.round(3)}s, status: #{result.status})"
          else
            @log.warn "Saved with review needed: #{final_name} (timing shift: #{result.offset.round(3)}s, status: #{result.status})"
          end
          cleanup_temp_files(video.directory)
          true
        rescue ex
          @log.error "Failed to rename #{output.basename}: #{ex.message}"
          cleanup_temp_files(video.directory)
          false
        end
      else
        cleanup_temp_files(video.directory)
        false
      end
    end

    private def delete_candidate_files(candidates : Array(Path)) : Nil
      candidates.each do |candidate|
        File.delete(candidate.to_s) if File.exists?(candidate.to_s)
      end
    rescue
      # Ignore candidate cleanup errors
    end

    private def mark_candidates(candidates : Array(Path), status : SyncStatus) : Nil
      candidates.each do |candidate|
        next unless File.exists?(candidate.to_s)

        marked_path = SubtitleFiles.mark(candidate, status)
        if File.exists?(marked_path.to_s)
          File.delete(candidate.to_s)
        else
          File.rename(candidate.to_s, marked_path.to_s)
        end
      end
    rescue
      # Ignore marker cleanup errors
    end

    private def cleanup_marked_candidates(video : VideoFile, language : String) : Nil
      Dir.each_child(video.directory.to_s) do |name|
        next unless name.starts_with?("#{video.stem}.#{language}.")
        next unless SubtitleFiles.marked_candidate?(name)

        path = video.directory / name
        File.delete(path.to_s) if File.file?(path.to_s)
      end
    rescue
      # Ignore marker cleanup errors
    end

    private def cleanup_temp_files(dir : Path) : Nil
      Dir.each_child(dir.to_s) do |name|
        if name.includes?("_synced.") || name.includes?("_synced_")
          path = dir / name
          File.delete(path.to_s) if File.file?(path.to_s)
        end
      end
    rescue
      # Ignore cleanup errors
    end
  end
end
