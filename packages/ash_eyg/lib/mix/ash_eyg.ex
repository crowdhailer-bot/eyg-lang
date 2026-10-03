defmodule AshEyg.Mix do
  @moduledoc false

  # Start the application and read the script from a file or `-e`.
  def setup(args) do
    source =
      case OptionParser.parse(args, strict: [eval: :string], aliases: [e: :eval]) do
        {[eval: source], [], []} -> source
        {[], [path], []} -> File.read!(path)
        _ -> Mix.raise("expected a path to a script or -e followed by a script")
      end

    Mix.Task.run("app.start")
    {source, Mix.Project.config()[:app]}
  end
end
