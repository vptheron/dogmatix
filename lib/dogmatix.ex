defmodule Dogmatix do
  @moduledoc """
  This module provides the main API to interface with a StasD/DogStatsD agent.

  ## Getting started

  A new instance of Dogmatix can be started via the `start_link/2` function:

      {:ok, pid} = Dogmatix.start_link("my_dogmatix", "localhost", 8125)

  This will create a new instance named "my_dogmatix", communicating via UDP with an agent located at `localhost:8125`.
  This instance will use all the default options.

  ### Instantiation via a custom module

      defmodule MyApp.Dogmatix do
        use Dogmatix
      end

      MyApp.Dogmatix.start_link("localhost", 8125)

  Your custom module can then be used without having to provide the name of your Dogmatix instance:

      MyApp.Dogmatix.increment("my_counter")

  ### Configuration

  Various options can be provided to `start_link` to configure the instance:

    * `:worker_count` - (positive integer) - number of UDP sockets and workers used to distribute the metrics.  Defaults to `4`.

    * `:prefix` - (binary) - all metrics sent to the agent will be prefixed with this value.  Not set by default.

    * `:tags` - ([binary]) - a list of tags to be sent with all metrics.  Format: `["tag1:value1", "tag2:value2"]`.  Not set by default.

    * `:max_datagram_size` - (integer) - the maximum number of bytes for a message that can be sent.  Defaults to `1432`.

    * `:buffer_flush_ms` - (integer) - metric flush interval in milliseconds.  Defaults to `500`.

  ## Sending metrics

  The module provides the functions to send all the supported metrics, event and service checks to the agent.

  All the functions accept the following options:

    * `:tags` - ([binary]) - to add metric specific tags to the global tags

    * `:timeout` - (integer) - a timeout value in milliseconds to be used when calling a worker from the pool.  Defaults to `1000`.

  ## Sampling

  All metric-sending functions support a `:sample_rate` options.  A sample rate is a float between 0 and 1 representing
  the percentage of packets that are effectively sent to the agent.

      Dogmatix.count("my_dogmatix", "current_users", 1, sample_rate: 0.2)

  In the example above, only 20% of the calls will effectively send a packet to the agent.  Agents supporting sampling
  will adjust the value according to the sample rate.

  ## Tagging

  Metrics, events and service checks can be tagged to add dimensions to their information. Note that not all agents
  support this feature.

  Constant tags can be defined when instantiating a Dogmatix client:

      Dogmatix.start_link("my_dogmatix", "localhost", 8125, tags: ["env:dev"])

  In the example above, all metrics, events and service checks sent with this instance will be tagged with "env:dev".

  Additionally, all functions support the `:tags` option to add ad-hoc tags.

      Dogmatix.increment("my_dogmatix", "page_views", tags: ["page:home"])

  In the example above, the metric "page_views" will be tagged with both "page:home" (and "env:dev").

  ## Pooling

  For each instance of Dogmatix, a pool of worker/socket is started to format and send datagrams.  The amount of workers
  can be configured via the `:worker_count` options when starting the instance.

  ## Metric Buffering

  In order to reduce network traffic, Dogmatix supports metric buffering.  It attempts to group as many metrics as
  possible into a single datagram before sending to the agent.  This behavior can be configured via two instantiation
  options:

  ### `:max_datagram_size`

  An integer representing the maximum size in bytes of a datagram.  Make sure to configure a size that does not exceed
  the Agent-side per-datagram buffer size or the network/OS max datagram size.  The default value is `1432` - the largest
  possible size given the Ethernet MTU of 1514 bytes.

  ### `:buffer_flush_ms`

  An integer representing in milliseconds the frequency of datagram buffer flush.  Each worker/socket maintains its
  own local buffered datagram, i.e. an accumulation of metrics to be sent once the size of the datagram reaches the
  maximum possible size of a packet.  For the case where your application does not capture metrics frequently, Dogmatix
  will regularly flush these buffers to make sure that buffered metrics are sent to the agent in a timely manner.

  The default value is `500`.

  If your application is so "metric intensive" that there is no chance of seeing your metrics lingering in the buffer,
  you can disable this behavior completely by setting this option to `0`.
  """

  use Supervisor

  alias Dogmatix.Event
  alias Dogmatix.ServiceCheck
  alias Dogmatix.SocketWorker

  @default_call_timeout 1000
  @default_worker_count 4

  @type id :: binary | atom

  @type start_option ::
          {:worker_count, pos_integer}
          | {:prefix, binary}
          | {:tags, [binary]}
          | {:max_datagram_size, pos_integer}
          | {:buffer_flush_ms, non_neg_integer}

  @type start_options :: [start_option]

  @type metric_option ::
          {:tags, [binary]}
          | {:timeout, non_neg_integer}

  @type metric_options :: [metric_option]

  @type metric_result :: :ok | {:error, binary}

  @type metric_value :: integer | float

  @doc """
  Starts a new pool of connection to an agent.

    * `name` - a binary or an atom to identify this instance of Dogmatix
    * `host` - a binary, the agent's host
    * `port` - a positive integer, the agent's host

  ## Options

  See the module documentation for details.

    * `:worker_count` - (positive integer) - number of UDP sockets and workers used to distribute the metrics.  Defaults to `4`.
    * `:prefix` - (binary) - all metrics sent to the agent will be prefixed with this value.  Not set by default.
    * `:tags` - ([binary]) - a list of tags to be sent with all metrics.  Format: `["tag1:value1", "tag2:value2"]`.  Not set by default.
    * `:max_datagram_size` - (integer) - the maximum number of bytes for a message that can be sent.  Defaults to `1432`.
    * `:buffer_flush_ms` - (integer) - metric flush interval in milliseconds.  Defaults to `500`. `0` to disable.
  """
  @spec start_link(id, binary, pos_integer, start_options) :: Supervisor.on_start()
  def start_link(name, host, port, opts \\ []) when is_binary(host) and is_integer(port) do
    Supervisor.start_link(__MODULE__, {name, host, port, opts})
  end

  @doc """
  Increments the counter identified by `metric_name` by 1.

  Equivalent to calling `count/4` with a `value` of 1.

  ## Examples

      iex> Dogmatix.increment("my_dogmatix", "page_views")
      :ok
  """
  @spec increment(id, binary, metric_options) :: metric_result
  def increment(name, metric_name, opts \\ []), do: count(name, metric_name, 1, opts)

  @doc """
  Decrements the counter identified by `metric_name` by 1.

  Equivalent to calling `count/4` with a `value` of -1.

  ## Examples

      iex> Dogmatix.decrement("my_dogmatix", "current_users")
      :ok
  """
  @spec decrement(id, binary, metric_options) :: metric_result
  def decrement(name, metric_name, opts \\ []), do: count(name, metric_name, -1, opts)

  @doc """
  Changes the counter identified by `metric_name` by the given `value`.

  ## Examples

      iex> Dogmatix.count("my_dogmatix", "cache_hits", 4)
      :ok
  """
  @spec count(id, binary, metric_value, metric_options) :: metric_result
  def count(name, metric_name, value, opts \\ []), do: metric(name, metric_name, value, "c", opts)

  @doc """
  Sets the value of the gauge identified by `metric_name` to the given `value`.

  ## Examples

      iex> Dogmatix.gauge("my_dogmatix", "disk_usage", 0.75)
      :ok
  """
  @spec gauge(id, binary, metric_value, metric_options) :: metric_result
  def gauge(name, metric_name, value, opts \\ []), do: metric(name, metric_name, value, "g", opts)

  @doc """
  Writes `value` to the timer identified by `metric_name`.

  ## Examples

      iex> Dogmatix.timer("my_dogmatix", "query_latency", 15)
      :ok
  """
  @spec timer(id, binary, metric_value, metric_options) :: metric_result
  def timer(name, metric_name, value, opts \\ []), do: metric(name, metric_name, value, "ms", opts)

  @doc """
  Writes `value` to the histogram identified by `metric_name`.

  ## Examples

      iex> Dogmatix.histogram("my_dogmatix", "page_views", 15)
      :ok
  """
  @spec histogram(id, binary, metric_value, metric_options) :: metric_result
  def histogram(name, metric_name, value, opts \\ []), do: metric(name, metric_name, value, "h", opts)

  @doc """
  Writes `value` to the set identified by `metric_name`.

  ## Examples

      iex> Dogmatix.set("my_dogmatix", "metric.set", 42)
      :ok
  """
  @spec set(id, binary, metric_value, metric_options) :: metric_result
  def set(name, metric_name, value, opts \\ []), do: metric(name, metric_name, value, "s", opts)

  @doc """
  Writes `value` to the distribution identified by `metric_name`.

  ## Examples

      iex> Dogmatix.set("my_dogmatix", "response_time", 9)
      :ok
  """
  @spec distribution(id, binary, metric_value, metric_options) :: metric_result
  def distribution(name, metric_name, value, opts \\ []), do: metric(name, metric_name, value, "d", opts)

  @doc """
  Sends the provided event.

  ## Examples

      iex> Dogmatix.event("my_dogmatix", %Dogmatix.Event{title: "An error occurred", text: "Error message"})
      :ok
  """
  @spec event(id, Dogmatix.Event.t()) :: metric_result
  def event(name, %Event{} = event, opts \\ []),
    do: send_to_worker(name, {:event, event, opts}, opts[:timeout] || @default_call_timeout)

  @doc """
  Sends the provided service check.

  ## Examples

      iex> Dogmatix.event("my_dogmatix", %Dogmatix.ServiceCheck{name: "application_check", status: :ok, message: "All good!"})
      :ok
  """
  @spec service_check(id, Dogmatix.ServiceCheck.t()) :: metric_result
  def service_check(name, %ServiceCheck{} = sc, opts \\ []),
    do: send_to_worker(name, {:service_check, sc, opts}, opts[:timeout] || @default_call_timeout)

  defp metric(name, metric_name, value, type, opts) do
    case apply_sampling(opts[:sample_rate]) do
      :send ->
        send_to_worker(name, {:metric, metric_name, value, opts, type}, opts[:timeout] || @default_call_timeout)

      :drop ->
        :ok
    end
  end

  defp apply_sampling(nil), do: :send

  defp apply_sampling(rate) do
    if :rand.uniform() > rate,
      do: :drop,
      else: :send
  end

  defp send_to_worker(name, message, timeout) do
    workers = Registry.lookup(registry_name(name), :workers)
    {pid, _value = nil} = Enum.random(workers)
    GenServer.call(pid, message, timeout)
  end

  defp registry_name(name), do: :"dogmatix_#{name}_registry"

  ## Callbacks

  @doc false
  @impl true
  def init({name, host, port, opts}) do
    worker_count = opts[:worker_count] || @default_worker_count
    registry_name = registry_name(name)

    worker_specs =
      for idx <- 1..worker_count do
        Supervisor.child_spec({SocketWorker, {registry_name, host, port, opts}}, id: {name, SocketWorker, idx})
      end

    worker_supervisor_spec = %{
      id: :"#{name}_worker_supervisor",
      type: :supervisor,
      start: {Supervisor, :start_link, [worker_specs, [strategy: :one_for_one]]}
    }

    children = [
      {Registry, name: registry_name, keys: :duplicate},
      worker_supervisor_spec
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  ## Macro syntax

  defmacro __using__(_opts) do
    quote do
      def start_link(host, port, opts \\ []) when is_binary(host) and is_integer(port) do
        Dogmatix.start_link(__MODULE__, host, port, opts)
      end

      def increment(metric_name, opts \\ []), do: Dogmatix.increment(__MODULE__, metric_name, opts)

      def decrement(metric_name, opts \\ []), do: Dogmatix.decrement(__MODULE__, metric_name, opts)

      def count(metric_name, value, opts \\ []), do: Dogmatix.count(__MODULE__, metric_name, value, opts)

      def gauge(metric_name, value, opts \\ []), do: Dogmatix.gauge(__MODULE__, metric_name, value, opts)

      def timer(metric_name, value, opts \\ []), do: Dogmatix.timer(__MODULE__, metric_name, value, opts)

      def histogram(metric_name, value, opts \\ []), do: Dogmatix.histogram(__MODULE__, metric_name, value, opts)

      def set(metric_name, value, opts \\ []), do: Dogmatix.set(__MODULE__, metric_name, value, opts)

      def distribution(metric_name, value, opts \\ []), do: Dogmatix.distribution(__MODULE__, metric_name, value, opts)

      def event(%Event{} = event, opts \\ []), do: Dogmatix.event(__MODULE__, event, opts)

      def service_check(%ServiceCheck{} = sc, opts \\ []), do: Dogmatix.service_check(__MODULE__, sc, opts)
    end
  end
end
