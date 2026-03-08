require "../../spec_helper"
require "webmock"

describe EasySubtitle::ApiClient do
  before_each do
    WebMock.reset
    EasySubtitle::Authenticator.new(EasySubtitle::Config.default).clear_token!
  end

  after_each do
    WebMock.reset
    EasySubtitle::Authenticator.new(EasySubtitle::Config.default).clear_token!
  end

  it "sends authenticated GET requests" do
    config = EasySubtitle::Config.default
    config.api_key = "test_key"

    WebMock.stub(:post, "https://api.opensubtitles.com/api/v1/login")
      .to_return(body: %({"token": "jwt_token_123", "base_url": "https://vip-api.opensubtitles.com/api/v1"}))

    WebMock.stub(:get, "https://vip-api.opensubtitles.com/api/v1/subtitles?languages=en")
      .to_return(body: %({"data": []}))

    auth = EasySubtitle::Authenticator.new(config)
    client = EasySubtitle::ApiClient.new(config, auth)

    response = client.get("/subtitles", {"languages" => "en"})
    response.status_code.should eq 200
  end

  it "sends authenticated POST requests" do
    config = EasySubtitle::Config.default
    config.api_key = "test_key"

    WebMock.stub(:post, "https://api.opensubtitles.com/api/v1/login")
      .to_return(body: %({"token": "jwt_token_123", "base_url": "https://vip-api.opensubtitles.com/api/v1"}))

    WebMock.stub(:post, "https://vip-api.opensubtitles.com/api/v1/download")
      .to_return(body: %({"link": "https://example.com/sub.srt"}))

    auth = EasySubtitle::Authenticator.new(config)
    client = EasySubtitle::ApiClient.new(config, auth)

    response = client.post("/download", %({"file_id": 123}))
    response.status_code.should eq 200
  end

  it "uses a host-only base_url returned by login" do
    config = EasySubtitle::Config.default
    config.api_key = "test_key"

    WebMock.stub(:post, "https://api.opensubtitles.com/api/v1/login")
      .to_return(body: %({"token": "jwt_token_789", "base_url": "vip-api.opensubtitles.com"}))

    WebMock.stub(:get, "https://vip-api.opensubtitles.com/api/v1/subtitles?languages=en")
      .to_return(body: %({"data": []}))

    auth = EasySubtitle::Authenticator.new(config)
    client = EasySubtitle::ApiClient.new(config, auth)

    client.get("/subtitles", {"languages" => "en"}).status_code.should eq 200
    auth.base_url.should eq "https://vip-api.opensubtitles.com/api/v1"
  end

  it "follows redirects on subtitle search requests" do
    config = EasySubtitle::Config.default
    config.api_key = "test_key"

    WebMock.stub(:post, "https://api.opensubtitles.com/api/v1/login")
      .to_return(body: %({"token": "jwt_token_999"}))

    WebMock.stub(:get, "https://api.opensubtitles.com/api/v1/subtitles?languages=en")
      .to_return(status: 301, headers: {"Location" => "https://vip-api.opensubtitles.com/api/v1/subtitles?languages=en"})

    WebMock.stub(:get, "https://vip-api.opensubtitles.com/api/v1/subtitles?languages=en")
      .to_return(body: %({"data": []}))

    auth = EasySubtitle::Authenticator.new(config)
    client = EasySubtitle::ApiClient.new(config, auth)

    client.get("/subtitles", {"languages" => "en"}).status_code.should eq 200
  end

  it "re-logins when the cached token file is in the old plain-text format" do
    config = EasySubtitle::Config.default
    config.api_key = "test_key"
    File.write(EasySubtitle::Config.token_path, "legacy_token")

    WebMock.stub(:post, "https://api.opensubtitles.com/api/v1/login")
      .to_return(body: %({"token": "jwt_token_456", "base_url": "https://vip-api.opensubtitles.com/api/v1"}))

    WebMock.stub(:get, "https://vip-api.opensubtitles.com/api/v1/subtitles?languages=en")
      .to_return(body: %({"data": []}))

    auth = EasySubtitle::Authenticator.new(config)
    client = EasySubtitle::ApiClient.new(config, auth)

    response = client.get("/subtitles", {"languages" => "en"})
    response.status_code.should eq 200
    auth.token.should eq "jwt_token_456"
  ensure
    EasySubtitle::Authenticator.new(EasySubtitle::Config.default).clear_token!
  end
end
