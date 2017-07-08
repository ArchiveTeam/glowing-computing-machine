-- This is the main configuration file for Propellor, and is used to build
-- the propellor program.

import Data.Functor
import Prelude
import Propellor
import qualified Propellor.Property.Apt as Apt
import qualified Propellor.Property.Cron as Cron
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Git as Git
import qualified Propellor.Property.Hostname as Hostname
import qualified Propellor.Property.HostingProvider.DigitalOcean as DigitalOcean
import qualified Propellor.Property.User as User
import qualified JSMESS
import System.Directory
import System.FilePath.Posix

main :: IO ()
main = defaultMain hosts

-- The hosts propellor knows about.
hosts :: [Host]
hosts = [ buildmachine
        ]

-- sets up a machine to build on
buildmachine :: Host
buildmachine = host "glowing-computing-machine.db48x.net" $ props
    & osBuntish "16.04" X86_64
    & DigitalOcean.distroKernel
    & JSMESS.swapFile "/swap" "4GiB" -- needed about 3GiB of swap in testing, on a machine with 8GiB of ram
    & Hostname.sane
    & Apt.unattendedUpgrades
    & Apt.installed ["ssh"]
    & User.lockedPassword (User "root")
    & Cron.runPropellor (Cron.Times "30 * * * *")
    & JSMESS.defaultUmask 0o002
    & JSMESS.admin (User "db48x") [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAMFoRm8trenxhZWe6dDEB2c6POPbsPfM5ArZep9lU+ db48x@anglachel"
                                  , "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJQkqIgZ7D8WHW5Y3o+fpZC/4xtv/3IQrORJrTPCt7KY db48x@erebor" ]
    & JSMESS.admin (User "sketchcow") [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQD7+Q8vqXSA5M0meUhTu0VoYAmaPXu3MeKzMyxS9OsQOMb0ZvyBAIHEWaUu96jiL047qZzy2Fq3ahAqbmzriSeV6eMfJEDRU4d6H2pVWD56pEssm/eW51MQJePI0NkdnZFXEr0KWGuwCwLQ76Ef18sDl5mECy4f8BHZYaGs3FIzuHhqOilrVByRz+rnr2+3uHI2qvkVMCV8Fwx5qoWP2EzN5cTiruyXDiXD/uu/uHZn0fnSOJ3YXcoCs9GVPlhlbtB2cR7RprioHqFC01u/GzG9BoBOykRZP1sp1LB+U5DeACw45Szk1xvgdyrXk9HFCkvSi+IPZb64XmQBVQQGtoGOoD3AGS3noAD0NFULQwegB9FuNFoOIZbyBMfSInM9JZrcqPbn6YFvM+RMj5JQ0pkdMR5OH7C4UtTxbwErtwcC5isD9zQMn/caGO9ULnz+xsgVYAOMwDMM1YXY8EGA7A/sl4l1GQ1ENVhwlUBFRL7eOevZiqV4C58DnwXG5FLN7tRBxe9SMISIWtxsarJQV1rWHqjLG9BDvJlugaFubJvZ9X1TI3JVofa1l0u63wHOImdVst1s6NxGh91xoiDnsie9SIaav6WdVNVqmb/PszuCkHPR8Ljc3WBURRT3osxFtCSN4BpiMpY2G75c5+OzFbjPlztAIfvpZbi5LBXy9pnjnQ== root@teamarchive0.fnf.archive.org" ]
--    & JSMESS.admin (User "bai") [ "" ]
--    & JSMESS.admin (User "vito") [""]
    & Apt.installed [ "vim", "emacs-nox", "nano" ] -- gotta have the right editor
    & Apt.installed [ "mosh", "tmux", "screen" ]
    & Apt.buildDep [ "dosbox" ] -- we also want this for mame, but mame has no src package?
    & Apt.installed [ "build-essential", "cmake", "python2.7", "nodejs", "default-jre" ] -- emscripten's dependencies
    & JSMESS.staffOwned (srcdir)
    & File.dirExists (srcdir </> "emsdk")
    & check (not <$> doesFileExist emsdktar)
      (cmdProperty "wget" [ "https://s3.amazonaws.com/mozilla-games/emscripten/releases/emsdk-portable.tar.gz"
                          , "-O", emsdktar ])
    & check (not <$> doesFileExist emsdk)
      (cmdProperty "tar" [ "xf", emsdktar
                         , "-C", srcdir </> "emsdk"
                         , "--strip-components=1" ])
    & cmdProperty emsdk [ "update" ] `assume` MadeChange
    & cmdProperty emsdk [ "install", "latest"
                        , "-j4"
                        ] `assume` MadeChange
    & File.dirExists (srcdir </> "dosbox")
    & Git.cloned (User "db48x") "https://github.com/dreamlayers/em-dosbox/" (srcdir </> "dosbox") (Just "master")
    & File.dirExists (srcdir </> "mame")
    & Git.cloned (User "db48x") "https://github.com/mamedev/mame" (srcdir </> "mame") (Just "master")
  where srcdir = "/src"
        emsdktar = srcdir </> "emsdk-portable.tar.gz"
        emsdk = (joinPath [ srcdir, "emsdk", "emsdk" ])
