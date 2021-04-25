# Dogmatix

> A StatsD/DogStatsD client for Elixir.

Dogmatix is a StatsD/DogStatsD client build in Elixir.  It is primarily designed to support the protocol and extensions provided by the [DataDog agent][datadog], but works with any StatsD-compatible server.

## Features

This library is still in its early stages.  Currently, the main supported features are:

  * Communication with an agent via UDP
  * Support for all types of metrics (count, gauge, timer, histogram, set and distribution)
  * Support for events and service checks
  * Support for metric sampling
  * Support for tagging
  * Connection pooling
  * Metric buffering

See the [documentation][documentation] for usage, configuration and implementation details.

## Installation

Add the `:dogmatix` dependency to your `mix.exs` file:

```elixir
def deps do
  [
    {:dogmatix, "~> 0.1"}
  ]
end
```

Then run `mix deps.get` in your shell to fetch the new dependency.

## Overview

The detailed documentation is available on [HexDocs][documentation].

An instance of the client can be started with `Dogmatix.start_link/4`:

```elixir
{:ok, pid} = Dogmatix.start_link("my_dogmatix", "localhost", 8125, _opts = [])
```

The returned pid can be used to incorporate in a supervision tree, the provided name (`"my_dogmatix"`) is used to identify the instance and query the Dogmatix API.

A few examples of sending data to the agent:

```elixir
# Increment a counter
Dogmatix.increment("my_dogmatix", "page.views")

# Set the value of a gauge
Dogmatix.gauge("my_dogmatix", "fuel.level", 0.5)

# Increment a counter with tags
Dogmatix.count("my_dogmatix", "users.online", 42, tags: ["country:USA", "app:mobile"])

# Sample a histogram 20% of the time
Dogmatix.histogram("my_dogmatix", "song.length", 100, sample_rate: 0.2)

# Send an event
Dogmatix.event("my_dogmatix", %Event{title: "Exception occurred", text: "Failed to parse CSV file", alert_type: :warning}, tags: ["error_type:input_file"])

# Send a service check
Dogmatix.service_check("my_dogmatix", %ServiceCheck{name: "DB Connection", status: :warning, message: "Timed out after 10s"}, tags: ["env:dev"])
```

The "name-based" API, while providing some flexibility, can be cumbersome.  A macro is provided to create custom client modules:

```elixir
defmodule MyDogmatix do
  use Dogmatix
end

{:ok, pid} = MyDogmatix.start_link("localhost", 8125)

MyDogmatix.count("users.online", 42)
```

## Features still in the work

* Support for Unix Domain Socket connections
* Client-side aggregation for some metrics (this is different from metric buffering which is already supported)

## License

Copyright 2021 Vincent Theron

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

[datadog]: https://docs.datadoghq.com/getting_started/agent/
[documentation]: https://hexdocs.pm/dogmatix
