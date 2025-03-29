defmodule OpenFeature.Provider.Flagd.HTTP do
  @moduledoc """
  OpenFeature provider for flagd that communicates with a `flagd` instance over HTTP.

  This is a remote flagd provider that uses the HTTP evaluation API (JSON) to resolve flag values.
  """

  @behaviour OpenFeature.Provider

  alias OpenFeature.Provider.Flagd.Config
  alias OpenFeature.ResolutionDetails

  @enforce_keys [:config]
  defstruct name: "FlagdHTTP",
            config: nil,
            domain: nil,
            state: :not_ready,
            hooks: [],
            req: nil,
            req_opts: []

  @typedoc "HTTP provider for flagd"
  @type t() :: %__MODULE__{
          name: String.t(),
          config: Config.t(),
          domain: String.t() | nil,
          state: :not_ready | :ready,
          hooks: [any()],
          req: Req.Request.t() | nil,
          req_opts: keyword()
        }

  @doc """
  Creates a new flagd HTTP provider.

  ## Options

    * `:config` - (required) a `%Flagd.Config{}` struct.
    * `:hooks` - (optional) a list of OpenFeature provider hooks.
    * `:req` - (optional) a preconfigured `Req.Request` struct.
    * `:req_opts` - Keyword list passed to `Req.new/1` for HTTP clients

  ## Example

      config = Flagd.Config.new(port: 8013)
      OpenFeature.Provider.Flagd.HTTP.new(config: config)
  """

  @spec new(opts :: Keyword.t()) :: t()
  def new(opts) do
    config = Keyword.fetch!(opts, :config)
    struct(__MODULE__, Keyword.put(opts, :config, config))
  end

  @impl true
  @spec initialize(provider :: t(), domain :: any(), context :: any()) :: {:ok, t()}
  def initialize(%__MODULE__{req: nil, config: %Config{} = config, req_opts: req_opts} = provider, domain, _context) do
    req = build_req(config, req_opts)
    {:ok, %{provider | req: req, domain: domain, state: :ready}}
  end

  @impl true
  def initialize(%__MODULE__{} = provider, domain, _context) do
    {:ok, %{provider | domain: domain, state: :ready}}
  end

  @impl true
  @spec shutdown(any()) :: :ok
  def shutdown(_), do: :ok

  @impl true
  @spec resolve_boolean_value(
          provider :: t(),
          key :: String.t(),
          default :: boolean,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_boolean_value(provider, key, _default, context) do
    request(provider, key, context, "ResolveBoolean")
  end

  @impl true
  @spec resolve_string_value(
          provider :: t(),
          key :: String.t(),
          default :: String.t(),
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_string_value(provider, key, _default, context) do
    request(provider, key, context, "ResolveString")
  end

  @impl true
  @spec resolve_number_value(
          provider :: t(),
          key :: String.t(),
          default :: number,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_number_value(provider, key, _default, context) do
    request(provider, key, context, "ResolveNumber")
  end

  @impl true
  @spec resolve_map_value(
          provider :: t(),
          key :: String.t(),
          default :: map,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_map_value(provider, key, _default, context) do
    request(provider, key, context, "ResolveObject")
  end

  defp build_req(config, req_opts) do
    Req.new(
      Keyword.merge(
        [
          base_url: Config.base_url(config),
          method: :post,
          headers: [{"Content-Type", "application/json"}]
        ],
        req_opts
      )
    )
  end

  defp request(provider, key, context, method_name) do
    case encode_payload(key, context) do
      {:ok, json_body} ->
        do_request(provider, method_name, json_body)

      {:error, error} ->
        {:error, :unexpected_error, error}
    end
  end

  defp encode_payload(key, context) do
    payload = %{"flagKey" => key, "context" => context}
    Jason.encode(payload)
  end

  defp do_request(provider, method_name, json_body) do
    service = "flagd.evaluation.v1.Service"
    method_path = "/#{service}/#{method_name}"

    provider.req
    |> Req.merge(url: method_path, body: json_body)
    |> Req.Request.run_request()
    |> parse_result()
  rescue
    e -> {:error, :unexpected_error, e}
  end

  defp parse_result({_req, %Req.Response{status: 200, body: body}}) do
    {:ok,
     %ResolutionDetails{
       value: body["value"],
       variant: body["variant"],
       reason: to_reason(body["reason"]),
       flag_metadata: body["flagMetadata"]
     }}
  end

  defp parse_result({_req, %Req.Response{body: body}}) do
    message = body["message"] || "Unknown error"
    code = body["code"] || "general"

    case code do
      "not_found" -> {:error, :flag_not_found}
      _ -> {:error, :unexpected_error, %RuntimeError{message: "[#{code}] #{message}"}}
    end
  end

  defp to_reason(nil), do: :unknown
  defp to_reason(reason), do: reason |> String.downcase() |> String.to_atom()
end
