-- This is the main configuration file for Propellor, and is used to build
-- the propellor program.

import Propellor
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Apt as Apt
import qualified Propellor.Property.Cron as Cron
import qualified Propellor.Property.User as User
import qualified JSMESS

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
--   & JSMESS.admin (User "sketchcow") ""
--   & JSMESS.admin (User "bai") ""
--   & JSMESS.admin (User "vito") ""
