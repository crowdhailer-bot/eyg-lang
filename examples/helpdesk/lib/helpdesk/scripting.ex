defmodule Helpdesk.Scripting do
  use Ash.Domain, extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Helpdesk.Scripting.Script
  end
end
