module EasySubtitle
  class SmartSync
    def initialize(@runner : AlassRunner, @config : Config, @log : Log)
    end

    def execute(candidates : Array(Path), video : VideoFile) : SyncResult?
      return nil if candidates.empty?

      channel = Channel(SyncResult).new(candidates.size)

      candidates.each do |candidate|
        spawn do
          result = begin
            sync_one(candidate, video)
          rescue ex : Exception
            SyncResult.new(
              candidate_path: candidate,
              status: SyncStatus::Failed,
              alass_output: ex.message || "Synchronization failed",
            )
          end
          channel.send(result)
        end
      end

      results = Array(SyncResult).new(candidates.size)
      candidates.size.times do
        results << channel.receive
      end

      @log.info "Smart sync: #{results.count(&.accepted?)} accepted, #{results.count(&.status.drift?)} drift, #{results.count(&.status.failed?)} failed"

      accepted = results.select(&.accepted?)
      if accepted.empty?
        drift = results.select(&.status.drift?)
        return best_result(drift) if drift.any?
        return best_result(results) if results.any?
        return nil
      end

      best_result(accepted)
    end

    private def sync_one(candidate : Path, video : VideoFile) : SyncResult
      suffix = "_synced#{candidate.extension}"
      output_path = candidate.parent / "#{candidate.stem}#{suffix}"

      shell_result = @runner.sync(video.path, candidate, output_path)

      unless shell_result.exit_code == 0 && File.exists?(output_path)
        return SyncResult.new(
          candidate_path: candidate,
          status: SyncStatus::Failed,
          alass_output: shell_result.stderr,
        )
      end

      offset = measure_timing_shift(candidate, output_path)

      SyncResult.new(
        candidate_path: candidate,
        output_path: output_path,
        offset: offset,
        status: classify_status(shell_result),
        alass_output: combined_output(shell_result),
      )
    rescue ex : Exception
      SyncResult.new(
        candidate_path: candidate,
        status: SyncStatus::Failed,
        alass_output: ex.message || "Synchronization failed",
      )
    end

    private def measure_timing_shift(candidate : Path, output_path : Path) : Float64
      OffsetCalculator.calculate(candidate, output_path)
    rescue
      0.0
    end

    private def classify_status(shell_result : ShellResult) : SyncStatus
      quality_warning?(shell_result) ? SyncStatus::Drift : SyncStatus::Accepted
    end

    private def quality_warning?(shell_result : ShellResult) : Bool
      output = combined_output(shell_result)
      output.matches?(/\bwarn:/i) || output.matches?(/negative timings?/i)
    end

    private def combined_output(shell_result : ShellResult) : String
      [shell_result.stdout, shell_result.stderr]
        .reject(&.empty?)
        .join('\n')
    end

    private def best_result(results : Array(SyncResult)) : SyncResult
      results.max_by do |result|
        {
          status_rank(result.status),
          candidate_download_count(result.candidate_path),
          -result.offset,
        }
      end
    end

    private def candidate_download_count(path : Path) : Int64
      SubtitleFiles.candidate_download_count(path.basename)
    end

    private def status_rank(status : SyncStatus) : Int32
      case status
      when .accepted?
        2
      when .drift?
        1
      else
        0
      end
    end
  end
end
