defmodule Explorer.Chain.GasFeeGrantTest do
  use ExUnit.Case, async: false
  use EthereumJSONRPC.Case

  import Mox

  alias Explorer.Chain.GasFeeGrant

  @grant_method_id "f2403dcd"
  @zero_address "0x0000000000000000000000000000000000000000"

  setup :set_mox_global
  setup :verify_on_exit!

  setup %{json_rpc_named_arguments: json_rpc_named_arguments} do
    previous = Application.get_env(:explorer, :json_rpc_named_arguments)
    Application.put_env(:explorer, :json_rpc_named_arguments, json_rpc_named_arguments)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:explorer, :json_rpc_named_arguments)
      else
        Application.put_env(:explorer, :json_rpc_named_arguments, previous)
      end
    end)

    :ok
  end

  describe "fetch_grant/3" do
    test "prefers wildcard grants over program-specific grants" do
      grantee = "0x00000000000000000000000000000000000000aa"
      program = "0x00000000000000000000000000000000000000bb"
      granter = "0x00000000000000000000000000000000000000cc"

      wildcard_data = grant_call_data(grantee, @zero_address)

      expect(EthereumJSONRPC.Mox, :json_rpc, fn request, _options ->
        assert get_in(request, [:params, Access.at(0), :data]) == wildcard_data
        {:ok, grant_response(granter, 3, 0, 0, 0, 0, 0, 0, 0)}
      end)

      assert {:ok, %{grant_type: :wildcard, granter: ^granter, remaining: nil}} =
               GasFeeGrant.fetch_grant(grantee, program, 42)
    end

    test "falls back to the program grant and uses the effective periodic remaining amount" do
      grantee = "0x00000000000000000000000000000000000000aa"
      program = "0x00000000000000000000000000000000000000bb"
      granter = "0x00000000000000000000000000000000000000cc"
      test_pid = self()

      wildcard_data = grant_call_data(grantee, @zero_address)
      program_data = grant_call_data(grantee, program)

      responses = %{
        wildcard_data => grant_response(@zero_address, 0, 0, 0, 0, 0, 0, 0, 0),
        program_data => grant_response(granter, 2, 350, 500, 500, 0, 0, 0, 10)
      }

      expect(EthereumJSONRPC.Mox, :json_rpc, 2, fn request, _options ->
        data = get_in(request, [:params, Access.at(0), :data])
        send(test_pid, {:json_rpc_call, data})
        {:ok, Map.fetch!(responses, data)}
      end)

      assert {:ok, %{grant_type: :periodic, granter: ^granter, remaining: 350}} =
               GasFeeGrant.fetch_grant(grantee, program, 42)

      assert_receive {:json_rpc_call, ^wildcard_data}
      assert_receive {:json_rpc_call, ^program_data}
    end

    test "uses spend_limit for non-periodic grants" do
      grantee = "0x00000000000000000000000000000000000000aa"
      program = "0x00000000000000000000000000000000000000bb"
      granter = "0x00000000000000000000000000000000000000cc"

      wildcard_data = grant_call_data(grantee, @zero_address)
      program_data = grant_call_data(grantee, program)

      responses = %{
        wildcard_data => grant_response(@zero_address, 0, 0, 0, 0, 0, 0, 0, 0),
        program_data => grant_response(granter, 1, 700, 0, 0, 0, 0, 0, 0)
      }

      expect(EthereumJSONRPC.Mox, :json_rpc, 2, fn request, _options ->
        data = get_in(request, [:params, Access.at(0), :data])
        {:ok, Map.fetch!(responses, data)}
      end)

      assert {:ok, %{grant_type: :normal, granter: ^granter, remaining: 700}} =
               GasFeeGrant.fetch_grant(grantee, program, 42)
    end
  end

  defp grant_call_data(grantee, program) do
    "0x" <> @grant_method_id <> encode_address(grantee) <> encode_address(program)
  end

  defp grant_response(
         granter,
         allowance,
         spend_limit,
         period_limit,
         period_can_spend,
         start_time,
         end_time,
         latest_transaction,
         period
       ) do
    "0x" <>
      Enum.join([
        encode_address(granter),
        encode_uint(allowance),
        encode_uint(spend_limit),
        encode_uint(period_limit),
        encode_uint(period_can_spend),
        encode_uint(start_time),
        encode_uint(end_time),
        encode_uint(latest_transaction),
        encode_uint(period)
      ])
  end

  defp encode_address(address) do
    address
    |> String.trim_leading("0x")
    |> String.downcase()
    |> String.pad_leading(64, "0")
  end

  defp encode_uint(value) do
    value
    |> Integer.to_string(16)
    |> String.pad_leading(64, "0")
  end
end