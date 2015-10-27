{-# LANGUAGE DeriveDataTypeable #-}

module Propellor.Property.Ssh (
	installed,
	restarted,
	PubKeyText,
	SshKeyType(..),
	-- * Daemon configuration
	sshdConfig,
	ConfigKeyword,
	setSshdConfigBool,
	setSshdConfig,
	RootLogin(..),
	permitRootLogin,
	passwordAuthentication,
	noPasswords,
	listenPort,
	-- * Host keys
	randomHostKeys,
	hostKeys,
	hostKey,
	hostPubKey,
	getHostPubKey,
	-- * User keys and configuration
	userKeys,
	userKeyAt,
	knownHost,
	unknownHost,
	authorizedKeysFrom,
	unauthorizedKeysFrom,
	authorizedKeys,
	authorizedKey,
	unauthorizedKey,
	hasAuthorizedKeys,
	getUserPubKeys,
) where

import Propellor.Base
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Service as Service
import qualified Propellor.Property.Apt as Apt
import Propellor.Property.User
import Propellor.Types.Info
import Utility.FileMode

import System.PosixCompat
import qualified Data.Map as M
import qualified Data.Set as S
import Data.List

installed :: Property NoInfo
installed = Apt.installed ["ssh"]

restarted :: Property NoInfo
restarted = Service.restarted "ssh"

sshBool :: Bool -> String
sshBool True = "yes"
sshBool False = "no"

sshdConfig :: FilePath
sshdConfig = "/etc/ssh/sshd_config"

type ConfigKeyword = String

setSshdConfigBool :: ConfigKeyword -> Bool -> Property NoInfo
setSshdConfigBool setting allowed = setSshdConfig setting (sshBool allowed)

setSshdConfig :: ConfigKeyword -> String -> Property NoInfo
setSshdConfig setting val = File.fileProperty desc f sshdConfig
	`onChange` restarted
  where
	desc = unwords [ "ssh config:", setting, val ]
	cfgline = setting ++ " " ++ val
	wantedline s
		| s == cfgline = True
		| (setting ++ " ") `isPrefixOf` s = False
		| otherwise = True
	f ls 
		| cfgline `elem` ls = filter wantedline ls
		| otherwise = filter wantedline ls ++ [cfgline]

data RootLogin
	= RootLogin Bool  -- ^ allow or prevent root login
	| WithoutPassword -- ^ disable password authentication for root, while allowing other authentication methods
	| ForcedCommandsOnly -- ^ allow root login with public-key authentication, but only if a forced command has been specified for the public key

permitRootLogin :: RootLogin -> Property NoInfo
permitRootLogin (RootLogin b) = setSshdConfigBool "PermitRootLogin" b
permitRootLogin WithoutPassword = setSshdConfig "PermitRootLogin" "without-password"
permitRootLogin ForcedCommandsOnly = setSshdConfig "PermitRootLogin" "forced-commands-only"

passwordAuthentication :: Bool -> Property NoInfo
passwordAuthentication = setSshdConfigBool "PasswordAuthentication"

-- | Configure ssh to not allow password logins.
--
-- To prevent lock-out, this is done only once root's 
-- authorized_keys is in place.
noPasswords :: Property NoInfo
noPasswords = check (hasAuthorizedKeys (User "root")) $
	passwordAuthentication False

dotDir :: User -> IO FilePath
dotDir user = do
	h <- homedir user
	return $ h </> ".ssh"

dotFile :: FilePath -> User -> IO FilePath
dotFile f user = do
	d <- dotDir user
	return $ d </> f

-- | Makes the ssh server listen on a given port, in addition to any other
-- ports it is configured to listen on.
--
-- Revert to prevent it listening on a particular port.
listenPort :: Int -> RevertableProperty NoInfo
listenPort port = enable <!> disable
  where
	portline = "Port " ++ show port
	enable = sshdConfig `File.containsLine` portline
		`describe` ("ssh listening on " ++ portline)
		`onChange` restarted
	disable = sshdConfig `File.lacksLine` portline
		`describe` ("ssh not listening on " ++ portline)
		`onChange` restarted

hasAuthorizedKeys :: User -> IO Bool
hasAuthorizedKeys = go <=< dotFile "authorized_keys"
  where
	go f = not . null <$> catchDefaultIO "" (readFile f)

-- | Blows away existing host keys and make new ones.
-- Useful for systems installed from an image that might reuse host keys.
-- A flag file is used to only ever do this once.
randomHostKeys :: Property NoInfo
randomHostKeys = flagFile prop "/etc/ssh/.unique_host_keys"
	`onChange` restarted
  where
	prop = property "ssh random host keys" $ do
		void $ liftIO $ boolSystem "sh"
			[ Param "-c"
			, Param "rm -f /etc/ssh/ssh_host_*"
			]
		ensureProperty $ scriptProperty 
			[ "DPKG_MAINTSCRIPT_NAME=postinst DPKG_MAINTSCRIPT_PACKAGE=openssh-server /var/lib/dpkg/info/openssh-server.postinst configure" ]

-- | The text of a ssh public key, for example, "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB3BJ2GqZiTR2LEoDXyYFgh/BduWefjdKXAsAtzS9zeI"
type PubKeyText = String

-- | Installs the specified list of ssh host keys.
--
-- The corresponding private keys come from the privdata.
--
-- Any host keys that are not in the list are removed from the host.
hostKeys :: IsContext c => c -> [(SshKeyType, PubKeyText)] -> Property HasInfo
hostKeys ctx l = propertyList desc $ catMaybes $
	map (\(t, pub) -> Just $ hostKey ctx t pub) l ++ [cleanup]
  where
	desc = "ssh host keys configured " ++ typelist (map fst l)
	typelist tl = "(" ++ unwords (map fromKeyType tl) ++ ")"
	alltypes = [minBound..maxBound]
	staletypes = let have = map fst l in filter (`notElem` have) alltypes
	removestale b = map (File.notPresent . flip keyFile b) staletypes
	cleanup
		| null staletypes || null l = Nothing
		| otherwise = Just $ toProp $
			property ("any other ssh host keys removed " ++ typelist staletypes) $
				ensureProperty $
					combineProperties desc (removestale True ++ removestale False)
					`onChange` restarted

-- | Installs a single ssh host key of a particular type.
--
-- The public key is provided to this function;
-- the private key comes from the privdata; 
hostKey :: IsContext c => c -> SshKeyType -> PubKeyText -> Property HasInfo
hostKey context keytype pub = combineProperties desc
	[ hostPubKey keytype pub
	, toProp $ property desc $ install File.hasContent True (lines pub)
	, withPrivData (keysrc "" (SshPrivKey keytype "")) context $ \getkey ->
		property desc $ getkey $
			install File.hasContentProtected False . privDataLines
	]
	`onChange` restarted
  where
	desc = "ssh host key configured (" ++ fromKeyType keytype ++ ")"
	install writer ispub keylines = do
		let f = keyFile keytype ispub
		ensureProperty $ writer f (keyFileContent keylines)
	keysrc ext field = PrivDataSourceFileFromCommand field ("sshkey"++ext)
		("ssh-keygen -t " ++ sshKeyTypeParam keytype ++ " -f sshkey")

-- Make sure that there is a newline at the end;
-- ssh requires this for some types of private keys.
keyFileContent :: [String] -> [File.Line]
keyFileContent keylines = keylines ++ [""]

keyFile :: SshKeyType -> Bool -> FilePath
keyFile keytype ispub = "/etc/ssh/ssh_host_" ++ fromKeyType keytype ++ "_key" ++ ext
  where
	ext = if ispub then ".pub" else ""

-- | Indicates the host key that is used by a Host, but does not actually
-- configure the host to use it. Normally this does not need to be used;
-- use 'hostKey' instead.
hostPubKey :: SshKeyType -> PubKeyText -> Property HasInfo
hostPubKey t = pureInfoProperty "ssh pubkey known" . HostKeyInfo . M.singleton t

getHostPubKey :: Propellor (M.Map SshKeyType PubKeyText)
getHostPubKey = fromHostKeyInfo <$> askInfo

newtype HostKeyInfo = HostKeyInfo 
	{ fromHostKeyInfo :: M.Map SshKeyType PubKeyText }
	deriving (Eq, Ord, Typeable, Show)

instance IsInfo HostKeyInfo where
	propagateInfo _ = False

instance Monoid HostKeyInfo where
	mempty = HostKeyInfo M.empty
	mappend (HostKeyInfo old) (HostKeyInfo new) = 
		-- new first because union prefers values from the first
		-- parameter when there is a duplicate key
		HostKeyInfo (new `M.union` old)

userPubKeys :: User -> [(SshKeyType, PubKeyText)] -> Property HasInfo
userPubKeys u@(User n) l = pureInfoProperty ("ssh pubkey for " ++ n) $
	UserKeyInfo (M.singleton u (S.fromList l))

getUserPubKeys :: User -> Propellor [(SshKeyType, PubKeyText)]
getUserPubKeys u = maybe [] S.toList . M.lookup u . fromUserKeyInfo <$> askInfo

newtype UserKeyInfo = UserKeyInfo
	{ fromUserKeyInfo :: M.Map User (S.Set (SshKeyType, PubKeyText)) }
	deriving (Eq, Ord, Typeable, Show)

instance IsInfo UserKeyInfo where
	propagateInfo _ = False

instance Monoid UserKeyInfo where
	mempty = UserKeyInfo M.empty
	mappend (UserKeyInfo old) (UserKeyInfo new) = 
		UserKeyInfo (M.unionWith S.union old new)

-- | Sets up a user with the specified public keys, and the corresponding
-- private keys from the privdata.
-- 
-- The public keys are added to the Info, so other properties like
-- `authorizedKeysFrom` can use them.
userKeys :: IsContext c => User -> c -> [(SshKeyType, PubKeyText)] -> Property HasInfo
userKeys user@(User name) context ks = combineProperties desc $
	userPubKeys user ks : map (userKeyAt Nothing user context) ks
  where
	desc = unwords
		[ name
		, "has ssh key"
		, "(" ++ unwords (map (fromKeyType . fst) ks) ++ ")"
		]

-- | Sets up a user with the specified pubic key, and a private
-- key from the privdata.
--
-- A file can be specified to write the key to somewhere other than
-- the default locations. Allows a user to have multiple keys for
-- different roles.
userKeyAt :: IsContext c => Maybe FilePath -> User -> c -> (SshKeyType, PubKeyText) -> Property HasInfo
userKeyAt dest user@(User u) context (keytype, pubkeytext) =
	combineProperties desc $ props
		& pubkey
		& privkey
  where
	desc = unwords $ catMaybes
		[ Just u
		, Just "has ssh key"
		, dest
		, Just $ "(" ++ fromKeyType keytype ++ ")"
		]
	pubkey = property desc $ install File.hasContent ".pub" [pubkeytext]
	privkey = withPrivData (SshPrivKey keytype u) context $ \getkey -> 
		property desc $ getkey $
			install File.hasContentProtected "" . privDataLines
	install writer ext key = do
		f <- liftIO $ keyfile ext
		ensureProperty $ combineProperties desc
			[ writer f (keyFileContent key)
			, File.ownerGroup f user (userGroup user)
			, File.ownerGroup (takeDirectory f) user (userGroup user)
			]
	keyfile ext = case dest of
		Nothing -> do
			home <- homeDirectory <$> getUserEntryForName u
			return $ home </> ".ssh" </> "id_" ++ fromKeyType keytype ++ ext
		Just f -> return $ f ++ ext

fromKeyType :: SshKeyType -> String
fromKeyType SshRsa = "rsa"
fromKeyType SshDsa = "dsa"
fromKeyType SshEcdsa = "ecdsa"
fromKeyType SshEd25519 = "ed25519"

-- | Puts some host's ssh public key(s), as set using `hostPubKey`
-- or `hostKey` into the known_hosts file for a user.
knownHost :: [Host] -> HostName -> User -> Property NoInfo
knownHost hosts hn user@(User u) = property desc $
	go =<< knownHostLines hosts hn
  where
	desc = u ++ " knows ssh key for " ++ hn

	go [] = do
		warningMessage $ "no configured ssh host keys for " ++ hn
		return FailedChange
	go ls = do
		f <- liftIO $ dotFile "known_hosts" user
		modKnownHost user f $
			f `File.containsLines` ls
				`requires` File.dirExists (takeDirectory f)

-- | Reverts `knownHost`
unknownHost :: [Host] -> HostName -> User -> Property NoInfo
unknownHost hosts hn user@(User u) = property desc $
	go =<< knownHostLines hosts hn
  where
	desc = u ++ " does not know ssh key for " ++ hn

	go [] = return NoChange
	go ls = do
		f <- liftIO $ dotFile "known_hosts" user
		ifM (liftIO $ doesFileExist f)
			( modKnownHost user f $ f `File.lacksLines` ls
			, return NoChange
			)

knownHostLines :: [Host] -> HostName -> Propellor [File.Line]
knownHostLines hosts hn = keylines <$> fromHost hosts hn getHostPubKey
  where
	keylines (Just m) = map (\k -> hn ++ " " ++ k) (M.elems m)
	keylines Nothing = []

modKnownHost :: User -> FilePath -> Property NoInfo -> Propellor Result
modKnownHost user f p = ensureProperty $ p
	`requires` File.ownerGroup f user (userGroup user)
	`requires` File.ownerGroup (takeDirectory f) user (userGroup user)

-- | Ensures that a local user's authorized_keys contains lines allowing
-- logins from a remote user on the specified Host.
--
-- The ssh keys of the remote user can be set using `keysImported`
--
-- Any other lines in the authorized_keys file are preserved as-is.
authorizedKeysFrom :: User -> (User, Host) -> Property NoInfo
localuser@(User ln) `authorizedKeysFrom` (remoteuser@(User rn), remotehost) = 
	property desc (go =<< authorizedKeyLines remoteuser remotehost)
  where
	remote = rn ++ "@" ++ hostName remotehost
	desc = ln ++ " authorized_keys from " ++ remote

	go [] = do
		warningMessage $ "no configured ssh user keys for " ++ remote
		return FailedChange
	go ls = ensureProperty $ combineProperties desc $
		map (authorizedKey localuser) ls

-- | Reverts `authorizedKeysFrom`
unauthorizedKeysFrom :: User -> (User, Host) -> Property NoInfo
localuser@(User ln) `unauthorizedKeysFrom` (remoteuser@(User rn), remotehost) =
	property desc (go =<< authorizedKeyLines remoteuser remotehost)
  where
	remote = rn ++ "@" ++ hostName remotehost
	desc = ln ++ " unauthorized_keys from " ++ remote

	go [] = return NoChange
	go ls = ensureProperty $ combineProperties desc $
		map (unauthorizedKey localuser) ls
	
authorizedKeyLines :: User -> Host -> Propellor [File.Line]
authorizedKeyLines remoteuser remotehost = 
	map snd <$> fromHost' remotehost (getUserPubKeys remoteuser)

-- | Makes a user have authorized_keys from the PrivData
--
-- This removes any other lines from the file.
authorizedKeys :: IsContext c => User -> c -> Property HasInfo
authorizedKeys user@(User u) context = withPrivData (SshAuthorizedKeys u) context $ \get ->
	property desc $ get $ \v -> do
		f <- liftIO $ dotFile "authorized_keys" user
		ensureProperty $ combineProperties desc
			[ File.hasContentProtected f (keyFileContent (privDataLines v))
			, File.ownerGroup f user (userGroup user)
			, File.ownerGroup (takeDirectory f) user (userGroup user)
			]
  where
	desc = u ++ " has authorized_keys"

-- | Ensures that a user's authorized_keys contains a line.
-- Any other lines in the file are preserved as-is.
authorizedKey :: User -> String -> Property NoInfo
authorizedKey user@(User u) l = property desc $ do
	f <- liftIO $ dotFile "authorized_keys" user
	modAuthorizedKey f user $
		f `File.containsLine` l
			`requires` File.dirExists (takeDirectory f)
  where
	desc = u ++ " has authorized_keys"

-- | Reverts `authorizedKey`
unauthorizedKey :: User -> String -> Property NoInfo
unauthorizedKey user@(User u) l = property desc $ do
	f <- liftIO $ dotFile "authorized_keys" user
	ifM (liftIO $ doesFileExist f) 
		( modAuthorizedKey f user $ f `File.lacksLine` l
		, return NoChange
		)
  where
	desc = u ++ " lacks authorized_keys"

modAuthorizedKey :: FilePath -> User -> Property NoInfo -> Propellor Result
modAuthorizedKey f user p = ensureProperty $ p
	`requires` File.mode f (combineModes [ownerWriteMode, ownerReadMode])
	`requires` File.ownerGroup f user (userGroup user)
	`requires` File.ownerGroup (takeDirectory f) user (userGroup user)
