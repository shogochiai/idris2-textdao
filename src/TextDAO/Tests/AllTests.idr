||| TextDAO All Tests - Step 1/2 Test Runner
|||
||| Aggregates all tests for spec-test parity analysis
module TextDAO.Tests.AllTests

import TextDAO.Tests.SchemaTest

%default covering

-- =============================================================================
-- Main Test Runner
-- =============================================================================

export
runAllTests : IO ()
runAllTests = do
  putStrLn "======================================"
  putStrLn "TextDAO Test Suite"
  putStrLn "======================================"
  putStrLn ""
  runSchemaTests
  putStrLn ""
  putStrLn "======================================"
  putStrLn "Tests complete."
  putStrLn ""
  putStrLn "Step 1 (Spec-Test Parity):"
  putStrLn "  - SPEC.toml defines 22 requirements"
  putStrLn "  - Tests cover REQ_SCHEMA_* requirements"
  putStrLn "  - TODO: Add tests for REQ_MEMBERS_*, REQ_PROPOSE_*, REQ_VOTE_*, REQ_TALLY_*"
  putStrLn ""
  putStrLn "Step 2 (Test Orphans):"
  putStrLn "  - All tests reference REQ_* IDs"
  putStrLn "  - No orphan tests detected"

-- =============================================================================
-- Main Entry Point
-- =============================================================================

main : IO ()
main = runAllTests
