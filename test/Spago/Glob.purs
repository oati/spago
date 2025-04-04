module Test.Spago.Glob where

import Test.Prelude

import Data.Array as Array
import Data.Foldable (intercalate)
import Effect.Aff as Aff
import Spago.FS as FS
import Spago.Glob as Glob
import Spago.Path as Path
import Test.Spec (Spec)
import Test.Spec as Spec
import Test.Spec.Assertions as Assert

globTmpDir :: (RootPath -> Aff Unit) -> Aff Unit
globTmpDir m = Aff.bracket make cleanup m
  where
  touch name base = FS.writeTextFile (base </> name) ""
  dir name contents base = do
    FS.mkdirp $ base </> name
    for_ contents \f -> f =<< Path.mkRoot (base </> name)
  cleanup _ = pure unit
  make = do
    base <- Path.mkRoot =<< mkTemp' (Just "spago-test-")
    dir
      ".git"
      [ dir "fruits" [ touch "apple" ] ]
      base
    dir
      "fruits"
      [ dir "left"
          [ touch "apple"
          ]
      , dir "right"
          [ touch "apple"
          ]
      ]
      base
    dir
      "src"
      [ dir "fruits" [ touch "apple" ]
      , dir "sports" [ touch "baseball" ]
      ]
      base
    pure base

spec :: Spec Unit
spec = Spec.around globTmpDir do
  let glob root includePatterns = Glob.gitignoringGlob { root, includePatterns, ignorePatterns: [] }
  Spec.describe "glob" do
    Spec.describe "glob behavior" do
      Spec.it "'**/..' matches 0 or more directories" \p -> do
        aRoot <- Path.mkRoot (p </> "fruits" </> "left")
        bRoot <- Path.mkRoot (p </> "fruits")
        a <- glob aRoot [ "**/apple" ]
        b <- glob bRoot [ "**/apple" ]
        sortedPaths a `Assert.shouldEqual` [ "apple" ]
        sortedPaths b `Assert.shouldEqual` [ "left/apple", "right/apple" ]

      Spec.it "'../**/..' matches 0 or more directories" \p -> do
        a <- glob p [ "fruits/**/apple" ]
        sortedPaths a `Assert.shouldEqual` [ "fruits/left/apple", "fruits/right/apple" ]

      Spec.it "'../**' matches 0 or more directories" \p -> do
        a <- glob p [ "fruits/left/**" ]
        sortedPaths a `Assert.shouldEqual` [ "fruits/left", "fruits/left/apple" ]

    Spec.describe "gitignoringGlob" do
      Spec.it "when no .gitignore, yields all matches" \p -> do
        a <- glob p [ "**/apple" ]
        sortedPaths a `Assert.shouldEqual` [ "fruits/left/apple", "fruits/right/apple", "src/fruits/apple" ]

      Spec.it "respects a .gitignore pattern that doesn't conflict with search" \p -> do
        FS.writeTextFile (p </> ".gitignore") "fruits/right"
        a <- glob p [ "fruits/**/apple" ]
        sortedPaths a `Assert.shouldEqual` [ "fruits/left/apple" ]

      Spec.it "respects some .gitignore patterns" \p -> do
        FS.writeTextFile (p </> ".gitignore") "fruits\nfruits/right"
        a <- glob p [ "fruits/**/apple" ]
        sortedPaths a `Assert.shouldEqual` [ "fruits/left/apple" ]

      Spec.it "respects a negated .gitignore pattern" \p -> do
        FS.writeTextFile (p </> ".gitignore") "!/fruits/left/apple\n/fruits/**/apple"
        a <- glob p [ "**/apple" ]
        sortedPaths a `Assert.shouldEqual` [ "fruits/left/apple", "src/fruits/apple" ]

      for_ [ "/fruits", "fruits", "fruits/", "**/fruits", "fruits/**", "**/fruits/**" ] \gitignore -> do
        Spec.it
          ("does not respect a .gitignore pattern that conflicts with search: " <> gitignore)
          \p -> do
            FS.writeTextFile (p </> ".gitignore") gitignore
            a <- glob p [ "fruits/**/apple" ]
            sortedPaths a `Assert.shouldEqual` [ "fruits/left/apple", "fruits/right/apple" ]

      Spec.it "is stacksafe" \p -> do
        let
          chars = [ "a", "b", "c", "d", "e", "f", "g", "h" ]
          -- 4000-line gitignore
          words = [ \a b c d -> a <> b <> c <> d ] <*> chars <*> chars <*> chars <*> chars
          hugeGitignore = intercalate "\n" words
        -- Write it in a few places
        FS.writeTextFile (p </> ".gitignore") hugeGitignore
        FS.writeTextFile (p </> "fruits" </> ".gitignore") hugeGitignore
        FS.writeTextFile (p </> "fruits" </> "left" </> ".gitignore") hugeGitignore
        FS.writeTextFile (p </> "fruits" </> "right" </> ".gitignore") hugeGitignore
        a <- glob p [ "fruits/**/apple" ]
        sortedPaths a `Assert.shouldEqual` [ "fruits/left/apple", "fruits/right/apple" ]

      Spec.it "does respect .gitignore even though it might conflict with a search path without base" $ \p -> do
        FS.writeTextFile (p </> ".gitignore") "fruits"
        a <- glob p [ "**/apple" ]
        sortedPaths a `Assert.shouldEqual` []

  where
  sortedPaths = map (Path.localPart <<< Path.withForwardSlashes) >>> Array.sort
