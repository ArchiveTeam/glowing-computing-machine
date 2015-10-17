-- This is the main configuration file for Propellor, and is used to build
-- the propellor program.

import Propellor
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Apt as Apt
import qualified Propellor.Property.Network as Network
--import qualified Propellor.Property.Ssh as Ssh
import qualified Propellor.Property.Cron as Cron
import Propellor.Property.Scheduled
--import qualified Propellor.Property.Sudo as Sudo
import qualified Propellor.Property.User as User
--import qualified Propellor.Property.Hostname as Hostname
--import qualified Propellor.Property.Tor as Tor
import qualified Propellor.Property.Docker as Docker

main :: IO ()
main = defaultMain hosts

-- The hosts propellor knows about.
hosts :: [Host]
hosts =
	[ mybox
	]

-- An example host.
mybox :: Host
mybox = host "mybox.example.com"
	& os (System (Debian Unstable) "amd64")
	& Apt.stdSourcesList
	& Apt.unattendedUpgrades
	& Apt.installed ["etckeeper"]
	& Apt.installed ["ssh"]
	& User.hasSomePassword (User "root")
	& Network.ipv6to4
	& File.dirExists "/var/www"
	& Docker.docked webserverContainer
	& Docker.garbageCollected `period` Daily
	& Cron.runPropellor (Cron.Times "30 * * * *")

-- A generic webserver in a Docker container.
webserverContainer :: Docker.Container
webserverContainer = Docker.container "webserver" (Docker.latestImage "debian")
	& os (System (Debian (Stable "jessie")) "amd64")
	& Apt.stdSourcesList
	& Docker.publish "80:80"
	& Docker.volume "/var/www:/var/www"
	& Apt.serviceInstalledRunning "apache2"
