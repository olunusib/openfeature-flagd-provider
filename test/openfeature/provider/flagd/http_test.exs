defmodule OpenFeature.Provider.Flagd.HTTPTest do
  use ExUnit.Case
  use Mimic

  setup :set_mimic_global
  setup :verify_on_exit!

  alias OpenFeature.Provider.Flagd.Config
  alias OpenFeature.Provider.Flagd.HTTP, as: FlagdHTTP

  setup do
    config = Config.new(port: 8015)
    provider = FlagdHTTP.new(config: config)
    {:ok, provider: provider}
  end

  test "successfully resolves boolean flag", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => true,
            "variant" => "on",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test-domain", %{})
    assert {:ok, result} = FlagdHTTP.resolve_boolean_value(provider, "bool-flag", false, %{})

    assert result.value == true
    assert result.reason == :static
    assert result.variant == "on"
  end

  test "handles not_found flag error", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 404,
          body: %{"code" => "not_found", "message" => "flag not found"}
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})

    assert {:error, :flag_not_found} =
             FlagdHTTP.resolve_boolean_value(provider, "missing", false, %{})
  end

  test "handles unexpected error with message", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 500,
          body: %{"code" => "server_error", "message" => "Boom"}
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})

    assert {:error, :unexpected_error, %RuntimeError{message: "[server_error] Boom"}} =
             FlagdHTTP.resolve_boolean_value(provider, "some-flag", false, %{})
  end

  test "successfully resolves string flag", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => "#FF00FF",
            "variant" => "magenta",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdHTTP.resolve_string_value(provider, "color", "red", %{})

    assert result.value == "#FF00FF"
    assert result.variant == "magenta"
    assert result.reason == :static
  end

  test "successfully resolves number flag (float)", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => 3.14,
            "variant" => "pi",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdHTTP.resolve_number_value(provider, "pi", 0, %{})
    assert result.value == 3.14
    assert result.variant == "pi"
  end

  test "successfully resolves map flag", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => %{"enabled" => true, "limit" => 10},
            "variant" => "default",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdHTTP.resolve_map_value(provider, "config", %{}, %{})
    assert result.value["enabled"] == true
    assert result.value["limit"] == 10
  end

  test "handles response with nil reason and metadata", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => "some_value",
            "variant" => "default"
            # no reason or flagMetadata provided
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdHTTP.resolve_string_value(provider, "some-flag", "fallback", %{})
    assert result.reason == :unknown
    assert result.flag_metadata == nil
  end

  test "handles invalid JSON body gracefully", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      raise Jason.DecodeError, data: "<html></html>", position: 0, token: "<"
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})

    assert {:error, :unexpected_error, %Jason.DecodeError{}} =
             FlagdHTTP.resolve_string_value(provider, "some-flag", "default", %{})
  end

  test "sends merged context from client and call", %{provider: provider} do
    expected_context = %{"env" => "prod", "user" => "alice"}

    expect(Req.Request, :run_request, fn req ->
      {:ok, payload} = Jason.decode(req.body)

      # Ensure merged context was sent
      assert payload["context"] == expected_context

      {
        req,
        %Req.Response{
          status: 200,
          body: %{
            "value" => true,
            "variant" => "v1",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})
    OpenFeature.set_provider(provider)

    # Simulate global + client context merging
    OpenFeature.set_global_context(%{"env" => "prod"})
    client = OpenFeature.get_client() |> OpenFeature.Client.set_context(%{"user" => "alice"})

    details = OpenFeature.Client.get_boolean_details(client, "merge-flag", false)

    assert %OpenFeature.EvaluationDetails{
             value: true,
             key: "merge-flag",
             reason: :static,
             variant: "v1",
             error_code: nil,
             error_message: nil
           } = details
  end

  test "handles network failure (e.g. timeout or SSL error)", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      raise RuntimeError, message: "connection refused"
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})

    assert {:error, :unexpected_error, %RuntimeError{message: "connection refused"}} =
             FlagdHTTP.resolve_boolean_value(provider, "network-flag", false, %{})
  end
end
