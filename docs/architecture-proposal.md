# EVM Idris2 Stack - 総合アーキテクチャ設計案

## 現状の問題

### 0. ERC-7546 / Proxy / Dictionary の重複と責務混在

**idris2-yul 側:**
```
src/EVM/Storage/ERC7201.idr   -- EVM FFI primitives (sload, sstore, mstore, keccak256)
src/EVM/Storage/ERC7546.idr   -- EVM FFI + Proxy helpers (delegatecall, forwardToImplementation)
examples/Dictionary.idr       -- Full contract (FFI再定義 + ビジネスロジック)
examples/Proxy.idr            -- Full contract (FFI再定義 + ビジネスロジック)
```

**idris2-subcontract 側:**
```
src/Subcontract/Core/Proxy.idr      -- Thin wrapper (imports ERC7546)
src/Subcontract/Core/Dictionary.idr -- Full contract (FFI再定義 + ロジック)
src/MC/Core/Proxy.idr               -- Duplicate of above
src/MC/Core/Dictionary.idr          -- Duplicate of above
```

**問題点:**
1. **FFI重複**: `%foreign "evm:sload"` 等が各ファイルで再定義
2. **責務混在**: idris2-yul の ERC7546.idr に高レベルヘルパー (`forwardToImplementation`)
3. **examples vs src**: idris2-yul/examples にフルコントラクトがある
4. **MC vs Subcontract**: idris2-subcontract 内で重複

### 1. Revert Reason
```idris
-- 現状: 理由なし
evmRevert 0 0

-- Solidity: 理由あり
revert NotMember();
revert("Already initialized");
```

**問題点:**
- `idris2-yul`: Error型は定義済みだが未使用
- `idris2-subcontract`: revertは理由なしのまま
- `idris2-evm`: returnDataを取得するが、デコードしない
- テストでexpectRevertできない

### 2. Schema可読性
```solidity
// Solidity (宣言的・人間可読)
struct Member {
    address addr;
    string metadataCid;
}
struct Members {
    Member[] members;
}
```

```idris
-- 現状 (手続き的・低レベル)
getMemberSlot : Integer -> IO Integer
getMemberSlot index = do
  mstore 0 index
  mstore 32 SLOT_MEMBERS
  keccak256 0 64

MEMBER_OFFSET_ADDRESS : Integer
MEMBER_OFFSET_ADDRESS = 0
```

---

## 提案: レイヤー別責務

```
┌─────────────────────────────────────────────────────────────────────┐
│                        idris2-textdao                               │
│  ・ビジネスロジック (Propose, Vote, Tally, etc.)                      │
│  ・宣言的Schema定義 (@storage annotation)                             │
│  ・カスタムエラー型 (TextDAOError)                                    │
└───────────────────────────────────────────────────────────────────────┘
                                 ↓ uses
┌─────────────────────────────────────────────────────────────────────┐
│                       idris2-subcontract                            │
│  【高レベル抽象化のみ - FFI定義なし】                                  │
│  ・Storage DSL (struct/array/mapping 抽象化)                         │
│  ・Error DSL (revert with reason)                                   │
│  ・Cheat DSL (expectRevert, prank, etc.)                            │
│  ・ERC-7546 高レベルAPI (Dictionary, Proxy ビジネスロジック)           │
│  ・Type-safe ABI encoder/decoder                                    │
└───────────────────────────────────────────────────────────────────────┘
                                 ↓ imports
┌─────────────────────────────────────────────────────────────────────┐
│                          idris2-yul                                 │
│  【FFI定義の唯一の場所】                                              │
│  ・EVM FFI primitives (%foreign "evm:*") - 全opcode                 │
│  ・Yul codegen (Idris AST → Yul)                                    │
│  ・ERC-7201 slot計算 primitives                                      │
│  ・ERC-7546 低レベルprimitives (DICTIONARY_SLOT, delegatecall)       │
│  ・Error selector生成 (keccak256[:4])                                │
└───────────────────────────────────────────────────────────────────────┘
                                 ↓ tested by
┌─────────────────────────────────────────────────────────────────────┐
│                          idris2-evm                                 │
│  ・Pure Idris2 EVM interpreter                                      │
│  ・Revert reason decoder                                            │
│  ・Cheat implementation (storage manipulation, etc.)                │
│  ・Coverage tracking                                                │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 詳細設計

### Phase 0: FFI統合と責務分離 (idris2-yul)

**現状の問題:**
```idris
-- ERC7201.idr (primitives)
%foreign "evm:sload"
prim__sload : Integer -> PrimIO Integer

-- ERC7546.idr (primitives + high-level混在)
%foreign "evm:delegatecall"    -- primitive
prim__delegatecall : ...
forwardToImplementation : IO () -- high-level helper ← ここが問題

-- examples/Dictionary.idr (FFI再定義)
%foreign "evm:sload"           -- 重複!
prim__sload : Integer -> PrimIO Integer
```

**提案: idris2-yul のモジュール再構成**

```
src/
├── EVM/
│   ├── Primitives.idr         -- 【統合】全EVM opcode FFI (唯一の定義場所)
│   │   %foreign "evm:sload", "evm:sstore", "evm:mstore"
│   │   %foreign "evm:caller", "evm:callvalue", "evm:calldataload"
│   │   %foreign "evm:delegatecall", "evm:staticcall", "evm:call"
│   │   %foreign "evm:return", "evm:revert", "evm:log0-4"
│   │   %foreign "evm:keccak256"
│   │   ...全opcode
│   │
│   ├── Storage/
│   │   ├── Slot.idr           -- 低レベルslot計算 (mappingSlot, arraySlot)
│   │   └── Namespace.idr      -- ERC-7201 namespace計算 (旧ERC7201.idr)
│   │
│   ├── ABI/
│   │   ├── Types.idr          -- ABIType, Function, Event, Error
│   │   ├── Encode.idr         -- ABI encoding
│   │   └── Decode.idr         -- ABI decoding
│   │
│   └── Error/
│       └── Selector.idr       -- error selector計算 (keccak256[:4])
│
└── Compiler/
    └── ...                    -- Yul codegen (変更なし)

※ ERC-7546 は idris2-subcontract へ完全移動 (後述)
※ ERC-7201 → Namespace.idr にリネーム (汎用的な名前)
```

**After: 統合されたPrimitives.idr**
```idris
module EVM.Primitives

-- Storage
%foreign "evm:sload"
prim__sload : Integer -> PrimIO Integer
%foreign "evm:sstore"
prim__sstore : Integer -> Integer -> PrimIO ()

-- Memory
%foreign "evm:mstore"
prim__mstore : Integer -> Integer -> PrimIO ()
%foreign "evm:mload"
prim__mload : Integer -> PrimIO Integer

-- Calldata
%foreign "evm:calldataload"
prim__calldataload : Integer -> PrimIO Integer
%foreign "evm:calldatasize"
prim__calldatasize : PrimIO Integer
%foreign "evm:calldatacopy"
prim__calldatacopy : Integer -> Integer -> Integer -> PrimIO ()

-- Environment
%foreign "evm:caller"
prim__caller : PrimIO Integer
%foreign "evm:callvalue"
prim__callvalue : PrimIO Integer
%foreign "evm:address"
prim__address : PrimIO Integer
%foreign "evm:origin"
prim__origin : PrimIO Integer
%foreign "evm:gas"
prim__gas : PrimIO Integer

-- Block
%foreign "evm:timestamp"
prim__timestamp : PrimIO Integer
%foreign "evm:number"
prim__number : PrimIO Integer
%foreign "evm:chainid"
prim__chainid : PrimIO Integer

-- Control
%foreign "evm:return"
prim__return : Integer -> Integer -> PrimIO ()
%foreign "evm:revert"
prim__revert : Integer -> Integer -> PrimIO ()
%foreign "evm:stop"
prim__stop : PrimIO ()

-- Call
%foreign "evm:call"
prim__call : Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> PrimIO Integer
%foreign "evm:delegatecall"
prim__delegatecall : Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> PrimIO Integer
%foreign "evm:staticcall"
prim__staticcall : Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> PrimIO Integer

-- Return data
%foreign "evm:returndatasize"
prim__returndatasize : PrimIO Integer
%foreign "evm:returndatacopy"
prim__returndatacopy : Integer -> Integer -> Integer -> PrimIO ()

-- Log
%foreign "evm:log0"
prim__log0 : Integer -> Integer -> PrimIO ()
%foreign "evm:log1"
prim__log1 : Integer -> Integer -> Integer -> PrimIO ()
%foreign "evm:log2"
prim__log2 : Integer -> Integer -> Integer -> Integer -> PrimIO ()
%foreign "evm:log3"
prim__log3 : Integer -> Integer -> Integer -> Integer -> Integer -> PrimIO ()
%foreign "evm:log4"
prim__log4 : Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> PrimIO ()

-- Crypto
%foreign "evm:keccak256"
prim__keccak256 : Integer -> Integer -> PrimIO Integer

-- ========================================
-- Wrapped IO versions (convenience)
-- ========================================
export sload : Integer -> IO Integer
export sstore : Integer -> Integer -> IO ()
export mstore : Integer -> Integer -> IO ()
-- ... etc
```

### Phase 0b: idris2-subcontract の責務明確化

**削除するもの:**
- `MC.*` モジュール群 (Subcontract.* と重複)
- FFI再定義 (`%foreign "evm:*"`)

**移動するもの:**
```
Before (idris2-yul):
  ERC7546.idr: forwardToImplementation, queryDictionary

After (idris2-subcontract):
  Subcontract/Proxy/Forward.idr: forwardToImplementation
  Subcontract/Proxy/Query.idr: queryDictionary
```

**idris2-subcontract 構成案:**
```
src/Subcontract/
├── Core/
│   ├── StorageCap.idr        -- Capability-based storage (既存)
│   ├── Handler.idr           -- Handler type (StorageCap -> IO a)
│   └── Entry.idr             -- Contract entry point helpers
│
├── Storage/
│   ├── DSL.idr               -- 【新規】Storage schema DSL
│   ├── Array.idr             -- 【新規】Array storage helpers
│   └── Mapping.idr           -- 【新規】Mapping storage helpers
│
├── Error/
│   ├── Types.idr             -- 【新規】RevertError typeclass
│   ├── Common.idr            -- 【新規】Unauthorized, AlreadyInitialized, etc.
│   └── Encode.idr            -- 【新規】Error encoding
│
├── Standards/
│   └── ERC7546/              -- 【移動】ERC-7546 UCS フル実装
│       ├── Slots.idr         -- DICTIONARY_SLOT 定数
│       ├── Dictionary.idr    -- Dictionary contract
│       ├── Proxy.idr         -- Proxy contract
│       └── Forward.idr       -- forwardToImplementation, queryDictionary
│
├── Cheat/
│   ├── Types.idr             -- 【新規】CheatCode GADT
│   ├── Script.idr            -- 【新規】CheatScript monad
│   └── Foundry.idr           -- 【新規】prank, expectRevert, warp, roll
│
└── ABI/
    ├── Sig.idr               -- 既存
    ├── Decoder.idr           -- 既存
    └── Encoder.idr           -- 【新規】ABI encoding
```

**設計方針:**
- **idris2-yul**: EVM primitives + 汎用slot計算のみ (標準規格の実装なし)
- **idris2-subcontract**: 標準規格(ERC-*)の実装は全て `Standards/` 以下に配置
- 将来的に ERC-20, ERC-721 等も `Standards/ERC20/`, `Standards/ERC721/` に追加可能

### Phase 1: idris2-yul - Error Primitives

```idris
-- src/EVM/Error.idr (新規)

||| Custom error definition (Solidity 0.8.4+ style)
||| error NotMember(address caller)
public export
data CustomError : Type where
  MkCustomError : (name : String) -> (selector : Bits32) -> (params : List ABIType) -> CustomError

||| Compile-time selector calculation
||| selector = keccak256("NotMember(address)")[:4]
export
errorSelector : String -> List ABIType -> Bits32
errorSelector name params = ... -- keccak256 at compile time

||| Generate Yul for revert with custom error
export
revertWithError : CustomError -> List YulExpr -> YulStmt
revertWithError err args =
  -- mstore(0, selector << 224)
  -- mstore(4, arg0)
  -- mstore(36, arg1)
  -- ...
  -- revert(0, 4 + 32*len(args))
```

### Phase 2: idris2-subcontract - Storage DSL

```idris
-- src/Subcontract/Storage/Schema.idr (新規)

||| Type-level storage slot
public export
data Slot : Type -> Type where
  MkSlot : Integer -> Slot a

||| Storage location annotation
public export
data StorageLocation : String -> Type where
  MkStorageLocation : StorageLocation namespace

||| Struct field with offset
public export
record Field (name : String) (ty : Type) where
  constructor MkField
  offset : Nat

||| Define a storage struct
||| Generates slot accessors automatically
public export
interface StorageStruct a where
  baseSlot : Slot a
  fieldOffsets : List (String, Nat)

-- ================================
-- 使用例 (idris2-textdao側)
-- ================================

-- 宣言的な定義
record Member where
  constructor MkMember
  addr : Address
  metadataCid : Bytes32

record Members where
  constructor MkMembers
  members : Array Member

-- deriving で自動生成される関数
-- getMemberAddr : StorageCap -> Integer -> IO Address
-- setMemberAddr : StorageCap -> Integer -> Address -> IO ()
-- getMemberMetadata : StorageCap -> Integer -> IO Bytes32
-- setMemberMetadata : StorageCap -> Integer -> Bytes32 -> IO ()
-- getMembersLength : StorageCap -> IO Integer
-- pushMember : StorageCap -> Member -> IO Integer
```

**比較:**
```idris
-- Before (現状): 400行の手続きコード
getProposalHeadersSlot : ProposalId -> IO Integer
getProposalHeadersSlot pid = do
  baseSlot <- getProposalSlot pid
  pure (baseSlot + 0x10)

getHeaderSlot : ProposalId -> HeaderId -> IO Integer
getHeaderSlot pid hid = do
  headersSlot <- getProposalHeadersSlot pid
  mstore 0 hid
  mstore 32 headersSlot
  keccak256 0 64

-- After (提案): 20行の宣言的定義
@storage "textDAO.Deliberation"
record Deliberation where
  proposals : Array Proposal
  config : DeliberationConfig

record Proposal where
  headers : Array Header
  cmds : Array Command
  meta : ProposalMeta

record Header where
  metadataCid : String
  tagIds : Array Integer
```

### Phase 3: idris2-subcontract - Error DSL

```idris
-- src/Subcontract/Error.idr (新規)

||| Define custom errors
public export
data TextDAOError
  = NotMember Address
  | AlreadyMember Address
  | ProposalExpired ProposalId
  | NotEnoughVotes ProposalId Integer
  | Unauthorized

||| Type class for error encoding
public export
interface RevertError a where
  errorName : a -> String
  errorSelector : a -> Bits32
  encodeError : a -> List Bits8

||| Implementation for TextDAOError
RevertError TextDAOError where
  errorName (NotMember _) = "NotMember"
  errorName (AlreadyMember _) = "AlreadyMember"
  ...

  errorSelector (NotMember _) = 0x... -- keccak256("NotMember(address)")[:4]
  ...

||| Revert with error
export
revert : RevertError e => e -> IO ()
revert err = do
  -- Encode error to memory
  let encoded = encodeError err
  -- mstore encoded data
  ...
  evmRevert 0 (length encoded)
```

### Phase 4: idris2-subcontract - Cheat DSL

```idris
-- src/Subcontract/Cheat.idr (新規)

||| Cheat codes for testing (Foundry-style)
public export
data CheatCode : Type -> Type where
  ||| Set msg.sender for next call
  Prank : Address -> CheatCode ()

  ||| Expect revert with specific error
  ExpectRevert : RevertError e => e -> CheatCode ()

  ||| Expect revert with any error
  ExpectRevertAny : CheatCode ()

  ||| Set storage directly
  Store : Address -> Slot a -> a -> CheatCode ()

  ||| Read storage directly
  Load : Address -> Slot a -> CheatCode a

  ||| Set block.timestamp
  Warp : Integer -> CheatCode ()

  ||| Set block.number
  Roll : Integer -> CheatCode ()

  ||| Give ETH to address
  Deal : Address -> Integer -> CheatCode ()

  ||| Label address for traces
  Label : Address -> String -> CheatCode ()

||| Cheat script monad
public export
data CheatScript : Type -> Type where
  Pure : a -> CheatScript a
  Bind : CheatScript a -> (a -> CheatScript b) -> CheatScript b
  Cheat : CheatCode a -> CheatScript a
  Call : Address -> Selector -> List Integer -> CheatScript Integer

-- ================================
-- 使用例
-- ================================

testNotMember : CheatScript ()
testNotMember = do
  -- Non-member tries to propose
  prank 0xBAD_USER
  expectRevert (NotMember 0xBAD_USER)
  call textDAO propose [headerCid, commandCid]

  -- Should not reach here if revert happened correctly
  pure ()
```

### Phase 5: idris2-evm - Cheat Implementation

```idris
-- src/EVM/Cheats.idr (新規)

||| Cheat state in interpreter
public export
record CheatState where
  constructor MkCheatState
  prankedCaller : Maybe Address
  expectedRevert : Maybe (Either () (Bits32, List Bits8))  -- Any or specific
  labels : SortedMap Address String
  warpedTimestamp : Maybe Integer
  rolledBlock : Maybe Integer

||| Check if revert matches expectation
export
checkExpectedRevert : CheatState -> List Bits8 -> Either String ()
checkExpectedRevert state returnData =
  case state.expectedRevert of
    Nothing => Left "Unexpected revert"
    Just (Left ()) => Right ()  -- ExpectRevertAny
    Just (Right (selector, params)) =>
      if decodeSelector returnData == selector
        then Right ()
        else Left $ "Expected " ++ showSelector selector
                 ++ " but got " ++ showSelector (decodeSelector returnData)

||| Decode revert reason from returnData
export
decodeRevertReason : List Bits8 -> Either String RevertInfo
decodeRevertReason data =
  if length data < 4 then Left "No selector"
  else
    let selector = bytesToSelector (take 4 data)
        params = drop 4 data
    in Right (MkRevertInfo selector params)
```

---

## マイグレーション計画

### Step 0: FFI統合 (idris2-yul) ★最優先
1. `EVM.Primitives` モジュール作成 (全FFI統合)
2. `EVM.Storage.ERC7201` から FFI を削除、Primitives を import
3. `EVM.Storage.ERC7546` から高レベルヘルパーを削除 (slot定数のみ残す)
4. `examples/*.idr` から FFI 再定義を削除、Primitives を import

### Step 0b: 重複削除 (idris2-subcontract)
1. `MC.*` モジュール群を削除
2. `Subcontract.Core.Dictionary/Proxy` から FFI 再定義を削除
3. `forwardToImplementation` 等を `Subcontract.Proxy.*` に移動
4. `EVM.Primitives` を import するよう書き換え

### Step 1: idris2-yul に Error primitives 追加
- `EVM.Error.Selector` モジュール追加
- keccak256 コンパイル時計算
- Yul revert with data 生成

### Step 2: idris2-subcontract に Error DSL 追加
- `Subcontract.Error.Types` モジュール追加
- `RevertError` type class
- 基本エラー型 (Unauthorized, etc.)

### Step 3: idris2-textdao でエラー型定義
- `TextDAO.Errors` モジュール追加
- TextDAOError 型定義
- 既存 `evmRevert 0 0` を置換

### Step 4: idris2-evm に Cheat 実装
- `EVM.Cheats` モジュール追加
- revert reason デコード
- expectRevert チェック

### Step 5: idris2-subcontract に Storage DSL 追加
- `Subcontract.Storage.DSL` モジュール追加
- record → slot accessor 自動導出
- 既存 Schema.idr をマイグレーション

---

## 期待される最終形

```idris
-- TextDAO/Errors.idr
data TextDAOError
  = NotMember Address
  | NotRep ProposalId Address
  | ProposalExpired ProposalId
  | AlreadyVoted ProposalId Address

-- TextDAO/Schema.idr (人間可読)
@storage "textDAO.Deliberation"
record Deliberation where
  proposals : Array Proposal
  config : DeliberationConfig

@storage "textDAO.Members"
record Members where
  members : Array Member

record Member where
  addr : Address
  metadataCid : Bytes32

-- TextDAO/Functions/Propose.idr
propose : Header -> Command -> Handler ProposalId
propose header cmd cap = do
  callerAddr <- caller
  isMem <- isMember cap callerAddr
  unless isMem $ revert (NotMember callerAddr)  -- ← 明確なエラー
  ...

-- TextDAO/Tests/ProposeTest.idr
testNotMemberCannotPropose : CheatScript ()
testNotMemberCannotPropose = do
  prank 0xBAD_USER
  expectRevert (NotMember 0xBAD_USER)  -- ← エラーを検証
  call textDAO SEL_PROPOSE [headerCid, cmdCid]
```

---

## 責務分担まとめ

| Layer | 責務 | 変更内容 |
|-------|------|----------|
| **idris2-yul** | FFI定義(唯一), Yul codegen | `EVM.Primitives`統合, `ERC7546`削除 |
| **idris2-subcontract** | 高レベル抽象化(FFIなし), 標準規格実装 | MC.*削除, `Standards/ERC7546`追加, Storage/Error/Cheat DSL追加 |
| **idris2-evm** | EVM interpreter, テスト | Revertデコード, Cheat実装 |
| **idris2-textdao** | ビジネスロジック | 宣言的Schema, カスタムエラー |

---

## 依存関係図 (After)

```
idris2-textdao
    │
    ├── imports ──→ idris2-subcontract
    │                    │
    │                    ├── Subcontract.Storage.DSL
    │                    ├── Subcontract.Error.Types
    │                    ├── Subcontract.Cheat.*
    │                    ├── Subcontract.Standards.ERC7546.*  ← 標準規格はここ
    │                    │
    │                    └── imports ──→ idris2-yul
    │                                        │
    │                                        ├── EVM.Primitives (全FFI)
    │                                        ├── EVM.Storage.Slot
    │                                        ├── EVM.Storage.Namespace (旧ERC7201)
    │                                        └── EVM.ABI.*
    │
    └── tested by ──→ idris2-evm
                          │
                          ├── EVM.Interpreter
                          ├── EVM.Cheats (expectRevert impl)
                          └── EVM.Decode.RevertReason
```

## クリーンアップ対象

### idris2-yul
- [ ] `EVM.Primitives` 作成 (全FFI統合)
- [ ] `EVM.Storage.ERC7201` → `EVM.Storage.Namespace` リネーム、FFI削除
- [ ] `EVM.Storage.ERC7546` → 削除 (idris2-subcontract へ完全移動)
- [ ] `examples/*.idr` の FFI 再定義 → 削除して `EVM.Primitives` を import

### idris2-subcontract
- [ ] `MC.*` モジュール群を削除
- [ ] `Subcontract.Core.Dictionary` → `Subcontract.Standards.ERC7546.Dictionary` へ移動
- [ ] `Subcontract.Core.Proxy` → `Subcontract.Standards.ERC7546.Proxy` へ移動
- [ ] FFI再定義を全て削除、`EVM.Primitives` を import

### 新規作成
- [ ] `idris2-yul/src/EVM/Primitives.idr`
- [ ] `idris2-subcontract/src/Subcontract/Standards/ERC7546/Slots.idr`
- [ ] `idris2-subcontract/src/Subcontract/Storage/DSL.idr`
- [ ] `idris2-subcontract/src/Subcontract/Error/Types.idr`
- [ ] `idris2-subcontract/src/Subcontract/Cheat/*.idr`
- [ ] `idris2-evm/src/EVM/Cheats.idr`
