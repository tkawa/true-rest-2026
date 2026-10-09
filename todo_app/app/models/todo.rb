class Todo < ApplicationRecord
  belongs_to :list

  validates :title, presence: true
  validates :title, length: { maximum: 100 }, if: -> { Rails.configuration.x.features.title_limit }
  validate :list_must_not_be_archived, on: :create
  validate :title_frozen_while_completed, on: :update

  def completed? = completed_at.present?
  def complete!  = update!(completed_at: Time.current)
  def reopen!    = update!(completed_at: nil)

  private

  def list_must_not_be_archived
    errors.add(:base, "アーカイブ済みのリストにはToDoを追加できません") if list&.archived?
  end

  def title_frozen_while_completed
    return unless completed? && title_changed?

    errors.add(:base, "完了済みのToDoは編集できません。先に再開してください")
  end
end
