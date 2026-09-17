module Agent
  # 単一オリジン・短時間の実行しか想定しないので、名前と値の対応だけを持つ。
  # ドメイン・パス・期限は扱わない。
  class CookieJar
    def initialize
      @cookies = {}
    end

    def store(set_cookie_values)
      Array(set_cookie_values).each do |value|
        pair = value.split(";", 2).first.to_s.strip
        name, _, cookie_value = pair.partition("=")
        next if name.empty?

        @cookies[name] = cookie_value
      end
    end

    def header
      return nil if @cookies.empty?

      @cookies.map { |name, value| "#{name}=#{value}" }.join("; ")
    end

    def empty? = @cookies.empty?

    def to_h = @cookies.dup
  end
end
