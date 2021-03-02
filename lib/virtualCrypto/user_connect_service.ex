defmodule VirtualCrypto.ConnectUser do
  alias VirtualCrypto.Repo
  import Ecto.Query

  def execute(base_user_id, source_user_id) do
    Repo.transaction(fn ->
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # merge base_user and from_user asset
      {:ok, assets} =
        Repo.delete_all(
          from(assets in VirtualCrypto.Money.Asset,
            where: assets.user_id == ^source_user_id,
            select: {assets.money_id, assets.amount}
          )
        )

      Repo.insert_all(
        VirtualCrypto.Money.Asset,
        assets
        |> Enum.map(fn {money_id, amount} ->
          [
            amount: amount,
            status: 0,
            user_id: base_user_id,
            money_id: money_id,
            inserted_at: now,
            updated_at: now
          ]
        end),
        on_conflict:
          from(assets in VirtualCrypto.Money.Asset,
            update: [inc: [amount: fragment("EXCLUDED.amount")]]
          ),
        conflict_target: {:money_id, :user_id}
      )

      # replace user_id of histories
      Repo.update_all(
        from(histories in VirtualCrypto.Money.GivenHistory,
          where: histories.receiver_id == ^source_user_id,
          update: [set: [receiver_id: ^base_user_id]]
        ),
        []
      )

      Repo.update_all(
        from(histories in VirtualCrypto.Money.PaymentHistory,
          where: histories.receiver_id == ^source_user_id,
          update: [set: [receiver_id: ^base_user_id]]
        ),
        []
      )

      Repo.update_all(
        from(histories in VirtualCrypto.Money.PaymentHistory,
          where: histories.sender_id == ^source_user_id,
          update: [set: [sender_id: ^base_user_id]]
        ),
        []
      )

      # replace user_id of claims
      Repo.update_all(
        from(claims in VirtualCrypto.Money.Claim,
          where: claims.claimant_user_id == ^source_user_id,
          update: [set: [sender_id: ^base_user_id]]
        ),
        []
      )

      Repo.update_all(
        from(claims in VirtualCrypto.Money.Claim,
          where: claims.payer_user_id == ^source_user_id,
          update: [set: [sender_id: ^base_user_id]]
        ),
        []
      )
    end)
  end
end