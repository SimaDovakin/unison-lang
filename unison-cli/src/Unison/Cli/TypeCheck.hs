module Unison.Cli.TypeCheck
  ( ShouldUseTndr (..),
    computeTypecheckingEnvironment,
    typecheckTerm,
  )
where

import Data.Map.Strict qualified as Map
import Unison.Codebase (Codebase)
import Unison.Codebase qualified as Codebase
import Unison.FileParsers qualified as FileParsers
import Unison.Parser.Ann (Ann (..))
import Unison.Prelude
import Unison.Result qualified as Result
import Unison.Sqlite qualified as Sqlite
import Unison.Symbol (Symbol (Symbol))
import Unison.Syntax.Parser qualified as Parser
import Unison.Term (Term)
import Unison.Type (Type)
import Unison.Typechecker qualified as Typechecker
import Unison.UnisonFile (UnisonFile)
import Unison.UnisonFile qualified as UF
import Unison.Var qualified as Var

-- | Should we use type-directed name resolution?
data ShouldUseTndr
  = ShouldUseTndr'No
  | ShouldUseTndr'Yes Parser.ParsingEnv

computeTypecheckingEnvironment ::
  ShouldUseTndr ->
  Codebase IO Symbol Ann ->
  [Type Symbol Ann] ->
  UnisonFile Symbol Ann ->
  Sqlite.Transaction (Typechecker.Env Symbol Ann)
computeTypecheckingEnvironment shouldUseTndr codebase ambientAbilities unisonFile =
  case shouldUseTndr of
    ShouldUseTndr'No -> do
      typeLookup <- Codebase.typeLookupForDependencies codebase (UF.dependencies unisonFile)
      pure
        Typechecker.Env
          { _ambientAbilities = ambientAbilities,
            _typeLookup = typeLookup,
            _termsByShortname = Map.empty
          }
    ShouldUseTndr'Yes parsingEnv ->
      FileParsers.computeTypecheckingEnvironment
        ambientAbilities
        (Codebase.typeLookupForDependencies codebase)
        parsingEnv
        unisonFile

typecheckTerm ::
  Codebase IO Symbol Ann ->
  Term Symbol Ann ->
  Sqlite.Transaction
    ( Result.Result
        (Seq (Result.Note Symbol Ann))
        (Type Symbol Ann)
    )
typecheckTerm codebase tm = do
  let v = Symbol 0 (Var.Inference Var.Other)
  let file = UF.UnisonFileId mempty mempty [(v, External, tm)] mempty
  typeLookup <- Codebase.typeLookupForDependencies codebase (UF.dependencies file)
  let typecheckingEnv =
        Typechecker.Env
          { _ambientAbilities = [],
            _typeLookup = typeLookup,
            _termsByShortname = Map.empty
          }
  pure $ fmap extract $ FileParsers.synthesizeFile typecheckingEnv file
  where
    extract tuf
      | [[(_, _, _, ty)]] <- UF.topLevelComponents' tuf = ty
      | otherwise = error "internal error: typecheckTerm"
