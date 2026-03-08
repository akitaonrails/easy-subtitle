require "http/client"
require "json"

module EasySubtitle
  class ApiClient
    @last_request_at : Time = Time::UNIX_EPOCH
    @mutex : Mutex = Mutex.new
    RATE_LIMIT_MS = 500
    MAX_REDIRECTS = 5

    def initialize(@config : Config, @authenticator : Authenticator)
    end

    def get(path : String, params : Hash(String, String) = Hash(String, String).new) : HTTP::Client::Response
      throttle!
      headers = authenticated_headers
      uri = build_uri(path, params)
      request_with_redirects("GET", uri, headers)
    rescue ex : IO::Error | Socket::Error
      raise ApiError.new(-1, "GET #{path} failed: #{ex.message}")
    end

    def post(path : String, body : String? = nil) : HTTP::Client::Response
      throttle!
      headers = authenticated_headers
      uri = "#{api_base_url}#{path}"
      headers["Content-Type"] = "application/json"
      request_with_redirects("POST", uri, headers, body)
    rescue ex : IO::Error | Socket::Error
      raise ApiError.new(-1, "POST #{path} failed: #{ex.message}")
    end

    def authenticated_headers : HTTP::Headers
      token = @authenticator.ensure_token!
      HTTP::Headers{
        "Api-Key"       => @config.api_key,
        "Authorization" => "Bearer #{token}",
        "User-Agent"    => "EasySubtitle v#{VERSION}",
        "Accept"        => "application/json",
      }
    end

    private def build_uri(path : String, params : Hash(String, String)) : String
      uri = "#{api_base_url}#{path}"
      unless params.empty?
        query = params.map { |k, v| "#{URI.encode_path_segment(k)}=#{URI.encode_path_segment(v)}" }.join("&")
        uri += "?#{query}"
      end
      uri
    end

    private def api_base_url : String
      @authenticator.base_url || @config.api_url
    end

    private def request_with_redirects(method : String, uri : String, headers : HTTP::Headers, body : String? = nil) : HTTP::Client::Response
      current_method = method
      current_uri = uri
      redirects = 0

      loop do
        response = execute_request(current_method, current_uri, headers, body)
        return response unless redirect?(response.status_code)

        location = response.headers["Location"]?
        return response unless location

        redirects += 1
        raise ApiError.new(response.status_code, "Too many redirects for #{uri}") if redirects > MAX_REDIRECTS

        current_uri = absolutize_redirect(current_uri, location)
        if current_method == "POST" && {301, 302, 303}.includes?(response.status_code)
          current_method = "GET"
          body = nil
        end
      end
    end

    private def execute_request(method : String, uri : String, headers : HTTP::Headers, body : String? = nil) : HTTP::Client::Response
      case method
      when "GET"
        HTTP::Client.get(uri, headers: headers)
      when "POST"
        HTTP::Client.post(uri, headers: headers, body: body)
      else
        raise Error.new("Unsupported HTTP method: #{method}")
      end
    end

    private def redirect?(status_code : Int32) : Bool
      {301, 302, 303, 307, 308}.includes?(status_code)
    end

    private def absolutize_redirect(current_uri : String, location : String) : String
      return location if location.starts_with?("http://") || location.starts_with?("https://")

      current = URI.parse(current_uri)
      base = "#{current.scheme}://#{current.host}"
      base += ":#{current.port}" if current.port && !default_port?(current.scheme, current.port.not_nil!)

      if location.starts_with?("/")
        "#{base}#{location}"
      else
        current_path = current.path.presence || "/"
        dir = current_path.ends_with?("/") ? current_path : File.dirname(current_path)
        dir = "/" if dir == "."
        "#{base}#{dir}/#{location}".gsub("//", "/").sub(%r{\Ahttps:/}, "https://").sub(%r{\Ahttp:/}, "http://")
      end
    end

    private def default_port?(scheme : String?, port : Int32) : Bool
      (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
    end

    private def throttle! : Nil
      @mutex.synchronize do
        elapsed = Time.utc - @last_request_at
        remaining = RATE_LIMIT_MS - elapsed.total_milliseconds
        if remaining > 0
          sleep(remaining.milliseconds)
        end
        @last_request_at = Time.utc
      end
    end
  end
end
