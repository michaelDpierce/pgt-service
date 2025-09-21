require "net/http"
require "uri"
require "json"

class HumeTokensController < ApplicationController
  def create
    api_key    = ENV.fetch("HUME_API_KEY")
    secret_key = ENV.fetch("HUME_SECRET_KEY")

    uri = URI("https://api.hume.ai/oauth2-cc/token")
    req = Net::HTTP::Post.new(uri)

    # OAuth2 client_credentials = Basic auth with key:secret
    basic = Base64.strict_encode64("#{api_key}:#{secret_key}")
    req["Authorization"] = "Basic #{basic}"
    req["Content-Type"]  = "application/x-www-form-urlencoded"

    # IMPORTANT: form-encoded, not JSON
    req.body = URI.encode_www_form(grant_type: "client_credentials")

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }

    # Helpful error surface
    render json: JSON.parse(res.body), status: res.code.to_i
  end
end