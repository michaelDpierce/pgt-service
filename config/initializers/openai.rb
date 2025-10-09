require "openai"

OpenAI.configure do |config|
  config.access_token = ENV["OPENAI_ACCESS_TOKEN"] ||
                        Rails.application.credentials.dig(:openai, :api_key)
end