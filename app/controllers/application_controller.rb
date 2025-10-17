 # app/controllers/application_controller.rb
 include Pagy::Backend

class ApplicationController < ActionController::API
  before_action :authenticate_with_clerk!

  attr_reader :current_user

  private

  def authenticate_with_clerk!
    token = bearer_token_from(request)
    return render_unauthorized("Missing bearer token") if token.blank?

    verified = clerk_sdk.verify_token(token)

    clerk_id   = verified["sub"]
    email      = verified["email"]
    first_name = verified["first_name"]
    last_name  = verified["last_name"]
    full_name  = verified["full_name"]
    avatar_url = verified["avatar_url"]

    @current_user = upsert_user_from_claims!(
      clerk_id: clerk_id,
      email: email,
      first_name: first_name,
      last_name: last_name,
      full_name: full_name,
      avatar_url: avatar_url
    )
  rescue => e
    Rails.logger.warn("[Auth] Clerk verify failed: #{e.class}: #{e.message}")
    render_unauthorized("Invalid or expired token")
  end

  def upsert_user_from_claims!(clerk_id:, email:, first_name:, last_name:, full_name:, avatar_url:)
    user = User.find_by(clerk_id: clerk_id) || begin
      User.create!(clerk_id: clerk_id, email: email, first_name: first_name, last_name: last_name,
                   full_name: full_name, avatar_url: avatar_url, last_sign_in_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      User.find_by!(clerk_id: clerk_id)
    end

    # Light sync on each authenticated hit (don’t overwrite with blanks)
    updates = {
      email:       email.presence       || user.email,
      first_name:  first_name.presence  || user.first_name,
      last_name:   last_name.presence   || user.last_name,
      full_name:   full_name.presence   || user.full_name,
      avatar_url:  avatar_url.presence  || user.avatar_url,
      last_sign_in_at: Time.current
    }
    user.update_columns(**updates, updated_at: Time.current)
    user
  end

  def bearer_token_from(request)
    h = request.headers["Authorization"]
    h&.start_with?("Bearer ") ? h.split(" ", 2).last : nil
  end

  def clerk_sdk
    @clerk_sdk ||= Clerk::SDK.new(secret_key: ENV["CLERK_SECRET_KEY"])
  end

  def render_unauthorized(msg) = render json: { error: msg }, status: :unauthorized
end
