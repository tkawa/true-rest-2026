class List < ApplicationRecord
  has_many :todos, dependent: :destroy

  validates :name, presence: true

  def archived? = archived_at.present?
  def archive!   = update!(archived_at: Time.current)
  def unarchive! = update!(archived_at: nil)
end
