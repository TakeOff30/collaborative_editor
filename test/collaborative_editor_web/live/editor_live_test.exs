defmodule CollaborativeEditorWeb.EditorLiveTest do
  use CollaborativeEditorWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    :ok = CollaborativeEditor.SessionHandler.reset_state()
    :ok
  end

  describe "EditorLive" do
    test "mounts and displays editor interface", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor/1")

      assert html =~ "textarea"
      assert html =~ "id=\"editor-1\""

      assert html =~ "phx-hook=\"Editor\""
      assert html =~ "Live Editor (Peer #1)"
    end

    test "handles text insertion via LiveView events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor/1")

      view
      |> render_hook("text_operation", %{
        "type" => "insert",
        "at" => 1,
        "char" => "H"
      })

      assert render(view)
    end

    test "handles text deletion via LiveView events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor/1")

      view
      |> render_hook("text_operation", %{
        "type" => "insert",
        "at" => 1,
        "char" => "H"
      })

      view
      |> render_hook("text_operation", %{
        "type" => "delete",
        "at" => 0
      })

      assert render(view)
    end

    test "displays network visualization and operation log", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor/1")

      assert html =~ "Network Visualization"
      assert html =~ "phx-hook=\"NetworkVisualization\""

      assert html =~ "Operation Log"
      assert html =~ "phx-hook=\"OperationLogger\""
      assert html =~ "Waiting for network activity..."
    end

    test "multiple peers can connect to different slots", %{conn: conn} do
      {:ok, view1, html1} = live(conn, ~p"/editor/1")
      assert html1 =~ "Live Editor (Peer #1)"

      {:ok, view2, html2} = live(conn, ~p"/editor/2")
      assert html2 =~ "Live Editor (Peer #2)"

      view1
      |> render_hook("text_operation", %{
        "type" => "insert",
        "at" => 1,
        "char" => "A"
      })

      view2
      |> render_hook("text_operation", %{
        "type" => "insert",
        "at" => 1,
        "char" => "B"
      })

      assert render(view1)
      assert render(view2)
    end

    test "handles peer updates via PubSub", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor/1")

      send(view.pid, {:peer_update})

      assert render(view)
    end

    test "handles document updates via PubSub", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor/1")

      send(view.pid, {:doc_update, "Hello World", 5})

      assert render(view)
    end

    test "redirects back to menu", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor/1")

      assert html =~ "Back to Menu"
      assert html =~ ~s(href="/")
    end
  end
end
