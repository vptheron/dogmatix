defmodule Dogmatix.Datagrams do
  @moduledoc false

  alias Dogmatix.Event
  alias Dogmatix.ServiceCheck

  def prepare_global(prefix, tags) do
    prepared_prefix =
      case prefix do
        nil -> ""
        p -> sanitize_name(p) <> "."
      end

    prepared_tags = format_tags(tags)
    {prepared_prefix, prepared_tags}
  end

  def metric_datagram({prefix, constant_tags}, name, value, opts, type) do
    [
      prefix,
      sanitize_name(name),
      ":",
      "#{value}",
      "|",
      type,
      sample_rate(opts[:sample_rate]),
      tags(constant_tags, opts)
    ]
  end

  def event_datagram({prefix, constant_tags}, %Event{} = event, opts) do
    title = prefix <> sanitize_content(event.title)
    text = sanitize_content(event.text)

    [
      "_e{#{String.length(title)},#{String.length(text)}}:",
      title,
      "|",
      text,
      timestamp(event.timestamp),
      hostname(event.hostname),
      priority(event.priority),
      alert_type(event.alert_type),
      tags(constant_tags, opts)
    ]
  end

  def service_check_datagram({prefix, constant_tags}, %ServiceCheck{} = sc, opts) do
    [
      "_sc|",
      prefix,
      sanitize_name(sc.name),
      "|",
      status(sc.status),
      timestamp(sc.timestamp),
      hostname(sc.hostname),
      tags(constant_tags, opts),
      message(sc.message)
    ]
  end

  defp status(i) when is_integer(i), do: status("#{i}")
  defp status(:ok), do: "0"
  defp status(:warning), do: "1"
  defp status(:critical), do: "2"
  defp status(:unknown), do: "3"
  defp status(s) when s in ["0", "1", "2", "3"], do: s

  defp timestamp(nil), do: ""
  defp timestamp(%DateTime{} = dt), do: dt |> DateTime.to_unix() |> timestamp()
  defp timestamp(ts), do: ["|d:", "#{ts}"]

  defp hostname(nil), do: ""
  defp hostname(hostname), do: ["|h:", sanitize_pipes(hostname)]

  defp priority(nil), do: ""
  defp priority(priority) when priority in [:normal, :low], do: ["|p:", "#{priority}"]

  defp alert_type(nil), do: ""
  defp alert_type(alert_type) when alert_type in [:error, :warning, :info, :success], do: ["|t:", "#{alert_type}"]

  defp message(nil), do: ""
  defp message(message), do: ["|m:", sanitize_content(message)]

  defp sample_rate(nil), do: ""
  defp sample_rate(rate) when is_float(rate), do: ["|@", "#{rate}"]

  defp tags(global_tags, opts) do
    local_tags = format_tags(Keyword.get(opts, :tags, []))

    case {global_tags, local_tags} do
      {[], []} -> []
      {[], local_only} -> ["|#", local_only]
      {global_only, []} -> ["|#", global_only]
      {global, local} -> ["|#", global, ",", local]
    end
  end

  defp format_tags(nil), do: []
  defp format_tags(tags), do: tags |> Enum.map(&sanitize_pipes/1) |> Enum.intersperse(",")

  defp sanitize_name(s), do: String.replace(s, ~r/[:|@]/, "_")

  defp sanitize_pipes(s), do: String.replace(s, "|", "")

  defp sanitize_content(s), do: String.replace(s, "\n", "\\n")
end
