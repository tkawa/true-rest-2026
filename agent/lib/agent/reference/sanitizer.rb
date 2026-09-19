require "json"

module Agent
  module Reference
    # 既製エージェントの stream-json には、実行した人の環境（インストール済みプラグイン、
    # スキル、出力スタイル、ホームディレクトリのパス、ソケットのパス）が入る。
    # 公開する記録には、実験条件として意味のある項目だけを残す。
    module Sanitizer
      SYSTEM_KEYS = %w[type subtype model permissionMode apiKeySource tools claude_code_version].freeze
      SOCKET_PATTERN = %r{/tmp/cc-socks/[^"\s]+}
      HOME_PLACEHOLDER = "<HOME>".freeze
      WORKDIR_PLACEHOLDER = "<WORKDIR>".freeze
      SOCKET_PLACEHOLDER = "<SOCKET>".freeze

      module_function

      # stream-json の各行を絞り込み、残った本文からパスを取り除く。
      def stream(text, home: Dir.home)
        lines = text.to_s.lines
        events = lines.map { |line| parse(line) }
        workdir = events.compact.find { |e| e["type"] == "system" }&.dig("cwd")

        lines.zip(events).map do |line, event|
          next redact(line, home: home, workdir: workdir) if event.nil?

          event = event.slice(*SYSTEM_KEYS) if event["type"] == "system"
          redact("#{JSON.generate(event)}\n", home: home, workdir: workdir)
        end.join
      end

      def redact(text, home: Dir.home, workdir: nil)
        result = text.to_s.dup
        each_form(workdir) { |path| result = result.gsub(path, WORKDIR_PLACEHOLDER) }
        each_form(home) { |path| result = result.gsub(path, HOME_PLACEHOLDER) }
        result.gsub(SOCKET_PATTERN, SOCKET_PLACEHOLDER)
      end

      # macOS の一時ディレクトリは /var と /private/var の両方で現れる。
      def each_form(path)
        return if path.nil? || path.empty?

        bare = path.delete_prefix("/private")
        [ "/private#{bare}", bare ].uniq.each { |form| yield form }
      end

      def parse(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
