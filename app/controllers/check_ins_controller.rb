class CheckInsController < ApplicationController
  def create
    ci = CheckIn.create!(check_in_params.merge(created_from: "client"))
    render json: { ok: true, id: ci.id }
  rescue => e
    render json: { ok: false, error: e.message }, status: 422
  end

  private

  def check_in_params
    params.permit(
      :chat_id,
      :kind, # kind: "high" | "low" (no rating)
      :step_index,
      :category,
      :question_id,
      :question_text,
      :rating,
      :user_message
    )
  end
end