-- This is the main configuration file for Propellor, and is used to build
-- the propellor program.

import Propellor
import qualified Propellor.Property.Apt as Apt
import qualified Propellor.Property.Cron as Cron
import qualified Propellor.Property.User as User
import qualified Propellor.Property.Git as Git
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
buildmachine = host "buildmachine.archiveteam.org" $ props
    & osDebian Unstable X86_64
    & Apt.stdSourcesList
    & Apt.unattendedUpgrades
    & Apt.installed ["ssh"]
    & User.hasSomePassword (User "root")
    & Cron.runPropellor (Cron.Times "30 * * * *")
    & JSMESS.admin (User "db48x") "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAMFoRm8trenxhZWe6dDEB2c6POPbsPfM5ArZep9lU+ db48x@anglachel"
    & JSMESS.admin (User "db48x") "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJQkqIgZ7D8WHW5Y3o+fpZC/4xtv/3IQrORJrTPCt7KY db48x@erebor"
--   & JSMESS.admin (User "sketchcow") [""]
--   & JSMESS.admin (User "bai") [""]
--   & JSMESS.admin (User "vito") [""]
    & Apt.buildDep [ "mame", "dosbox" ]
    & JSMESS.staffOwned (srcdir </> "emsdk")
    & check (not <$> doesFileExist emsdktar)
      (cmdProperty "wget" [ "https://s3.amazonaws.com/mozilla-games/emscripten/releases/emsdk-portable.tar.gz"
                          , "-O", emsdktar])
    & check (not <$> doesFileExist emsdk)
      (cmdProperty "tar" ["xf", emsdktar
                          , "-C", srcdir </> "emsdk"
                          , "--strip-components=1"])
    & cmdProperty emsdk [ "update" ] `assume` MadeChange
    & cmdProperty emsdk [ "install", "sdk-incoming-64bit" ] `assume` MadeChange
    & JSMESS.staffOwned (srcdir </> "dosbox")
    & Git.cloned (User "db48x") "https://github.com/dreamlayers/em-dosbox/" (srcdir </> "dosbox") (Just "master")
    & JSMESS.staffOwned (srcdir </> "mame")
    & Git.cloned (User "db48x") "https://github.com/mamedev/mame" (srcdir </> "mame") (Just "master")
  where srcdir = "/usr/local/src"
        emsdktar = srcdir </> "emsdk-portable-tar.gz"
        emsdk = (joinPath [ srcdir, "emsdk", "emsdk" ])
