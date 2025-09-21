module HumeSignatureVerifiable
  extend ActiveSupport::Concern

  included do
    before_action :verify_hume_signature!
  end

  private

  def verify_hume_signature!
    secret    = ENV.fetch("HUME_SECRET_KEY")
    timestamp = request.headers["X-Hume-AI-Webhook-Timestamp"].to_s
    given_sig = request.headers["X-Hume-AI-Webhook-Signature"].to_s
    body      = request.raw_post.to_s

    computed = OpenSSL::HMAC.hexdigest("SHA256", secret, body + timestamp)
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(computed, given_sig)
  end
end