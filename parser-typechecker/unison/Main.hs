{-# LANGUAGE OverloadedStrings #-}

module Main where

import           Control.Monad                    (when)
import qualified Data.Set                         as Set
import           Safe                             (headMay)
import           System.Environment               (getArgs)
import qualified Unison.Codebase                  as Codebase
import qualified Unison.Codebase.FileCodebase     as FileCodebase
import           Unison.Codebase.Runtime.JVM      (javaRuntime)
import qualified Unison.Codebase.Serialization    as S
import           Unison.Codebase.Serialization.V0 (formatSymbol, getSymbol)
import qualified Unison.Codebase.CommandLine      as CommandLine
import           Unison.Parser                    (Ann (External))
import qualified Unison.Runtime.Rt1               as Rt1

main :: IO ()
main = do
  args0 <- getArgs
  let javaRtFlag = "-java"
      useJavaRuntime = javaRtFlag `elem` args0
      args = Set.toList $ Set.delete javaRtFlag (Set.fromList args0)
  -- hSetBuffering stdout NoBuffering -- cool
  let codebasePath  = ".unison"
      initialBranchName = "master"
      scratchFilePath   = "."
      theCodebase =
        FileCodebase.codebase1 External formatSymbol formatAnn codebasePath
      launch = CommandLine.main
        scratchFilePath
        initialBranchName
        (headMay args)
        (if useJavaRuntime
         then javaRuntime getSymbol 42441
         else pure Rt1.runtime)
        theCodebase
  exists <- FileCodebase.exists codebasePath
  when (not exists) $ do
    putStrLn $ "☝️  No codebase exists here so I'm initializing one in: " <> codebasePath
    FileCodebase.initialize codebasePath
    Codebase.initialize theCodebase
  launch

formatAnn :: S.Format Ann
formatAnn = S.Format (pure External) (\_ -> pure ())
