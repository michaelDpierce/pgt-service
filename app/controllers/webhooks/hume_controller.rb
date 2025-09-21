class Webhooks::HumeController < ApplicationController
  include HumeSignatureVerifiable

  def create
    payload    = JSON.parse(request.raw_post)
    event_name = payload["event_name"]
    chat_id    = payload.dig("data","chat_id") || payload["chat_id"]
    occurred   = parse_time(payload["created_at"] || payload.dig("data","created_at"))

    session = ChatSession.find_or_create_by!(chat_id: chat_id)

    case event_name
    when "chat_started"
      session.update!(status: "started", started_at: occurred)

    when "assistant_message", "user_message"
      msg = payload.dig("data","message") || payload["message"] || {}
      ChatMessage.insert_all(
        [{
          id: SecureRandom.uuid,
          chat_session_id: session.id,
          hume_message_id: msg["id"] || Digest::SHA256.hexdigest(msg.to_json),
          role: (msg["role"] || "assistant"),
          content: (msg["content"] || ""),
          occurred_at: parse_time(msg["created_at"] || msg["timestamp"] || occurred),
          meta: msg.except("id","role","content","created_at","timestamp"),
          created_at: Time.current,
          updated_at: Time.current
        }],
        unique_by: :index_chat_messages_on_hume_message_id
      )

    when "chat_ended"
      started = session.started_at || occurred
      session.update!(
        status: "ended",
        ended_at: occurred,
        duration_seconds: (occurred - started).to_i
      )
      refresh_transcripts_mv
    end

    head :ok
  end

  private

  def parse_time(s)
    Time.parse(s.to_s)
  rescue
    Time.current
  end

  def refresh_transcripts_mv
    ActiveRecord::Base.connection.execute("REFRESH MATERIALIZED VIEW CONCURRENTLY chat_transcripts")
  rescue ActiveRecord::StatementInvalid
    ActiveRecord::Base.connection.execute("REFRESH MATERIALIZED VIEW chat_transcripts")
  end
end