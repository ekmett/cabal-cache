{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TypeApplications      #-}

module HaskellWorks.Ci.Assist.Core
  ( PackageInfo(..)
  , getPackages
  , relativePaths
  ) where

import Control.DeepSeq
import Control.Lens              hiding ((<.>))
import Control.Monad
import Data.Aeson
import Data.Bool
import Data.Generics.Product.Any
import Data.Maybe
import Data.Semigroup            ((<>))
import Data.Text                 (Text)
import GHC.Generics
import System.FilePath           ((<.>), (</>))

import qualified Data.List                    as List
import qualified Data.Text                    as T
import qualified HaskellWorks.Ci.Assist.Text  as T
import qualified HaskellWorks.Ci.Assist.Types as Z
import qualified System.Directory             as IO
import qualified System.IO                    as IO

type CompilerId = Text
type PackageId  = Text
type PackageDir = FilePath
type ConfPath   = FilePath
type Library    = FilePath

data PackageInfo = PackageInfo
  { compilerId :: CompilerId
  , packageId  :: PackageId
  , packageDir :: PackageDir
  , confPath   :: Maybe ConfPath
  , libs       :: [Library]
  } deriving (Show, Eq, Generic, NFData)

relativePaths :: PackageInfo -> [FilePath]
relativePaths pInfo = mempty
  <>  maybeToList (pInfo ^. the @"confPath")
  <>  [packageDir pInfo]
  <>  (pInfo ^. the @"libs")

getPackages :: FilePath -> Z.PlanJson -> IO [PackageInfo]
getPackages basePath planJson = forM packages (mkPackageInfo basePath compilerId)
  where compilerId :: Text
        compilerId = planJson ^. the @"compilerId"
        packages :: [Z.Package]
        packages = planJson ^.. the @"installPlan" . each . filtered predicate
        predicate :: Z.Package -> Bool
        predicate package = package ^. the @"packageType" /= "pre-existing" && package ^. the @"style" == Just "global"

mkPackageInfo :: FilePath -> CompilerId -> Z.Package -> IO PackageInfo
mkPackageInfo basePath cid pkg = do
  let pid               = pkg ^. the @"id"
  let compilerPath      = basePath </> T.unpack cid
  let relativeConfPath  = T.unpack cid </> "package.db" </> T.unpack pid <.> ".conf"
  let absoluteConfPath  = basePath </> relativeConfPath
  let libPath           = compilerPath </> "lib"
  let relativeLibPath   = T.unpack cid </> "lib"
  let libPrefix         = "libHS" <> pid
  absoluteConfPathExists <- IO.doesFileExist absoluteConfPath
  libPathExists <- IO.doesDirectoryExist libPath
  libFiles <- getLibFiles relativeLibPath libPath libPrefix
  return PackageInfo
    { compilerId  = cid
    , packageId   = pid
    , packageDir  = T.unpack cid </> T.unpack pid
    , confPath    = bool Nothing (Just relativeConfPath) absoluteConfPathExists
    , libs        = libFiles
    }

getLibFiles :: FilePath -> FilePath -> Text -> IO [Library]
getLibFiles relativeLibPath libPath libPrefix =
  fmap (relativeLibPath </>) . mfilter (List.isPrefixOf (T.unpack libPrefix)) <$> IO.listDirectory libPath
