namespace :experiment do
  desc "シード投入済みのSQLiteスナップショット db/seed.sqlite3 を作り直す"
  task :snapshot do
    require "fileutils"

    snapshot_path = Rails.root.join("db/seed.sqlite3")
    work_path = Rails.root.join("tmp/seed-snapshot.sqlite3")

    FileUtils.mkdir_p(work_path.dirname)
    FileUtils.rm_f(Dir[work_path.to_s + "*"])

    env = {
      "RAILS_ENV" => "experiment",
      "EXPERIMENT_DB" => work_path.to_s,
      "SECRET_KEY_BASE" => ENV.fetch("SECRET_KEY_BASE", "experiment-only-fixed-key")
    }
    %w[db:schema:load db:seed].each do |task|
      system(env, "bin/rails", task, chdir: Rails.root.to_s, exception: true)
    end

    # ar_internal_metadata の時刻とページの並びを正規化し、
    # 再生成してもバイト列が同じになるようにする。
    normalize = [
      %(c = ActiveRecord::Base.connection),
      %(c.execute("UPDATE ar_internal_metadata SET created_at = '2026-01-01 00:00:00', updated_at = '2026-01-01 00:00:00'")),
      %(c.execute("VACUUM"))
    ].join("; ")
    system(env, "bin/rails", "runner", normalize, chdir: Rails.root.to_s, exception: true)

    FileUtils.cp(work_path, snapshot_path)
    FileUtils.rm_f(Dir[work_path.to_s + "*"])
    puts "wrote #{snapshot_path}"
  end
end
