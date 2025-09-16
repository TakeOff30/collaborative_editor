defmodule CollaborativeEditor.Logger do
  use GenServer

  @default_log_file "lib/collaborative_editor/logger/peer_communication.log"

  #client callbacks

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Logs a message by sending a request to the named Logger process.
  """
  def log(message) do
    GenServer.cast(__MODULE__, {:log, message})
  end

  #server callbacks

  @impl GenServer
  def init(opts) do
    log_file = Keyword.get(opts, :file_name, @default_log_file)
    {:ok, file} = File.open(log_file, [:write, :utf8])

    {:ok,file}
  end

  @impl GenServer
  @spec handle_cast({:log, String.t()}, state :: File.io_device()) :: {:noreply, File.io_device()}
  def handle_cast({:log, message}, file) do
    IO.puts(file, message)
    {:noreply, file}
  end

  @impl true
  def terminate(_reason, file) do
    File.close(file)
  end
end
