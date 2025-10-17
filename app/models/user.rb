class User < ApplicationRecord
  has_many :meetings, dependent: :nullify
end
