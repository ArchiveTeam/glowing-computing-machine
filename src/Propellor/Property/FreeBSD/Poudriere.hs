-- | Maintainer: 2016 Evan Cofsky <evan@theunixman.com>
--
-- FreeBSD Poudriere properties

{-# Language GeneralizedNewtypeDeriving #-}

module Propellor.Property.FreeBSD.Poudriere where

import Propellor.Base
import Propellor.Types.Info
import Data.List
import Data.String (IsString(..))

import qualified Propellor.Property.FreeBSD.Pkg as Pkg
import qualified Propellor.Property.ZFS as ZFS
import qualified Propellor.Property.File as File

poudriereConfigPath :: FilePath
poudriereConfigPath = "/usr/local/etc/poudriere.conf"

newtype PoudriereConfigured = PoudriereConfigured String
	deriving (Typeable, Monoid, Show)
instance IsInfo PoudriereConfigured where
	propagateInfo _ = False

poudriereConfigured :: PoudriereConfigured -> Bool
poudriereConfigured (PoudriereConfigured _) = True

setConfigured :: Property HasInfo
setConfigured = pureInfoProperty "Poudriere Configured" (PoudriereConfigured "")

poudriere :: Poudriere -> Property HasInfo
poudriere conf@(Poudriere _ _ _ _ _ _ zfs) = prop
	`requires` Pkg.installed "poudriere"
	`before` setConfigured
  where
	confProp = File.containsLines poudriereConfigPath (toLines conf)
	setZfs (PoudriereZFS z p) = ZFS.zfsSetProperties z p `describe` "Configuring Poudriere with ZFS"
	prop :: CombinedType (Property NoInfo) (Property NoInfo)
	prop
		| isJust zfs = ((setZfs $ fromJust zfs) `before` confProp)
		| otherwise = propertyList "Configuring Poudriere without ZFS" [confProp]

poudriereCommand :: String -> [String] -> (String, [String])
poudriereCommand cmd args = ("poudriere", cmd:args)

runPoudriere :: String -> [String] -> IO [String]
runPoudriere cmd args =
	let
		(p, a) = poudriereCommand cmd args
	in
		lines <$> readProcess p a

listJails :: IO [String]
listJails = mapMaybe (headMaybe . take 1 . words)
	<$> runPoudriere "jail" ["-l", "-q"]

jailExists :: Jail -> IO Bool
jailExists (Jail name _ _) = isInfixOf [name] <$> listJails

jail :: Jail -> Property NoInfo
jail j@(Jail name version arch) =
	let
		chk = do
			c <- poudriereConfigured <$> askInfo
			nx <- liftIO $ not <$> jailExists j
			return $ c && nx

		(cmd, args) = poudriereCommand "jail"  ["-c", "-j", name, "-a", show arch, "-v", show version]
		createJail = cmdProperty cmd args
	in
		check chk createJail
		`describe` unwords ["Create poudriere jail", name]

data JailInfo = JailInfo String

data Poudriere = Poudriere
	{ _resolvConf :: String
	, _freebsdHost :: String
	, _baseFs :: String
	, _usePortLint :: Bool
	, _distFilesCache :: FilePath
	, _svnHost :: String
	, _zfs :: Maybe PoudriereZFS
	}

defaultConfig :: Poudriere
defaultConfig = Poudriere
	"/etc/resolv.conf"
	"ftp://ftp5.us.FreeBSD.org"
	"/usr/local/poudriere"
	True
	"/usr/ports/distfiles"
	"svn.freebsd.org"
	Nothing

data PoudriereZFS = PoudriereZFS ZFS.ZFS ZFS.ZFSProperties

data Jail = Jail String FBSDVersion PoudriereArch

data PoudriereArch = I386 | AMD64 deriving (Eq)
instance Show PoudriereArch where
	show I386 = "i386"
	show AMD64 = "amd64"

instance IsString PoudriereArch where
	fromString "i386" = I386
	fromString "amd64" = AMD64
	fromString _ = error "Not a valid Poudriere architecture."

yesNoProp :: Bool -> String
yesNoProp b = if b then "yes" else "no"

instance ToShellConfigLines Poudriere where
	toAssoc c = map (\(k, f) -> (k, f c))
		[ ("RESOLV_CONF", _resolvConf)
		, ("FREEBSD_HOST", _freebsdHost)
		, ("BASEFS", _baseFs)
		, ("USE_PORTLINT", yesNoProp . _usePortLint)
		, ("DISTFILES_CACHE", _distFilesCache)
		, ("SVN_HOST", _svnHost)
		] ++ maybe [ ("NO_ZFS", "yes") ] toAssoc (_zfs c)

instance ToShellConfigLines PoudriereZFS where
	toAssoc (PoudriereZFS (ZFS.ZFS (ZFS.ZPool pool) dataset) _) =
		[ ("NO_ZFS", "no")
		, ("ZPOOL", pool)
		, ("ZROOTFS", show dataset)
		]

type ConfigLine = String
type ConfigFile = [ConfigLine]

class ToShellConfigLines a where
	toAssoc :: a -> [(String, String)]

	toLines :: a -> [ConfigLine]
	toLines c = map (\(k, v) -> intercalate "=" [k, v]) (toAssoc c)

confFile :: FilePath
confFile = "/usr/local/etc/poudriere.conf"
