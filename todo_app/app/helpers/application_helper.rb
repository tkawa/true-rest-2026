module ApplicationHelper
  # アーカイブ状態を変更する操作が有効かどうか。
  # フラグが制御するのは操作の有無だけで、アーカイブ済みの表示は常に出す。
  def archive_feature_enabled?
    Rails.configuration.x.features.archive
  end
end
