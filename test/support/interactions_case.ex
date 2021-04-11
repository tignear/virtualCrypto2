defmodule VirtualCryptoWeb.InteractionsCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use VirtualCryptoWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import VirtualCryptoWeb.InteractionsCase
      import VirtualCryptoWeb.EnvironmentBootstrapper
      import VirtualCryptoWeb.ConditionChecker

      alias VirtualCryptoWeb.Router.Helpers, as: Routes
      alias VirtualCrypto.Repo
      # The default endpoint for testing
      @endpoint VirtualCryptoWeb.Endpoint

      def post_command(conn, body) do
        body = Jason.encode!(body)

        conn
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> sign_request(body)
        |> Phoenix.ConnTest.post(
          "/api/integrations/discord/interactions",
          body
        )
      end
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(VirtualCrypto.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(VirtualCrypto.Repo, {:shared, self()})
    end

    conn = Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("accept", "application/json")

    conn =
      if tags[:ctype] == :json do
        conn |> Plug.Conn.put_req_header("content-type", "application/json")
      else
        conn
      end

    {:ok,
     %{
       conn: conn
     }}
  end
end