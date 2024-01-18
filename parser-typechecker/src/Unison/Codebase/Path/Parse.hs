{-# LANGUAGE OverloadedLists #-}

module Unison.Codebase.Path.Parse
  ( parsePath',
    parseSplit',
    parseHQSplit,
    parseHQSplit',
    parseShortHashOrHQSplit',
  )
where

import Control.Lens (over, _1)
import Control.Lens qualified as Lens
import Data.List.Extra (stripPrefix)
import Data.Text qualified as Text
import Text.Megaparsec qualified as P
import Unison.Codebase.Path
import Unison.HashQualified' qualified as HQ'
import Unison.NameSegment (NameSegment (NameSegment))
import Unison.NameSegment qualified as NameSegment
import Unison.Prelude hiding (empty, toList)
import Unison.ShortHash (ShortHash)
import Unison.ShortHash qualified as SH
import Unison.Syntax.Lexer qualified as Lexer
import Unison.Syntax.Name qualified as Name
import Unison.Syntax.NameSegment qualified as NameSegment (renderParseErr)

parsePath' :: String -> Either Text Path'
parsePath' = \case
  "." -> Right absoluteEmpty'
  path -> unsplit' <$> parseSplit' path

-- implementation detail of parsePath' and parseSplit'
-- foo.bar.baz.34 becomes `Right (foo.bar.baz, "34")
-- foo.bar.baz    becomes `Right (foo.bar, "baz")
-- baz            becomes `Right (, "baz")
-- foo.bar.baz#a8fj becomes `Left`; we don't hash-qualify paths.
-- TODO: Get rid of this thing.
parsePathImpl' :: String -> Either String (Path', String)
parsePathImpl' p = case p of
  "." -> Right (Path' . Left $ absoluteEmpty, "")
  '.' : p -> over _1 (Path' . Left . Absolute . fromList) <$> segs p
  p -> over _1 (Path' . Right . Relative . fromList) <$> segs p
  where
    go f p = case f p of
      Right (a, "") -> case Lens.unsnoc (NameSegment.segments' $ Text.pack a) of
        Nothing -> Left "empty path"
        Just (segs, last) -> Right (NameSegment <$> segs, Text.unpack last)
      Right (segs, '.' : rem) ->
        let segs' = NameSegment.segments' (Text.pack segs)
         in Right (NameSegment <$> segs', rem)
      Right (segs, rem) ->
        Left $ "extra characters after " <> segs <> ": " <> show rem
      Left e -> Left e
    segs p = go parseSegment p

parseSegment :: String -> Either String (String, String)
parseSegment s =
  first show
    . (Lexer.wordyId <> Lexer.symbolyId)
    <> unit'
    <> const (Left ("I expected an identifier but found " <> s))
    $ s

wordyNameSegment, definitionNameSegment :: String -> Either String NameSegment
wordyNameSegment s = case Lexer.wordyId0 s of
  Left e -> Left (show e)
  Right (a, "") -> Right (NameSegment (Text.pack a))
  Right (a, rem) ->
    Left $ "trailing characters after " <> show a <> ": " <> show rem

-- Parse a name segment like "()"
unit' :: String -> Either String (String, String)
unit' s = case stripPrefix "()" s of
  Nothing -> Left $ "Expected () but found: " <> s
  Just rem -> Right ("()", rem)

unit :: String -> Either String NameSegment
unit s = case unit' s of
  Right (_, "") -> Right $ NameSegment "()"
  Right (_, rem) -> Left $ "trailing characters after (): " <> show rem
  Left _ -> Left $ "I don't know how to parse " <> s

definitionNameSegment s = wordyNameSegment s <> symbolyNameSegment s <> unit s
  where
    symbolyNameSegment s = case Lexer.symbolyId0 s of
      Left e -> Left (show e)
      Right (a, "") -> Right (NameSegment (Text.pack a))
      Right (a, rem) ->
        Left $ "trailing characters after " <> show a <> ": " <> show rem

parseSplit' :: String -> Either Text Split'
parseSplit' path = do
  case P.runParser (Name.nameP <* P.eof) "" path of
    Left err -> Left (NameSegment.renderParseErr err)
    Right name -> Right (splitFromName' name)

parseShortHashOrHQSplit' :: String -> Either String (Either ShortHash HQSplit')
parseShortHashOrHQSplit' s =
  case Text.breakOn "#" $ Text.pack s of
    ("", "") -> error $ "encountered empty string parsing '" <> s <> "'"
    (n, "") -> do
      (p, rem) <- parsePathImpl' (Text.unpack n)
      seg <- definitionNameSegment rem
      pure $ Right (p, HQ'.NameOnly seg)
    ("", sh) -> do
      sh <- maybeToRight (shError s) . SH.fromText $ sh
      pure $ Left sh
    (n, sh) -> do
      (p, rem) <- parsePathImpl' (Text.unpack n)
      seg <- definitionNameSegment rem
      hq <-
        maybeToRight (shError s)
          . fmap (\sh -> (p, HQ'.HashQualified seg sh))
          . SH.fromText
          $ sh
      pure $ Right hq
  where
    shError s = "couldn't parse shorthash from " <> s

parseHQSplit :: String -> Either String HQSplit
parseHQSplit s = case parseHQSplit' s of
  Right (Path' (Right (Relative p)), hqseg) -> Right (p, hqseg)
  Right (Path' Left {}, _) ->
    Left $ "Sorry, you can't use an absolute name like " <> s <> " here."
  Left e -> Left e

parseHQSplit' :: String -> Either String HQSplit'
parseHQSplit' s = case Text.breakOn "#" $ Text.pack s of
  ("", "") -> error $ "encountered empty string parsing '" <> s <> "'"
  ("", _) -> Left "Sorry, you can't use a hash-only reference here."
  (n, "") -> do
    (p, rem) <- parsePath n
    seg <- definitionNameSegment rem
    pure (p, HQ'.NameOnly seg)
  (n, sh) -> do
    (p, rem) <- parsePath n
    seg <- definitionNameSegment rem
    maybeToRight (shError s)
      . fmap (\sh -> (p, HQ'.HashQualified seg sh))
      . SH.fromText
      $ sh
  where
    shError s = "couldn't parse shorthash from " <> s
    parsePath n = do
      x <- parsePathImpl' $ Text.unpack n
      pure $ case x of
        (Path' (Left e), "") | e == absoluteEmpty -> (relativeEmpty', ".")
        x -> x
