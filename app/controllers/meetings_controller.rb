# app/controllers/meetings_controller.rb
class MeetingsController < ApplicationController
  before_action :set_meeting, only: %i[show destroy]

  def index
    scope = current_user.meetings

    if params[:q].present?
      q = params[:q].to_s.strip
      like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      scope = scope.where("title ILIKE ?", like)
    end

    sortable = %w[id title created_at updated_at]

    sort = params[:sort].presence_in(sortable) || "created_at"
    direction = params[:direction] == "asc" ? "asc" : "desc"
    scope = scope.order("#{sort} #{direction}")

    per_page = params[:per_page].presence&.to_i || 25
    pagy, records = pagy(scope, limit: per_page)

    render json: {
      data: records.as_json(only: %i[id title description created_at updated_at]),
      pagination: {
        page: pagy.page,
        per_page: pagy.limit,
        total: pagy.count,
        pages: pagy.pages
      }
    }
  end

  def show
    return render json: { error: "Forbidden" }, status: :forbidden if @meeting.user_id != current_user.id

    render json: @meeting.as_json(
      include: {
        hume_session: { only: %i[id data created_at updated_at] }
      }
    )
  end

  def create
    meeting = Meeting.new(create_params.merge(user_id: current_user.id))
    if meeting.save
      render json: { id: meeting.id, meeting: meeting }, status: :created
    else
      render json: { error: meeting.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def destroy
    @meeting.destroy!
    head :no_content
  end

  private

  def set_meeting
    @meeting = Meeting.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not Found" }, status: :not_found
  end

  def create_params
    params.require(:meeting).permit(:title, :hume_config, :hume_label)
  end
end
