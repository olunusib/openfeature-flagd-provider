defmodule OpenFeature.Provider.Flagd.Config do
  @moduledoc """
  Shared configuration for all flagd providers (HTTP, gRPC, In-Process).

  This module centralizes common options like host, port, TLS, certificate path,
  and request/retry configuration.
  """

  @enforce_keys [:host, :port]
  defstruct host: "localhost",
            port: 8013,
            tls: false,
            cert_path: nil,
            retry_opts: [],
            req_opts: []

  @type t :: %__MODULE__{
          host: String.t(),
          port: pos_integer(),
          tls: boolean(),
          cert_path: String.t() | nil,
          retry_opts: keyword(),
          req_opts: keyword()
        }

  @doc """
  Builds a new config struct from the given keyword list.

  ## Options

    * `:host` - The hostname or IP address of the flagd instance (default: "localhost")
    * `:port` - The port number (default: 8013)
    * `:tls` - Whether to use TLS (default: false)
    * `:cert_path` - Optional path to a custom TLS certificate (PEM-encoded)
    * `:retry_opts` - Keyword list of retry options (used for gRPC or HTTP retries)
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @doc """
  Returns the full base URL, including scheme, for HTTP-based providers.
  """
  @spec base_url(t()) :: String.t()
  def base_url(%__MODULE__{host: host, port: port, tls: tls}) do
    scheme = if tls, do: "https", else: "http"
    "#{scheme}://#{host}:#{port}"
  end
end
