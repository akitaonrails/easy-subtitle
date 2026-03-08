require "../../spec_helper"
require "webmock"

describe EasySubtitle::Authenticator do
  before_each do
    WebMock.reset
    EasySubtitle::Authenticator.new(EasySubtitle::Config.default).clear_token!
  end

  after_each do
    WebMock.reset
    EasySubtitle::Authenticator.new(EasySubtitle::Config.default).clear_token!
  end

  it "logs in and returns token" do
    config = EasySubtitle::Config.default
    config.api_key = "test_key"
    config.username = "testuser"
    config.password = "testpass"

    WebMock.stub(:post, "https://api.opensubtitles.com/api/v1/login")
      .to_return(body: %({"token": "jwt_token_abc", "base_url": "https://vip-api.opensubtitles.com/api/v1"}))

    auth = EasySubtitle::Authenticator.new(config)
    token = auth.login!
    token.should eq "jwt_token_abc"
    auth.base_url.should eq "https://vip-api.opensubtitles.com/api/v1"
  end

  it "normalizes host-only base_url responses" do
    config = EasySubtitle::Config.default
    config.api_key = "test_key"
    config.username = "testuser"
    config.password = "testpass"

    WebMock.stub(:post, "https://api.opensubtitles.com/api/v1/login")
      .to_return(body: %({"token": "jwt_token_abc", "base_url": "vip-api.opensubtitles.com"}))

    auth = EasySubtitle::Authenticator.new(config)
    auth.login!.should eq "jwt_token_abc"
    auth.base_url.should eq "https://vip-api.opensubtitles.com/api/v1"
  end

  it "raises on failed login" do
    config = EasySubtitle::Config.default
    config.api_key = "bad_key"

    WebMock.stub(:post, "https://api.opensubtitles.com/api/v1/login")
      .to_return(status: 401, body: %({"message": "Unauthorized"}))

    auth = EasySubtitle::Authenticator.new(config)
    expect_raises(EasySubtitle::ApiError) do
      auth.login!
    end
  end

  it "raises when the login response is missing a token" do
    config = EasySubtitle::Config.default
    config.api_key = "test_key"
    config.username = "testuser"
    config.password = "testpass"

    WebMock.stub(:post, "https://api.opensubtitles.com/api/v1/login")
      .to_return(body: %({"ok": true}))

    auth = EasySubtitle::Authenticator.new(config)
    expect_raises(EasySubtitle::ApiError, /missing token/) do
      auth.login!
    end
  end
end
