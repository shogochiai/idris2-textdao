||| TextDAO All Tests - Complete EVM Runtime Test Suite
|||
||| Aggregates all tests for spec-test parity analysis with lazy core ask
module TextDAO.Tests.AllTests

import TextDAO.Tests.SchemaTest
import TextDAO.Tests.MembersTest
import TextDAO.Tests.ProposeTest
import TextDAO.Tests.VoteTest
import TextDAO.Tests.TallyTest
import TextDAO.Tests.EvmTest

%default covering

-- =============================================================================
-- Test Statistics
-- =============================================================================

countTests : List (String, a) -> Nat
countTests = length

-- =============================================================================
-- Main Test Runner
-- =============================================================================

export
runAllTests : IO ()
runAllTests = do
  putStrLn "======================================"
  putStrLn "TextDAO Complete Test Suite"
  putStrLn "======================================"
  putStrLn ""

  -- Schema tests (pure)
  runSchemaTests
  putStrLn ""

  -- Members tests (EVM runtime)
  runMembersTests
  putStrLn ""

  -- Propose tests (EVM runtime)
  runProposeTests
  putStrLn ""

  -- Vote tests (EVM runtime)
  runVoteTests
  putStrLn ""

  -- Tally tests (EVM runtime)
  runTallyTests
  putStrLn ""

  -- EVM integration tests
  runEvmTests
  putStrLn ""

  putStrLn "======================================"
  putStrLn "Test Summary"
  putStrLn "======================================"
  putStrLn $ "  Schema:  " ++ show (countTests allSchemaTests) ++ " tests"
  putStrLn $ "  Members: " ++ show (countTests allMembersTests) ++ " tests"
  putStrLn $ "  Propose: " ++ show (countTests allProposeTests) ++ " tests"
  putStrLn $ "  Vote:    " ++ show (countTests allVoteTests) ++ " tests"
  putStrLn $ "  Tally:   " ++ show (countTests allTallyTests) ++ " tests"
  putStrLn $ "  EVM:     " ++ show (countTests allEvmTests) ++ " tests"
  let numTotal = countTests allSchemaTests +
                 countTests allMembersTests +
                 countTests allProposeTests +
                 countTests allVoteTests +
                 countTests allTallyTests +
                 countTests allEvmTests
  putStrLn $ "  ----------------------"
  putStrLn $ "  Total:   " ++ show numTotal ++ " tests"
  putStrLn ""
  putStrLn "Spec-Test Parity Coverage:"
  putStrLn "  REQ_SCHEMA_*  : 4 specs"
  putStrLn "  REQ_MEMBERS_* : 5 specs"
  putStrLn "  REQ_PROPOSE_* : 5 specs"
  putStrLn "  REQ_VOTE_*    : 5 specs"
  putStrLn "  REQ_TALLY_*   : 5 specs"
  putStrLn "  REQ_EVM_*     : 4 specs"
  putStrLn "  ----------------------"
  putStrLn "  Total:          28 specs"

-- =============================================================================
-- Main Entry Point
-- =============================================================================

main : IO ()
main = runAllTests
