require "json"

module EasySubtitle
  module MkvInfo
    def self.parse(json_str : String) : {subtitle_tracks: Array(SubtitleTrack), audio_tracks: Array(AudioTrack)}
      subtitle_tracks = [] of SubtitleTrack
      audio_tracks = [] of AudioTrack
      parser = JSON::PullParser.new(json_str)

      parser.read_object do |key|
        if key == "tracks"
          parser.read_array do
            track = parse_track(parser)
            case track
            when SubtitleTrack
              subtitle_tracks << track
            when AudioTrack
              audio_tracks << track
            end
          end
        else
          parser.skip
        end
      end

      {subtitle_tracks: subtitle_tracks, audio_tracks: audio_tracks}
    rescue ex : JSON::ParseException
      raise Error.new("Invalid mkvmerge JSON output: #{ex.message}")
    end

    def self.identify(video_path : String) : {subtitle_tracks: Array(SubtitleTrack), audio_tracks: Array(AudioTrack)}
      result = Shell.run("mkvmerge", ["-J", video_path])
      parse(result.stdout)
    end

    def self.identify(video_path : Path) : {subtitle_tracks: Array(SubtitleTrack), audio_tracks: Array(AudioTrack)}
      identify(video_path.to_s)
    end

    private def self.parse_track(parser : JSON::PullParser) : SubtitleTrack | AudioTrack | Nil
      id : Int32? = nil
      type : String? = nil
      codec = ""
      language = "und"
      name = ""
      default = false
      forced = false
      codec_id = ""

      parser.read_object do |key|
        case key
        when "id"
          if value = parser.read?(Int32)
            id = value
          else
            parser.skip
          end
        when "type"
          type = read_string_or_skip(parser)
        when "codec"
          codec = read_string_or_skip(parser)
        when "properties"
          props = parse_track_properties(parser)
          language = props[:language]
          name = props[:name]
          default = props[:default]
          forced = props[:forced]
          codec_id = props[:codec_id]
        else
          parser.skip
        end
      end

      return nil unless id && type

      case type
      when "subtitles"
        SubtitleTrack.new(
          id: id,
          language: language,
          codec: codec,
          codec_id: codec_id,
          name: name,
          default: default,
          forced: forced,
        )
      when "audio"
        AudioTrack.new(
          id: id,
          language: language,
          codec: codec,
          name: name,
          default: default,
        )
      else
        nil
      end
    end

    private def self.parse_track_properties(parser : JSON::PullParser) : NamedTuple(language: String, name: String, default: Bool, forced: Bool, codec_id: String)
      language = "und"
      name = ""
      default = false
      forced = false
      codec_id = ""

      parser.read_object do |key|
        case key
        when "language"
          language = read_string_or_skip(parser)
        when "track_name"
          name = read_string_or_skip(parser)
        when "default_track"
          default = read_bool_or_skip(parser)
        when "forced_track"
          forced = read_bool_or_skip(parser)
        when "codec_id"
          codec_id = read_string_or_skip(parser)
        else
          parser.skip
        end
      end

      {
        language: language,
        name:     name,
        default:  default,
        forced:   forced,
        codec_id: codec_id,
      }
    end

    private def self.read_string_or_skip(parser : JSON::PullParser) : String
      if value = parser.read?(String)
        value
      else
        parser.skip
        ""
      end
    end

    private def self.read_bool_or_skip(parser : JSON::PullParser) : Bool
      value = parser.read?(Bool)
      if value.nil?
        parser.skip
        false
      else
        value
      end
    end
  end
end
