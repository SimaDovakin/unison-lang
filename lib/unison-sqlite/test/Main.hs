module Main (main) where

import EasyTest
import System.IO.CodePage (withCP65001)
import Unison.Sqlite.Internal (internalParseSql)

main :: IO ()
main =
  withCP65001 (run (scope "sqlite" test))

test :: Test ()
test =
  tests
    [ scope "internalParseSql" . tests $
        [ do
            let sql = "   foo :a\n   'foo''foo' @b\n   \"foo\"\"foo\" $c\n   `foo``foo`   \n[foo] :d  "
            let expected = Right ("foo ? 'foo''foo' ? \"foo\"\"foo\" ? `foo``foo` [foo] ?", ["a", "b", "c", "d"])
            let actual = internalParseSql sql
            expectEqual expected actual,
          scope "strips line comments" do
            let sql = "foo -- bar \n baz"
            let expected = Right ("foo baz", [])
            let actual = internalParseSql sql
            expectEqual expected actual,
          scope "strips block comments" do
            let sql = "foo /* bar baz \n */ qux"
            let expected = Right ("foo qux", [])
            let actual = internalParseSql sql
            expectEqual expected actual
        ]
    ]