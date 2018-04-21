class Officer < ApplicationRecord
  belongs_to :chapter
  has_many :officer_assignments, dependent: :destroy
  has_many :users, through: :officer_assignments

  has_many :role_assignments, dependent: :destroy
  has_many :roles, through: :role_assignments

  def name
    "#{officer_type} (#{chapter.name})"
  end
end