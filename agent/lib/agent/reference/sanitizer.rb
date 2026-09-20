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
      USER_PLACEHOLDER = "<USER>".freeze
      WORKDIR_PLACEHOLDER = "<WORKDIR>".freeze
      SOCKET_PLACEHOLDER = "<SOCKET>".freeze
      # 短すぎる名前を置換すると本文を壊すので、その場合は何もしない。
      MIN_USER_LENGTH = 3

      module_function

      def default_user = ENV["USER"] || File.basename(Dir.home)

      # stream-json の各行を絞り込み、残った本文からパスと利用者名を取り除く。
      def stream(text, home: Dir.home, user: default_user)
        lines = text.to_s.lines
        events = lines.map { |line| parse(line) }
        workdir = events.compact.find { |e| e["type"] == "system" }&.dig("cwd")

        lines.zip(events).map do |line, event|
          next redact(line, home: home, workdir: workdir, user: user) if event.nil?

          event = event.slice(*SYSTEM_KEYS) if event["type"] == "system"
          redact("#{JSON.generate(event)}\n", home: home, workdir: workdir, user: user)
        end.join
      end

      def redact(text, home: Dir.home, workdir: nil, user: default_user)
        result = text.to_s.dup
        each_form(workdir) { |path| result = result.gsub(path, WORKDIR_PLACEHOLDER) }
        each_form(home) { |path| result = result.gsub(path, HOME_PLACEHOLDER) }
        result = redact_user(result, user)
        result.gsub(SOCKET_PATTERN, SOCKET_PLACEHOLDER)
      end

      # ls -la の所有者欄のように、パスの外に出てくる OS の利用者名。
      def redact_user(text, user)
        return text if user.nil? || user.length < MIN_USER_LENGTH

        text.gsub(/\b#{Regexp.escape(user)}\b/, USER_PLACEHOLDER)
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
