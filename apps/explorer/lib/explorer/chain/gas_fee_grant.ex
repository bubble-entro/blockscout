defmodule Explorer.Chain.GasFeeGrant do
  @moduledoc """
  Fetches gas fee grants for validators.

  This module interacts with a precompiled contract to retrieve gas fee grant information
  for a specific validator at a given block height.
  """

  require Logger

  import EthereumJSONRPC, only: [json_rpc: 2]

  alias EthereumJSONRPC.Contract

  @default_precompile_address "0x0000000000000000000000000000000000001006"
  @wildcard_program "0x0000000000000000000000000000000000000000"
  @grant_response_words 9
  @word_size 64
  @grant_response_length @grant_response_words * @word_size
  @allowance_normal 1
  @allowance_periodic 2
  @allowance_wildcard 3

  # grant(address,address)
  @grant_method_id "f2403dcd"

  @doc """
  Fetches the gas fee grant details for a grantee and program.

  ## Parameters
    * `grantee` - The address of the grantee (hex string).
    * `program` - The address of the program (hex string).
    * `block_number_int` - The block number to query at (optional, defaults to latest).

  ## Returns
    * `{:ok, %{granter: String.t(), grant_type: atom(), remaining: integer() | nil}}`
    * `{:error, any()}`
  """
  def fetch_grant(grantee, program, block_number_int \\ nil) do
    json_rpc_named_arguments = Application.get_env(:explorer, :json_rpc_named_arguments)

    if is_nil(json_rpc_named_arguments) do
      {:error, :no_json_rpc_named_arguments}
    else
      do_fetch_grant(grantee, program, block_number_int, json_rpc_named_arguments)
    end
  rescue
    error ->
      Logger.error("Failed to fetch gas fee grant: #{inspect(error)}")
      {:error, :exception}
  end

  defp do_fetch_grant(grantee, program, block_number_int, json_rpc_named_arguments) do
    precompile_address = config(:precompile_address, @default_precompile_address)
    method_id = config(:grant_method_id, @grant_method_id)

    clean_grantee = clean_address(grantee)
    clean_program = clean_address(program)

    with {:error, :grant_not_found} <-
           fetch_grant_view(
             clean_grantee,
             clean_address(@wildcard_program),
             block_number_int,
             precompile_address,
             method_id,
             json_rpc_named_arguments
           ) do
      fetch_grant_view(
        clean_grantee,
        clean_program,
        block_number_int,
        precompile_address,
        method_id,
        json_rpc_named_arguments
      )
    end
  end

  defp clean_address(address) do
    address
    |> String.trim_leading("0x")
    |> String.downcase()
    |> String.pad_leading(64, "0")
  end

  defp fetch_grant_view(
         clean_grantee,
         clean_program,
         block_number_int,
         precompile_address,
         method_id,
         json_rpc_named_arguments
       ) do
    data = "0x" <> method_id <> clean_grantee <> clean_program

    case Contract.eth_call_request(data, precompile_address, 0, block_number_int, nil)
         |> json_rpc(json_rpc_named_arguments) do
      {:ok, hex_value} ->
        parse_grant_response(hex_value, block_number_int)

      {:error, reason} ->
        Logger.debug("Failed to fetch gas fee grant: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_grant_response(hex_value, block_number_int) do
    hex = String.trim_leading(hex_value, "0x")

    if String.length(hex) < @grant_response_length do
      {:error, :invalid_response_length}
    else
      with {:ok, granter} <- parse_address_word(hex, 0),
           {:ok, allowance} <- parse_uint_word(hex, 1),
           {:ok, spend_limit} <- parse_uint_word(hex, 2),
           {:ok, period_can_spend} <- parse_uint_word(hex, 4),
           {:ok, end_time} <- parse_uint_word(hex, 6) do
        build_grant(granter, allowance, spend_limit, period_can_spend, end_time, block_number_int)
      end
    end
  end

  defp parse_address_word(hex, index) do
    word = String.slice(hex, index * @word_size, @word_size)

    if is_binary(word) and String.length(word) == @word_size do
      {:ok, "0x" <> String.slice(word, 24, 40)}
    else
      {:error, :invalid_response_length}
    end
  end

  defp parse_uint_word(hex, index) do
    case String.slice(hex, index * @word_size, @word_size) |> Integer.parse(16) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_hex_value}
    end
  end

  defp build_grant(_granter, 0, _spend_limit, _period_can_spend, _end_time, _block_number_int),
    do: {:error, :grant_not_found}

  defp build_grant(_granter, _allowance, _spend_limit, _period_can_spend, end_time, block_number_int)
       when is_integer(block_number_int) and end_time > 0 and block_number_int > end_time,
       do: {:error, :grant_not_found}

  defp build_grant(granter, @allowance_wildcard, _spend_limit, _period_can_spend, _end_time, _block_number_int),
    do: {:ok, %{granter: granter, grant_type: :wildcard, remaining: nil}}

  defp build_grant(granter, @allowance_periodic, spend_limit, period_can_spend, _end_time, _block_number_int) do
    remaining =
      if spend_limit == 0 do
        period_can_spend
      else
        min(spend_limit, period_can_spend)
      end

    {:ok, %{granter: granter, grant_type: :periodic, remaining: remaining}}
  end

  defp build_grant(granter, @allowance_normal, 0, _period_can_spend, _end_time, _block_number_int),
    do: {:ok, %{granter: granter, grant_type: :normal, remaining: nil}}

  defp build_grant(granter, @allowance_normal, spend_limit, _period_can_spend, _end_time, _block_number_int),
    do: {:ok, %{granter: granter, grant_type: :normal, remaining: spend_limit}}

  defp build_grant(_granter, _allowance, _spend_limit, _period_can_spend, _end_time, _block_number_int),
    do: {:error, :grant_not_found}

  defp config(key, default) do
    Application.get_env(:explorer, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
