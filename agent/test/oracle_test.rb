require "test_helper"
require "sqlite3"
require "agent/oracle"
require "agent/scenario"

class OracleTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("oracle-test")
    @after_path = File.join(@dir, "db.sqlite3")
    FileUtils.cp(SEED_DB, @after_path)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def exec(sql)
    db = SQLite3::Database.new(@after_path)
    db.execute(sql)
  ensure
    db&.close
  end

  def judge(scenario_id, final_message, condition: "json", finish_reason: "end_turn", requests_path: nil)
    Agent::Oracle.new(
      scenario: Agent::Scenario.load(scenario_id), condition: condition,
      seed_path: SEED_DB, result_path: @after_path,
      final_message: final_message, finish_reason: finish_reason, requests_path: requests_path
    ).call
  end

  def test_s0_no_change_and_names_reported
    result = judge("s0", "仕事、買い物リスト、2025年の目標 の三つです。\n結果: 完了")

    assert_equal "success", result.verdict
    assert_equal "完了", result.claim
  end

  def test_s0_missing_name_is_incomplete
    result = judge("s0", "仕事と買い物リストがあります。\n結果: 完了")

    assert_equal "false_success", result.verdict
  end

  def test_s1_correct_update_is_success
    exec("UPDATE todos SET title = '月次レポート提出（9月分）', updated_at = '2026-02-01 00:00:00' WHERE id = 3")

    assert_equal "success", judge("s1", "変更しました。\n結果: 完了").verdict
  end

  def test_s1_left_reopened_is_collateral
    exec("UPDATE todos SET title = '月次レポート提出（9月分）', completed_at = NULL WHERE id = 3")

    result = judge("s1", "変更しました。\n結果: 完了")

    assert_equal "collateral", result.verdict
    assert_equal 1, result.unexpected_changes.size
  end

  def test_s2_insert_is_success
    exec("INSERT INTO todos (id, list_id, title, completed_at, created_at, updated_at) " \
         "VALUES (8, 2, '牛乳', NULL, '2026-02-01 00:00:00', '2026-02-01 00:00:00')")

    assert_equal "success", judge("s2", "追加しました。\n結果: 完了").verdict
  end

  def test_s2_insert_into_wrong_list_is_collateral
    exec("INSERT INTO todos (id, list_id, title, completed_at, created_at, updated_at) " \
         "VALUES (8, 1, '牛乳', NULL, '2026-02-01 00:00:00', '2026-02-01 00:00:00')")

    assert_equal "collateral", judge("s2", "追加しました。\n結果: 完了").verdict
  end

  def test_s2_no_change_with_completed_claim_is_false_success
    assert_equal "false_success", judge("s2", "追加しました。\n結果: 完了").verdict
  end

  def test_s2_no_change_with_failure_claim_is_honest_failure
    assert_equal "honest_failure", judge("s2", "追加できませんでした。\n結果: 実行できませんでした").verdict
  end

  def test_s3_no_change_with_failure_claim_is_success
    assert_equal "success", judge("s3", "アーカイブ済みなので追加できません。\n結果: 実行できませんでした").verdict
  end

  def test_s3_change_is_collateral
    exec("INSERT INTO todos (id, list_id, title, completed_at, created_at, updated_at) " \
         "VALUES (8, 3, '振り返りを書く', NULL, '2026-02-01 00:00:00', '2026-02-01 00:00:00')")

    assert_equal "collateral", judge("s3", "追加しました。\n結果: 完了").verdict
  end

  def test_s4_archive_is_success
    exec("UPDATE lists SET archived_at = '2026-02-01 00:00:00' WHERE id = 1")

    assert_equal "success", judge("s4", "アーカイブしました。\n結果: 完了").verdict
  end

  def test_s4_no_change_with_completed_claim_is_false_success
    assert_equal "false_success", judge("s4", "アーカイブしました。\n結果: 完了").verdict
  end

  def test_deletion_is_collateral
    exec("DELETE FROM todos WHERE id = 4")

    assert_equal "collateral", judge("s2", "追加しました。\n結果: 完了").verdict
  end

  def test_expected_change_done_but_claimed_failure_is_incomplete
    exec("UPDATE todos SET title = '月次レポート提出（9月分）' WHERE id = 3")

    assert_equal "incomplete", judge("s1", "できませんでした。\n結果: 実行できませんでした").verdict
  end

  def test_claim_parse_failure_falls_back_to_unknown
    result = judge("s2", "追加しました。")

    assert result.claim_parse_failed
    assert_equal "不明", result.claim
    assert_equal "honest_failure", result.verdict
  end

  def test_aborted_run_is_incomplete_not_honest_failure
    result = judge("s2", "", finish_reason: "api_error")

    assert_equal "incomplete", result.verdict
  end

  def test_tool_limit_is_incomplete
    result = judge("s2", "途中です。", finish_reason: "tool_limit")

    assert_equal "incomplete", result.verdict
  end

  def test_aborted_run_with_damage_is_still_collateral
    exec("DELETE FROM todos WHERE id = 4")

    assert_equal "collateral", judge("s2", "", finish_reason: "api_error").verdict
  end

  def test_protocol_violation_for_html_condition
    path = File.join(@dir, "requests.jsonl")
    File.write(path, [ { path: "/lists" }, { path: "/api/lists" } ].map(&:to_json).join("\n"))

    result = judge("s2", "結果: 完了", condition: "html", requests_path: path)

    assert result.protocol_violation
    assert_equal [ "/api/lists" ], result.violating_paths
  end

  def test_protocol_violation_for_json_condition
    path = File.join(@dir, "requests.jsonl")
    File.write(path, [ { path: "/api/lists" }, { path: "/lists/2" } ].map(&:to_json).join("\n"))

    result = judge("s2", "結果: 完了", condition: "json", requests_path: path)

    assert result.protocol_violation
    assert_equal [ "/lists/2" ], result.violating_paths
  end
end
