module Agent
  # 条件によって変わるのはここだけ。指示文に初期入力を続ける。
  # 整形は実験からも汎用の入口からも同じものを通す。
  class InitialMessage
    # ハイパーメディア方式。入口の URL だけを渡す。
    def self.for_url(instruction, url)
      "#{instruction}\n\n操作対象: #{url}\n"
    end

    # カタログ方式。仕様書の本文をそのまま渡す。
    def self.for_spec(instruction, body)
      <<~MESSAGE
        #{instruction}

        操作対象のサービスの仕様書（OpenAPI）:
        ```yaml
        #{body}
        ```
      MESSAGE
    end

    def initialize(app_dir:, origin:)
      @app_dir = app_dir
      @origin = origin
    end

    def build(instruction, condition)
      return self.class.for_url(instruction, "#{@origin}/") if condition.spec_version.nil?

      self.class.for_spec(instruction, spec_body(condition.spec_version))
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
