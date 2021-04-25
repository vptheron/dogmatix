defmodule Dogmatix.SocketWorker do
  @moduledoc false

  use GenServer

  alias Dogmatix.Datagrams
  alias Dogmatix.Event
  alias Dogmatix.ServiceCheck

  @default_buffer_flush_ms 500
  @default_max_datagram_size 1432

  defstruct [
    :socket,
    :destination,
    :global,
    :buffered_datagram,
    :buffer_flush_ms,
    :max_datagram_size
  ]

  def start_link({registry_name, host, port, opts}) when is_binary(host) and is_integer(port) do
    GenServer.start_link(__MODULE__, {registry_name, host, port, opts})
  end

  @impl true
  def init({registry_name, host, port, opts}) do
    with {:ok, socket} <- :gen_udp.open(0),
         host_char = String.to_charlist(host),
         {:ok, address} <- :inet.getaddr(host_char, :inet) do
      state = %__MODULE__{
        socket: socket,
        destination: {address, port},
        global: Datagrams.prepare_global(opts[:prefix], opts[:tags]),
        buffered_datagram: [],
        buffer_flush_ms: opts[:buffer_flush_ms] || @default_buffer_flush_ms,
        max_datagram_size: opts[:max_datagram_size] || @default_max_datagram_size
      }

      schedule_flush(state)

      Registry.register(registry_name, :workers, _value = nil)

      {:ok, state}
    else
      {:error, reason} ->
        {:stop, "Failed to open a socket: #{reason}"}
    end
  end

  @impl true
  def handle_call({:metric, name, value, opts, type}, _from, state) do
    Datagrams.metric_datagram(state.global, name, value, opts, type)
    |> handle_datagram(state)
  end

  @impl true
  def handle_call({:event, %Event{} = event, opts}, _from, state) do
    Datagrams.event_datagram(state.global, event, opts)
    |> handle_datagram(state)
  end

  @impl true
  def handle_call({:service_check, %ServiceCheck{} = sc, opts}, _from, state) do
    Datagrams.service_check_datagram(state.global, sc, opts)
    |> handle_datagram(state)
  end

  @impl true
  def handle_info(:buffer_flush, state) do
    if state.buffered_datagram != [] do
      :gen_udp.send(state.socket, state.destination, state.buffered_datagram)
    end

    schedule_flush(state)

    {:noreply, %{state | buffered_datagram: []}}
  end

  defp handle_datagram(datagram, state) do
    new_buffered_datagram = append_datagram(state.buffered_datagram, datagram)

    cond do
      IO.iodata_length(datagram) > state.max_datagram_size ->
        {:reply, {:error, "Payload is too big (more than #{state.max_datagram_size} bytes), dropped."}, state}

      IO.iodata_length(new_buffered_datagram) > state.max_datagram_size ->
        :gen_udp.send(state.socket, state.destination, state.buffered_datagram)
        {:reply, :ok, %{state | buffered_datagram: datagram}}

      true ->
        {:reply, :ok, %{state | buffered_datagram: new_buffered_datagram}}
    end
  end

  defp schedule_flush(%{buffer_flush_ms: buffer_flush_ms}) when buffer_flush_ms > 0,
    do: Process.send_after(self(), :buffer_flush, buffer_flush_ms)

  defp schedule_flush(_), do: :ok

  defp append_datagram([], first_datagram), do: first_datagram
  defp append_datagram(current_buffer, datagram), do: [current_buffer, "\n", datagram]
end
