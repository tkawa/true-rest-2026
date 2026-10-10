module ApplicationHelper
  # アーカイブ状態を変更する操作が有効かどうか。
  # フラグが制御するのは操作の有無だけで、アーカイブ済みの表示は常に出す。
  def archive_feature_enabled?
    Rails.configuration.x.features.archive
  end

  # 期限の表示と編集が有効かどうか。カラムは常にあり、HTML に出すかどうかだけを決める。
  def due_feature_enabled?
    Rails.configuration.x.features.due
  end

  # サーバの「今日」。期限の判定はすべてこの値を使う。
  def today
    Rails.configuration.x.today
  end

  # タイトルの文字数上限が有効かどうか。HTML の maxlength を出すかどうかだけを決める。
  # 検証そのものはモデルが行う。
  def title_limit_enabled?
    Rails.configuration.x.features.title_limit
  end
end
