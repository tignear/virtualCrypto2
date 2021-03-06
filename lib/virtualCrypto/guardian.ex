defmodule VirtualCrypto.Guardian do
  use Guardian, otp_app: :virtualCrypto
  import Ecto.Query
  @impl Guardian
  def subject_for_token(resource, _claims) do
    # You can use any value for the subject of your token but
    # it should be useful in retrieving the resource later, see
    # how it being used on `resource_from_claims/1` function.
    # A unique `id` is a good subject, a non-unique email address
    # is a poor subject.
    sub = to_string(resource.id)
    {:ok, sub}
  end

  @impl Guardian
  def resource_from_claims(claims) do
    scopes = Map.get(claims, "scopes", [])

    {
      :ok,
      %{
        "sub" => String.to_integer(claims["sub"]),
        "oauth2.register" => "oauth2.register" in scopes,
        "vc.pay" => "vc.pay" in scopes,
        "vc.claim" => "vc.claim" in scopes,
        "kind" => claims["kind"]
      }
    }
  end

  def issue_token_for_user(id, scopes) when is_list(scopes) do
    encode_and_sign(
      %{id: id},
      %{
        "scopes" => scopes,
        "kind" => "user",
        "jti" => Ecto.UUID.generate()
      },
      ttl: {1, :hour}
    )
  end

  def issue_token_for_app(id, scopes) when is_list(scopes) do
    encode_and_sign(
      %{id: id},
      %{
        "scopes" => scopes,
        "kind" => "app",
        "jti" => Ecto.UUID.generate()
      },
      ttl: {1, :hour}
    )
  end

  @impl Guardian
  def after_encode_and_sign(
        _resource,
        %{"kind" => kind, "jti" => token_id, "exp" => expires, "sub" => user_id},
        token,
        _options
      )
      when kind in ["user", "app"] do
    VirtualCrypto.Repo.insert!(%VirtualCrypto.Auth.UserAccessToken{
      user_id: String.to_integer(user_id),
      token_id: token_id,
      expires: expires |> DateTime.from_unix!() |> DateTime.to_naive()
    })

    {:ok, token}
  end

  @impl Guardian
  def after_encode_and_sign(_resource, _cliams, _token, _options) do
    {:error, :invalid_kind}
  end

  @impl Guardian
  def verify_claims(%{"kind" => kind, "jti" => token_id} = claims, _options)
      when kind in ["user", "app"] do
    q =
      from uat in VirtualCrypto.Auth.UserAccessToken,
        where: uat.token_id == ^token_id

    case VirtualCrypto.Repo.exists?(q) do
      true ->
        {:ok, claims}

      false ->
        {:error, :token_not_found}
    end
  end

  @impl Guardian
  def verify_claims(_cliams, _options) do
    {:error, :invalid_kind}
  end

  @impl Guardian
  def on_revoke(claims, _token, _options) do
    revoke_with_jti(claims)
    {:ok, claims}
  end

  def revoke_with_jti(%{"kind" => kind, "jti" => jti}) when kind in ["app", "user"] do
    q =
      from uat in VirtualCrypto.Auth.UserAccessToken,
        where: uat.token_id == ^jti

    VirtualCrypto.Repo.delete_all(q)
  end
end
