-- This is the live config file used by propellor's author.
-- https://propellor.branchable.com/
module Main where

import Propellor
import Propellor.Property.Scheduled
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Apt as Apt
import qualified Propellor.Property.Network as Network
import qualified Propellor.Property.Service as Service
import qualified Propellor.Property.Ssh as Ssh
import qualified Propellor.Property.Cron as Cron
import qualified Propellor.Property.Sudo as Sudo
import qualified Propellor.Property.User as User
import qualified Propellor.Property.Hostname as Hostname
import qualified Propellor.Property.Tor as Tor
import qualified Propellor.Property.Dns as Dns
import qualified Propellor.Property.OpenId as OpenId
import qualified Propellor.Property.Git as Git
import qualified Propellor.Property.Postfix as Postfix
import qualified Propellor.Property.Apache as Apache
import qualified Propellor.Property.Grub as Grub
import qualified Propellor.Property.Obnam as Obnam
import qualified Propellor.Property.Gpg as Gpg
import qualified Propellor.Property.Systemd as Systemd
import qualified Propellor.Property.Journald as Journald
import qualified Propellor.Property.Chroot as Chroot
import qualified Propellor.Property.Aiccu as Aiccu
import qualified Propellor.Property.OS as OS
import qualified Propellor.Property.HostingProvider.CloudAtCost as CloudAtCost
import qualified Propellor.Property.HostingProvider.Linode as Linode
import qualified Propellor.Property.SiteSpecific.GitHome as GitHome
import qualified Propellor.Property.SiteSpecific.GitAnnexBuilder as GitAnnexBuilder
import qualified Propellor.Property.SiteSpecific.IABak as IABak
import qualified Propellor.Property.SiteSpecific.Branchable as Branchable
import qualified Propellor.Property.SiteSpecific.JoeySites as JoeySites
import Propellor.Property.DiskImage

main :: IO ()           --     _         ______`|                       ,-.__ 
main = defaultMain hosts --  /   \___-=O`/|O`/__|                      (____.'
  {- Propellor            -- \          / | /    )          _.-"-._
     Deployed -}          --  `/-==__ _/__|/__=-|          (       \_
hosts :: [Host]          --   *             \ | |           '--------'
hosts =                --                  (o)  `
	[ darkstar
	, gnu
	, clam
	, orca
	, honeybee
	, kite
	, elephant
	, beaver
	, pell
	, iabak
	] ++ monsters

testvm :: Host
testvm = host "testvm.kitenet.net"
	& os (System (Debian Unstable) "amd64")
	& OS.cleanInstallOnce (OS.Confirmed "testvm.kitenet.net")
	 	`onChange` propertyList "fixing up after clean install"
	 		[ OS.preserveRootSshAuthorized
			, OS.preserveResolvConf
			, Apt.update
			, Grub.boots "/dev/sda"
				`requires` Grub.installed Grub.PC
	 		]
	& Hostname.sane
	& Hostname.searchDomain
	& Apt.installed ["linux-image-amd64"]
	& Apt.installed ["ssh"]
	& User.hasPassword (User "root")

darkstar :: Host
darkstar = host "darkstar.kitenet.net"
	& ipv6 "2001:4830:1600:187::2"
	& Aiccu.hasConfig "T18376" "JHZ2-SIXXS"

	& Apt.buildDep ["git-annex"] `period` Daily

	& JoeySites.postfixClientRelay (Context "darkstar.kitenet.net")
	& JoeySites.dkimMilter

	& imageBuilt "/tmp/img" c MSDOS (grubBooted PC)
		[ partition EXT2 `mountedAt` "/boot"
			`setFlag` BootFlag
		, partition EXT4 `mountedAt` "/"
			`mountOpt` errorReadonly
		, swapPartition (MegaBytes 256)
		]
  where
	c d = Chroot.debootstrapped mempty d
		& os (System (Debian Unstable) "amd64")
		& Hostname.setTo "demo"
		& Apt.installed ["linux-image-amd64"]
		& User "root" `User.hasInsecurePassword` "root"

gnu :: Host
gnu = host "gnu.kitenet.net"
	& Apt.buildDep ["git-annex"] `period` Daily

	& JoeySites.postfixClientRelay (Context "gnu.kitenet.net")
	& JoeySites.dkimMilter

clam :: Host
clam = standardSystem "clam.kitenet.net" Unstable "amd64"
	[ "Unreliable server. Anything here may be lost at any time!" ]
	& ipv4 "167.88.41.194"

	& CloudAtCost.decruft
	& Ssh.hostKeys hostContext
		[ (SshDsa, "ssh-dss AAAAB3NzaC1kc3MAAACBAI3WUq0RaigLlcUivgNG4sXpso2ORZkMvfqKz6zkc60L6dpxvWDNmZVEH8hEjxRSYG07NehcuOgQqeyFnS++xw1hdeGjf37JqCUH49i02lra3Zxv8oPpRxyeqe5MmuzUJhlWvBdlc3O/nqZ4bTUfnxMzSYWyy6++s/BpSHttZplNAAAAFQC1DE0vzgVeNAv9smHLObQWZFe2VQAAAIBECtpJry3GC8NVTFsTHDGWksluoFPIbKiZUFFztZGdM0AO2VwAbiJ6Au6M3VddGFANgTlni6d2/9yS919zO90TaFoIjywZeXhxE2CSuRfU7sx2hqDBk73jlycem/ER0sanFhzpHVpwmLfWneTXImWyq37vhAxatJANOtbj81vQ3AAAAIBV3lcyTT9xWg1Q4vERJbvyF8mCliwZmnIPa7ohveKkxlcgUk5d6dnaqFfjVaiXBPN3Qd08WXoQ/a9k3chBPT9nW2vWgzzM8l36j2MbHLmaxGwevAc9+vx4MXqvnGHzd2ex950mC33ct3j0fzMZlO6vqEsgD4CYmiASxhfefj+JCQ==")
		, (SshRsa, "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDJybAjUPUWIhvVMmer8K5ZgdfI54DM6vc8Mzw+5KmVKL0TwkvzbR1HAB4heyMGtN1F8YzkWhsI3/Txh+MQUJ+i4u8SvSYc6D1q3j3ZyCi06wZ3DJS25tZrOM/thOOA1DFA4Hhb0uI/1Kg8PguNNNSMXn8F7q3F6cFQizYgszs6z6ktiST/BTC+IXWovhcnn2vQXXU8FTcTsqBFqA5dEjZbp1WDzqp3km84ZyXGmoVlpqzXeMvlkWTIshYiQjXIwPOkALzlGYjp1lw1OaxPVI1IGFcgCbIWQQWoCReb+genX2VaR+odAYXjaOdRx0lQj7UCPTBCpqMyzBMLtT5Yiaqh")
		, (SshEcdsa, "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPhfvcOuw0Yt+MnsFc4TI2gWkKi62Eajxz+TgbHMO/uRTYF8c5V8fOI3o+J/3m5+lT0S5o8j8a7xIC3COvi+AVw=")
		]
	& Apt.unattendedUpgrades
	& Network.ipv6to4

	& Tor.isRelay
	& Tor.named "kite1"
	& Tor.bandwidthRate (Tor.PerMonth "400 GB")

	& Systemd.nspawned webserver
	& File.dirExists "/var/www/html"
	& File.notPresent "/var/www/index.html"
	& "/var/www/html/index.html" `File.hasContent` ["hello, world"]
	& alias "helloworld.kitenet.net"
	
	& Systemd.nspawned oldusenetShellBox

	& JoeySites.scrollBox
	& alias "scroll.joeyh.name"
	& alias "us.scroll.joeyh.name"
	
	-- ssh on some extra ports to deal with horrible networks
	-- while travelling
	& alias "travelling.kitenet.net"
	! Ssh.listenPort 80
	! Ssh.listenPort 443

	& Systemd.persistentJournal

orca :: Host
orca = standardSystem "orca.kitenet.net" Unstable "amd64"
	[ "Main git-annex build box." ]
	& ipv4 "138.38.108.179"

	& Apt.unattendedUpgrades
	& Postfix.satellite
	& Apt.serviceInstalledRunning "ntp"
	& Systemd.persistentJournal

	& Systemd.nspawned (GitAnnexBuilder.autoBuilderContainer
		GitAnnexBuilder.standardAutoBuilder
		(System (Debian Unstable) "amd64") Nothing fifteenpast "2h")
	& Systemd.nspawned (GitAnnexBuilder.autoBuilderContainer
		GitAnnexBuilder.standardAutoBuilder
		(System (Debian Unstable) "i386") Nothing fifteenpast "2h")
	& Systemd.nspawned (GitAnnexBuilder.autoBuilderContainer
		GitAnnexBuilder.standardAutoBuilder
		(System (Debian (Stable "jessie")) "i386") (Just "ancient") fifteenpast "2h")
	& Systemd.nspawned (GitAnnexBuilder.androidAutoBuilderContainer
		(Cron.Times "1 1 * * *") "3h")
  where
	fifteenpast = Cron.Times "15 * * * *"

honeybee :: Host
honeybee = standardSystem "honeybee.kitenet.net" Testing "armhf"
	[ "Arm git-annex build box." ]
	
	-- I have to travel to get console access, so no automatic
	-- upgrades, and try to be robust.
	& "/etc/default/rcS" `File.containsLine` "FSCKFIX=yes"

	& Apt.installed ["flash-kernel"]
	& "/etc/flash-kernel/machine" `File.hasContent` ["Cubietech Cubietruck"]
	& Apt.installed ["linux-image-armmp"]
	& Network.dhcp "eth0" `requires` Network.cleanInterfacesFile
	& Postfix.satellite
	
	-- ipv6 used for remote access thru firewalls
	& Apt.serviceInstalledRunning "aiccu"
	& ipv6 "2001:4830:1600:187::2"

	-- In case compiler needs more than available ram
	& Apt.serviceInstalledRunning "swapspace"

	-- No hardware clock.
	& Apt.serviceInstalledRunning "ntp"

	& Systemd.nspawned (GitAnnexBuilder.autoBuilderContainer
		GitAnnexBuilder.armAutoBuilder
			(System (Debian Unstable) "armel") Nothing Cron.Daily "22h")

-- This is not a complete description of kite, since it's a
-- multiuser system with eg, user passwords that are not deployed
-- with propellor.
kite :: Host
kite = standardSystemUnhardened "kite.kitenet.net" Testing "amd64"
	[ "Welcome to kite!" ]
	& ipv4 "66.228.36.95"
	& ipv6 "2600:3c03::f03c:91ff:fe73:b0d2"
	& alias "kitenet.net"
	& alias "wren.kitenet.net" -- temporary
	& Ssh.hostKeys (Context "kitenet.net")
		[ (SshDsa, "ssh-dss AAAAB3NzaC1kc3MAAACBAO9tnPUT4p+9z7K6/OYuiBNHaij4Nzv5YVBih1vMl+ALz0gYAj8RWJzXmqp5buFAyfgOoLw+H9s1bBS01Sy3i07Dm6cx1fWG4RXL/E/3w1tavX99GD2bBxDBu890ebA5Tp+eFRJkS9+JwSvFiF6CP7NbVjifCagoUO56Ig048RwDAAAAFQDPY2xM3q6KwsVQliel23nrd0rV2QAAAIEAga3hj1hL00rYPNnAUzT8GAaSP62S4W68lusErH+KPbsMwFBFY/Ib1FVf8k6Zn6dZLh/HH/RtJi0JwdzPI1IFW+lwVbKfwBvhQ1lw9cH2rs1UIVgi7Wxdgfy8gEWxf+QIqn62wG+Ulf/HkWGvTrRpoJqlYRNS/gnOWj9Z/4s99koAAACBAM/uJIo2I0nK15wXiTYs/NYUZA7wcErugFn70TRbSgduIFH6U/CQa3rgHJw9DCPCQJLq7pwCnFH7too/qaK+czDk04PsgqV0+Jc7957gU5miPg50d60eJMctHV4eQ1FpwmGGfXxRBR9k2ZvikWYatYir3L6/x1ir7M0bA9IzNU45")
		, (SshRsa, "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAIEA2QAJEuvbTmaN9ex9i9bjPhMGj+PHUYq2keIiaIImJ+8mo+yKSaGUxebG4tpuDPx6KZjdycyJt74IXfn1voGUrfzwaEY9NkqOP3v6OWTC3QeUGqDCeJ2ipslbEd9Ep9XBp+/ldDQm60D0XsIZdmDeN6MrHSbKF4fXv1bqpUoUILk=")
		, (SshEcdsa, "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLF+dzqBJZix+CWUkAd3Bd3cofFCKwHMNRIfwx1G7dL4XFe6fMKxmrNetQcodo2edyufwoPmCPr3NmnwON9vyh0=")
		, (SshEd25519, "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZftKMnH/zH29BHMKbcBO4QsgTrstYFVhbrzrlRzBO3")
		]

	& Network.static "eth0" `requires` Network.cleanInterfacesFile
	& Apt.installed ["linux-image-amd64"]
	& Linode.chainPVGrub 5
	& Linode.mlocateEnabled
	& Apt.unattendedUpgrades
	& Systemd.installed
	& Systemd.persistentJournal
	& Journald.systemMaxUse "500MiB"
	& Ssh.passwordAuthentication True
	-- Since ssh password authentication is allowed:
	& Apt.serviceInstalledRunning "fail2ban"
	& Obnam.backupEncrypted "/" (Cron.Times "33 1 * * *")
		[ "--repository=sftp://joey@eubackup.kitenet.net/~/lib/backup/kite.obnam"
		, "--client-name=kitenet.net"
		, "--exclude=/var/cache"
		, "--exclude=/var/tmp"
		, "--exclude=/home/joey/lib"
		, "--exclude=.*/tmp/"
		, "--one-file-system"
		] Obnam.OnlyClient (Gpg.GpgKeyId "98147487")
		`requires` Ssh.userKeys (User "root")
			(Context "kite.kitenet.net")
			[ (SshRsa, "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC5Gza2sNqSKfNtUN4dN/Z3rlqw18nijmXFx6df2GtBoZbkIak73uQfDuZLP+AXlyfHocwdkdHEf/zrxgXS4EokQMGLZhJ37Pr3edrEn/NEnqroiffw7kyd7EqaziA6UOezcLTjWGv+Zqg9JhitYs4WWTpNzrPH3yQf1V9FunZnkzb4gJGndts13wGmPEwSuf+QHbgQvjMOMCJwWSNcJGdhDR66hFlxfG26xx50uIczXYAbgLfHp5W6WuR/lcaS9J6i7HAPwcsPDA04XDinrcpl29QwsMW1HyGS/4FSCgrDqNZ2jzP49Bka78iCLRqfl1efyYas/Zo1jQ0x+pxq2RMr root@kite")
			]
		`requires` Ssh.knownHost hosts "eubackup.kitenet.net" (User "root")
	& Apt.serviceInstalledRunning "ntp"
	& "/etc/timezone" `File.hasContent` ["US/Eastern"]

	& alias "smtp.kitenet.net"
	& alias "imap.kitenet.net"
	& alias "pop.kitenet.net"
	& alias "mail.kitenet.net"
	& JoeySites.kiteMailServer
	
	& JoeySites.kitenetHttps
	& JoeySites.legacyWebSites
	& File.ownerGroup "/srv/web" (User "joey") (Group "joey")
	& Apt.installed ["analog"]
	
	& alias "git.kitenet.net"
	& alias "git.joeyh.name"
	& JoeySites.gitServer hosts

	& JoeySites.downloads hosts
	& JoeySites.gitAnnexDistributor
	& JoeySites.tmp

	& alias "bitlbee.kitenet.net"
	& Apt.serviceInstalledRunning "bitlbee"
	& "/etc/bitlbee/bitlbee.conf" `File.hasContent`
		[ "[settings]"
		, "User = bitlbee"
		, "AuthMode = Registered"
		, "[defaults]"
		] 
		`onChange` Service.restarted "bitlbee"
	& "/etc/default/bitlbee" `File.containsLine` "BITLBEE_PORT=\"6767\""
		`onChange` Service.restarted "bitlbee"

	& Apt.installed
		[ "git-annex", "myrepos"
		, "build-essential", "make"
		, "rss2email", "archivemail"
		, "devscripts"
		-- Some users have zsh as their login shell.
		, "zsh"
		]
	
	& alias "nntp.olduse.net"
	& JoeySites.oldUseNetServer hosts
	
	& alias "ns4.kitenet.net"
	& myDnsPrimary True "kitenet.net" []
	& myDnsPrimary True "joeyh.name" []
	& myDnsPrimary True "ikiwiki.info" []
	& myDnsPrimary True "olduse.net"
		[ (RelDomain "article", CNAME $ AbsDomain "virgil.koldfront.dk")
		]
	& alias "ns4.branchable.com"
	& branchableSecondary
	& Dns.secondaryFor ["animx"] hosts "animx.eu.org"

elephant :: Host
elephant = standardSystem "elephant.kitenet.net" Unstable "amd64"
	[ "Storage, big data, and backups, omnomnom!"
	, "(Encrypt all data stored here.)"
	]
	& ipv4 "193.234.225.114"
	& Ssh.hostKeys hostContext
		[ (SshDsa, "ssh-dss AAAAB3NzaC1kc3MAAACBANxXGWac0Yz58akI3UbLkphAa8VPDCGswTS0CT3D5xWyL9OeArISAi/OKRIvxA4c+9XnWtNXS7nYVFDJmzzg8v3ZMx543AxXK82kXCfvTOc/nAlVz9YKJAA+FmCloxpmOGrdiTx1k36FE+uQgorslGW/QTxnOcO03fDZej/ppJifAAAAFQCnenyJIw6iJB1+zuF/1TSLT8UAeQAAAIEA1WDrI8rKnxnh2rGaQ0nk+lOcVMLEr7AxParnZjgC4wt2mm/BmkF/feI1Fjft2z4D+V1W7MJHOqshliuproxhFUNGgX9fTbstFJf66p7h7OLAlwK8ZkpRk/uV3h5cIUPel6aCwjL5M2gN6/yq+gcCTXeHLq9OPyUTmlN77SBL71UAAACBAJJiCHWxPAGooe7Vv3W7EIBbsDyf7b2kDH3bsIlo+XFcKIN6jysBu4kn9utjFlrlPeHUDzGQHe+DmSqTUQQ0JPCRGcAcuJL8XUqhJi6A6ye51M9hVt51cJMXmERx9TjLOP/adkEuxpv3Fj20FxRUr1HOmvRvewSHrJ1GeA1bjbYL")
		, (SshRsa, "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCrEQ7aNmRYyLKY7xHILQsyV/w0B3++D98vn5IvjHkDnitrUWjB+vPxlS7LYKLzN9Jx7Hb14R2lg7+wdgtFMxLZZukA8b0tqFpTdRFBvBYGh8IM8Id1iE/6io/NZl+hTQEDp0LJP+RljH1CLfz7J3qtc+v6NbfTP5cOgH104mWYoLWzJGaZ4p53jz6THRWnVXy5nPO3dSBr2f/SQgRuJQWHNIh0jicRGD8H2kzOQzilpo+Y46PWtkufl3Yu3UsP5UMAyLRIXwZ6nNRZqRiVWrX44hoNfDbooTdFobbHlqMl+y6291bOXaOA6PACk8B4IVcC89/gmc9Oe4EaDuszU5kD")
		, (SshEcdsa, "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAJkoPRhUGT8EId6m37uBdYEtq42VNwslKnc9mmO+89ody066q6seHKeFY6ImfwjcyIjM30RTzEwftuVNQnbEB0=")
		, (SshEd25519, "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB6VtXi0uygxZeCo26n6PuCTlSFCBcwRifv6N8HdWh2Z")
		]

	& Grub.chainPVGrub "hd0,0" "xen/xvda1" 30
	& Postfix.satellite
	& Apt.unattendedUpgrades
	& Systemd.installed
	& Systemd.persistentJournal
	& Ssh.userKeys (User "joey") hostContext
		[ (SshRsa, "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC4wJuQEGno+nJvtE75IKL6JQ08sJHZ9Bzs9Dvu0zuxSEZE30MWK98/twNwCH9PVf2N9m4apfN7f9GHgHTUongfo8xnLAk4PuBSTV74YgKyOCvNYqANuKKa+76PsS/vFf/or3ct++uTEWsRyYD29cQndufwKA4rthAqHG+fifbLDC53AjcldI0zI1RckpPzT+AMazlnSBFMlpKvGD2uzSXALVRXa3vSqWkWd0z7qmIkpmpq0AAgbDLwrGBcUGV/h0rOa2s8zSeirA0tLmHNROl4cZsX0T/6VBGfBRkrHSxL67xJziATw4WPq6spYlxg84pC/5qJVr9SC5HosppbDqgj joey@elephant")
		] 
	& Apt.serviceInstalledRunning "swapspace"

	& alias "eubackup.kitenet.net"
	& Apt.installed ["obnam", "sshfs", "rsync"]
	& JoeySites.obnamRepos ["pell", "kite"]
	& JoeySites.githubBackup
	& JoeySites.rsyncNetBackup hosts

	& alias "podcatcher.kitenet.net"
	& JoeySites.podcatcher
	
	& alias "znc.kitenet.net"
	& JoeySites.ircBouncer
	& alias "kgb.kitenet.net"
	& JoeySites.kgbServer
	
	& alias "mumble.kitenet.net"
	& JoeySites.mumbleServer hosts
	
	& alias "ns3.kitenet.net"
	& myDnsSecondary
	
	& Systemd.nspawned oldusenetShellBox
	& Systemd.nspawned ancientKitenet
	& Systemd.nspawned openidProvider
	 	`requires` Apt.serviceInstalledRunning "ntp"
	
	& JoeySites.scrollBox
	& alias "scroll.joeyh.name"
	& alias "eu.scroll.joeyh.name"
	
	-- For https port 443, shellinabox with ssh login to
	-- kitenet.net
	& alias "shell.kitenet.net"
	& Systemd.nspawned kiteShellBox
	-- Nothing is using http port 80, so listen on
	-- that port for ssh, for traveling on bad networks that
	-- block 22.
	& Ssh.listenPort 80

beaver :: Host
beaver = host "beaver.kitenet.net"
	& ipv6 "2001:4830:1600:195::2"
	& Apt.serviceInstalledRunning "aiccu"
	& Apt.installed ["ssh"]
	& Ssh.hostPubKey SshDsa "ssh-dss AAAAB3NzaC1kc3MAAACBAIrLX260fY0Jjj/p0syNhX8OyR8hcr6feDPGOj87bMad0k/w/taDSOzpXe0Wet7rvUTbxUjH+Q5wPd4R9zkaSDiR/tCb45OdG6JsaIkmqncwe8yrU+pqSRCxttwbcFe+UU+4AAcinjVedZjVRDj2rRaFPc9BXkPt7ffk8GwEJ31/AAAAFQCG/gOjObsr86vvldUZHCteaJttNQAAAIB5nomvcqOk/TD07DLaWKyG7gAcW5WnfY3WtnvLRAFk09aq1EuiJ6Yba99Zkb+bsxXv89FWjWDg/Z3Psa22JMyi0HEDVsOevy/1sEQ96AGH5ijLzFInfXAM7gaJKXASD7hPbVdjySbgRCdwu0dzmQWHtH+8i1CMVmA2/a5Y/wtlJAAAAIAUZj2US2D378jBwyX1Py7e4sJfea3WSGYZjn4DLlsLGsB88POuh32aOChd1yzF6r6C2sdoPBHQcWBgNGXcx4gF0B5UmyVHg3lIX2NVSG1ZmfuLNJs9iKNu4cHXUmqBbwFYQJBvB69EEtrOw4jSbiTKwHFmqdA/mw1VsMB+khUaVw=="
	& alias "usbackup.kitenet.net"
	& JoeySites.backupsBackedupFrom hosts "eubackup.kitenet.net" "/home/joey/lib/backup"
	& Apt.serviceInstalledRunning "anacron"
	& Cron.niceJob "system disk backed up" Cron.Weekly (User "root") "/"
		"rsync -a -x / /home/joey/lib/backup/beaver.kitenet.net/"

-- Branchable is not completely deployed with propellor yet.
pell :: Host
pell = host "pell.branchable.com"
	& alias "branchable.com"
	& ipv4 "66.228.46.55"
	& ipv6 "2600:3c03::f03c:91ff:fedf:c0e5"
	
	-- All the websites I host at branchable that don't use
	-- branchable.com dns.
	& alias "olduse.net"
	& alias "www.olduse.net"
	& alias "www.kitenet.net"
	& alias "joeyh.name"
	& alias "campaign.joeyh.name"
	& alias "ikiwiki.info"
	& alias "git.ikiwiki.info"
	& alias "l10n.ikiwiki.info"
	& alias "dist-bugs.kitenet.net"
	& alias "family.kitenet.net"

	& Apt.installed ["linux-image-amd64"]
	& Linode.chainPVGrub 5
	& Apt.unattendedUpgrades
	& Branchable.server hosts

iabak :: Host
iabak = host "iabak.archiveteam.org"
	& ipv4 "124.6.40.227"
	& Hostname.sane
	& os (System (Debian Testing) "amd64")
	& Systemd.persistentJournal
	& Cron.runPropellor (Cron.Times "30 * * * *")
	& Apt.stdSourcesList `onChange` Apt.upgrade
	& Apt.installed ["git", "ssh"]
	& Ssh.hostKeys (Context "iabak.archiveteam.org")
		[ (SshDsa, "ssh-dss AAAAB3NzaC1kc3MAAACBAMhuYTshLxavWCpfyJxg3j/GWyIRlL3VTharsfUTzMOqyMSWantZjflfJX21z2KzFDtPEA711GYztsgMVXMrsPQInaOKNISe/R9cfgnEktKTxeppWTfw0GTNcpCeeecddU0FCPVW3a6yDoT6+Rv0jPvkQoDGmhQ40MhauMrO0mJ9AAAAFQDpCbXG8o/3Sg7wrsp5abizJoQ0yQAAAIEAxxyHo/ZhDPP+EWtDS05s5dwiDMUsxIllk1NeleAOQIyLtFkaifOeskDJybIPWYPGX1trjcPoGuXJ5GBYrRaPiu6FBvYdYMFRLr4uNBsaSHHqlHhBPkP3RzCrdUyau4XyjdE4iA0EQlO+u11A+o3f7aTuJSveM0YRfbqvaatG89EAAACAWd0h0SkRLnGjBzkou0SQfYujFY9ilhWXPWV/oOs+bieDSpvfmnaEfLSinVFRrJPvQp/dtpxPLEm+StrK3w6dmwTZVUM5JEoB1mRjBkVs6gPC9PVVg9qLpzC2/x+r5cTfrffjyRrlPdkwLKpO6oiPxTIxAyCW8ixjafkxe2hAeJo=")
		, (SshRsa, "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDP13oPRLRY0V9ZDWojb8TgHbUdE30Nq3b541TwPmlLMbYPAhldxGHkuXGlX8g9/FYP/1AgkPcxs2Uc61ZV+1Ss7q7t52f4R0bO4WHqxfdXHd9FlLzMLWxMU3aMr693pGlhnUp3/xH6O6/+bNEIo3VGGgv9XDr2cAxypS9J7X9ibHZcZ3BGvoCR+nnFJ00ERG2tREKZBPDWKk76lhCiM21fG/CSmcApXaA45FHDaM9/2Clj1sXvoS72f0hEKpl1m08sUx+F0GPzQESnKqNFl+xXdYPPbfhdrgCnDmx9tL5NnXsJU2beFiuxpICOeB1HV6DJsdlO18WqwXYhOg/2A1H3")
		, (SshEcdsa, "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHb0kXcrF5ThwS8wB0Hez404Zp9bz78ZxEGSqnwuF4d/N3+bymg7/HAj7l/SzRoEXKHsJ7P5320oMxBHeM16Y+k=")
		]
	& Apt.installed ["etckeeper", "sudo"]
	& Apt.installed ["vim", "screen", "tmux", "less", "emax-nox", "netcat"]
	& User.hasSomePassword (User "root")
	& propertyList "admin accounts"
		(map User.accountFor admins ++ map Sudo.enabledFor admins)
	& User.hasSomePassword (User "joey")
	& GitHome.installedFor (User "joey")
	& Ssh.authorizedKey (User "db48x") "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAIAQDQ6urXcMDeyuFf4Ga7CuGezTShKnEMPHKJm7RQUtw3yXCPX5wnbvPS2+UFnHMzJvWOX5S5b/XpBpOusP0jLpxwOCEg4nA5b7uvWJ2VIChlMqopYMo+tDOYzK/Q74MZiNWi2hvf1tn3N9SnqOa7muBMKMENIX5KJdH8cJ/BaPqAP883gF8r2SwSZFvaB0xYCT/CIylC593n/+0+Lm07NUJIO8jil3n2SwXdVg6ib65FxZoO86M46wTghnB29GXqrzraOg+5DY1zzCWpIUtFwGr4DP0HqLVtmAkC7NI14l1M0oHE0UEbhoLx/a+mOIMD2DuzW3Rs3ZmHtGLj4PL/eBU8D33AqSeM0uR/0pEcoq6A3a8ixibj9MBYD2lMh+Doa2audxS1OLM//FeNccbm1zlvvde82PZtiO11P98uN+ja4A+CfgQU5s0z0wikc4gXNhWpgvz8DrOEJrjstwOoqkLg2PpIdHRw7dhpp3K1Pc+CGAptDwbKkxs4rzUgMbO9DKI7fPcXXgKHLLShMpmSA2vsQUMfuCp2cVrQJ+Vkbwo29N0Js5yU7L4NL4H854Nbk5uwWJCs/mjXtvTimN2va23HEecTpk44HDUjJ9NyevAfPcO9q1ZtgXFTQSMcdv1m10Fvmnaiy8biHnopL6MBo1VRITh5UFiJYfK4kpTTg2vSspii/FYkkYOAnnZtXZqMehP7OZjJ6HWJpsCVR2hxP3sKOoQu+kcADWa/4obdp+z7gY8iMMjd6kwuIWsNV8KsX+eVJ4UFpAi/L00ZjI2B9QLVCsOg6D1fT0698wEchwUROy5vZZJq0078BdAGnwC0WGLt+7OUgn3O2gUAkb9ffD0odbZSqq96NCelM6RaHA+AaIE4tjGL3lFkyOtb+IGPNACQ73/lmaRQd6Cgasq9cEo0g22Ew5NQi0CBuu1aLDk7ezu3SbU09eB9lcZ+8lFnl5K2eQFeVJStFJbJNfOvgKyOb7ePsrUFF5GJ2J/o1F60fRnG64HizZHxyFWkEOh+k3i8qO+whPa5MTQeYLYb6ysaTPrUwNRcSNNCcPEN8uYOh1dOFAtIYDcYA56BZ321yz0b5umj+pLsrFU+4wMjWxZi0inJzDS4dVegBVcRm0NP5u8VRosJQE9xdbt5K1I0khzhrEW1kowoTbhsZCaDHhL9LZo73Z1WIHvulvlF3RLZip5hhtQu3ZVkbdV5uts8AWaEWVnIu9z0GtQeeOuseZpT0u1/1xjVAOKIzuY3sB7FKOaipe8TDvmdiQf/ICySqqYaYhN6GOhiYccSleoX6yzhYuCvzTgAyWHIfW0t25ff1CM7Vn+Vo9cVplIer1pbwhZZy4QkROWTOE+3yuRlQ+o6op4hTGdAZhjKh9zkDW7rzqQECFrZrX/9mJhxYKjhpkk0X3dSipPt9SUHagc4igya+NgCygQkWBOQfr4uia0LcwDxy4Kchw7ZuypHuGVZkGhNHXS+9JdAHopnSqYwDMG/z1ys1vQihgER0b9g3TchvGF+nmHe2kbM1iuIYMNNlaZD1yGZ5qR7wr/8dw8r0NBEwzsUfak3BUPX7H6X0tGS96llwUxmvQD85WNNoef0uryuAtDEwWlfN1RmWysZDc57Rn4gZi0M5jXmQD23ZiYXYBcG849OeqNzlxONEFsForXO/29Ud4x/Hqa9tf+kJbqMRsaLFO+PXhHzgl6ZHLAljQDxrJ6keNnkqaYfqQ8wyRi1mKv4Ab57kde7mUsZhe7w93GaE9Lxfvu7d3pB+lXfI9NJCSITHreUP4JfmFW+p/eVg+r/1wbElNylGna4I4+qYObOUncGwFKYdFPdtU1XLDKXmywTEgbEh7iI9zX0xD3bPHQLMg+TTtXiU9dQm1x/0zRf9trwDsRDJCbG4/P4iQYkcVvYx2CCfi0JSHv8tWsLi3GJKJLXUxZyzfvY2lThPeYnnY/HFrPJCyJUN55QuRmfzbu8rHgWlcyOlVpKtz+7kn823kEQykiIYKIKrb0G6VBzuMtAk9XzJPv+Wu7suOGXHlVfCqPLk6RjHDm4kTYciW9VgxDts5Y+zwcAbrUeA4UuN/6KisWpivMrfDSIHUCeH/lHBtNkqKohdrUKJMEOx5X6r2dJbmoTFBDi5XtYu/5cBtiDMmupNB0S+pZ2JD5/RKtj6kgzTeE1q/OG4q/eq1O1rjf0vIS31luy27K/YHFIGE0D/CmuXE74Uyaxm27RnrKUxEBl84V70GaIF4F5On8pSThxxizigXTRTKiczc+A5Zi29mid+1EFeUAJOa/DuHJfpVNY4pYEmhPl/Bk66L8kzlbJz6Hg/LIiJIRcy3UKrbSxPFIDpXn33drBHgklMDlrIVDZDXF6cn0Ml71SabB4A3TM6TK+oWZoyvftPIhcWhVwAWQj7nFNAiMEl1z/29ovHrRooqQFozf7GDW8Mjiu7ChZP9zx2H8JB/AAEFuWMwGV4AHICYdS9lOl/v+cDhgsnXdeuKEuxHhYlRxuRxJk/f17Sm/5H85UIzlu85wi3q/DW2FTZnlw4iJLnL6FArUIMzuBOZyoEhh0SPR41Xc4kkucDhnENybTZSR/yDzb0P1B7qjZ4GqcSEFja/hm/LH1oKJzZg8MEqeUoKYCUdVv9ek4IUGUONtVs53V5SOwFWR/nVuDk2BENr7NadYYVtu6MjBwgjso7NuhoNxVwIEP3BW67OQ8bxfNBtJJQNJejAhgZiqJItI9ucAfjQ== db48x@anglachel"
	& Apt.installed ["sudo"]
	& Ssh.noPasswords
	& IABak.gitServer monsters
	& IABak.registrationServer monsters
	& IABak.graphiteServer
	& IABak.publicFace
  where
	admins = map User ["joey", "db48x"]

       --'                        __|II|      ,.
     ----                      __|II|II|__   (  \_,/\
--'-------'\o/-'-.-'-.-'-.- __|II|II|II|II|___/   __/ -'-.-'-.-'-.-'-.-'-.-'-
-------------------------- |   [Containers]      / --------------------------
-------------------------- :                    / ---------------------------
--------------------------- \____, o          ,' ----------------------------
---------------------------- '--,___________,'  -----------------------------

-- Simple web server, publishing the outside host's /var/www
webserver :: Systemd.Container
webserver = standardStableContainer "webserver"
	& Systemd.bind "/var/www"
	& Apache.installed

-- My own openid provider. Uses php, so containerized for security
-- and administrative sanity.
openidProvider :: Systemd.Container
openidProvider = standardStableContainer "openid-provider"
	& alias hn
	& OpenId.providerFor [User "joey", User "liw"] hn (Just (Port 8081))
  where
	hn = "openid.kitenet.net"

-- Exhibit: kite's 90's website on port 1994.
ancientKitenet :: Systemd.Container
ancientKitenet = standardStableContainer "ancient-kitenet"
	& alias hn
	& Git.cloned (User "root") "git://kitenet-net.branchable.com/" "/var/www/html"
		(Just "remotes/origin/old-kitenet.net")
	& Apache.installed
	& Apache.listenPorts [p]
	& Apache.virtualHost hn p "/var/www/html"
	& Apache.siteDisabled "000-default"
  where
	p = Port 1994
	hn = "ancient.kitenet.net"

oldusenetShellBox :: Systemd.Container
oldusenetShellBox = standardStableContainer "oldusenet-shellbox"
	& alias "shell.olduse.net"
	& JoeySites.oldUseNetShellBox

kiteShellBox :: Systemd.Container
kiteShellBox = standardStableContainer "kiteshellbox"
	& JoeySites.kiteShellBox

type Motd = [String]

-- This is my standard system setup.
standardSystem :: HostName -> DebianSuite -> Architecture -> Motd -> Host
standardSystem hn suite arch motd = standardSystemUnhardened hn suite arch motd
	& Ssh.noPasswords

standardSystemUnhardened :: HostName -> DebianSuite -> Architecture -> Motd -> Host
standardSystemUnhardened hn suite arch motd = host hn
	& os (System (Debian suite) arch)
	& Hostname.sane
	& Hostname.searchDomain
	& File.hasContent "/etc/motd" ("":motd++[""])
	& Apt.stdSourcesList `onChange` Apt.upgrade
	& Apt.cacheCleaned
	& Apt.installed ["etckeeper"]
	& Apt.installed ["ssh"]
	& GitHome.installedFor (User "root")
	& User.hasSomePassword (User "root")
	& User.accountFor (User "joey")
	& User.hasSomePassword (User "joey")
	& Sudo.enabledFor (User "joey")
	& GitHome.installedFor (User "joey")
	& Apt.installed ["vim", "screen", "less"]
	& Cron.runPropellor (Cron.Times "30 * * * *")
	-- I use postfix, or no MTA.
	& Apt.removed ["exim4", "exim4-daemon-light", "exim4-config", "exim4-base"]
		`onChange` Apt.autoRemove

-- This is my standard container setup, Featuring automatic upgrades.
standardContainer :: Systemd.MachineName -> DebianSuite -> Architecture -> Systemd.Container
standardContainer name suite arch =
	Systemd.container name system (Chroot.debootstrapped mempty)
		& Apt.stdSourcesList `onChange` Apt.upgrade
		& Apt.unattendedUpgrades
		& Apt.cacheCleaned
  where
	system = System (Debian suite) arch

standardStableContainer :: Systemd.MachineName -> Systemd.Container
standardStableContainer name = standardContainer name (Stable "jessie") "amd64"

myDnsSecondary :: Property HasInfo
myDnsSecondary = propertyList "dns secondary for all my domains" $ props
	& Dns.secondary hosts "kitenet.net"
	& Dns.secondary hosts "joeyh.name"
	& Dns.secondary hosts "ikiwiki.info"
	& Dns.secondary hosts "olduse.net"

branchableSecondary :: RevertableProperty HasInfo
branchableSecondary = Dns.secondaryFor ["branchable.com"] hosts "branchable.com"

-- Currently using kite (ns4) as primary with secondaries
-- elephant (ns3) and gandi.
-- kite handles all mail.
myDnsPrimary :: Bool -> Domain -> [(BindDomain, Record)] -> RevertableProperty HasInfo
myDnsPrimary dnssec domain extras = (if dnssec then Dns.signedPrimary (Weekly Nothing) else Dns.primary) hosts domain
	(Dns.mkSOA "ns4.kitenet.net" 100) $
	[ (RootDomain, NS $ AbsDomain "ns4.kitenet.net")
	, (RootDomain, NS $ AbsDomain "ns3.kitenet.net")
	, (RootDomain, NS $ AbsDomain "ns6.gandi.net")
	, (RootDomain, MX 0 $ AbsDomain "kitenet.net")
	, (RootDomain, TXT "v=spf1 a a:kitenet.net ~all")
	, JoeySites.domainKey
	] ++ extras


monsters :: [Host]    -- Systems I don't manage with propellor,
monsters =            -- but do want to track their public keys etc.
	[ host "usw-s002.rsync.net"
		& Ssh.hostPubKey SshDsa "ssh-dss AAAAB3NzaC1kc3MAAAEBAI6ZsoW8a+Zl6NqUf9a4xXSMcV1akJHDEKKBzlI2YZo9gb9YoCf5p9oby8THUSgfh4kse7LJeY7Nb64NR6Y/X7I2/QzbE1HGGl5mMwB6LeUcJ74T3TQAlNEZkGt/MOIVLolJHk049hC09zLpkUDtX8K0t1yaCirC9SxDGLTCLEhvU9+vVdVrdQlKZ9wpLUNbdAzvbra+O/IVvExxDZ9WCHrnfNA8ddVZIGEWMqsoNgiuCxiXpi8qL+noghsSQNFTXwo7W2Vp9zj1JkCt3GtSz5IzEpARQaXEAWNEM0n1nJ686YUOhou64iRM8bPC1lp3QXvvZNgj3m+QHhIempx+de8AAAAVAKB5vUDaZOg14gRn7Bp81ja/ik+RAAABACPH/bPbW912x1NxNiikzGR6clLh+bLpIp8Qie3J7DwOr8oC1QOKjNDK+UgQ7mDQEgr4nGjNKSvpDi4c1QCw4sbLqQgx1y2VhT0SmUPHf5NQFldRQyR/jcevSSwOBxszz3aq9AwHiv9OWaO3XY18suXPouiuPTpIcZwc2BLDNHFnDURQeGEtmgqj6gZLIkTY0iw7q9Tj5FOyl4AkvEJC5B4CSzaWgey93Wqn1Imt7KI8+H9lApMKziVL1q+K7xAuNkGmx5YOSNlE6rKAPtsIPHZGxR7dch0GURv2jhh0NQYvBRn3ukCjuIO5gx56HLgilq59/o50zZ4NcT7iASF76TcAAAEAC6YxX7rrs8pp13W4YGiJHwFvIO1yXLGOdqu66JM0plO4J1ItV1AQcazOXLiliny3p2/W+wXZZKd5HIRt52YafCA8YNyMk/sF7JcTR4d4z9CfKaAxh0UpzKiAk+0j/Wu3iPoTOsyt7N0j1+dIyrFodY2sKKuBMT4TQ0yqQpbC+IDQv2i1IlZAPneYGfd5MIGygs2QMfaMQ1jWAKJvEO0vstZ7GB6nDAcg4in3ZiBHtomx3PL5w+zg48S4Ed69BiFXLZ1f6MnjpUOP75pD4MP6toS0rgK9b93xCrEQLgm4oD/7TCHHBo2xR7wwcsN2OddtwWsEM2QgOkt/jdCAoVCqwQ=="
	, host "github.com" 
		& Ssh.hostPubKey SshRsa "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="
	, host "gitlab.com"
		& Ssh.hostPubKey SshEcdsa "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY="
	, host "ns6.gandi.net"
		& ipv4 "217.70.177.40"
	, host "turtle.kitenet.net"
		& ipv4 "67.223.19.96"
		& ipv6 "2001:4978:f:2d9::2"
	, host "mouse.kitenet.net"
		& ipv6 "2001:4830:1600:492::2"
	, host "animx"
		& ipv4 "76.7.162.101"
		& ipv4 "76.7.162.186"
	]



                          --                                o
                          --             ___                 o              o
                       {-----\          / o \              ___o            o
                       {      \    __   \   /   _        (X___>--         __o
  _____________________{ ______\___  \__/ | \__/ \____                  |X__>
 <                                  \___//|\\___/\     \____________   _
  \                                  ___/ | \___    # #             \ (-)
   \    O      O      O             #     |     \ #                  >=)
    \______________________________# #   /       #__________________/ (-}


