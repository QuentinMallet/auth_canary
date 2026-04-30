defmodule AuthCanary.Error do
  @doc "Sanitize error reasons to prevent token/secret leakage in logs"
  def sanitize_reason(%Req.Response{status: s}), do: "http_#{s}"
  def sanitize_reason(%{message: m}), do: String.slice(m, 0, 200)
  def sanitize_reason(other) when is_binary(other), do: String.slice(other, 0, 200)
  def sanitize_reason(_), do: "unknown_error"
end
