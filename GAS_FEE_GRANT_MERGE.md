# Gas Fee Grant Feature Merge - Blockscout v7.0.2 to v9.3.2

## Summary

This document outlines all the files that were created or modified to merge the custom **Gas Fee Grant** feature from Blockscout v7.0.2 (in `blockscout/`) to the new v9.3.2 (in `bs/`).

## Files Created

### 1. `apps/explorer/lib/explorer/chain/gas_fee_grant.ex`
**Path:** `/Users/entronica/Desktop/Coding/bs/apps/explorer/lib/explorer/chain/gas_fee_grant.ex`

This is the core module that interacts with the precompiled contract at `0x0000000000000000000000000000000000001006` to fetch gas fee grant information.

**Key Functions:**
- `fetch_grant/3` - Fetches gas fee grant details for a grantee and program
- `periodCanSpend(address,address)` - Method signature: `0xf2403dcd`

---

## Files Modified

### 2. `apps/block_scout_web/lib/block_scout_web/controllers/api/v2/transaction_controller.ex`

**Changes:**
- Added `fetch_gas_fee_grant_info/1` private function at the end of the module
- Modified `transaction/2` function to fetch gas fee grant info and pass it to the view

### 3. `apps/block_scout_web/lib/block_scout_web/views/api/v2/transaction_view.ex`

**Changes:**
- Modified `render("transaction.json", ...)` to accept `gas_fee_grant_info` from assigns
- Modified `prepare_transaction/7` function signature to accept optional `gas_fee_grant_info` parameter
- Added `"gas_fee_grant_info"` key to the result map in `prepare_transaction`

### 4. `apps/block_scout_web/lib/block_scout_web/controllers/transaction_controller.ex`

**Changes:**
- Added `fetch_gas_fee_grant_info/1` private function
- Modified `show/2` to pass `gas_fee_grant_info` to both `show_token_transfers.html` and `show_internal_transactions.html` templates

### 5. `apps/block_scout_web/lib/block_scout_web/templates/transaction/overview.html.eex`

**Changes:**
- Added "Gas Grant Remaining" section after "Gas Used by Transaction"
- Displays the remaining gas fee grant allowance when `gas_fee_grant_info` is available

---

## API Response Format

The API response for `/api/v2/transactions/:hash` now includes:

```json
{
  "gas_fee_grant_info": {
    "amount": "21000000000000",
    "granter": "0x1234...",
    "remaining": "1000000000000000000"
  }
}
```

Where:
- `amount`: The transaction fee (gas fee) in wei
- `granter`: The address of the granter who provided the gas subsidy
- `remaining`: The remaining period allowance in wei

If the transaction doesn't have a gas fee grant, `gas_fee_grant_info` will be `null`.

---

## Configuration

You can optionally configure the precompile address via application config:

```elixir
config :explorer, Explorer.Chain.GasFeeGrant,
  precompile_address: "0x0000000000000000000000000000000000001006",
  grant_method_id: "f2403dcd"
```

---

## Testing

After applying these changes, you should:

1. Compile the project:
   ```bash
   cd /Users/entronica/Desktop/Coding/bs
   mix deps.get
   mix compile
   ```

2. Test the API endpoint:
   ```bash
   curl http://localhost:4000/api/v2/transactions/<tx_hash>
   ```

3. Verify the gas_fee_grant_info field is present in the response for transactions where the sender has an active gas fee grant.

---

## Notes

- The precompile contract address defaults to `0x0000000000000000000000000000000000001006`
- The feature only fetches grant info for confirmed transactions with a `to_address_hash` and `block_number`
- Grant info is always fetched at the block height of the transaction for historical accuracy
