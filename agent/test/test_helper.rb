$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# テストは agent/env を経由しないので、ここでも同じ固定をする。
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require "minitest/autorun"
require "fileutils"
require "tmpdir"

AGENT_ROOT = File.expand_path("..", __dir__).freeze
TODO_APP_DIR = File.expand_path("../todo_app", AGENT_ROOT).freeze
SEED_DB = File.join(TODO_APP_DIR, "db", "seed.sqlite3").freeze

# 自己テストの実行記録は一時ディレクトリに書き、experiment/runs/ を汚さない。
TEST_RUNS_DIR = Dir.mktmpdir("agent-test-runs").freeze
ENV["RUNS_DIR"] = TEST_RUNS_DIR
Minitest.after_run { FileUtils.rm_rf(TEST_RUNS_DIR) }
