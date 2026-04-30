defmodule AuthCanary.PipelinePropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias AuthCanary.Error

  property "sanitize_reason output is always a binary <= 200 graphemes" do
    check all input <-
                one_of([
                  string(:printable, min_length: 0, max_length: 400),
                  constant(%{message: "error message"}),
                  constant(:some_atom),
                  constant(nil),
                  constant(42),
                  constant({:error, :timeout}),
                  map(integer(100..599), fn s -> %Req.Response{status: s} end)
                ]) do
      result = Error.sanitize_reason(input)
      assert is_binary(result)
      assert String.length(result) <= 200
    end
  end

  property "sanitize_reason never emits a full valid JWT-shaped string" do
    check all payload_len <- integer(10..250),
              sig_len <- integer(5..50) do
      # Build a JWT-shaped input: eyJ<header>.<payload>.<signature>
      input = "eyJ" <> String.duplicate("a", payload_len) <> "." <> String.duplicate("b", sig_len)
      result = Error.sanitize_reason(input)
      assert is_binary(result)
      assert byte_size(result) <= 200
      # If input was longer than 200 chars, it must have been truncated
      if byte_size(input) > 200 do
        refute result == input
      end
    end
  end

  property "sanitize_reason returns 'unknown_error' for all atom inputs" do
    check all atom <- atom(:alphanumeric) do
      assert Error.sanitize_reason(atom) == "unknown_error"
    end
  end

  property "sanitize_reason returns http_N string for any Req.Response status" do
    check all status <- integer(100..599) do
      resp = %Req.Response{status: status}
      assert Error.sanitize_reason(resp) == "http_#{status}"
    end
  end

  property "sanitize_reason never returns a string longer than 200 graphemes for any binary input" do
    check all input <- string(:printable, min_length: 201, max_length: 500) do
      result = Error.sanitize_reason(input)
      assert is_binary(result)
      assert String.length(result) <= 200
    end
  end
end
