class Meeting < ApplicationRecord
  validates :title, presence: true
  validates :hume_label,  presence: true
  validates :hume_config, presence: true

  belongs_to :user
  has_one :hume_session, dependent: :destroy, inverse_of: :meeting
end
