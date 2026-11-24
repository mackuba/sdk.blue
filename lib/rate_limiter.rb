module RateLimiter
  LIMITS = {
    'crates.io' => { count: 1, interval: 1 },
  }

  @request_times = {}
  @mutex = Mutex.new

  class << self
    def request(uri)
      host = uri.host
      policy = LIMITS[host]
      return unless policy

      count = policy.fetch(:count)
      interval = policy.fetch(:interval)
      delay = nil

      loop do
        @mutex.synchronize {
          @request_times[host] ||= []
          timestamps = @request_times[host]

          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          cleanup_old_timestamps(timestamps, older_than: now - interval)

          if timestamps.length < count
            timestamps << now
            return
          else
            expiration_time = timestamps.first + interval
            delay = expiration_time - now
          end
        }

        sleep(delay)
      end
    end

    private

    def cleanup_old_timestamps(timestamps, older_than:)
      while timestamps.first && timestamps.first <= older_than
        timestamps.shift
      end
    end
  end
end
