# 実験環境のサーバの時計を EXPERIMENT_TODAY の 09:00 起点に合わせる。
# 凍結ではなく時差なので、時刻は起点から進み続ける。
# これで Time.current、Date.current と、created_at、updated_at などの書き込み時刻が、
# overdue? や JSON の today と同じ「今日」の世界になる。
#
# ActiveSupport の travel は Rails 7 以降、時刻を止める（travel_to と同じ）ので使わない。
# Time.now と Date.today に一定の差分を足す。
module ExperimentClock
  START_HOUR = 9

  module TimeShift
    def now(...)
      time = super
      offset = ExperimentClock.offset
      offset ? time + offset : time
    end
  end

  module DateShift
    def today(...)
      offset = ExperimentClock.offset
      offset ? Time.now.to_date : super
    end
  end

  class << self
    attr_reader :offset

    def start(today)
      date = today.is_a?(Date) ? today : Date.iso8601(today.to_s)
      origin = Time.zone.local(date.year, date.month, date.day, START_HOUR)
      install
      @offset = origin - Time.now
      origin
    end

    def stop = @offset = nil

    private

    def install
      return if Time.singleton_class.include?(TimeShift)

      Time.singleton_class.prepend(TimeShift)
      Date.singleton_class.prepend(DateShift)
    end
  end
end
