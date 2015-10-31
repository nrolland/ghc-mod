-- ghc-mod: Making Haskell development *more* fun
-- Copyright (C) 2015  Daniel Gröber <dxld ÄT darkboxed DOT org>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Language.Haskell.GhcMod.Logging (
    module Language.Haskell.GhcMod.Logging
  , module Language.Haskell.GhcMod.Pretty
  , GmLogLevel(..)
  , module Text.PrettyPrint
  , module Data.Monoid
  ) where

import Control.Applicative hiding (empty)
import Control.Monad
import Control.Monad.Trans.Class
import Data.List
import Data.Char
import Data.Monoid
import Data.Maybe
import System.IO
import System.FilePath
import Text.PrettyPrint hiding (style, (<>))
import Prelude

import Language.Haskell.GhcMod.Monad.Types
import Language.Haskell.GhcMod.Types
import Language.Haskell.GhcMod.Pretty
import Language.Haskell.GhcMod.Output

gmSetLogLevel :: GmLog m => GmLogLevel -> m ()
gmSetLogLevel level =
    gmlJournal $ GhcModLog (Just level) (Last Nothing) []

gmSetDumpLevel :: GmLog m => Bool -> m ()
gmSetDumpLevel level =
    gmlJournal $ GhcModLog Nothing (Last (Just level)) []


increaseLogLevel :: GmLogLevel -> GmLogLevel
increaseLogLevel l | l == maxBound = l
increaseLogLevel l = succ l

decreaseLogLevel :: GmLogLevel -> GmLogLevel
decreaseLogLevel l | l == minBound = l
decreaseLogLevel l = pred l

-- |
-- >>> Just GmDebug <= Nothing
-- False
-- >>> Just GmException <= Just GmDebug
-- True
-- >>> Just GmDebug <= Just GmException
-- False
gmLog :: (MonadIO m, GmLog m, GmOut m) => GmLogLevel -> String -> Doc -> m ()
gmLog level loc' doc = do
  GhcModLog { gmLogLevel = Just level' } <- gmlHistory

  let loc | loc' == "" = empty
          | otherwise = text loc' <+>: empty
      msgDoc = gmLogLevelDoc level <+>: sep [loc, doc]
      msg = dropWhileEnd isSpace $ gmRenderDoc msgDoc

  when (level <= level') $ gmErrStrLn msg

  gmlJournal (GhcModLog Nothing (Last Nothing) [(level, loc', msgDoc)])

-- | Appends a collection of logs to the logging environment, with effects
-- | if their log level specifies it should
gmLog' :: (MonadIO m, GmLog m, GmOut m) => GhcModLog -> m ()
gmLog' newLog@ GhcModLog { gmLogMessages } = do
  GhcModLog { gmLogLevel = Just level' } <- gmlHistory
  mapM_ (\(level, _, msgDoc) ->  when (level <= level') $ gmErrStrLn (docToString msgDoc)) gmLogMessages
  -- instance Monoid GhcModLog takes the second debug level for some reason, so we need to force this to nothing
  gmlJournal (GhcModLog Nothing (Last Nothing)  gmLogMessages)
  where
    docToString msgDoc = dropWhileEnd isSpace $ gmRenderDoc msgDoc

gmVomit :: (MonadIO m, GmLog m, GmOut m, GmEnv m) => String -> Doc -> String -> m ()
gmVomit filename doc content = do
  gmLog GmVomit "" $ doc <+>: text content

  GhcModLog { gmLogVomitDump = Last mdump }
      <- gmlHistory

  dir <- cradleTempDir `liftM` cradle
  when (fromMaybe False mdump) $
       liftIO $ writeFile (dir </> filename) content


newtype LogDiscardT m a = LogDiscardT { runLogDiscard :: m a }
    deriving (Functor, Applicative, Monad)

instance MonadTrans LogDiscardT where
    lift = LogDiscardT

instance Monad m => GmLog (LogDiscardT m) where
    gmlJournal = const $ return ()
    gmlHistory = return mempty
    gmlClear = return ()
