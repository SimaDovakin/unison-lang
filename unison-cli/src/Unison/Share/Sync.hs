module Unison.Share.Sync
  ( -- * Get causal hash by path
    getCausalHashByPath,
    GetCausalHashByPathError (..),

    -- * Push
    push,
    PushError (..),
  )
where

import qualified Data.Map.NonEmpty as NEMap
import qualified Data.Set as Set
import Data.Set.NonEmpty (NESet)
import qualified Data.Set.NonEmpty as NESet
import U.Codebase.HashTags (CausalHash (unCausalHash))
import U.Codebase.Sqlite.Causal (DbCausal, GDbCausal (..))
import qualified U.Codebase.Sqlite.Causal as Sqlite.Causal (GDbCausal (..))
import U.Codebase.Sqlite.DbId (CausalHashId (..), HashId)
import qualified U.Util.Base32Hex as Base32Hex
import qualified U.Util.Hash as Hash
import Unison.Prelude
import qualified Unison.Sync.Types as Share
import qualified Unison.Sync.Types as Share.RepoPath (RepoPath (..))

------------------------------------------------------------------------------------------------------------------------
-- Get causal hash by path

data GetCausalHashByPathResponse
  = GetCausalHashByPathSuccess Share.HashJWT
  | GetCausalHashByPathEmpty
  | GetCausalHashByPathNoReadPermission

data GetCausalHashByPathError
  = GetCausalHashByPathErrorNoReadPermission

getCausalHashByPath :: Share.RepoPath -> IO (Either GetCausalHashByPathError (Maybe Share.HashJWT))
getCausalHashByPath repoPath =
  _getCausalHashByPath (Share.GetCausalHashByPathRequest repoPath) <&> \case
    GetCausalHashByPathSuccess hashJwt -> Right (Just hashJwt)
    GetCausalHashByPathEmpty -> Right Nothing
    GetCausalHashByPathNoReadPermission -> Left GetCausalHashByPathErrorNoReadPermission

_getCausalHashByPath :: Share.GetCausalHashByPathRequest -> IO GetCausalHashByPathResponse
_getCausalHashByPath = undefined

------------------------------------------------------------------------------------------------------------------------
-- Push

data PushError
  = PushErrorServerMissingDependencies (NESet Share.Hash)
  | PushErrorHashMismatch Share.HashMismatch

_updatePath :: Share.UpdatePathRequest -> IO UpdatePathResponse
_updatePath = undefined

_uploadEntities :: Share.UploadEntitiesRequest -> IO UploadEntitiesResponse
_uploadEntities = undefined

push :: Connection -> Share.RepoPath -> Maybe Share.Hash -> CausalHash -> IO (Either PushError ())
push conn repoPath expectedHash causalHash = do
  _updatePath request >>= \case
    UpdatePathSuccess -> pure (Right ())
    UpdatePathHashMismatch mismatch -> pure (Left (PushErrorHashMismatch mismatch))
    UpdatePathMissingDependencies (Share.NeedDependencies dependencies) -> do
      upload conn (Share.RepoPath.repoName repoPath) dependencies
      _updatePath request <&> \case
        UpdatePathSuccess -> Right ()
        UpdatePathHashMismatch mismatch -> Left (PushErrorHashMismatch mismatch)
        UpdatePathMissingDependencies (Share.NeedDependencies dependencies) ->
          Left (PushErrorServerMissingDependencies dependencies)
  where
    request =
      Share.UpdatePathRequest
        { path = repoPath,
          expectedHash =
            expectedHash <&> \hash ->
              Share.TypedHash
                { hash,
                  entityType = Share.CausalType
                },
          newHash =
            Share.TypedHash
              { hash =
                  causalHash
                    & unCausalHash
                    & Hash.toBase32Hex
                    & Base32Hex.toText
                    & Share.Hash,
                entityType = Share.CausalType
              }
        }

upload :: Connection -> Share.RepoName -> NESet Share.Hash -> IO ()
upload conn repoName dependencies = do
  request <- do
    entities <-
      NEMap.fromAscList <$> traverse (\dep -> (dep,) <$> resolveHashToEntity conn dep) (NESet.toAscList dependencies)
    pure Share.UploadEntitiesRequest {repoName, entities}

  _uploadEntities request >>= \case
    UploadEntitiesNeedDependencies (Share.NeedDependencies dependencies) ->
      upload conn repoName dependencies
    UploadEntitiesSuccess -> pure ()

------------------------------------------------------------------------------------------------------------------------
-- Pull

-- If we just got #thing from the server,
--   If we already have the entity in the main database, we're done.
--     - This should't happen, why would the server have sent us this?
--
--   Otherwise, if we already have the entity in temp_entity, ???
--
--   Otherwise (if we don't have it at all),
--     1. Extract dependencies #dep1, #dep2, #dep3 from #thing blob.
--     2. Filter down to just the dependencies we don't have. <-- "have" means in either real/temp storage.
--     3. If that's {}, then store it in the main table.
--     4. If that's (say) {#dep1, #dep2},
--         1. Add (#thing, #dep1), (#thing, #dep2) to temp_entity_missing_dependency
--
--  Note: beef up insert_entity procedure to flush temp_entity table
--    1. When inserting object #foo,
--        look up all dependents of #foo in
--        temp_entity_missing_dependency table (say #bar, #baz).
--    2. Delete (#bar, #foo) and (#baz, #foo) from temp_entity_missing_dependency.
--    3. Delete #foo from temp_entity (if it's there)
--    4. For each like #bar and #baz with no more rows in temp_entity_missing_dependency,
--        insert_entity them.
--

------------------------------------------------------------------------------------------------------------------------
--

data UpdatePathResponse
  = UpdatePathSuccess
  | UpdatePathHashMismatch Share.HashMismatch
  | UpdatePathMissingDependencies (Share.NeedDependencies Share.Hash)

data UploadEntitiesResponse
  = UploadEntitiesSuccess
  | UploadEntitiesNeedDependencies (Share.NeedDependencies Share.Hash)

data PullError

-- Option 1: have push be itself in the Transaction monad, use unsafePerformIdempotentIO
-- fuction to do the interleaved IO calls (http, etc)
--
--   push :: RepoPath -> ... -> Transaction (Either PushError ())
--   push = do
--     unsafePerformIdempotentIO (updatePath ...)
--
-- Option 2: have push "go around" the Transaction abstraction by beginning/commiting explicitly,
-- and immediately un-Transaction-newtyping the low-level calls like loadHashId
--
--   push :: Connection -> RepoPath -> ... -> IO (Either PushError ())
--   push conn = do
--     let foo transaction = unsafeUnTransaction transaction conn
--
--     ...
--     result <- foo (loadHashId hashId)
--     ...
--
-- newtype Transaction a = Transaction { unsafeUnTransaction :: Connection -> IO a }

type Connection = ()

type Transaction a = ()

expectHash :: HashId -> Transaction Hash.Hash
expectHash = undefined

pull :: Connection -> Share.RepoPath -> IO (Either PullError CausalHash)
pull _conn _repoPath = undefined

-- FIXME rename, etc
resolveHashToEntity :: Connection -> Share.Hash -> IO (Share.Entity Text Share.Hash Share.Hash)
resolveHashToEntity = undefined
