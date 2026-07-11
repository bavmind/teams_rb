# frozen_string_literal: true

require_relative "test_helper"

class RetryTest < Minitest::Test
  def test_returns_result_on_success
    attempts = 0
    result = Teams::Common::Retry.call(delay: 0.001) do
      attempts += 1
      "ok"
    end

    assert_equal "ok", result
    assert_equal 1, attempts
  end

  def test_retries_transient_errors_until_success
    attempts = 0
    result = Teams::Common::Retry.call(max_attempts: 5, delay: 0.001, jitter: :none) do
      attempts += 1
      raise Teams::HttpError.new("boom", status: 500, headers: {}, body: "") if attempts < 3

      "ok"
    end

    assert_equal "ok", result
    assert_equal 3, attempts
  end

  def test_raises_after_max_attempts
    attempts = 0
    assert_raises(Teams::HttpError) do
      Teams::Common::Retry.call(max_attempts: 3, delay: 0.001, jitter: :none) do
        attempts += 1
        raise Teams::HttpError.new("boom", status: 500, headers: {}, body: "")
      end
    end

    assert_equal 3, attempts
  end

  def test_non_retryable_errors_raise_immediately
    attempts = 0
    assert_raises(Teams::TerminalStreamError) do
      Teams::Common::Retry.call(max_attempts: 5, delay: 0.001, non_retryable: [Teams::TerminalStreamError]) do
        attempts += 1
        raise Teams::TerminalStreamError, "terminal"
      end
    end

    assert_equal 1, attempts
  end

  def test_non_retryable_covers_subclasses
    attempts = 0
    assert_raises(Teams::StreamTimedOutError) do
      Teams::Common::Retry.call(max_attempts: 5, delay: 0.001, non_retryable: [Teams::TerminalStreamError]) do
        attempts += 1
        raise Teams::StreamTimedOutError, "timed out"
      end
    end

    assert_equal 1, attempts
  end
end
