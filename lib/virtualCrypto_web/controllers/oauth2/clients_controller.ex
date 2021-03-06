defmodule VirtualCryptoWeb.OAuth2.ClientsController do
  use VirtualCryptoWeb, :controller
  alias VirtualCrypto.Auth
  alias VirtualCrypto.User
  alias VirtualCrypto.DiscordAuth
  alias VirtualCrypto.Auth.Application.Metadata.Validator, as: Validator

  defp fetch(m, k, e) do
    case Map.fetch(m, k) do
      :error -> {:error, e}
      {:ok, v} -> v
    end
  end

  defp get_and_compute(req) do
    fn km, validater ->
      case Map.fetch(req, to_string(km)) do
        {:ok, v} ->
          case validater.(v) do
            {:ok, v} -> %{km => v}
            {:error, _} = err -> err
          end

        :error ->
          %{}
      end
    end
  end

  def get(conn, %{"user" => "@me"}) do
    with cr <- Guardian.Plug.current_resource(conn),
         {{:validate_token, :invalid_token}, %{"sub" => user_id, "kind" => "user"}} <-
           {{:validate_token, :invalid_token}, cr},
         {{:validate_token, :insufficient_scope}, %{"oauth2.register" => true}} <-
           {{:validate_token, :insufficient_scope}, cr} do
      conn |> render("clients.register.json", applications: Auth.get_user_applications(user_id))
    else
      {{:validate_token, :invalid_token}, _} ->
        conn
        |> put_status(401)
        |> render("error.register.json",
          error: :invalid_token,
          error_description: :invalid_kind
        )

      {{:validate_token, :insufficient_scope}, _} ->
        conn
        |> put_status(403)
        |> render("error.register.json",
          error: :insufficient_scope,
          error_description: :required_oauth2_register
        )
    end
  end

  def get(conn, _) do
    conn
    |> put_status(400)
    |> render("error.register.json",
      error: :invalid_request,
      error_description: :required_user_parameter
    )
  end

  def post(conn, req) do
    f = get_and_compute(req)

    params =
      with cr <- Guardian.Plug.current_resource(conn),
           {{:validate_token, :token_verification_failed}, %{"sub" => user_id, "kind" => "user"}} <-
             {{:validate_token, :token_verification_failed}, cr},
           {{:validate_scope, :required_oauth2_register_scope}, %{"oauth2.register" => true}} <-
             {{:validate_scope, :required_oauth2_register_scope}, cr},
           {{:validate_token, :invalid_user}, %User.User{discord_id: owner_discord_id}} <-
             {{:validate_token, :invalid_user}, User.get_user_by_id(user_id)},
           {{:validate_token, :getting_discord_access_token_failed_while_user_verification},
            %DiscordAuth.DiscordUser{token: discord_access_token}} <-
             {{:validate_token, :getting_discord_access_token_failed_while_user_verification},
              DiscordAuth.refresh_user(owner_discord_id)},
           {{:validate_token, :user_verification_failed}, false} <-
             {{:validate_token, :user_verification_failed},
              Map.get(Discord.Api.V8.OAuth2.get_user_info(discord_access_token), "bot", false)},
           %{} = response_types <- f.(:response_types, &Validator.validate_response_types/1),
           %{} = grant_types <- f.(:grant_types, &Validator.validate_grant_types/1),
           %{} = application_type <-
             f.(:application_type, &Validator.validate_application_type/1),
           %{} = client_name <- f.(:client_name, &{:ok, &1}),
           %{} = client_uri <- f.(:client_uri, &Validator.validate_client_uri/1),
           %{} = logo_uri <- f.(:logo_uri, &Validator.validate_logo_uri/1),
           %{} = discord_support_server_invite_slug <-
             f.(
               :discord_support_server_invite_slug,
               &Validator.validate_discord_support_server_invite_slug/1
             ),
           redirect_uris when is_list(redirect_uris) <-
             fetch(req, "redirect_uris", {:invalid_redirect_uri, :redirect_uris_must_be_array}),
           {:validate_redirect_uris, true} <-
             {:validate_redirect_uris,
              redirect_uris |> Enum.all?(&(URI.parse(&1).scheme in ["http", "https"]))} do
        Auth.register_application(
          %{
            redirect_uris: redirect_uris,
            owner_discord_id: owner_discord_id
          }
          |> Map.merge(response_types)
          |> Map.merge(application_type)
          |> Map.merge(client_name)
          |> Map.merge(grant_types)
          |> Map.merge(client_uri)
          |> Map.merge(logo_uri)
          |> Map.merge(discord_support_server_invite_slug)
        )
      else
        {{:validate_token, more}, _} ->
          {:error, {:invalid_token, more}}

        {{:validate_scope, more}, _} ->
          {:error, {:insufficient_scope, more}}

        {:validate_redirect_uris, _} ->
          {:error, {:invalid_redirect_uri, :redirect_uri_scheme_must_be_http_or_https}}

        err ->
          err
      end

    case params do
      {:ok, application_data} ->
        {:ok, access_token, _} =
          VirtualCrypto.Guardian.issue_token_for_app(application_data.user.id, [
            "oauth2.register"
          ])

        conn
        |> put_status(201)
        |> render("ok.register.json",
          application: application_data.application,
          registration_access_token: access_token,
          registration_client_uri:
            Application.get_env(:virtualCrypto, :site_url)
            |> URI.parse()
            |> Map.put(:path, "/oauth2/clients/@me")
            |> URI.to_string()
        )

      {:error, {:invalid_token, more}} ->
        conn
        |> put_status(401)
        |> render("error.register.json", error: :invalid_token, error_description: more)

      {:error, {:insufficient_scope, more}} ->
        conn
        |> put_status(403)
        |> render("error.register.json", error: :insufficient_scope, error_description: more)

      {:error, {error, error_description}} ->
        conn
        |> put_status(400)
        |> render("error.register.json", error: error, error_description: error_description)
    end
  end
end
