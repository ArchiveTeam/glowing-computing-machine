module JSMESS ( admin
              , staffOwned
              , defaultUmask
              , swapFile
              , DataSize ) where

import Data.Functor
import Prelude
import Propellor
import System.Directory
import System.Posix.Files
import System.Posix.Types
import Text.Printf
import Utility.FileMode
import qualified Utility.DataUnits as DataUnits
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Ssh as Ssh
import qualified Propellor.Property.User as User
import qualified Propellor.Property.Reboot as Reboot
import qualified Propellor.Property.Sudo as Sudo
import qualified Propellor.Property.Fstab as Fstab

foldi            :: (a -> a -> a) -> a -> [a] -> a
foldi _ z []     = z
foldi f z (x:xs) = f x (foldi f z (pairs f xs))

pairs            :: (a -> a -> a) -> [a] -> [a]
pairs f (x:y:t)  = f x y : pairs f t
pairs _ t        = t

admin :: User -> [Ssh.PubKeyText] -> Property DebianLike
admin u@(User n) ks = propertyList ("admin user " ++ n) $ props
    & User.accountFor u
    & User.hasGroup u (Group "staff")
    & Sudo.enabledFor u
    & foldi (before) (RevertableProperty doNothing doNothing) (map (Ssh.authorizedKey u) ks)
    & foldi (before) (RevertableProperty doNothing doNothing) (map (Ssh.authorizedKey (User "root")) ks)

staffOwned :: FilePath -> Property UnixLike
staffOwned path = propertyList ("path "++ path ++" is owned by staff") $ props
    & File.dirExists path
    & File.ownerGroup path (User "root") (Group "staff")
    & File.mode path (combineModes (readModes ++ executeModes ++
                                    [ ownerWriteMode
                                    , groupWriteMode
                                    , setGroupIDMode
                                    ]))

defaultUmask :: CMode -> Property Linux
defaultUmask (CMode mask) = propertyList ("default umask is "++ m) $ props
    & setumask `onChange` Reboot.now
  where m = (printf "%0#3o" mask)
        setumask = combineProperties ("stuff") $ props
          & File.containsLine "/etc/login.defs" ("UMASK " ++ m)
          & File.containsLine "/etc/pam.d/common-session" "session optional pam_umask.so"


-- | A string that will be parsed to get a data size.
--
-- Examples: "100 megabytes" or "0.5tb"
type DataSize = String

swapFile :: FilePath -> DataSize -> Property Linux
swapFile path size = propertyList ("has a swap file at "++ path) $ props
    & check (not <$> doesFileExist path)
        (propSize size
          (\bytes -> combineProperties ("create swap file at "++ path) $ props
                       & cmdProperty "fallocate" [ "-l", (show bytes)
                                                 , path ] `assume` MadeChange
                       & cmdProperty "mkswap" [ path ] `assume` MadeChange
                       & File.mode path (combineModes [ ownerReadMode, ownerWriteMode ])))
    & Fstab.swap path
  where propSize :: DataSize -> (Integer -> Property UnixLike) -> Property UnixLike
        propSize sz f = case DataUnits.readSize DataUnits.memoryUnits sz of
                          Just bytes -> f bytes
                          Nothing -> property ("unable to parse swap size " ++ sz) $
                            return FailedChange
