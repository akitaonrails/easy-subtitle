module EasySubtitle
  enum SyncStatus
    Accepted
    Drift
    Failed
  end

  class SyncResult
    property candidate_path : Path
    property output_path : Path?
    property offset : Float64
    property status : SyncStatus
    property alass_output : String

    def initialize(
      @candidate_path,
      @output_path = nil,
      @offset = 0.0,
      @status = SyncStatus::Failed,
      @alass_output = "",
    )
    end

    def accepted? : Bool
      status.accepted?
    end

    def drift? : Bool
      status.drift?
    end

    def failed? : Bool
      status.failed?
    end

    def to_s(io : IO) : Nil
      io << "#{candidate_path.basename}: #{status} (timing shift: #{offset.round(3)}s)"
    end
  end
end
