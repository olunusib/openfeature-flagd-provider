defmodule Openfeature.Provider.Flagd.GRPCTest do
  use ExUnit.Case
  use Mimic

  setup :set_mimic_global
  setup :verify_on_exit!

  alias OpenFeature.Provider.Flagd.GRPC, as: FlagdGRPC
  alias Flagd.Evaluation.V1.Service.Stub
  alias Flagd.Evaluation.V1.ResolveBooleanResponse

  setup do
    Mimic.expect(GRPC.Stub, :connect, fn _target, _opts -> {:ok, :channel} end)

    config = OpenFeature.Provider.Flagd.Config.new(port: 8013)
    provider = FlagdGRPC.new(config: config)
    {:ok, provider: provider}
  end

  test "successfully resolves a boolean flag", %{provider: provider} do
    expect(Stub, :resolve_boolean, fn :channel, _ ->
      {:ok, %ResolveBooleanResponse{value: true, variant: "on", reason: "STATIC"}}
    end)

    {:ok, provider} = FlagdGRPC.initialize(provider, "test", %{})

    assert {:ok, result} =
             FlagdGRPC.resolve_boolean_value(provider, "some-flag", false, %{})

    assert result.value == true
    assert result.variant == "on"
    assert result.reason == :static
  end

  test "returns error when flag is not found", %{provider: provider} do
    expect(Stub, :resolve_boolean, fn :channel, _ ->
      {:error, :not_found}
    end)

    {:ok, provider} = FlagdGRPC.initialize(provider, "test", %{})

    assert {:error, :flag_not_found} =
             FlagdGRPC.resolve_boolean_value(provider, "missing-flag", false, %{})
  end
end
