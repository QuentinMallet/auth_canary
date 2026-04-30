defmodule AuthCanary.ErrorTest do
  use ExUnit.Case, async: true
  alias AuthCanary.Error

  describe "sanitize_reason/1" do
    test "returns 'http_404' for %Req.Response{status: 404}" do
      assert Error.sanitize_reason(%Req.Response{status: 404}) == "http_404"
    end

    test "returns 'http_200' for %Req.Response{status: 200}" do
      assert Error.sanitize_reason(%Req.Response{status: 200}) == "http_200"
    end

    test "returns 'http_500' for %Req.Response{status: 500}" do
      assert Error.sanitize_reason(%Req.Response{status: 500}) == "http_500"
    end

    test "returns message string for map with :message key" do
      assert Error.sanitize_reason(%{message: "some error"}) == "some error"
    end

    test "returns binary reason directly when <= 200 chars" do
      assert Error.sanitize_reason("binary reason") == "binary reason"
    end

    test "returns 'unknown_error' for atom input" do
      assert Error.sanitize_reason(:some_atom) == "unknown_error"
    end

    test "returns 'unknown_error' for nil input" do
      assert Error.sanitize_reason(nil) == "unknown_error"
    end

    test "returns 'unknown_error' for integer input" do
      assert Error.sanitize_reason(42) == "unknown_error"
    end

    test "returns 'unknown_error' for tuple input" do
      assert Error.sanitize_reason({:error, :timeout}) == "unknown_error"
    end

    test "truncates binary string longer than 200 chars to exactly 200 chars" do
      long = String.duplicate("x", 250)
      result = Error.sanitize_reason(long)
      assert byte_size(result) == 200
      assert result == String.slice(long, 0, 200)
    end

    test "truncates :message field longer than 200 chars to 200 chars" do
      long = String.duplicate("y", 300)
      result = Error.sanitize_reason(%{message: long})
      assert byte_size(result) == 200
    end

    test "passes through string of exactly 200 chars unchanged" do
      exact = String.duplicate("a", 200)
      assert Error.sanitize_reason(exact) == exact
    end

    test "passes through string shorter than 200 chars unchanged" do
      short = "short error message"
      assert Error.sanitize_reason(short) == short
    end
  end
end
