require "rails_helper"
require "open3"

# ExperimentClock は Time.now を書き換えるので、request spec の travel_to（同じ Time.now を差し替える）と
# 干渉しないよう、別プロセスで確かめる。
RSpec.describe "ExperimentClock" do
  def run_ruby(script, today: "2026-03-04")
    out, status = Open3.capture2(
      { "EXPERIMENT_TODAY" => today }, RbConfig.ruby, "-I", Rails.root.join("lib").to_s, "-e",
      "require 'active_support/all'; Time.zone = 'UTC'; require 'experiment_clock'; #{script}"
    )
    raise "子プロセスが失敗しました: #{out}" unless status.success?

    out
  end

  it "時計を指定した日の 09:00 起点に進め、時間は止めない" do
    out = run_ruby(<<~RUBY).lines.map(&:strip)
      ExperimentClock.start(ENV["EXPERIMENT_TODAY"])
      a = Time.current
      sleep 0.05
      b = Time.current
      puts a.iso8601, (b > a), Date.current, Date.today
    RUBY

    expect(out[0]).to start_with("2026-03-04T09:00:0")
    expect(out[1..]).to eq(%w[true 2026-03-04 2026-03-04])
  end

  it "stop で実時計に戻る" do
    out = run_ruby(<<~RUBY).strip
      ExperimentClock.start(ENV["EXPERIMENT_TODAY"])
      ExperimentClock.stop
      puts (Time.current - Time.now).abs < 1
    RUBY

    expect(out).to eq("true")
  end

  it "Date.current が config.x.today（EXPERIMENT_TODAY の Date.iso8601）と一致する" do
    out = run_ruby(<<~RUBY).strip
      ExperimentClock.start(ENV["EXPERIMENT_TODAY"])
      puts Date.current == Date.iso8601(ENV["EXPERIMENT_TODAY"])
    RUBY

    expect(out).to eq("true")
  end
end
