class HumeSession < ApplicationRecord
  has_one :meeting, foreign_key: :hume_session_id, inverse_of: :hume_session
end
