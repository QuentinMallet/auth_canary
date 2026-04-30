# Load e2e environment variables written by test/e2e/bootstrap/03-setup.sh
# Run with: EXUNIT_EXTRAS=test/e2e_test_helper.exs mix test --only e2e
# Or source manually before running tests.
if File.exists?("test/e2e/data/e2e.env") do
  File.read!("test/e2e/data/e2e.env")
  |> String.split("\n", trim: true)
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [k, v] -> System.put_env(k, v)
      _ -> :ok
    end
  end)
end
