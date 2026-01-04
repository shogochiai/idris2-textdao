||| Schema Tests - Step 1 Spec-Test Parity
|||
||| Tests for: REQ_SCHEMA_001, REQ_SCHEMA_002, REQ_SCHEMA_003, REQ_SCHEMA_004
module TextDAO.Tests.SchemaTest

import TextDAO.Storages.Schema

%default covering

-- =============================================================================
-- REQ_SCHEMA_004: ActionStatus enum encoding
-- =============================================================================

||| Test: ActionStatus round-trip encoding
||| REQ_SCHEMA_004
export
test_REQ_SCHEMA_004_actionStatus_roundtrip : Bool
test_REQ_SCHEMA_004_actionStatus_roundtrip =
  let pending = intToActionStatus (actionStatusToInt Pending)
      executed = intToActionStatus (actionStatusToInt Executed)
      failed = intToActionStatus (actionStatusToInt Failed)
  in case (pending, executed, failed) of
       (Pending, Executed, Failed) => True
       _ => False

||| Test: ActionStatus encoding values
||| REQ_SCHEMA_004
export
test_REQ_SCHEMA_004_actionStatus_values : Bool
test_REQ_SCHEMA_004_actionStatus_values =
  actionStatusToInt Pending == 0 &&
  actionStatusToInt Executed == 1 &&
  actionStatusToInt Failed == 2

-- =============================================================================
-- REQ_SCHEMA_001: Storage slot constants
-- =============================================================================

||| Test: Storage slot layout is non-overlapping
||| REQ_SCHEMA_001
export
test_REQ_SCHEMA_001_slot_layout : Bool
test_REQ_SCHEMA_001_slot_layout =
  SLOT_DELIBERATION /= SLOT_TEXTS &&
  SLOT_TEXTS /= SLOT_MEMBERS &&
  SLOT_MEMBERS /= SLOT_TAGS &&
  SLOT_TAGS /= SLOT_ADMINS

||| Test: Config slots are sequential
||| REQ_SCHEMA_001
export
test_REQ_SCHEMA_001_config_slots : Bool
test_REQ_SCHEMA_001_config_slots =
  SLOT_CONFIG_EXPIRY_DURATION + 1 == SLOT_CONFIG_SNAP_INTERVAL &&
  SLOT_CONFIG_SNAP_INTERVAL + 1 == SLOT_CONFIG_REPS_NUM &&
  SLOT_CONFIG_REPS_NUM + 1 == SLOT_CONFIG_QUORUM_SCORE

-- =============================================================================
-- Meta offset tests
-- =============================================================================

||| Test: Meta offsets are sequential and non-overlapping
export
test_meta_offsets_sequential : Bool
test_meta_offsets_sequential =
  META_OFFSET_CREATED_AT == 0 &&
  META_OFFSET_EXPIRATION == 1 &&
  META_OFFSET_SNAP_INTERVAL == 2 &&
  META_OFFSET_HEADER_COUNT == 3 &&
  META_OFFSET_CMD_COUNT == 4 &&
  META_OFFSET_APPROVED_HEADER == 5 &&
  META_OFFSET_APPROVED_CMD == 6 &&
  META_OFFSET_EXECUTED == 7

-- =============================================================================
-- Test Runner
-- =============================================================================

export
allSchemaTests : List (String, Bool)
allSchemaTests =
  [ ("REQ_SCHEMA_004_actionStatus_roundtrip", test_REQ_SCHEMA_004_actionStatus_roundtrip)
  , ("REQ_SCHEMA_004_actionStatus_values", test_REQ_SCHEMA_004_actionStatus_values)
  , ("REQ_SCHEMA_001_slot_layout", test_REQ_SCHEMA_001_slot_layout)
  , ("REQ_SCHEMA_001_config_slots", test_REQ_SCHEMA_001_config_slots)
  , ("meta_offsets_sequential", test_meta_offsets_sequential)
  ]

countPassed : List (String, Bool) -> Integer
countPassed = cast . length . filter snd

||| Run all schema tests and return passed count
||| NOTE: Schema tests are pure (Bool), not IO Bool
export
runSchemaTests : IO Integer
runSchemaTests = pure $ countPassed allSchemaTests
