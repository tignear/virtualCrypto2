defmodule VirtualCrypto.Repo.Migrations.ClaimMetadata do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION metadata_limitation(json_obj in jsonb)
      RETURNS BOOLEAN
      LANGUAGE plpgsql
    AS
    $body$
    DECLARE
    entry RECORD;
    key_count INTEGER;
    BEGIN
      key_count := 0;
      FOR entry IN (
        SELECT * FROM jsonb_each(json_obj)
      )
      LOOP
        key_count := key_count + 1;
        IF length(entry.key::text) > 40 OR jsonb_typeof(entry.value) != 'string' OR length(entry.value::text) > 400 OR key_count > 50 THEN
          RETURN FALSE;
        END IF;
      END LOOP;
      RETURN TRUE;
    END;
    $body$;
    """)

    create table(:claim_metadata) do
      add(:claim_id, references(:claims, on_delete: :delete_all), null: false)
      add(:claimant_user_id, references(:users, on_delete: :delete_all), null: false)
      add(:payer_user_id, references(:users, on_delete: :delete_all), null: false)
      add(:owner_user_id, references(:users, on_delete: :delete_all), null: false)
      add(:metadata, :map, null: false)
    end

    execute("""
      ALTER TABLE claims
      ADD CONSTRAINT claims_unique_ordered_claim_metadata_fk UNIQUE (id, claimant_user_id, payer_user_id);
    """)

    execute("""
      ALTER TABLE claim_metadata
      ADD CONSTRAINT claim_metadata_fk
      FOREIGN KEY (claim_id, claimant_user_id, payer_user_id)
      REFERENCES claims(id, claimant_user_id, payer_user_id)
      ON DELETE CASCADE
    """)

    create(
      constraint(:claim_metadata, "metadata_owner_is_must_related_user",
        check: "owner_user_id IN (claimant_user_id,payer_user_id)"
      )
    )

    create(
      constraint(:claim_metadata, "metadata_limit",
        check: "jsonb_typeof(metadata) = 'object' AND metadata_limitation(metadata)"
      )
    )

    create(unique_index(:claim_metadata, [:claim_id, :owner_user_id]))
  end

  def down do
    execute("DROP TABLE claim_metadata")
    execute("DROP FUNCTION metadata_limitation(jsonb)")
    execute("ALTER TABLE claims DROP CONSTRAINT claims_unique_ordered_claim_metadata_fk")
  end
end
