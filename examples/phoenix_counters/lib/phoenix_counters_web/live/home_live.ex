defmodule PhoenixCountersWeb.HomeLive do
  use PhoenixCountersWeb, :live_view

  alias PhoenixCounters.{Counters, Scripts}
  alias PhoenixCounters.Counters.Eyg

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(500, :refresh)
    {:ok, assign(socket, check: nil, runs: [], counters: Counters.list())}
  end

  @impl true
  def handle_event("check", %{"source" => source}, socket) do
    {:noreply, assign(socket, check: check(source))}
  end

  def handle_event("run", %{"source" => source}, socket) do
    case Scripts.run(source) do
      {:ok, value} ->
        run = %{source: source, value: Eyg.inspect_value(value)}

        socket
        |> assign(check: nil, runs: [run | socket.assigns.runs], counters: Counters.list())
        |> push_event("clear", %{})
        |> then(&{:noreply, &1})

      {:error, errors} ->
        {:noreply, assign(socket, check: {:error, errors})}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, counters: Counters.list())}
  end

  # Only programs that parse are type checked, an unfinished program has no errors yet.
  defp check(source) do
    case Eyg.parse(source) do
      :ok -> Scripts.check(source)
      {:error, _} -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-bold">Counters</h1>
      <p>
        Script the counters with EYG. Effects: <code>StartCounter</code>, <code>SetTickRate</code>,
        <code>GetValue</code>
        and <code>Shutdown</code>.
      </p>

      <form id="script" phx-change="check" phx-submit="run" class="space-y-2">
        <div id="script-box" phx-hook="ScriptBox" phx-update="ignore" class="script-box">
          <pre aria-hidden="true"></pre>
          <textarea
            name="source"
            rows="6"
            spellcheck="false"
            autofocus
            phx-debounce="200"
            placeholder={"perform StartCounter(\"apples\")"}
          ></textarea>
        </div>
        <div class="flex items-center gap-4">
          <button type="submit" class="btn btn-primary">Run</button>
          <span class="text-sm opacity-70">Enter to run, shift + enter for a new line</span>
        </div>
      </form>

      <pre :if={match?({:error, _}, @check)} id="errors" class="errors">{elem(@check, 1)}</pre>
      <p :if={match?({:ok, _}, @check)} id="type" class="font-mono text-sm text-success">
        {elem(@check, 1)}
      </p>

      <table id="counters" class="table">
        <thead>
          <tr>
            <th>Counter</th><th>Value</th><th>Tick every</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={counter <- @counters}>
            <td>{counter.name}</td>
            <td>{counter.value}</td>
            <td>{counter.seconds}s</td>
          </tr>
        </tbody>
      </table>

      <div id="runs" class="space-y-2">
        <div :for={run <- @runs} class="run border-l-4 border-base-300 pl-3">
          <pre class="opacity-70">{run.source}</pre>
          <pre>{run.value}</pre>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
