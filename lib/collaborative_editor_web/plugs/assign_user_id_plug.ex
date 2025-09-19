defmodule CollaborativeEditorWeb.Plugs.AssignUserIdPlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        user_id = :erlang.unique_integer()
        put_session(conn, :user_id, user_id)

      _ ->
        conn
    end
  end
end
