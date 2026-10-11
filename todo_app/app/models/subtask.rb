class Subtask < ApplicationRecord
  belongs_to :todo

  validates :title, presence: true

  def completed? = completed_at.present?
  def complete!  = update!(completed_at: Time.current)
  def reopen!    = update!(completed_at: nil)
end
