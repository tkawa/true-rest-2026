$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "fileutils"
require "tmpdir"

AGENT_ROOT = File.expand_path("..", __dir__).freeze
TODO_APP_DIR = File.expand_path("../todo_app", AGENT_ROOT).freeze
SEED_DB = File.join(TODO_APP_DIR, "db", "seed.sqlite3").freeze
