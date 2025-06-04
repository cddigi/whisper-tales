defmodule VoxDialog.Repo do
  use Ecto.Repo,
    otp_app: :vox_dialog,
    adapter: Ecto.Adapters.Postgres
end
