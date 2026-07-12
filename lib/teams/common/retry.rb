# frozen_string_literal: true

module Teams
  module Common
    module Retry
      module_function

      # Retries the block with exponential backoff, mirroring the retry
      # helpers the TypeScript and Python SDKs use for stream sends.
      # jitter :full randomizes each wait between 0 and the capped delay;
      # :none waits the capped delay exactly.
      def call(max_attempts: 5, delay: 0.5, max_delay: 30.0, jitter: :full, non_retryable: [], logger: nil)
        attempt = 1
        begin
          yield
        rescue *non_retryable
          raise
        rescue StandardError => error
          raise if attempt >= max_attempts

          capped = [delay * (2**(attempt - 1)), max_delay].min
          wait = jitter == :full ? rand * capped : capped
          logger&.debug("retrying in #{format('%.2f', wait)}s (attempt #{attempt}/#{max_attempts}): #{error.message}")
          sleep(wait)
          attempt += 1
          retry
        end
      end
    end
  end
end
