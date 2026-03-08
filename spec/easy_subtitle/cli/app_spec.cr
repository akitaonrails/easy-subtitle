require "../../spec_helper"

class AlwaysFailingRunner < EasySubtitle::AlassRunner
  def initialize(log : EasySubtitle::Log)
    super(log)
  end

  def sync(video_path : Path, sub_in : Path, sub_out : Path) : EasySubtitle::ShellResult
    EasySubtitle::ShellResult.new(stdout: "", stderr: "no match", exit_code: 1)
  end
end

describe EasySubtitle::CLI::App do
  it "can be instantiated" do
    app = EasySubtitle::CLI::App.new
    app.should_not be_nil
  end

  it "marks failed numbered subtitle candidates after sync" do
    dir = Path.new("/tmp/easy-subtitle-sync-cleanup")
    Dir.mkdir_p(dir.to_s)

    video_path = dir / "movie.mkv"
    c1 = dir / "movie.en.d100.f1.srt"
    c2 = dir / "movie.en.d200.f2.srt"

    File.write(video_path.to_s, "video")
    File.write(c1.to_s, "1\n00:00:01,000 --> 00:00:02,000\nhi\n")
    File.write(c2.to_s, "1\n00:00:01,000 --> 00:00:02,000\nhi\n")

    log = EasySubtitle::Log.new(colorize: false, io: IO::Memory.new)
    syncer = EasySubtitle::Syncer.new(EasySubtitle::Config.default, log, AlwaysFailingRunner.new(log))
    video = EasySubtitle::VideoFile.from_path(video_path)

    result = syncer.sync(video, [c1, c2], "en")
    result.should_not be_nil
    result.not_nil!.status.failed?.should be_true
    File.exists?((dir / "movie.en.d100.f1.FAILED.srt").to_s).should be_true
    File.exists?((dir / "movie.en.d200.f2.FAILED.srt").to_s).should be_true
  ensure
    FileUtils.rm_rf(dir.to_s) if dir
  end
end
