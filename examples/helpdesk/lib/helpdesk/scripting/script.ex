defmodule Helpdesk.Scripting.Script do
  @moduledoc "Run EYG scripts against the helpdesk."
  use Ash.Resource,
    domain: Helpdesk.Scripting,
    extensions: [AshAdmin.Resource]

  admin do
    form do
      field :source, type: :long_text
    end
  end

  actions do
    action :run, :string do
      argument :source, :string, allow_nil?: false

      run {AshEyg.RunScript,
           otp_app: :helpdesk,
           packages: %{"standard" => Application.compile_env!(:helpdesk, :standard_library)}}
    end
  end
end
