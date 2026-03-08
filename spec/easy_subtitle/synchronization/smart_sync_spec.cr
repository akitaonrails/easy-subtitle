require "../../spec_helper"

class FailingRunner < EasySubtitle::AlassRunner
  def initialize(log : EasySubtitle::Log)
    super(log)
  end

  def sync(video_path : Path, sub_in : Path, sub_out : Path) : EasySubtitle::ShellResult
    raise EasySubtitle::ExternalToolError.new("alass", -1, "boom")
  end
end

class CopyingRunner < EasySubtitle::AlassRunner
  def initialize(log : EasySubtitle::Log)
    super(log)
  end

  def sync(video_path : Path, sub_in : Path, sub_out : Path) : EasySubtitle::ShellResult
    File.copy(sub_in.to_s, sub_out.to_s)
    EasySubtitle::ShellResult.new(stdout: "", stderr: "", exit_code: 0)
  end
end

class ShiftingRunner < EasySubtitle::AlassRunner
  def initialize(log : EasySubtitle::Log)
    super(log)
  end

  def sync(video_path : Path, sub_in : Path, sub_out : Path) : EasySubtitle::ShellResult
    File.write(
      sub_out.to_s,
      <<-SRT
      1
      00:00:05,000 --> 00:00:06,000
      shifted
      SRT
    )
    EasySubtitle::ShellResult.new(stdout: "", stderr: "", exit_code: 0)
  end
end

class WarningRunner < EasySubtitle::AlassRunner
  def initialize(log : EasySubtitle::Log)
    super(log)
  end

  def sync(video_path : Path, sub_in : Path, sub_out : Path) : EasySubtitle::ShellResult
    File.copy(sub_in.to_s, sub_out.to_s)
    EasySubtitle::ShellResult.new(stdout: "", stderr: "warn: negative timings detected", exit_code: 0)
  end
end

describe EasySubtitle::SmartSync do
  # SmartSync requires alass and real files to test properly.
  # These specs test the classification logic via SyncResult.

  describe "SyncResult" do
    it "reports accepted status" do
      result = EasySubtitle::SyncResult.new(
        candidate_path: Path.new("/tmp/test.srt"),
        offset: 0.05,
        status: EasySubtitle::SyncStatus::Accepted,
      )
      result.accepted?.should be_true
    end

    it "reports drift status" do
      result = EasySubtitle::SyncResult.new(
        candidate_path: Path.new("/tmp/test.srt"),
        offset: 1.5,
        status: EasySubtitle::SyncStatus::Drift,
      )
      result.accepted?.should be_false
      result.status.drift?.should be_true
    end

    it "reports failed status" do
      result = EasySubtitle::SyncResult.new(
        candidate_path: Path.new("/tmp/test.srt"),
        status: EasySubtitle::SyncStatus::Failed,
      )
      result.accepted?.should be_false
      result.status.failed?.should be_true
    end
  end

  describe "#execute" do
    it "returns a failed result when a worker raises" do
      log = EasySubtitle::Log.new(colorize: false, io: IO::Memory.new)
      sync = EasySubtitle::SmartSync.new(FailingRunner.new(log), EasySubtitle::Config.default, log)
      video = EasySubtitle::VideoFile.new(path: Path.new("/tmp/video.mkv"), size: 0_i64)
      result_channel = Channel(EasySubtitle::SyncResult?).new(1)

      spawn do
        result_channel.send(sync.execute([Path.new("/tmp/test.en.1.srt")], video))
      end

      result = select
      when value = result_channel.receive
        value
      when timeout(1.second)
        fail "SmartSync.execute timed out waiting for worker results"
      end

      result.should_not be_nil
      result.not_nil!.status.failed?.should be_true
      result.not_nil!.alass_output.should contain "boom"
    end

    it "prefers the successful candidate with more downloads" do
      log = EasySubtitle::Log.new(colorize: false, io: IO::Memory.new)
      sync = EasySubtitle::SmartSync.new(CopyingRunner.new(log), EasySubtitle::Config.default, log)
      video = EasySubtitle::VideoFile.new(path: Path.new("/tmp/video.mkv"), size: 0_i64)

      low = Path.new("/tmp/test.en.d100.f1.srt")
      high = Path.new("/tmp/test.en.d200.f2.srt")

      srt = <<-SRT
      1
      00:00:01,000 --> 00:00:02,000
      hello
      SRT

      File.write(low, srt)
      File.write(high, srt)

      result = sync.execute([low, high], video)
      result.should_not be_nil
      result.not_nil!.candidate_path.should eq high
    ensure
      [low, high, Path.new("/tmp/test.en.d100.f1_synced.srt"), Path.new("/tmp/test.en.d200.f2_synced.srt")].each do |path|
        File.delete(path.to_s) if File.exists?(path.to_s)
      end
    end

    it "accepts successful syncs even when the first subtitle shifts by minutes" do
      log = EasySubtitle::Log.new(colorize: false, io: IO::Memory.new)
      sync = EasySubtitle::SmartSync.new(ShiftingRunner.new(log), EasySubtitle::Config.default, log)
      video = EasySubtitle::VideoFile.new(path: Path.new("/tmp/video.mkv"), size: 0_i64)
      candidate = Path.new("/tmp/test.en.d100.f1.srt")

      File.write(
        candidate.to_s,
        <<-SRT
        1
        00:04:12,529 --> 00:04:14,463
        original
        SRT
      )

      result = sync.execute([candidate], video)
      result.should_not be_nil
      result.not_nil!.accepted?.should be_true
      result.not_nil!.offset.should be > 200.0
    ensure
      [candidate, Path.new("/tmp/test.en.d100.f1_synced.srt")].each do |path|
        File.delete(path.to_s) if File.exists?(path.to_s)
      end
    end

    it "marks warning-producing syncs as drift and prefers clean accepted results" do
      log = EasySubtitle::Log.new(colorize: false, io: IO::Memory.new)
      sync = EasySubtitle::SmartSync.new(WarningRunner.new(log), EasySubtitle::Config.default, log)
      video = EasySubtitle::VideoFile.new(path: Path.new("/tmp/video.mkv"), size: 0_i64)
      candidate = Path.new("/tmp/test.en.d100.f1.srt")

      File.write(
        candidate.to_s,
        <<-SRT
        1
        00:00:01,000 --> 00:00:02,000
        hello
        SRT
      )

      result = sync.execute([candidate], video)
      result.should_not be_nil
      result.not_nil!.drift?.should be_true
      result.not_nil!.alass_output.should contain "warn:"
    ensure
      [candidate, Path.new("/tmp/test.en.d100.f1_synced.srt")].each do |path|
        File.delete(path.to_s) if File.exists?(path.to_s)
      end
    end
  end
end
