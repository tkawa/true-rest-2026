# 日時を Rails 標準の ISO 8601（"2026-01-01T00:00:00.000Z"）で出す。
# 既定のバックエンドは Time#to_s の形式になり、Rails の to_json と食い違う。
Alba.backend = :active_support
