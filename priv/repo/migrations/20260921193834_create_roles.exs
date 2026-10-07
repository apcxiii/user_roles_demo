defmodule UserRolesDemo.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def up do
    create table(:roles) do
      add :name, :string, null: false
      add :description, :string
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:roles, [:name])
    create index(:roles, [:active])
  end

  def down do
    drop table(:roles)
  end
end
