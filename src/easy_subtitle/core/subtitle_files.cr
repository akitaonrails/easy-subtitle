module EasySubtitle
  module SubtitleFiles
    extend self

    def final_name(video : VideoFile, language : String) : String
      "#{video.stem}.#{language}.srt"
    end

    def final_path(video : VideoFile, language : String) : Path
      video.directory / final_name(video, language)
    end

    def final_subtitle?(name : String, video : VideoFile, language : String) : Bool
      name == final_name(video, language)
    end

    def active_candidate?(name : String, video : VideoFile, language : String) : Bool
      return false unless name.starts_with?("#{video.stem}.#{language}.")
      return false unless name.ends_with?(".srt")
      return false if final_subtitle?(name, video, language)
      return false if marked_candidate?(name)

      true
    end

    def marked_candidate?(name : String) : Bool
      drift_candidate?(name) || failed_candidate?(name)
    end

    def drift_candidate?(name : String) : Bool
      name.ends_with?(".DRIFT.srt")
    end

    def failed_candidate?(name : String) : Bool
      name.ends_with?(".FAILED.srt")
    end

    def candidate_download_count(name : String) : Int64
      if match = /\.d(\d+)\./.match(name)
        match[1].to_i64
      else
        0_i64
      end
    end

    def candidate_file_id(name : String) : Int64?
      if match = /\.f(\d+)(?:\.(?:DRIFT|FAILED))?\.srt$/.match(name)
        match[1].to_i64
      end
    end

    def mark(path : Path, status : SyncStatus) : Path
      marker = case status
               when .drift?
                 "DRIFT"
               when .failed?
                 "FAILED"
               else
                 raise ArgumentError.new("Cannot mark #{path.basename} as #{status}")
               end

      path.parent / "#{path.stem}.#{marker}#{path.extension}"
    end
  end
end
