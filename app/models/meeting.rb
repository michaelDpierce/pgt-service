class Meeting < ApplicationRecord
  validates :title, presence: true
  validates :hume_label,  presence: true
  validates :hume_config, presence: true

  belongs_to :user
  belongs_to :hume_session, optional: true, inverse_of: :meeting
end
