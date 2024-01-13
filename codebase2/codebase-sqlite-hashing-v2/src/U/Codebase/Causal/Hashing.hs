module U.Codebase.Causal.Hashing where

import Data.Set
import Data.Set qualified as Set
import U.Codebase.HashTags (BranchHash (..), CausalHash (..))
import Unison.Hashing.V2 qualified as Hashing

hashCausal :: BranchHash -> Set CausalHash -> CausalHash
hashCausal branchHash ancestors =
  CausalHash . Hashing.contentHash $
    Hashing.Causal
      { Hashing.branchHash = unBranchHash branchHash,
        Hashing.parents = Set.map unCausalHash ancestors
      }
