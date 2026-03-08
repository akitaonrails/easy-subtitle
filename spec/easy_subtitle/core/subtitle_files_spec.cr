require "../../spec_helper"

describe EasySubtitle::SubtitleFiles do
  it "distinguishes final, active, and marked subtitle files" do
    video = EasySubtitle::VideoFile.new(path: Path.new("/tmp/movie.mkv"), size: 0_i64)

    EasySubtitle::SubtitleFiles.final_subtitle?("movie.en.srt", video, "en").should be_true
    EasySubtitle::SubtitleFiles.active_candidate?("movie.en.d100.f1.srt", video, "en").should be_true
    EasySubtitle::SubtitleFiles.active_candidate?("movie.en.srt", video, "en").should be_false
    EasySubtitle::SubtitleFiles.active_candidate?("movie.en.d100.f1.DRIFT.srt", video, "en").should be_false
    EasySubtitle::SubtitleFiles.active_candidate?("movie.en.d100.f1.FAILED.srt", video, "en").should be_false
  end

  it "extracts candidate metadata from filenames" do
    EasySubtitle::SubtitleFiles.candidate_download_count("movie.en.d123.f456.srt").should eq 123_i64
    EasySubtitle::SubtitleFiles.candidate_file_id("movie.en.d123.f456.srt").should eq 456_i64
    EasySubtitle::SubtitleFiles.candidate_file_id("movie.en.d123.f456.FAILED.srt").should eq 456_i64
  end

  it "builds marker filenames" do
    path = Path.new("/tmp/movie.en.d123.f456.srt")

    EasySubtitle::SubtitleFiles.mark(path, EasySubtitle::SyncStatus::Drift).basename.should eq "movie.en.d123.f456.DRIFT.srt"
    EasySubtitle::SubtitleFiles.mark(path, EasySubtitle::SyncStatus::Failed).basename.should eq "movie.en.d123.f456.FAILED.srt"
  end
end
