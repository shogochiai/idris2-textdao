||| TextDAO Text Test Suite
||| Tests for createText function
module TextDAO.Functions.Text.Tests.TextTest

import TextDAO.Storages.Schema
import TextDAO.Functions.Propose.Propose
import TextDAO.Functions.Tally.Tally
import TextDAO.Functions.Text.Text

%default covering

-- =============================================================================
-- REQ_TEXT_001: Create text from approved proposal
-- =============================================================================

||| Test: Create text stores metadata correctly
||| REQ_TEXT_001
export
test_REQ_TEXT_001_createText : IO Bool
test_REQ_TEXT_001_createText = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111

  -- Approve proposal
  approveProposal pid 1 1

  -- Create text
  textId <- createText pid 0xabcdef1234567890

  -- Verify
  metadata <- getTextMetadata textId
  storedPid <- getTextProposalId textId
  storedHid <- getTextHeaderId textId

  pure (metadata == 0xabcdef1234567890 && storedPid == pid && storedHid == 1)

||| Test: Text count increases
||| REQ_TEXT_002
export
test_REQ_TEXT_002_textCount : IO Bool
test_REQ_TEXT_002_textCount = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111
  approveProposal pid 1 1

  -- Get initial count
  initialCount <- getTextCount

  -- Create text
  _ <- createText pid 0xaaaa

  -- Verify count increased
  finalCount <- getTextCount

  pure (finalCount == initialCount + 1)

||| Test: Multiple texts can be created
export
test_text_multiple : IO Bool
test_text_multiple = do
  -- Setup
  setExpiryDuration 86400

  -- Create and approve first proposal
  pid1 <- createProposal 0x1111
  approveProposal pid1 1 1

  -- Create and approve second proposal
  pid2 <- createProposal 0x2222
  approveProposal pid2 1 1

  -- Create texts
  t1 <- createText pid1 0xaaaa
  t2 <- createText pid2 0xbbbb

  -- Verify texts are independent
  m1 <- getTextMetadata t1
  m2 <- getTextMetadata t2

  pure (m1 == 0xaaaa && m2 == 0xbbbb && t1 /= t2)

||| Test: Text links to correct proposal
export
test_text_proposal_link : IO Bool
test_text_proposal_link = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111
  approveProposal pid 1 1

  -- Create text
  textId <- createText pid 0xcccc

  -- Verify proposal link
  storedPid <- getTextProposalId textId

  pure (storedPid == pid)

-- =============================================================================
-- Test Collection
-- =============================================================================

export
allTextTests : List (String, IO Bool)
allTextTests =
  [ ("REQ_TEXT_001_createText", test_REQ_TEXT_001_createText)
  , ("REQ_TEXT_002_textCount", test_REQ_TEXT_002_textCount)
  , ("text_multiple", test_text_multiple)
  , ("text_proposal_link", test_text_proposal_link)
  ]

||| Run all text tests and return passed count
export
runTextTests : IO Integer
runTextTests = do
  r1 <- test_REQ_TEXT_001_createText
  r2 <- test_REQ_TEXT_002_textCount
  r3 <- test_text_multiple
  r4 <- test_text_proposal_link
  pure $ (if r1 then 1 else 0) + (if r2 then 1 else 0) +
         (if r3 then 1 else 0) + (if r4 then 1 else 0)
