ExUnit.start()

# Load support files
Code.require_file("support/conn_case.ex", __DIR__)

# Configure longer timeouts for performance tests
ExUnit.configure(
  exclude: [:performance],
  timeout: 30_000
)

# Run performance tests with special flag
if System.get_env("RUN_PERFORMANCE_TESTS") do
  ExUnit.configure(include: [:performance])
end
