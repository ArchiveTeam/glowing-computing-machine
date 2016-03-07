-- | Maintainer: 2016 Evan Cofsky <evan@theunixman.com>
-- 
-- FreeBSD pkgng properties

{-# Language ScopedTypeVariables, GeneralizedNewtypeDeriving #-}

module Propellor.Property.FreeBSD.Pkg where

import Propellor.Base
import Propellor.Types.Info

noninteractiveEnv :: [([Char], [Char])]
noninteractiveEnv = [("ASSUME_ALWAYS_YES", "yes")]

pkgCommand :: String -> [String] -> (String, [String])
pkgCommand cmd args = ("pkg", (cmd:args))

runPkg :: String -> [String] -> IO [String]
runPkg cmd args =
	let
		(p, a) = pkgCommand cmd args
	in
		lines <$> readProcess p a

pkgCmdProperty :: String -> [String] -> UncheckedProperty NoInfo
pkgCmdProperty cmd args =
	let
		(p, a) = pkgCommand cmd args
	in
		cmdPropertyEnv p a noninteractiveEnv

pkgCmd :: String -> [String] -> IO [String]
pkgCmd cmd args =
	let
		(p, a) = pkgCommand cmd args
	in
		lines <$> readProcessEnv p a (Just noninteractiveEnv)

newtype PkgUpdate = PkgUpdate String
	deriving (Typeable, Monoid, Show)
instance IsInfo PkgUpdate where
	propagateInfo _ = False

pkgUpdated :: PkgUpdate -> Bool
pkgUpdated (PkgUpdate _) = True

update :: Property HasInfo
update =
	let
		upd = pkgCmd "update" []
		go = ifM (pkgUpdated <$> askInfo) ((noChange), (liftIO upd >> return MadeChange))
	in
		infoProperty "pkg update has run" go (addInfo mempty (PkgUpdate "")) []

newtype PkgUpgrade = PkgUpgrade String
	deriving (Typeable, Monoid, Show)
instance IsInfo PkgUpgrade where
	propagateInfo _ = False

pkgUpgraded :: PkgUpgrade -> Bool
pkgUpgraded (PkgUpgrade _) = True

upgrade :: Property HasInfo
upgrade =
	let
		upd = pkgCmd "upgrade" []
		go = ifM (pkgUpgraded <$> askInfo) ((noChange), (liftIO upd >> return MadeChange))
	in
		infoProperty "pkg upgrade has run" go (addInfo mempty (PkgUpgrade "")) [] `requires` update

type Package = String

installed :: Package -> Property NoInfo
installed pkg = check (isInstallable pkg) $ pkgCmdProperty "install" [pkg]

isInstallable :: Package -> IO Bool
isInstallable p = (not <$> isInstalled p) <&&> exists p

isInstalled :: Package -> IO Bool
isInstalled p = (runPkg "info" [p] >> return True)
	`catchIO` (\_ -> return False)

exists :: Package -> IO Bool
exists p = (runPkg "search" ["--search", "name", "--exact", p] >> return True)
	`catchIO` (\_ -> return False)
