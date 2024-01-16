{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE QuasiQuotes #-}

module Unison.LSP.CodeAction where

import Control.Lens hiding (List)
import Data.IntervalMap qualified as IM
import Language.LSP.Protocol.Lens
import Language.LSP.Protocol.Message qualified as Msg
import Language.LSP.Protocol.Types
import Unison.Debug qualified as Debug
import Unison.LSP.Conversions
import Unison.LSP.FileAnalysis
import Unison.LSP.Types
import Unison.Prelude

-- | Computes code actions for a document.
codeActionHandler :: Msg.TRequestMessage 'Msg.Method_TextDocumentCodeAction -> (Either Msg.ResponseError (Msg.MessageResult 'Msg.Method_TextDocumentCodeAction) -> Lsp ()) -> Lsp ()
codeActionHandler m respond =
  respond . maybe (Right $ InL mempty) (Right . InL . fmap InR) =<< runMaybeT do
    FileAnalysis {codeActions} <- getFileAnalysis (m ^. params . textDocument . uri)
    let r = m ^. params . range
    let relevantActions = IM.intersecting codeActions (rangeToInterval r)
    Debug.debugM Debug.LSP "All CodeActions" (codeActions)
    Debug.debugM Debug.LSP "Relevant actions" (r, relevantActions)
    pure $ fold relevantActions
