defmodule AuthCanary.Error do
  @doc "Sanitize error reasons to prevent token/secret leakage in logs"
  def sanitize_reason(%Req.Response{status: s}), do: "http_#{s}"
  def sanitize_reason(%{message: m}), do: String.slice(m, 0, 200)
  def sanitize_reason(other) when is_binary(other), do: String.slice(other, 0, 200)
  def sanitize_reason(_), do: "unknown_error"

  @doc "Normalize a pipeline step result into {:ok, val} | {:error, step, reason}"
  def wrap_step(step, fun) do
    case fun.() do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, step, sanitize_reason(reason)}
      other -> {:error, step, sanitize_reason(other)}
    end
  rescue
    e -> {:error, :unknown, sanitize_reason(e)}
  catch
    kind, value -> {:error, :unknown, sanitize_reason({kind, value})}
  end
end
