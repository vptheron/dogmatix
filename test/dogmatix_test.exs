defmodule DogmatixTest do
  use ExUnit.Case

  alias Dogmatix.Event
  alias Dogmatix.ServiceCheck

  setup do
    {:ok, socket} = :gen_udp.open(1234)

    on_exit(fn ->
      :gen_udp.close(socket)
    end)

    :ok
  end

  describe "metrics" do
    test "increment" do
      {:ok, dog} = fast_flush_dogmatix(:increment)
      Dogmatix.increment(:increment, "my_counter")
      assert_receive {:udp, _, _, _, 'my_counter:1|c'}
      Supervisor.stop(dog)
    end

    test "decrement" do
      {:ok, dog} = fast_flush_dogmatix(:decrement)
      Dogmatix.decrement(:decrement, "my_counter")
      assert_receive {:udp, _, _, _, 'my_counter:-1|c'}
      Supervisor.stop(dog)
    end

    test "count" do
      {:ok, dog} = fast_flush_dogmatix(:count)
      Dogmatix.count(:count, "my_counter", 42)
      assert_receive {:udp, _, _, _, 'my_counter:42|c'}
      Dogmatix.count(:count, "my_counter", -3)
      assert_receive {:udp, _, _, _, 'my_counter:-3|c'}
      Supervisor.stop(dog)
    end

    test "gauge" do
      {:ok, dog} = fast_flush_dogmatix(:gauge)
      Dogmatix.gauge(:gauge, "my_gauge", 14)
      assert_receive {:udp, _, _, _, 'my_gauge:14|g'}
      Supervisor.stop(dog)
    end

    test "histogram" do
      {:ok, dog} = fast_flush_dogmatix(:histogram)
      Dogmatix.histogram(:histogram, "my_histogram", 14)
      assert_receive {:udp, _, _, _, 'my_histogram:14|h'}
      Supervisor.stop(dog)
    end

    test "set" do
      {:ok, dog} = fast_flush_dogmatix(:set)
      Dogmatix.set(:set, "my_set", 14)
      assert_receive {:udp, _, _, _, 'my_set:14|s'}
      Supervisor.stop(dog)
    end

    test "timer" do
      {:ok, dog} = fast_flush_dogmatix(:timer)
      Dogmatix.timer(:timer, "my_timer", 14)
      assert_receive {:udp, _, _, _, 'my_timer:14|ms'}
      Supervisor.stop(dog)
    end

    test "distribution" do
      {:ok, dog} = fast_flush_dogmatix(:distribution)
      Dogmatix.distribution(:distribution, "my_distribution", 14)
      assert_receive {:udp, _, _, _, 'my_distribution:14|d'}
      Supervisor.stop(dog)
    end
  end

  describe "Global prefix" do
    test "when set, the prefix is prepended to the metric name" do
      {:ok, dog} = fast_flush_dogmatix(:prefix, prefix: "my_prefix")
      Dogmatix.increment(:prefix, "my_count")
      assert_receive {:udp, _, _, _, 'my_prefix.my_count:1|c'}
      Supervisor.stop(dog)
    end

    test "the prefix and the metric name are sanitized" do
      {:ok, dog} = fast_flush_dogmatix(:prefix, prefix: "bob@saget.one|two:three")
      Dogmatix.increment(:prefix, "my:count")
      assert_receive {:udp, _, _, _, 'bob_saget.one_two_three.my_count:1|c'}
      Supervisor.stop(dog)
    end
  end

  describe "Tags" do
    test "global tags are sent" do
      {:ok, dog} = fast_flush_dogmatix(:tags, tags: ["foo:oof", "bar:rab"])
      Dogmatix.increment(:tags, "my_count")
      assert_receive {:udp, _, _, _, 'my_count:1|c|#foo:oof,bar:rab'}
      Supervisor.stop(dog)
    end

    test "local tags are sent" do
      {:ok, dog} = fast_flush_dogmatix(:tags)
      Dogmatix.increment(:tags, "my_count", tags: ["foo:oof", "bar:rab"])
      assert_receive {:udp, _, _, _, 'my_count:1|c|#foo:oof,bar:rab'}
      Supervisor.stop(dog)
    end

    test "both global and local tags are sent" do
      {:ok, dog} = fast_flush_dogmatix(:tags, tags: ["foo:oof", "bar:rab"])
      Dogmatix.increment(:tags, "my_count", tags: ["hello:world"])
      assert_receive {:udp, _, _, _, 'my_count:1|c|#foo:oof,bar:rab,hello:world'}
      Supervisor.stop(dog)
    end
  end

  describe "sampling" do
    test "sample rate is added to the datagram" do
      {:ok, dog} = fast_flush_dogmatix(:sampling)
      Dogmatix.increment(:sampling, "my_count", sample_rate: 1.0)
      assert_receive {:udp, _, _, _, 'my_count:1|c|@1.0'}
      Supervisor.stop(dog)
    end

    test "sample rate is applied when sending metrics" do
      {:ok, dog} = fast_flush_dogmatix(:sampling)
      Dogmatix.increment(:sampling, "my_count", sample_rate: 0.0)
      refute_receive {:udp, _, _, _, 'my_count:1|c|@0.0'}
      Supervisor.stop(dog)
    end
  end

  describe "events" do
    test "simple events are sent" do
      {:ok, dog} = fast_flush_dogmatix(:event)
      event = %Event{title: "hello", text: "world"}
      Dogmatix.event(:event, event)
      assert_receive {:udp, _, _, _, '_e{5,5}:hello|world'}
      Supervisor.stop(dog)
    end

    test "full events are sent" do
      {:ok, dog} = fast_flush_dogmatix(:event)

      event = %Event{
        title: "hello",
        text: "world",
        timestamp: 1_234_567_890,
        hostname: "foo",
        priority: :low,
        alert_type: :warning
      }

      Dogmatix.event(:event, event, tags: ["foo:bar"])
      assert_receive {:udp, _, _, _, '_e{5,5}:hello|world|d:1234567890|h:foo|p:low|t:warning|#foo:bar'}
      Supervisor.stop(dog)
    end

    test "new lines are escaped in title and text" do
      {:ok, dog} = fast_flush_dogmatix(:event)
      event = %Event{title: "title \n second line", text: "event \n second line"}
      Dogmatix.event(:event, event)
      assert_receive {:udp, _, _, _, '_e{20,20}:title \\n second line|event \\n second line'}
      Supervisor.stop(dog)
    end
  end

  describe "service checks" do
    test "simple checks are sent" do
      {:ok, dog} = fast_flush_dogmatix(:checks)
      check = %ServiceCheck{name: "hello", status: :critical}
      Dogmatix.service_check(:checks, check)
      assert_receive {:udp, _, _, _, '_sc|hello|2'}
      Supervisor.stop(dog)
    end

    test "full checks are sent" do
      {:ok, dog} = fast_flush_dogmatix(:checks)

      check = %ServiceCheck{
        name: "hello",
        status: :warning,
        timestamp: DateTime.from_unix!(1_234_567_890),
        hostname: "foo",
        message: "the message"
      }

      Dogmatix.service_check(:checks, check, tags: ["foo:bar"])
      assert_receive {:udp, _, _, _, '_sc|hello|1|d:1234567890|h:foo|#foo:bar|m:the message'}
      Supervisor.stop(dog)
    end
  end

  describe "datagram buffering" do
    test "datagrams are dropped when they are too big" do
      {:ok, dog} = fast_flush_dogmatix(:buffer, max_datagram_size: 2)
      assert {:error, "Payload is too big (more than 2 bytes), dropped."} == Dogmatix.increment(:buffer, "my_counter")
      refute_receive {:udp, _, _, _, 'my_counter:1|c'}
      Supervisor.stop(dog)
    end

    test "the buffer is sent as soon as the limit is reached" do
      {:ok, dog} = fast_flush_dogmatix(:buffer, worker_count: 1, buffer_flush_ms: 2000, max_datagram_size: 32)
      Dogmatix.increment(:buffer, "my_counter")
      Dogmatix.increment(:buffer, "my_counter2")

      # So far we have buffered 30 bytes
      refute_receive {:udp, _, _, _, _}

      # This metric takes us above the limit, we send the buffer
      # and add this last metric to the buffer.
      Dogmatix.increment(:buffer, "my_counter3")
      assert_receive {:udp, _, _, _, 'my_counter:1|c\nmy_counter2:1|c'}
      assert_receive {:udp, _, _, _, 'my_counter3:1|c'}, 2000
      Supervisor.stop(dog)
    end
  end

  defp fast_flush_dogmatix(name, opts \\ []) do
    opts = Keyword.merge([buffer_flush_ms: 10], opts)
    Dogmatix.start_link(name, "localhost", 1234, opts)
  end
end
