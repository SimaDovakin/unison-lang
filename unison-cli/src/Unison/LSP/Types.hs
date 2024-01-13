{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

module Unison.LSP.Types where

import Colog.Core hiding (Lens')
import Control.Comonad.Cofree (Cofree)
import Control.Comonad.Cofree qualified as Cofree
import Control.Lens hiding (List, (:<))
import Control.Monad.Except
import Control.Monad.Reader
import Data.Aeson qualified as Aeson
import Data.IntervalMap.Lazy (IntervalMap)
import Data.IntervalMap.Lazy qualified as IM
import Data.Map qualified as Map
import Ki qualified
import Language.LSP.Logging qualified as LSP
import Language.LSP.Protocol.Lens
import Language.LSP.Protocol.Message (MessageDirection (..), MessageKind (..), Method, TMessage, TNotificationMessage, fromServerNot)
import Language.LSP.Protocol.Types
import Language.LSP.Server
import Language.LSP.Server qualified as LSP
import Language.LSP.VFS
import Unison.Codebase
import Unison.Codebase.Path qualified as Path
import Unison.Codebase.Runtime (Runtime)
import Unison.DataDeclaration qualified as DD
import Unison.Debug qualified as Debug
import Unison.LSP.Orphans ()
import Unison.LabeledDependency (LabeledDependency)
import Unison.Name (Name)
import Unison.NameSegment (NameSegment)
import Unison.Names (Names)
import Unison.Parser.Ann
import Unison.Prelude
import Unison.PrettyPrintEnvDecl (PrettyPrintEnvDecl)
import Unison.Reference qualified as Reference
import Unison.Referent (Referent)
import Unison.Result (Note)
import Unison.Server.Backend qualified as Backend
import Unison.Server.NameSearch (NameSearch)
import Unison.Sqlite qualified as Sqlite
import Unison.Symbol
import Unison.Syntax.Lexer qualified as Lexer
import Unison.Term (Term)
import Unison.Type (Type)
import Unison.UnisonFile qualified as UF
import UnliftIO

-- | A custom LSP monad wrapper so we can provide our own environment.
newtype Lsp a = Lsp {runLspM :: ReaderT Env (LspM Config) a}
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadUnliftIO, MonadReader Env, MonadLsp Config)

-- | Log an info message to the client's LSP log.
logInfo :: Text -> Lsp ()
logInfo msg = do
  let LogAction log = LSP.defaultClientLogger
  log (WithSeverity msg Info)

-- | Log an error message to the client's LSP log, this will be shown to the user in most LSP
-- implementations.
logError :: Text -> Lsp ()
logError msg = do
  let LogAction log = LSP.defaultClientLogger
  log (WithSeverity msg Error)

-- | Environment for the Lsp monad.
data Env = Env
  { -- contains handlers for talking to the client.
    lspContext :: LanguageContextEnv Config,
    codebase :: Codebase IO Symbol Ann,
    parseNamesCache :: IO Names,
    ppedCache :: IO PrettyPrintEnvDecl,
    nameSearchCache :: IO (NameSearch Sqlite.Transaction),
    currentPathCache :: IO Path.Absolute,
    vfsVar :: MVar VFS,
    runtime :: Runtime Symbol,
    -- The information we have for each file.
    -- The MVar is filled when analysis finishes, and is emptied whenever
    -- the file has changed (until it's checked again)
    checkedFilesVar :: TVar (Map Uri (TMVar FileAnalysis)),
    dirtyFilesVar :: TVar (Set Uri),
    -- A map  of request IDs to an action which kills that request.
    cancellationMapVar :: TVar (Map (Int32 |? Text) (IO ())),
    -- A lazily computed map of all valid completion suffixes from the current path.
    completionsVar :: TVar CompletionTree,
    scope :: Ki.Scope
  }

-- | A suffix tree over path segments of name completions.
-- see 'namesToCompletionTree' for more on how this is built and the invariants it should have.
newtype CompletionTree = CompletionTree
  { unCompletionTree :: Cofree (Map NameSegment) (Set (Name, LabeledDependency))
  }
  deriving (Show)

instance Semigroup CompletionTree where
  CompletionTree (a Cofree.:< subtreeA) <> CompletionTree (b Cofree.:< subtreeB) =
    CompletionTree (a <> b Cofree.:< Map.unionWith (\a b -> unCompletionTree $ CompletionTree a <> CompletionTree b) subtreeA subtreeB)

instance Monoid CompletionTree where
  mempty = CompletionTree $ mempty Cofree.:< mempty

-- | A monotonically increasing file version tracked by the lsp client.
type FileVersion = Int32

type LexedSource = (Text, [Lexer.Token Lexer.Lexeme])

data TypeSignatureHint = TypeSignatureHint
  { name :: Name,
    referent :: Referent,
    bindingLocation :: Range,
    signature :: Type Symbol Ann
  }
  deriving (Show)

data FileAnalysis = FileAnalysis
  { fileUri :: Uri,
    fileVersion :: FileVersion,
    lexedSource :: LexedSource,
    tokenMap :: IM.IntervalMap Position Lexer.Lexeme,
    parsedFile :: Maybe (UF.UnisonFile Symbol Ann),
    typecheckedFile :: Maybe (UF.TypecheckedUnisonFile Symbol Ann),
    notes :: Seq (Note Symbol Ann),
    diagnostics :: IntervalMap Position [Diagnostic],
    codeActions :: IntervalMap Position [CodeAction],
    typeSignatureHints :: Map Symbol TypeSignatureHint,
    fileSummary :: Maybe FileSummary
  }
  deriving stock (Show)

-- | A file that parses might not always type-check, but often we just want to get as much
-- information as we have available. This provides a type where we can summarize the
-- information available in a Unison file.
--
-- If the file typechecked then all the Ref Ids and types will be filled in, otherwise
-- they will be Nothing.
data FileSummary = FileSummary
  { dataDeclsBySymbol :: Map Symbol (Reference.Id, DD.DataDeclaration Symbol Ann),
    dataDeclsByReference :: Map Reference.Id (Map Symbol (DD.DataDeclaration Symbol Ann)),
    effectDeclsBySymbol :: Map Symbol (Reference.Id, DD.EffectDeclaration Symbol Ann),
    effectDeclsByReference :: Map Reference.Id (Map Symbol (DD.EffectDeclaration Symbol Ann)),
    termsBySymbol :: Map Symbol (Ann, Maybe Reference.Id, Term Symbol Ann, Maybe (Type Symbol Ann)),
    termsByReference :: Map (Maybe Reference.Id) (Map Symbol (Ann, Term Symbol Ann, Maybe (Type Symbol Ann))),
    testWatchSummary :: [(Ann, Maybe Symbol, Maybe Reference.Id, Term Symbol Ann, Maybe (Type Symbol Ann))],
    exprWatchSummary :: [(Ann, Maybe Symbol, Maybe Reference.Id, Term Symbol Ann, Maybe (Type Symbol Ann))],
    fileNames :: Names
  }
  deriving stock (Show)

getCurrentPath :: Lsp Path.Absolute
getCurrentPath = asks currentPathCache >>= liftIO

getCodebaseCompletions :: Lsp CompletionTree
getCodebaseCompletions = asks completionsVar >>= readTVarIO

globalPPED :: Lsp PrettyPrintEnvDecl
globalPPED = asks ppedCache >>= liftIO

getNameSearch :: Lsp (NameSearch Sqlite.Transaction)
getNameSearch = asks nameSearchCache >>= liftIO

getParseNames :: Lsp Names
getParseNames = asks parseNamesCache >>= liftIO

data Config = Config
  { formattingWidth :: Int,
    rewriteNamesOnFormat :: Bool,
    -- 'Nothing' will load ALL available completions, which is slower, but may provide a better
    -- solution for some users.
    --
    -- 'Just n' will only fetch the first 'n' completions and will prompt the client to ask for
    -- more completions after more typing.
    maxCompletions :: Maybe Int
  }
  deriving stock (Show)

instance Aeson.FromJSON Config where
  parseJSON = Aeson.withObject "Config" \obj -> do
    maxCompletions <- obj Aeson..:! "maxCompletions" Aeson..!= maxCompletions defaultLSPConfig
    Debug.debugM Debug.LSP "Config" $ "maxCompletions: " <> show maxCompletions
    formattingWidth <- obj Aeson..:? "formattingWidth" Aeson..!= formattingWidth defaultLSPConfig
    rewriteNamesOnFormat <- obj Aeson..:? "rewriteNamesOnFormat" Aeson..!= rewriteNamesOnFormat defaultLSPConfig
    pure Config {..}

instance Aeson.ToJSON Config where
  toJSON (Config formattingWidth rewriteNamesOnFormat maxCompletions) =
    Aeson.object
      [ "formattingWidth" Aeson..= formattingWidth,
        "rewriteNamesOnFormat" Aeson..= rewriteNamesOnFormat,
        "maxCompletions" Aeson..= maxCompletions
      ]

defaultLSPConfig :: Config
defaultLSPConfig = Config {..}
  where
    formattingWidth = 80
    rewriteNamesOnFormat = True
    maxCompletions = Just 100

-- | Lift a backend computation into the Lsp monad.
lspBackend :: Backend.Backend IO a -> Lsp (Either Backend.BackendError a)
lspBackend = liftIO . runExceptT . flip runReaderT (Backend.BackendEnv False) . Backend.runBackend

sendNotification :: forall (m :: Method 'ServerToClient 'Notification). (TMessage m ~ TNotificationMessage m) => TNotificationMessage m -> Lsp ()
sendNotification notif = do
  sendServerMessage <- asks (resSendMessage . lspContext)
  liftIO $ sendServerMessage $ fromServerNot notif -- (notif ^. method) notif

data RangedCodeAction = RangedCodeAction
  { -- All the ranges the code action applies
    _codeActionRanges :: [Range],
    _codeAction :: CodeAction
  }
  deriving stock (Eq, Show)

instance HasCodeAction RangedCodeAction CodeAction where
  codeAction = lens (\RangedCodeAction {_codeAction} -> _codeAction) (\rca ca -> RangedCodeAction {_codeActionRanges = _codeActionRanges rca, _codeAction = ca})

rangedCodeAction :: Text -> [Diagnostic] -> [Range] -> RangedCodeAction
rangedCodeAction title diags ranges =
  RangedCodeAction ranges $
    CodeAction
      { _title = title,
        _kind = Nothing,
        _diagnostics = Just diags,
        _isPreferred = Nothing,
        _disabled = Nothing,
        _edit = Nothing,
        _command = Nothing,
        _data_ = Nothing
      }

-- | Provided ranges must not intersect.
includeEdits :: Uri -> Text -> [Range] -> RangedCodeAction -> RangedCodeAction
includeEdits uri replacement ranges rca =
  let edits = do
        r <- ranges
        pure $ TextEdit r replacement
      workspaceEdit =
        WorkspaceEdit
          { _changes = Just $ Map.singleton uri edits,
            _documentChanges = Nothing,
            _changeAnnotations = Nothing
          }
   in rca & codeAction . edit ?~ workspaceEdit

getConfig :: Lsp Config
getConfig = LSP.getConfig

setConfig :: Config -> Lsp ()
setConfig = LSP.setConfig
