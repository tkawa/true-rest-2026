module Agent
  # 条件によって変わるのはここだけ。指示文に初期入力を続ける。
  class InitialMessage
    def initialize(app_dir:, origin:)
      @app_dir = app_dir
      @origin = origin
    end

    def build(instruction, condition)
      return "#{instruction}\n\n操作対象: #{@origin}/\n" if condition.spec_version.nil?

      <<~MESSAGE
        #{instruction}

        操作対象のサービスの仕様書（OpenAPI）:
        ```yaml
        #{spec_body(condition.spec_version)}
        ```
      MESSAGE
    end

    private

    # 仕様書の servers はポート 3000 で書かれている。
    # 実行時のポートに合わせる以外、本文には手を触れない。
    def spec_body(version)
      path = File.join(@app_dir, "doc", "openapi-#{version}.yaml")
      File.read(path).gsub("http://localhost:3000/", "#{@origin}/")
    end
  end
end
