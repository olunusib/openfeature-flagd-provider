defmodule OpenFeature.Provider.Flagd.GRPC do
  @moduledoc """
  OpenFeature provider for flagd that communicates with a `flagd` instance over gRPC.

  This is a remote flagd provider that uses the gRPC evaluation API to resolve flag values.
  """

  require Logger

  @behaviour OpenFeature.Provider

  alias Flagd.Evaluation.V1, as: Eval
  alias Google.Protobuf.Struct
  alias OpenFeature.Provider.Flagd.Config
  alias OpenFeature.ResolutionDetails
  alias Protobuf.JSON.Decode
  alias Protobuf.JSON.Encode

  @enforce_keys [:config]
  defstruct name: "FlagdGRPC",
            config: nil,
            domain: nil,
            state: :not_ready,
            hooks: [],
            channel: nil

  @typedoc "GRPC provider for flagd"
  @type t() :: %__MODULE__{
          name: String.t(),
          config: Config.t(),
          domain: String.t() | nil,
          state: :not_ready | :ready,
          hooks: [any()],
          channel: GRPC.Channel.t() | nil
        }

  @doc """
  Creates a new flagd gRPC provider.

  ## Options

    * `:config` - A `%Config{}` struct with host, port, TLS, etc.
    * `:hooks` - (optional) a list of OpenFeature provider hooks.

  ## Example

      config = OpenFeature.Provider.Flagd.Config.new(port: 8013)
      OpenFeature.Provider.Flagd.GRPC.new(config: config)
      OpenFeature.set_provider(provider)
  """

  @spec new(opts :: Keyword.t()) :: t()
  def new(opts) do
    config = Keyword.fetch!(opts, :config)
    struct(__MODULE__, Keyword.put(opts, :config, config))
  end

  @impl true
  @spec initialize(t(), any(), any()) :: {:ok, t()} | {:error, :provider_not_ready, term()}
  def initialize(%{config: config} = provider, domain, _context) do
    target = "#{config.host}:#{config.port}"
    opts = grpc_connection_opts(config)

    case GRPC.Stub.connect(target, opts) do
      {:ok, channel} ->
        {:ok, %{provider | domain: domain, state: :ready, channel: channel}}

      {:error, reason} ->
        {:error, :provider_not_ready, reason}
    end
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
    request = %Eval.ResolveBooleanRequest{flag_key: key, context: to_struct(context)}

    case Eval.Service.Stub.resolve_boolean(provider.channel, request) do
      {:ok, %Eval.ResolveBooleanResponse{} = res} -> {:ok, to_result(res)}
      {:error, _} -> {:error, :flag_not_found}
    end
  end

  @impl true
  @spec resolve_string_value(
          provider :: t(),
          key :: String.t(),
          default :: String.t(),
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_string_value(provider, key, _default, context) do
    request = %Eval.ResolveStringRequest{flag_key: key, context: to_struct(context)}

    case Eval.Service.Stub.resolve_string(provider.channel, request) do
      {:ok, %Eval.ResolveStringResponse{} = res} -> {:ok, to_result(res)}
      {:error, _} -> {:error, :flag_not_found}
    end
  end

  @impl true
  @spec resolve_number_value(
          provider :: t(),
          key :: String.t(),
          default :: number,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_number_value(provider, key, default, context) do
    {fun, request} =
      if is_integer(default) do
        {:resolve_int, %Eval.ResolveIntRequest{flag_key: key, context: to_struct(context)}}
      else
        {:resolve_float, %Eval.ResolveFloatRequest{flag_key: key, context: to_struct(context)}}
      end

    case apply(Eval.Service.Stub, fun, [provider.channel, request]) do
      {:ok, res} -> {:ok, to_result(res)}
      {:error, _} -> {:error, :flag_not_found}
    end
  end

  @impl true
  @spec resolve_map_value(
          provider :: t(),
          key :: String.t(),
          default :: map,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_map_value(provider, key, _default, context) do
    request = %Eval.ResolveObjectRequest{flag_key: key, context: to_struct(context)}

    case Eval.Service.Stub.resolve_object(provider.channel, request) do
      {:ok, %Eval.ResolveObjectResponse{} = res} -> {:ok, to_result(res)}
      {:error, _} -> {:error, :flag_not_found}
    end
  end

  defp grpc_connection_opts(%Config{tls: true, cert_path: cert_path}) when is_binary(cert_path) do
    {:ok, cacert} = File.read(cert_path)
    cert = :public_key.pem_decode(cacert) |> hd() |> :public_key.pem_entry_decode()
    [cred: GRPC.Credential.new(ssl: [cacerts: [cert]])]
  end

  defp grpc_connection_opts(%Config{tls: true}) do
    [cred: GRPC.Credential.new(ssl: true)]
  end

  defp grpc_connection_opts(_config), do: []

  defp to_result(res) do
    %ResolutionDetails{
      value: unwrap_value(res.value),
      variant: res.variant,
      reason: to_reason(res.reason),
      flag_metadata: unwrap_value(res.metadata)
    }
  end

  defp unwrap_value(%Struct{} = struct), do: Encode.encodable(struct, nil)
  defp unwrap_value(val), do: val

  defp to_struct(context) do
    context
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.into(%{})
    |> Decode.from_json_data(Google.Protobuf.Struct)
  end

  defp to_reason(nil), do: :unknown

  defp to_reason(reason) when is_binary(reason),
    do: reason |> String.downcase() |> String.to_atom()
end
